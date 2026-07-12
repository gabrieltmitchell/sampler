# Use Sampler With An AI Coding Agent

This workflow lets an AI coding agent install Sampler into an iOS app for you.

It improves setup friction. It does not automatically sync annotations back to the agent. For live annotation sync, use the MCP workflow.

## When To Use This

Use this flow when you want Cursor, Claude Code, Codex, Windsurf, or another coding agent to add Sampler to your app instead of doing the Xcode wiring manually.

Good fit for:

- Existing iOS apps with an AI agent already editing the codebase
- Developers who do not want to manually edit Xcode package settings
- Teams that want the integration committed safely

## Copy-Paste Prompt

Open your iOS app in your AI coding tool and paste:

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

## What The Agent Should Do

The agent should:

1. Detect whether the app uses SwiftUI, UIKit scenes, or another launch pattern.
2. Add the Swift Package Manager dependency.
3. Link only the `Sampler` library product to the main app target.
4. Add `import Sampler`.
5. Call `Sampler.startOnce()` once after the main SwiftUI root view appears, or `Sampler.start(in:)` from UIKit scene setup.
6. Build Debug and Release.

The demo app in the Sampler repository is for Sampler development only. It should not be added to the user's app.

If the app already tracks Sampler branch `main`, check `Package.resolved`: Xcode pins a specific commit even for branch dependencies. Use **File > Packages > Update to Latest Package Versions** to move that pin when the user wants the newest widget.

## Claude Skill Flow

Claude Code users can install the Sampler skill with:

```bash
npx skills add gabrieltmitchell/sampler
```

Then run:

```text
/sampler
```

The skill performs the same install steps automatically: detect the app structure, add the package, wire `Sampler.startOnce()` or `Sampler.start(in:)`, and recommend MCP setup if the user wants live sync.

## What Users Get

After this workflow, users get the normal Sampler widget in Debug builds.

They can then use:

- The copy/paste workflow for manual agent feedback
- The MCP workflow for simulator-to-agent live sync, once configured

## Production Safety

Sampler is intended to be committed normally.

In Release builds, the public API is present but empty, so `Sampler.start()` and `Sampler.stop()` do nothing.
