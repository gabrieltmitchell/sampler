# Install Sampler

Sampler is designed to be installed by either an iOS developer or the AI coding tool already working in the app.

## Fastest Option: Paste This Into Your AI Coding Tool

Open your iOS app in Cursor, Claude Code, Codex, Windsurf, or another coding agent, then paste:

```text
Add the Sampler visual feedback widget to my iOS app:
1. Add the Swift package https://github.com/gabrieltmitchell/sampler from version 0.1.2 to my app target.
2. Import Sampler.
3. Start Sampler once after the root UI appears (SwiftUI: Sampler.startOnce() in .onAppear; UIKit: scene(_:willConnectTo:)).
4. Sampler compiles to a no-op in Release builds, so this is safe to commit.
Full instructions: https://github.com/gabrieltmitchell/sampler/blob/main/AGENTS.md
```

The agent should add the package, wire up the startup call, and build Debug and Release.

## Claude Code Skill

Claude Code users can install Sampler's setup skill:

```bash
npx skills add gabrieltmitchell/sampler
```

Then run:

```text
/sampler
```

The skill detects your iOS app structure, adds the Swift package, wires `Sampler.start()`, and verifies Debug and Release builds.

## MCP Live Sync

If you want simulator annotations to go directly to your coding agent, configure the Sampler MCP server:

```bash
npx add-mcp "npx -y sampler-mcp@latest server --project ."
```

Or run the server manually:

```bash
npx -y sampler-mcp@latest server --project .
```

The server listens on `http://localhost:4747`. When Sampler is running in the iOS Simulator and the server is reachable, the annotation toolbar shows a Send to Agent button. In Cursor projects, new annotations can auto-dispatch a local `cursor-agent` run; use `sampler-mcp doctor` if sends succeed but no agent appears to start.

## Manual Xcode Install

1. Open your app in Xcode.
2. Choose **File > Add Package Dependencies...**.
3. Enter `https://github.com/gabrieltmitchell/sampler`.
4. For the dependency rule, choose **Up to Next Major Version** from `0.1.2`.
5. Choose the `Sampler` package product.
6. Add it to your main app target.
7. Call `Sampler.startOnce()` after your root SwiftUI view appears, or `Sampler.start(in:)` from a UIKit scene.

SwiftUI example:

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

UIKit scene example:

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

## What You Should See

Run your app in Debug on an iOS Simulator or device. A floating Sampler button should appear over your UI. Tap it to capture the current screen and start annotating.

## Updating Sampler

For normal installs, prefer tagged releases such as `0.1.2` with Xcode's **Up to Next Major Version** rule. If you track branch `main`, Xcode still pins a specific commit in `Package.resolved`; a plain resolve may keep using that older commit. Use **File > Packages > Update to Latest Package Versions** when you want the newest widget code.

To check a stale branch pin, compare the Sampler revision in `Package.resolved` with:

```bash
git ls-remote https://github.com/gabrieltmitchell/sampler refs/heads/main
```

## Will This Ship To Production?

Sampler is safe to commit.

In Release builds:

- `Sampler.start()` is an empty no-op.
- `Sampler.stop()` is an empty no-op.
- The overlay implementation is not compiled.

You can still wrap the call in `#if DEBUG` if your team prefers that style:

```swift
#if DEBUG
Sampler.startOnce()
#endif
```

## Do I Need To Gitignore Anything?

No. The intended install is a normal Swift package dependency plus one startup call. There is no generated local widget file that needs to be ignored.

## How Do I Remove Sampler?

1. Remove `import Sampler`.
2. Remove `Sampler.start()`.
3. Remove the `Sampler` package product from your app target.
4. Remove the package dependency if no other target uses it.

## Troubleshooting

If the widget does not appear:

- Confirm you are running a Debug build.
- Confirm the `Sampler` package product is linked to the app target.
- Confirm `Sampler.startOnce()` is called after the main SwiftUI root view appears, or `Sampler.start(in:)` is called with a real UIKit scene.
- If you track branch `main`, remember Xcode pins a commit in `Package.resolved`; use **File > Packages > Update to Latest Package Versions** to move to the newest widget code.
- For multi-scene UIKit apps, prefer `Sampler.start(in: windowScene)`.
