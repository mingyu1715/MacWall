# MacWall Native Wallpaper Spike

This directory is a macOS 26-only private API spike.

Goals:

- Build a third-party ExtensionKit extension with `EXExtensionPointIdentifier = com.apple.wallpaper`.
- Verify whether `WallpaperAgent` discovers and loads the extension.
- Verify whether the extension can receive native wallpaper lifecycle requests.
- Verify whether generated frames can appear as the desktop wallpaper surface.
- Verify whether an actual bundled mp4 can play through the native wallpaper surface.

## Confirmed Success State

Confirmed by user verification:

- `WallpaperAgent` discovers and launches the MacWall wallpaper extension.
- connect, settings view model, and acquire handshakes pass.
- `CAContext.remoteContext()` can be returned through `WallpaperRemoteContextXPC`.
- `AVSampleBufferDisplayLayer` can render into the native wallpaper surface.
- A bundled sample mp4 can play through `AVAssetReader` into the Desktop wallpaper.
- The native path removes the Fullscreen -> Desktop red-pill behavior seen with the custom `NSWindow` backend.

The important architecture is:

```text
Renderer
-> Frame
-> Native Wallpaper Backend
-> WallpaperAgent
```

Treat `WallpaperAgent` as the frame consumer. Video, Scene, and Web renderers
should remain producers in front of this backend.

## Support Policy

- Official target: macOS 26+.
- Hardware target: Apple Silicon only.
- Keep the existing `NSWindow` backend as fallback.
- Preserve this spike as a research project until the native backend design is stable.
- Do not start Main App integration from this directory without a separate design.

Non-goals:

- macOS 14/15 support.
- release packaging.
- App Store distribution.
- Dock/Finder injection.
- SIP disablement.
- system wallpaper database mutation.
- Main App integration.

## Development Run Protocol

Do not treat `open` launch/quit of the containing app as the test lifecycle.
`WallpaperAgent` owns the wallpaper extension process and may keep it alive
after the host app exits.

Use the spike dev runner:

```bash
./dev.sh reset
./dev.sh install
./dev.sh status
./dev.sh logs --last 10m
```

Protocol:

```text
1. ./dev.sh reset
2. ./dev.sh install
3. User selects MacWall Native Spike in System Settings
4. Check WallpaperAgent and extension logs with ./dev.sh logs
5. User verifies the actual screen
6. Before retesting, always reset first and then install
```

Runner commands:

- `reset`: terminates stale `MacWallNativeWallpaperExtension` processes.
- `install`: runs CMake, Xcode build, codesign verification, and LaunchServices registration.
- `status`: prints `WallpaperAgent`, extension process, and recent session log state.
- `logs`: shows or streams WallpaperAgent and extension logs.

Rules:

- Do not use ad-hoc `open` launch/quit as proof of a clean test run.
- Do not assume host app quit stops `MacWallNativeWallpaperExtension`.
- Compare user-visible results with `WallpaperAgent` and extension logs before
  making the next implementation change.
- System Settings selection and actual Desktop output verification remain manual.

## Snapshot Export Gate Protocol

The default snapshot mode is `disabled`.

Run one candidate at a time:

```bash
./dev.sh reset
./dev.sh install --snapshot-mode disabled
```

Then manually select `MacWall Native Spike` in System Settings -> Wallpaper.
Do not use `open`/quit as test evidence.

For a candidate:

```bash
./dev.sh reset
./dev.sh install --snapshot-mode error
```

Collect logs:

```bash
./dev.sh logs --last 2m
```

Check for:

- `snapshotGate event=snapshot-request`
- `snapshotGate event=snapshot-reply`
- `WallpaperExtensionError (2)`
- `NSCocoaErrorDomain (4101)`
- `ReportCrash`
- continued `nativeVideoBridge enqueued`

If a candidate crashes the extension, return to:

```bash
./dev.sh reset
./dev.sh install --snapshot-mode disabled
```
