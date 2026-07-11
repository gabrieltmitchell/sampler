# Sampler

[![downloads](https://img.shields.io/endpoint?url=https%3A%2F%2Fraw.githubusercontent.com%2Fgabrieltmitchell%2Fsampler%2Ftraffic%2Fbadge.json)](https://github.com/gabrieltmitchell/sampler)

Sampler is a lightweight visual feedback widget for iOS apps. Add it to a local Debug build, tap the floating button, annotate the screen, and export structured feedback that helps AI coding agents understand exactly what you mean.

Sampler is local-first and debug-only. The package compiles the overlay implementation only for Debug iOS builds, and `Sampler.start()` is a no-op in Release builds.

## Install With Your AI Coding Tool

Paste this into Cursor, Claude Code, Codex, Windsurf, or another AI coding tool while it has your iOS app open:

```text
Add the Sampler visual feedback widget to my iOS app:
1. Add the Swift package https://github.com/gabrieltmitchell/sampler (from: 0.1.0) to my app target.
2. Import Sampler.
3. Call Sampler.start() once at app launch (SwiftUI: .onAppear on the root view; UIKit: scene(_:willConnectTo:)).
4. Sampler compiles to a no-op in Release builds, so this is safe to commit.
Full instructions: https://github.com/gabrieltmitchell/sampler/blob/main/AGENTS.md
```

### Claude Code Skill

Claude Code users can install the Sampler skill:

```bash
npx skills add gabrieltmitchell/sampler
```

Then run:

```text
/sampler
```

The skill detects your iOS app structure, adds the Swift package, wires `Sampler.start()`, and verifies Debug and Release builds.

## MCP Live Sync

For simulator-based direct-to-agent feedback, configure the Sampler MCP server:

```bash
npx add-mcp "npx -y sampler-mcp server"
```

Or run it manually:

```bash
npx -y sampler-mcp server
```

When `sampler-mcp` is reachable at `http://localhost:4747`, Sampler running in the iOS Simulator shows a Send to Agent button in the annotation toolbar. Tap it to send the current annotations directly to MCP-aware agents.

Useful agent prompt:

```text
Watch for Sampler annotations. When a new annotation arrives, acknowledge it, inspect the relevant code, make the fix, run the appropriate checks, and mark the annotation resolved with a short summary. Continue until I say stop.
```

## Install Manually

In Xcode, go to **File > Add Package Dependencies...** and add:

```text
https://github.com/gabrieltmitchell/sampler
```

Choose the `Sampler` package product and add it to your app target.

Then start Sampler once when your app launches:

```swift
import SwiftUI
import Sampler

@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .onAppear {
                    Sampler.start()
                }
        }
    }
}
```

For UIKit apps:

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

You may still wrap the call in `#if DEBUG` if you prefer, but Sampler already makes Release builds no-op.

## Features

- Floating iOS feedback widget for local builds
- Screenshot annotation with boxes, labels, and comments
- Accessibility metadata capture for annotated regions
- Copy annotated screenshots to the pasteboard
- Share a ZIP containing `report.md`, `annotations.json`, screenshots, and snippet images
- Zero runtime dependencies
- Release builds compile to a no-op API

## How It Works

Sampler creates a transparent overlay window above your app in Debug builds. When you tap the floating widget, it captures the current screen, lets you mark regions, and exports a report that an AI coding agent can use to identify the relevant UI and accessibility context.

The default export includes:

- `report.md` with human-readable notes and device context
- `annotations.json` with normalized annotation rectangles and matched accessibility elements
- `screenshot.png` and `annotated.png`
- `snippets/box-N.png` crops for each annotation

## Requirements

- iOS 16+
- Swift Package Manager
- Swift 5.9+
- Xcode 15+

## Example

Open `Example/SamplerExample.xcodeproj` and run the `SamplerExample` scheme on an iOS Simulator or device.

## Security Notes

Sampler runs inside your local app build. By default, it does not send data anywhere. Exports are created locally through the pasteboard or iOS share sheet.

The overlay implementation is compiled only for Debug iOS builds. In Release builds, `Sampler.start()` and `Sampler.stop()` are empty methods.

## License

MIT
