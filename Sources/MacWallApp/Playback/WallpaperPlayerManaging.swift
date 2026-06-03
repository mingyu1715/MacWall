import MacWallCore

@MainActor
protocol WallpaperPlayerManaging: AnyObject {
    var activeSessionSnapshot: PlaybackSessionSnapshot? { get }

    @discardableResult
    func play(
        asset: WallpaperAsset,
        autoPauseWhenCovered: Bool,
        experimentalSceneRendering: Bool,
        webMouseInteractionEnabled: Bool,
        displayMode: WallpaperDisplayMode
    ) throws -> PlaybackSessionSnapshot

    func stop()
    func setDisplayMode(_ displayMode: WallpaperDisplayMode)
    func setAutoPauseWhenCovered(_ enabled: Bool)
    func setExperimentalSceneRendering(_ enabled: Bool)
    func setWebMouseInteractionEnabled(_ enabled: Bool)
}
