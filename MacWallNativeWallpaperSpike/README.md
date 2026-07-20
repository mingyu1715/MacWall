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

## Video Source Diagnostic Protocol

The default video source is `asset`, which uses the bundled mp4 through
`AVAssetReader` and `AVSampleBufferDisplayLayer`.

Use `generated` when isolating stutter or frame pacing issues. This bypasses
the bundled mp4 and `AVAssetReader` completely, while still exercising the
native `CAContext` and `AVSampleBufferDisplayLayer` path.

```bash
./dev.sh reset
./dev.sh install --snapshot-mode disabled --video-source generated
```

Then manually reselect `MacWall Native Spike` in System Settings and verify the
actual Desktop output.

Collect focused logs:

```bash
./dev.sh logs --last 3m \
  | grep -E "videoSourceMode|nativeVideoBridge enqueued|snapshotGate|WallpaperExtensionError|NSCocoaErrorDomain|interruptionHandler|invalidationHandler|runtime"
```

Interpretation:

- `videoSourceMode=generated` with smooth output: bundled mp4, `AVAssetReader`,
  asset PTS, or asset loop handling is the likely stutter source.
- `videoSourceMode=generated` with similar stutter: the issue is likely in
  `AVSampleBufferDisplayLayer` pacing, native surface scheduling, or
  WallpaperAgent runtime updates.
- Keep `--snapshot-mode disabled` during this test so snapshot/export work does
  not affect frame pacing.

## Playback Timing Verification Protocol

Run timing comparisons with the asset source, normal profile, and snapshot
probe disabled. Always reset before installing another clock mode.

Control timebase:

```bash
./dev.sh reset
./dev.sh install --snapshot-mode disabled --video-source asset --timing-clock control-timebase --timing-profile normal
```

Synchronizer:

```bash
./dev.sh reset
./dev.sh install --snapshot-mode disabled --video-source asset --timing-clock synchronizer --timing-profile normal
```

Reduced profile:

```bash
./dev.sh reset
./dev.sh install --snapshot-mode disabled --video-source asset --timing-clock synchronizer --timing-profile reduced
```

Collect focused timing and failure logs:

```bash
./dev.sh logs --last 3m \
  | grep -E "nativeVideoTiming|nativeVideoBridge asset loop|clockMode|hard-reset|asset-repeated-hard-reset|WallpaperExtensionError|NSCocoaErrorDomain"
```

For each run, manually verify natural speed, smooth playback, the loop boundary,
and Fullscreen -> Desktop behavior. Compare that observation with lead/lag,
queued/dropped frame counts, and hard-reset events in the logs before changing
the implementation.

`WallpaperExtensionError(2)` is expected while snapshot mode is `disabled`.
It belongs to the separate snapshot/export gate and does not fail playback
acceptance by itself.

To test a user-owned local video, pass an absolute path to an existing regular
file:

```bash
./dev.sh reset
./dev.sh install \
  --snapshot-mode disabled \
  --video-source asset \
  --timing-clock synchronizer \
  --timing-profile normal \
  --video-path /absolute/path/to/user-owned-video.mp4
```

The runner passes that path to CMake, which copies the file into the temporary
build resource. It does not edit or commit the original video.

## Snapshot Export Gate Protocol

The default snapshot mode is `disabled`.

Current candidate matrix:

| Mode | Current classification | WallpaperAgent result | Runtime result |
| --- | --- | --- | --- |
| `disabled` | baseline | `WallpaperExtensionError(2)` expected | video preserved |
| `error` | explicit-error probe | custom `MacWallNativeWallpaperSnapshotProbe(2001)` | video preserved |
| `empty-object` | safe-rejected | `NSCocoaErrorDomain(4101)` | video preserved |
| `raw-value-retained-iosurface` | safe-rejected | `NSCocoaErrorDomain(4101)` | video preserved |
| `box-retained-iosurface` | safe-rejected | `NSCocoaErrorDomain(4101)` | video preserved |
| `png-data` | safe-rejected | `NSCocoaErrorDomain(4101)` | video preserved |
| `file-url` | safe-rejected | PNG is written under request `cacheDirectory`, direct `NSURL` reply is rejected with `NSCocoaErrorDomain(4101)` | video preserved |
| `snapshot-xpc-file-url` | unsafe / connection-interrupting | `WallpaperSnapshotXPC.rawValue = NSURL` can trigger `NSCocoaErrorDomain(4099)`, WallpaperAgent XPC invalidation, and runtime removal | Desktop surface can disappear until reset/install/reselect |

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
./dev.sh install --snapshot-mode file-url
```

Do not use `snapshot-xpc-file-url` as a normal visual/video test mode. It is
blocked by default because the current `WallpaperSnapshotXPC.rawValue = NSURL`
shape can interrupt the WallpaperAgent XPC connection and remove the active
runtime surface. Only run it when intentionally reproducing that failure:

```bash
./dev.sh reset
./dev.sh install --snapshot-mode snapshot-xpc-file-url --allow-unsafe-snapshot-xpc
```

If the Desktop surface disappears after an unsafe candidate, return to a safe
baseline and manually reselect the wallpaper:

```bash
./dev.sh reset
./dev.sh install --snapshot-mode file-url
```

Collect logs:

```bash
./dev.sh logs --last 2m
```

Check for:

- `snapshotGate event=snapshot-request`
- `snapshotGate event=snapshot-reply`
- `shapeProbe label=acquire.request`
- `shapeProbe label=update.request`
- `shapeProbe label=snapshot.id`
- `shapeProbe classLayout`
- `WallpaperExtensionError (2)`
- `NSCocoaErrorDomain (4101)`
- `ReportCrash`
- continued `nativeVideoBridge enqueued`
- for file candidates: `snapshot request home`, `snapshot home write preflight failed`,
  `snapshot home write preflight skipped`, `snapshot home security scope`,
  `snapshot home coordinated write preflight`, `snapshot file written`

Focused shape probe log check:

```bash
./dev.sh logs --last 3m \
  | grep -E "shapeProbe|remoteContext request|cacheHomeURL|snapshotGate|snapshot request home|snapshot home security scope|snapshot home coordinated write preflight|snapshot home write preflight|WallpaperExtensionError|NSCocoaErrorDomain|nativeVideoBridge enqueued"
```

Use `disabled` first when investigating request/response shape. It avoids file
candidate work while still logging acquire, update, and snapshot request
structure.

If a candidate crashes the extension, return to:

```bash
./dev.sh reset
./dev.sh install --snapshot-mode disabled
```
