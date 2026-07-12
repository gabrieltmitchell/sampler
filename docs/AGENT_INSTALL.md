# Add Sampler With An AI Coding Agent

Open your iOS app in Cursor, Claude Code, Codex, Windsurf, or another AI coding tool. Paste this prompt:

```text
Add the Sampler visual feedback widget to this iOS app.

Requirements:
1. Add the Swift package https://github.com/gabrieltmitchell/sampler from version 0.1.2.
2. Link the Sampler package product to the main app target only.
3. Import Sampler.
4. Start Sampler once after the app UI exists.
   - SwiftUI: call Sampler.startOnce() from .onAppear on the root view inside WindowGroup.
   - UIKit: use scene(_:willConnectTo:) and call Sampler.start(in: windowScene).
5. Build both Debug and Release.

Sampler is safe to commit because it compiles to a no-op in Release builds.
Do not add the example app. Only add the Sampler library product.
```

## What The Agent Should Change

The agent should add Sampler as a Swift Package Manager dependency and add one startup call.

Prefer tagged releases for normal installs. If the app tracks branch `main`, remember Xcode pins a resolved commit in `Package.resolved`; update packages to move that pin.

SwiftUI example:

```swift
import Sampler

RootView()
    .onAppear {
        Sampler.startOnce()
    }
```

UIKit example:

```swift
import Sampler

if let windowScene = scene as? UIWindowScene {
    Sampler.start(in: windowScene)
}
```

## What Users Get

Users only link the `Sampler` library product. The demo app in this repository is for Sampler development and is not built into the user's app.

In Release builds, `Sampler.start()` and `Sampler.stop()` are empty no-ops.
