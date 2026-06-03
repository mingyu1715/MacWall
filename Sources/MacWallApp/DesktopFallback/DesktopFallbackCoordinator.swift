import AppKit
import Foundation
import MacWallCore

@MainActor
final class DesktopFallbackCoordinator {
    typealias GenerateFallback = @MainActor (WallpaperAsset, URL) async throws -> Void
    typealias ApplyDesktopImage = @MainActor (URL) throws -> Void

    private struct InFlightAutomaticTask {
        let token: UUID
        let task: Task<Void, Never>
    }

    private let fileManager: FileManager
    private let generateFallback: GenerateFallback
    private let applyDesktopImage: ApplyDesktopImage
    private var activeProjectDirectory: String?
    private var inFlightAutomaticTasks: [String: InFlightAutomaticTask] = [:]
    private var latestGenerationTokens: [String: UUID] = [:]

    init(
        fileManager: FileManager = .default,
        generateFallback: GenerateFallback? = nil,
        applyDesktopImage: @escaping ApplyDesktopImage = DesktopFallbackCoordinator.applyDesktopImageOnAllScreens
    ) {
        self.fileManager = fileManager
        self.generateFallback = generateFallback ?? Self.generateDefaultFallback
        self.applyDesktopImage = applyDesktopImage
    }

    static func cacheURL(for asset: WallpaperAsset) -> URL {
        URL(filePath: asset.projectDirectory)
            .appending(path: "Derived")
            .appending(path: "desktop-fallback.png")
    }

    func hasCache(for asset: WallpaperAsset) -> Bool {
        fileManager.fileExists(atPath: Self.cacheURL(for: asset).path)
    }

    func prepareForPlayback(asset: WallpaperAsset) {
        activeProjectDirectory = projectKey(for: asset)
        let cache = Self.cacheURL(for: asset)
        guard fileManager.fileExists(atPath: cache.path) else {
            return
        }
        try? applyDesktopImage(cache)
    }

    func clearActiveAsset() {
        activeProjectDirectory = nil
    }

    func applyOrGenerate(asset: WallpaperAsset) {
        activeProjectDirectory = projectKey(for: asset)
        let cache = Self.cacheURL(for: asset)
        if fileManager.fileExists(atPath: cache.path) {
            try? applyDesktopImage(cache)
            return
        }
        scheduleGenerationIfNeeded(asset: asset)
    }

    func scheduleGenerationIfNeeded(asset: WallpaperAsset) {
        let key = projectKey(for: asset)
        guard !hasCache(for: asset), inFlightAutomaticTasks[key] == nil else {
            return
        }
        let token = UUID()
        latestGenerationTokens[key] = token
        let task = Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            try? await self.generateAndInstall(asset: asset, token: token)
            self.finishAutomaticTask(key: key, token: token)
        }
        inFlightAutomaticTasks[key] = InFlightAutomaticTask(token: token, task: task)
    }

    func waitForAutomaticGeneration() async {
        while !inFlightAutomaticTasks.isEmpty {
            let tasks = inFlightAutomaticTasks.values.map(\.task)
            for task in tasks {
                await task.value
            }
        }
    }

    func invalidate(asset: WallpaperAsset) {
        let key = projectKey(for: asset)
        latestGenerationTokens[key] = UUID()
        inFlightAutomaticTasks.removeValue(forKey: key)?.task.cancel()
    }

    func generate(asset: WallpaperAsset) async throws {
        if hasCache(for: asset) {
            if activeProjectDirectory == projectKey(for: asset) {
                try applyDesktopImage(Self.cacheURL(for: asset))
            }
            return
        }
        try await generateLatest(asset: asset)
    }

    func regenerate(asset: WallpaperAsset) async throws {
        invalidate(asset: asset)
        try await generateLatest(asset: asset)
    }

    func refreshFromLiveSnapshot(
        asset: WallpaperAsset,
        writeSnapshot: @escaping @MainActor (URL) async throws -> Void
    ) async throws {
        guard asset.kind == .video || asset.kind == .web else {
            throw DesktopFallbackError.unsupportedAsset
        }
        let key = projectKey(for: asset)
        let token = UUID()
        latestGenerationTokens[key] = token
        try await installGenerated(asset: asset, token: token, writeOutput: writeSnapshot)
    }

    private func generateLatest(asset: WallpaperAsset) async throws {
        let key = projectKey(for: asset)
        let token = UUID()
        latestGenerationTokens[key] = token
        try await generateAndInstall(asset: asset, token: token)
    }

    private func generateAndInstall(asset: WallpaperAsset, token: UUID) async throws {
        try await installGenerated(asset: asset, token: token) { output in
            try await self.generateFallback(asset, output)
        }
    }

    private func installGenerated(
        asset: WallpaperAsset,
        token: UUID,
        writeOutput: @escaping @MainActor (URL) async throws -> Void
    ) async throws {
        let cache = Self.cacheURL(for: asset)
        let projectDirectory = URL(filePath: asset.projectDirectory)
        let temporary = cache.deletingLastPathComponent()
            .appending(path: ".desktop-fallback.\(UUID().uuidString).png")
        try fileManager.createDirectory(
            at: cache.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        defer {
            if fileManager.fileExists(atPath: temporary.path) {
                try? fileManager.removeItem(at: temporary)
            }
            removeDirectoryIfEmpty(cache.deletingLastPathComponent())
            removeDirectoryIfEmpty(projectDirectory)
        }
        try await writeOutput(temporary)
        let key = projectKey(for: asset)
        guard latestGenerationTokens[key] == token else {
            throw DesktopFallbackError.generationInvalidated
        }
        let data = try Data(contentsOf: temporary)
        try data.write(to: cache, options: [.atomic])
        if activeProjectDirectory == key {
            try applyDesktopImage(cache)
        }
    }

    private func finishAutomaticTask(key: String, token: UUID) {
        guard inFlightAutomaticTasks[key]?.token == token else {
            return
        }
        inFlightAutomaticTasks.removeValue(forKey: key)
    }

    private func removeDirectoryIfEmpty(_ url: URL) {
        guard let contents = try? fileManager.contentsOfDirectory(atPath: url.path),
              contents.isEmpty else {
            return
        }
        try? fileManager.removeItem(at: url)
    }

    private func projectKey(for asset: WallpaperAsset) -> String {
        URL(filePath: asset.projectDirectory).standardizedFileURL.path
    }

    private static func generateDefaultFallback(asset: WallpaperAsset, output: URL) async throws {
        if asset.kind == .web {
            guard let entrypoint = asset.entrypoint else {
                throw DesktopFallbackError.unsupportedAsset
            }
            try await WebDesktopFallbackSnapshotter().snapshot(
                url: URL(filePath: entrypoint),
                readAccessURL: URL(filePath: asset.projectDirectory),
                output: output
            )
            return
        }
        try await DesktopFallbackImageGenerator().generate(asset: asset, output: output)
    }

    private static func applyDesktopImageOnAllScreens(_ url: URL) throws {
        for screen in NSScreen.screens {
            try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:])
        }
    }
}
