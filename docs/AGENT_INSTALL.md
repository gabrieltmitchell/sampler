# Add Sampler With An AI Coding Agent

Open your iOS app in Cursor, Claude Code, Codex, Windsurf, or another AI coding tool. Paste this prompt:

```text
Add the Sampler visual feedback widget to this iOS app.

Requirements:
1. Add the Swift package https://github.com/gabrieltmitchell/sampler from the main branch.
2. Link the Sampler package product to the main app target only.
3. Import Sampler.
4. Call Sampler.start() once when the app launches.
   - SwiftUI: use .onAppear on the root view inside WindowGroup.
   - UIKit: use scene(_:willConnectTo:) and call Sampler.start(in: windowScene).
5. Build both Debug and Release.

Sampler is safe to commit because it compiles to a no-op in Release builds.
Do not add the example app. Only add the Sampler library product.
```

## What The Agent Should Change

The agent should add Sampler as a Swift Package Manager dependency and add one startup call.

SwiftUI example:

```swift
import Sampler

RootView()
    .onAppear {
        Sampler.start()
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
