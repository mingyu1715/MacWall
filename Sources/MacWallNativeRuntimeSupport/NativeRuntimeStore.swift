import Foundation

public struct NativeRuntimeStore: Sendable {
    public let rootURL: URL

    public init(rootURL: URL) {
        self.rootURL = rootURL.standardizedFileURL
    }

    public static func live(
        appGroupIdentifier: String = NativeRuntimeConstants.appGroupIdentifier
    ) throws -> Self {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else {
            throw NativeRuntimeStoreError.appGroupUnavailable
        }
        return Self(rootURL: container.appending(path: "NativeRuntime"))
    }

    public var commandURL: URL {
        rootURL.appending(path: "command.json")
    }

    public var statusURL: URL {
        rootURL.appending(path: "status.json")
    }

    public var generationsURL: URL {
        rootURL.appending(path: "Generations")
    }

    public func writeCommand(_ command: NativeRuntimeCommand) throws {
        try writeAtomically(JSONEncoder().encode(command), to: commandURL)
    }

    public func readCommand() throws -> NativeRuntimeCommand? {
        guard FileManager.default.fileExists(atPath: commandURL.path) else {
            return nil
        }
        let command = try JSONDecoder().decode(
            NativeRuntimeCommand.self,
            from: Data(contentsOf: commandURL)
        )
        try validateSchema(command.schemaVersion)
        return command
    }

    public func writeStatus(_ status: NativeRuntimeStatus) throws {
        try writeAtomically(JSONEncoder().encode(status), to: statusURL)
    }

    public func readStatus() throws -> NativeRuntimeStatus? {
        guard FileManager.default.fileExists(atPath: statusURL.path) else {
            return nil
        }
        let status = try JSONDecoder().decode(
            NativeRuntimeStatus.self,
            from: Data(contentsOf: statusURL)
        )
        try validateSchema(status.schemaVersion)
        return status
    }

    public func stageVideo(
        sourceURL: URL,
        generation: UUID
    ) throws -> String {
        let fileManager = FileManager.default
        try validateRegularNonSymbolicFile(sourceURL)

        let destinationDirectory = generationsURL
            .appending(path: generation.uuidString)
        guard !fileManager.fileExists(atPath: destinationDirectory.path) else {
            throw NativeRuntimeStoreError.generationAlreadyExists
        }

        let stagingRoot = rootURL.appending(path: ".Staging")
        let stagingDirectory = stagingRoot.appending(path: generation.uuidString)
        if fileManager.fileExists(atPath: stagingDirectory.path) {
            try fileManager.removeItem(at: stagingDirectory)
        }

        do {
            try fileManager.createDirectory(
                at: stagingDirectory,
                withIntermediateDirectories: true
            )
            try fileManager.copyItem(
                at: sourceURL,
                to: stagingDirectory.appending(path: "source.mp4")
            )
            try fileManager.createDirectory(
                at: generationsURL,
                withIntermediateDirectories: true
            )
            try fileManager.moveItem(
                at: stagingDirectory,
                to: destinationDirectory
            )
            try removeDirectoryIfEmpty(stagingRoot)
        } catch {
            try? fileManager.removeItem(at: stagingDirectory)
            try? removeDirectoryIfEmpty(stagingRoot)
            throw error
        }

        return "Generations/\(generation.uuidString)/source.mp4"
    }

    public func resolveSourceURL(
        for command: NativeRuntimeCommand
    ) throws -> URL {
        guard command.kind == .play,
              command.assetKind == .video,
              command.assetID?.isEmpty == false,
              let relativeSourcePath = command.relativeSourcePath else {
            throw NativeRuntimeStoreError.invalidCommand
        }

        let components = relativeSourcePath.split(
            separator: "/",
            omittingEmptySubsequences: false
        ).map(String.init)
        guard components == [
            "Generations",
            command.generation.uuidString,
            "source.mp4"
        ] else {
            throw NativeRuntimeStoreError.invalidSourcePath
        }

        let sourceURL = rootURL.appending(path: relativeSourcePath)
        try validatePathHasNoSymbolicLinks(
            sourceURL,
            relativeComponents: components
        )

        let resolvedRoot = generationsURL.resolvingSymlinksInPath()
            .standardizedFileURL
        let resolvedSource = sourceURL.resolvingSymlinksInPath()
            .standardizedFileURL
        guard resolvedSource.path.hasPrefix(resolvedRoot.path + "/") else {
            throw NativeRuntimeStoreError.invalidSourcePath
        }

        try validateRegularNonSymbolicFile(sourceURL)
        return sourceURL
    }

    public func removeGeneration(_ generation: UUID) throws {
        let directory = generationsURL.appending(path: generation.uuidString)
        guard FileManager.default.fileExists(atPath: directory.path) else {
            return
        }
        try FileManager.default.removeItem(at: directory)
    }

    public func removeUnreferencedGenerations(
        keeping generations: Set<UUID>
    ) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: generationsURL.path) else {
            return
        }

        let entries = try fileManager.contentsOfDirectory(
            at: generationsURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        for entry in entries {
            guard let generation = UUID(uuidString: entry.lastPathComponent),
                  !generations.contains(generation) else {
                continue
            }
            try fileManager.removeItem(at: entry)
        }
    }

    private func writeAtomically(_ data: Data, to destination: URL) throws {
        let fileManager = FileManager.default
        let directory = destination.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let temporary = directory.appending(
            path: ".tmp-\(UUID().uuidString)"
        )
        do {
            try data.write(to: temporary, options: [.withoutOverwriting])
            if fileManager.fileExists(atPath: destination.path) {
                _ = try fileManager.replaceItemAt(
                    destination,
                    withItemAt: temporary
                )
            } else {
                try fileManager.moveItem(at: temporary, to: destination)
            }
        } catch {
            try? fileManager.removeItem(at: temporary)
            throw error
        }
    }

    private func validateSchema(_ schemaVersion: Int) throws {
        guard schemaVersion == NativeRuntimeConstants.schemaVersion else {
            throw NativeRuntimeStoreError.unsupportedSchema(schemaVersion)
        }
    }

    private func validateRegularNonSymbolicFile(_ url: URL) throws {
        guard url.isFileURL else {
            throw NativeRuntimeStoreError.sourceMissing
        }
        let values: URLResourceValues
        do {
            values = try url.resourceValues(
                forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
            )
        } catch {
            throw NativeRuntimeStoreError.sourceMissing
        }
        if values.isSymbolicLink == true {
            throw NativeRuntimeStoreError.unsafeSymbolicLink
        }
        guard values.isRegularFile == true else {
            throw NativeRuntimeStoreError.sourceMissing
        }
    }

    private func validatePathHasNoSymbolicLinks(
        _ sourceURL: URL,
        relativeComponents: [String]
    ) throws {
        var current = rootURL
        for component in relativeComponents {
            current.append(path: component)
            guard FileManager.default.fileExists(atPath: current.path) else {
                throw NativeRuntimeStoreError.sourceMissing
            }
            let values = try current.resourceValues(
                forKeys: [.isSymbolicLinkKey]
            )
            if values.isSymbolicLink == true {
                throw NativeRuntimeStoreError.unsafeSymbolicLink
            }
        }

        guard current.standardizedFileURL == sourceURL.standardizedFileURL else {
            throw NativeRuntimeStoreError.invalidSourcePath
        }
    }

    private func removeDirectoryIfEmpty(_ url: URL) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else {
            return
        }
        let entries = try fileManager.contentsOfDirectory(atPath: url.path)
        if entries.isEmpty {
            try fileManager.removeItem(at: url)
        }
    }
}
