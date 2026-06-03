# Desktop Fallback Cache Design

## Scope

Implement product phase P1 from `plans/development-roadmap.md`: reduce flashes of the existing macOS system wallpaper during Spaces and full-screen transitions by maintaining a representative PNG fallback for each supported imported library item.

This phase does not start Scene S0, add Scene audit output, extend the experimental Scene renderer, or add Metal runtime work.

## Goals

- Apply an existing desktop fallback immediately before live wallpaper playback starts.
- Generate a missing desktop fallback asynchronously after live playback starts.
- Keep live playback working when fallback application, generation, Web snapshot, or snapshot timeout fails.
- Store the fallback inside the imported asset directory at `Derived/desktop-fallback.png`.
- Expose manual Generate and Regenerate actions from each library item menu.
- Keep Web fallback capture local-only and aligned with live Web wallpaper restrictions.

## Non-Goals

- Do not use Workshop thumbnails such as `preview.gif`, `preview.jpg`, `thumbnail.jpg`, or `cover.png` as desktop fallback sources.
- Do not generate Scene fallbacks until a stable Metal Scene runtime exists.
- Do not modify the existing manual `Set Still Wallpaper` or Lock Screen still-image behavior beyond preserving compatibility.
- Do not fetch remote content, Workshop assets, or shared Scene assets.
- Do not regenerate or compare an existing desktop fallback automatically.

## Storage

The cache URL is calculated from the imported asset directory:

```swift
URL(filePath: asset.projectDirectory)
    .appending(path: "Derived")
    .appending(path: "desktop-fallback.png")
```

The implementation must not derive this path from `asset.id`. Library asset directories use encoded storage names, so the identifier and on-disk directory name can differ.

## Playback Flow

Playback is split into two independent fallback steps around live playback:

```text
Play selected asset
├─ Before live playback
│  ├─ Derived/desktop-fallback.png exists
│  │  └─ Attempt to apply it as the macOS system wallpaper immediately
│  └─ Cache missing
│     └─ Leave the current macOS system wallpaper unchanged
├─ Start live desktop playback
└─ After live playback starts
   ├─ Cache exists
   │  └─ Do not regenerate or compare it
   └─ Cache missing
      └─ Schedule one asynchronous generation task for the asset
```

Fallback application errors never block live playback. Automatic generation errors never stop live playback and never replace the current macOS system wallpaper.

Automatic generation requests are deduplicated per imported asset directory. Repeated Play actions while generation is running must reuse the existing task instead of starting a second capture. The in-flight entry is removed when the task succeeds, fails, or times out.

When asynchronous generation finishes, the PNG is always retained in the asset cache after a successful generation. The coordinator applies that new PNG as the macOS system wallpaper only when the currently playing asset still matches the generation target. If the user switched to another asset while generation was running, the completed cache remains available for the next playback but must not replace the current system wallpaper.

Every generation attempt has a monotonically increasing token for its imported asset directory. Only the newest token may atomically install a generated PNG. Removing an item, reimporting an item, or manually regenerating its fallback invalidates earlier tokens so an older asynchronous completion cannot recreate or overwrite the cache. Stopping playback or failing to start live playback clears the active asset, so later asynchronous completion may retain a valid cache but cannot change the macOS system wallpaper.

## Supported Sources

| Asset type | Automatic and manual cache source |
| --- | --- |
| Video (`mp4`, `mov`, `m4v`) | Extract a frame from the real video entrypoint at approximately `0.5s`, with a zero-time fallback if needed |
| Image | Normalize the real image entrypoint to PNG |
| Web | Snapshot a separately rendered restricted `WKWebView` |
| Convertible video (`webm`, `mkv`, `avi`) | Unsupported until conversion produces a playable MP4 |
| Scene | Unsupported in P1 |
| Thumbnail-only or unknown asset | Unsupported |

No generator path may fall back to `asset.thumbnail`.

## Components

### DesktopFallbackCoordinator

Add an app-layer coordinator responsible for cache policy and macOS system-wallpaper integration.

Responsibilities:

- Calculate the cache URL from `asset.projectDirectory`.
- Report whether a fallback cache exists.
- Apply an existing fallback before live playback without throwing into the playback path.
- Schedule missing-cache generation after live playback starts.
- Deduplicate automatic generation tasks by standardized imported project-directory path.
- Track the currently playing imported asset directory so stale asynchronous completion cannot apply a previous asset's PNG.
- Invalidate earlier generation tokens on Remove, reimport, and manual Regenerate so only the newest generation may install a PNG.
- Clear the active asset when playback stops or live playback fails to start.
- Expose manual Generate and Regenerate operations.
- Apply a newly generated PNG as the macOS system wallpaper only after generation succeeds.
- Preserve the previous PNG when manual regeneration fails by generating into a temporary sibling file and replacing atomically only after success.

Manual operation semantics:

| Operation | Existing cache | Behavior |
| --- | --- | --- |
| Generate | Missing | Generate and apply |
| Generate | Present | Reuse and apply existing cache without regeneration |
| Regenerate | Missing or present | Generate a replacement, atomically install it, and apply it |

### DesktopFallbackImageGenerator

Add a focused generator for Video and Image assets.

Responsibilities:

- Reject unsupported asset kinds without consulting thumbnails.
- Export a playable Video frame near `0.5s`.
- Normalize the real Image entrypoint into PNG data.
- Write generated data to the caller-provided temporary URL.
- Run Video extraction and Image PNG normalization outside the main actor.
- Use ImageIO and CoreGraphics for Image PNG normalization so detached work does not use `NSImage`.

### WebDesktopFallbackSnapshotter

Add a `@MainActor` snapshotter for Web assets.

Responsibilities:

- Create a dedicated `WKWebView` with the same local-only content-rule policy as live Web wallpaper playback.
- Use the current main monitor frame size as the default viewport.
- Attach the WebView to an off-screen borderless temporary `NSWindow` so WebKit renders a real viewport without becoming visible to the user.
- Load the asset entrypoint with read access limited to `asset.projectDirectory`.
- Wait for navigation `didFinish`, then wait `500ms` for stabilization.
- Capture the rendered output as PNG.
- Enforce an overall `5s` timeout.
- Close the temporary window, detach the WebView, cancel pending work, and release navigation state after success, navigation failure, content-rule failure, snapshot failure, or timeout.

### WebWallpaperContentPolicy

Extract the local-only content-rule setup currently embedded in `RestrictedWebWallpaperView` into a small shared helper.

Responsibilities:

- Provide the remote HTTP and HTTPS blocker rule.
- Compile and install the blocker into a supplied `WKUserContentController`.
- Keep live Web playback and Web fallback snapshots on the same policy path.

If blocker compilation fails, neither path loads the Web entrypoint.

### AppViewModel and ContentView

Wire coordinator operations into the app:

- Immediately before `WallpaperPlayer.shared.play`, attempt to apply an existing cache.
- Immediately after live playback starts, schedule missing-cache generation.
- Keep fallback errors out of the successful live-playback status message for automatic operations.
- Add item-specific menu commands:

```text
Show in Finder
Generate Desktop Fallback
Regenerate Desktop Fallback
Remove
```

- Show Generate when the cache is absent and Regenerate when it exists. `Show in Finder` opens the imported project directory.
- Surface manual operation success and failure through the existing status string.

## Error Handling

- Existing-cache application failure: continue starting live playback.
- Automatic Video, Image, or Web generation failure: retain live playback and preserve the current macOS system wallpaper.
- Web navigation failure, blocker compilation failure, snapshot failure, or timeout: clean up the temporary off-screen window and retain live playback.
- Manual regeneration failure: keep the previous `desktop-fallback.png` intact.
- Atomic installation failure: keep any previous cache intact where the filesystem permits and report the error for manual actions.
- Invalidated generation cleanup: remove its temporary PNG and remove only empty `Derived` or asset directories so delayed completion cannot recreate a removed library item.
- Unsupported format: do not create a PNG and report a clear message for manual actions.

## Testing Strategy

Add focused XCTest coverage before implementation code:

- Cache URL is derived from `asset.projectDirectory`, not `asset.id`.
- Existing cache is applied immediately without calling a generator.
- Missing cache schedules one asynchronous generation after live playback.
- Repeated automatic requests for the same asset deduplicate while in flight.
- Successful generation installs `Derived/desktop-fallback.png` and applies it.
- Successful stale generation installs the cache but does not apply it after playback has switched to another asset.
- Failed manual regeneration preserves the prior cache bytes.
- Image generation reads the real entrypoint and never uses the thumbnail.
- Video generation requests a frame near `0.5s`.
- Video and Image generation execute outside the main actor.
- Scene and thumbnail-only assets are rejected.
- Shared Web policy installs the same remote blocker for live playback and snapshots.
- Web snapshot configuration uses the main-screen viewport, `500ms` stabilization delay, and `5s` timeout.
- Web success, failure, and timeout paths all tear down the temporary window.
- A real local HTML integration fixture produces a non-empty PNG through the off-screen Web snapshot path.
- Stop Playback clears the active asset but preserves an existing `desktop-fallback.png` for later reuse.
- Existing scanner, library, playback, CLI, build, and packaging behavior continue to pass.

## Verification

Run:

```bash
swift test
swift build
swift run wwbctl scan test --out /tmp/workshop-wallpaper-bridge-scan.json
bash Scripts/package-app.sh
plutil -extract LSUIElement raw -o - "dist/Workshop Wallpaper Bridge.app/Contents/Info.plist"
```

Expected:

- All XCTest cases pass.
- Debug build succeeds.
- CLI scan succeeds and writes the sample index.
- Packaging succeeds.
- `LSUIElement` remains `true`.
