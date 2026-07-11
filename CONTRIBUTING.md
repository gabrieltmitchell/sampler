# Contributing

Thanks for helping improve Sampler.

## Local Checks

Run the Swift package checks:

```bash
swift package dump-package
swift build
swift build -c release
```

Build the example app:

```bash
xcodebuild \
  -project Example/SamplerExample.xcodeproj \
  -scheme SamplerExample \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  build
```

Run the MCP package checks:

```bash
cd mcp
npm install
npm run typecheck
npm run build
node dist/index.js doctor --store /tmp/sampler-mcp-doctor
```

## Release Process

Sampler uses semantic version tags so Swift Package Manager installs can pin releases with `from:`.

1. Update docs if install instructions changed.
2. Run the local checks above.
3. Commit the release changes.
4. Tag the release:

   ```bash
   git tag 0.1.1
   git push origin main
   git push origin 0.1.1
   ```

5. Confirm the README examples still use the latest intended version.

## Package Layout

- `Sources/Sampler/` contains the Swift package.
- `Example/SamplerExample.xcodeproj` is only for local development and demos.
- `mcp/` contains the `sampler-mcp` TypeScript package.
- `skills/sampler/SKILL.md` contains the Claude Code setup skill.
- `docs/` contains user-facing workflow guides.

## Production Safety

Keep all Sampler runtime behavior behind the existing `DEBUG && os(iOS)` guards. Release builds should retain no-op `Sampler.start()` and `Sampler.stop()` behavior.
