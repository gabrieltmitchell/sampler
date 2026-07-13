---
name: sampler
description: Add the Sampler visual feedback widget to an iOS app
---

# Sampler Setup

Set up the Sampler visual feedback widget in this iOS project.

Sampler repository:

```text
https://github.com/gabrieltmitchell/sampler
```

Package product:

```text
Sampler
```

## Steps

1. **Check if already installed**
   - Search for `import Sampler` and `Sampler.start`.
   - If both are present and the app builds, report that Sampler is already configured and exit.

2. **Detect the app structure**
   - SwiftUI app: look for an `@main` `App` type and `WindowGroup`.
   - UIKit scene app: look for `SceneDelegate` and `scene(_:willConnectTo:options:)`.
   - Xcode project: look for `.xcodeproj/project.pbxproj`.
   - Swift package app: look for `Package.swift`.

3. **Add the Swift package**
   - Add `https://github.com/gabrieltmitchell/sampler` from version `0.1.2`.
   - Link only the `Sampler` product to the main iOS app target.
   - Do not add the example app from the Sampler repository.

4. **Wire the startup call**

   For SwiftUI apps, add Sampler at the root of the main window:

   ```swift
   import Sampler

   RootView()
       .onAppear {
           Sampler.startOnce()
       }
   ```

   For UIKit scene apps, pass the window scene explicitly:

   ```swift
   import Sampler

   if let windowScene = scene as? UIWindowScene {
       Sampler.start(in: windowScene)
   }
   ```

5. **Verify**
   - Build Debug for an iOS Simulator or device.
   - Build Release for an iOS Simulator or device.
   - Confirm Release still builds cleanly. Sampler compiles to a no-op in Release builds.

6. **Explain usage**
   - In Debug, the floating Sampler widget should appear over the app UI.
   - Users can annotate the screen, then copy/share feedback into their coding agent.
   - If MCP support is desired, run `npx -y sampler-mcp@latest init` from the app project root after the basic install succeeds, then reload MCP servers in Cursor.
   - If `npx` itself fails, try `/opt/homebrew/bin/npx -y sampler-mcp@latest init` or `npm exec --yes --package=sampler-mcp@latest -- sampler-mcp init`.
   - In Cursor projects, `sampler-mcp server` can auto-dispatch a local `cursor-agent --trust` run for new annotations. Tell users to run `sampler-mcp doctor` if the widget sends annotations but no agent appears to start, and `npx -y sampler-mcp@latest update` to check for new releases.
   - If Cursor reports `EADDRINUSE 127.0.0.1:4747`, stop the old Sampler MCP server or remove the Home/global MCP entry, then reload MCP. Prefer project-local `.cursor/mcp.json` for multiple app repos.

## Notes

- Sampler requires iOS 16+.
- Sampler is safe to commit. `Sampler.start()` and `Sampler.stop()` are empty no-ops in Release builds.
- Do not create gitignored local source files for Sampler. The intended install is a normal Swift package dependency plus one startup call.
- If the app already tracks Sampler branch `main`, Xcode may keep an older commit pinned in `Package.resolved`; update packages when the user wants the newest widget.
- Full agent instructions live in `AGENTS.md`.
