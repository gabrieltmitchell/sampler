# Sampler Agent Install Instructions

Use these instructions when a user asks you to add Sampler to an iOS app.

Sampler repository:

```text
https://github.com/gabrieltmitchell/sampler
```

Package product:

```text
Sampler
```

Minimum platform:

```text
iOS 16.0
```

## Goal

Add Sampler so the app shows a local visual feedback widget in Debug builds. Sampler's package implementation compiles to an empty no-op API in Release builds, so committing the integration is safe.

## Install Steps

1. Add the Swift package dependency `https://github.com/gabrieltmitchell/sampler` from version `0.1.2` to the app.
2. Link the `Sampler` product to the app target, not a test target or extension target.
3. Import `Sampler`.
4. Call `Sampler.startOnce()` once after the root SwiftUI view appears, or `Sampler.start(in:)` from a UIKit scene.
5. Build the app for Debug and Release.

## SwiftUI Apps

Prefer the root `App` or the first root view inside `WindowGroup`.

```swift
import SwiftUI
import Sampler

@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .onAppear {
                    Sampler.startOnce()
                }
        }
    }
}
```

If the app already has a root view startup hook, add `Sampler.startOnce()` there instead of creating a duplicate lifecycle path.

## UIKit Apps

Prefer `SceneDelegate` when the app uses scenes:

```swift
import UIKit
import Sampler

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        if let windowScene = scene as? UIWindowScene {
            Sampler.start(in: windowScene)
        }
    }
}
```

For older app delegate setups without scenes, call `Sampler.start()` after the main window is key and visible.

## Xcode Project Files

If editing an `.xcodeproj` directly:

- Add a Swift package reference for `https://github.com/gabrieltmitchell/sampler` using version `0.1.2` or newer.
- Add an `XCSwiftPackageProductDependency` with `productName = Sampler`.
- Add the product dependency to the app target's `packageProductDependencies`.
- Add the package product to the app target's Frameworks build phase.

Do not add Sampler to production extension targets unless the user specifically asks.

## Package.swift Apps

If the app is managed by `Package.swift`, add Sampler as a dependency and target dependency:

```swift
.package(url: "https://github.com/gabrieltmitchell/sampler", from: "0.1.2")
```

```swift
.product(name: "Sampler", package: "sampler")
```

## Production Safety

Do not create gitignored local source files for Sampler. The intended setup is committed normally.

Sampler has a Release no-op API:

- `Sampler.start()` does nothing in Release builds.
- `Sampler.stop()` does nothing in Release builds.
- The overlay implementation is only compiled for `DEBUG && os(iOS)`.

Adding an extra call-site guard is optional:

```swift
#if DEBUG
Sampler.start()
#endif
```

Use the guard only if it fits the existing code style or if the user explicitly wants the import/call excluded from Release source paths too.

## Verification

After installing:

1. Build Debug for an iOS Simulator or device.
2. Build Release for an iOS Simulator or device.
3. Run Debug and confirm the floating Sampler widget appears.
4. Confirm there are no new warnings about missing package products or unresolved imports.

## Optional MCP Live Sync

If the user wants simulator annotations to go directly to their coding agent, configure Sampler MCP after the basic package install succeeds. Run this from the app project root; it writes `.cursor/mcp.json` itself and automatically picks a working `npx` or `npm exec` command form (so a broken npx shim does not require manual debugging):

```bash
npx -y sampler-mcp@latest init
```

Then reload MCP servers in Cursor (Settings > MCP) or restart Cursor. Do not hand-edit `mcp.json` or probe ports unless `init` fails.

Preflight check:

```bash
npx -y sampler-mcp@latest doctor --project .
```

To update later (new sampler-mcp release or new widget release):

```bash
npx -y sampler-mcp@latest update
```

This prints the running vs latest npm version, the app's resolved Sampler Swift package pin vs the latest release tag, and the exact update steps. Because `init` configures the server as `sampler-mcp@latest`, restarting the MCP in Cursor picks up new server releases automatically.

The MCP server listens on `http://localhost:4747`. When Sampler is running in the iOS Simulator and the server is reachable, the annotation toolbar shows a Send to Agent button.

In Cursor projects, `sampler-mcp server` auto-dispatches a local `cursor-agent` run for new annotations when the Cursor CLI is installed and signed in. The widget shows one persistent status toast while the agent works, including progress such as "Making code changes..." and "Rebuilding app...", then the final resolution summary.

Useful watch-mode prompt for MCP clients without auto-dispatch:

```text
Watch for Sampler annotations. When a new annotation arrives, acknowledge it, inspect the relevant code, make the fix, run the appropriate checks, and mark the annotation resolved with a short summary. Continue until I say stop.
```

If an app tracks branch `main`, Xcode still pins a resolved commit in `Package.resolved`. Use **File > Packages > Update to Latest Package Versions** to move the pin, or compare the resolved revision with `git ls-remote https://github.com/gabrieltmitchell/sampler refs/heads/main`.

## Removal

To remove Sampler:

1. Delete the `import Sampler` line.
2. Delete the `Sampler.start()` call.
3. Remove the `Sampler` package product from the app target.
4. Remove the package dependency if no targets use it.
