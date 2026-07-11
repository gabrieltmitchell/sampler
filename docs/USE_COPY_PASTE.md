# Use Sampler With Copy And Paste

This is the simplest Sampler workflow. It works with the iOS Simulator or a physical device, and it does not require MCP, a local server, or any special agent setup.

## When To Use This

Use this flow when you want to quickly show an AI coding agent exactly what is wrong in your app UI.

Good fit for:

- One-off UI fixes
- Physical-device testing
- Teams that do not want to configure MCP
- Any coding agent that can accept pasted screenshots or text

## Setup

Add Sampler to your app and call `Sampler.start()` once at launch.

See [INSTALL.md](INSTALL.md) for the full install guide.

## Workflow

1. Run your app in a Debug build.
2. Tap the floating Sampler button.
3. Capture the current screen.
4. Add boxes, labels, and comments to the screenshot.
5. Use Copy or Share from Sampler.
6. Paste the screenshot, report, or ZIP contents into your AI coding tool.
7. Ask the agent to make the fix.

## What The Agent Receives

Depending on whether you copy or share, Sampler can provide:

- An annotated screenshot
- A Markdown report
- Structured annotation JSON
- Cropped snippet images for each marked region
- Accessibility metadata for the UI under each annotation

This gives the agent more context than a plain screenshot, especially when your app uses accessibility labels or identifiers.

## Production Safety

Sampler is safe to leave committed in your app.

In Release builds:

- `Sampler.start()` is an empty no-op.
- `Sampler.stop()` is an empty no-op.
- The overlay implementation is not compiled.

## Limitations

This flow is manual. The agent only sees the feedback after you paste or share it.

For automatic simulator-to-agent delivery, use the MCP live-sync flow.
