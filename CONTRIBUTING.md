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

## Swift Widget Release Process

Sampler uses semantic version tags so Swift Package Manager installs can pin releases with `from:`.

1. Update the widget version shown in the settings sheet:

   ```bash
   scripts/release-widget-version 0.2.1
   ```

2. Update docs if install instructions changed.
3. Run the local checks above.
4. Commit the release changes.
5. Tag the release:

   ```bash
   git tag 0.2.1
   git push origin main
   git push origin 0.2.1
   ```

6. Confirm the README examples still use the latest intended version.

## MCP npm Release Process

`sampler-mcp` has its own npm version. npm-only fixes do not need to change `Sampler.version` unless the Swift/iOS widget package changed too.

```bash
cd mcp
npm version 0.2.1 --no-git-tag-version
npm run typecheck
npm run build
npm publish --access public
```

## Package Layout

- `Sources/Sampler/` contains the Swift package.
- `Example/SamplerExample.xcodeproj` is only for local development and demos.
- `mcp/` contains the `sampler-mcp` TypeScript package.
- `skills/sampler/SKILL.md` contains the Claude Code setup skill.
- `docs/` contains user-facing workflow guides.

## Production Safety

Keep all Sampler runtime behavior behind the existing `DEBUG && os(iOS)` guards. Release builds should retain no-op `Sampler.start()` and `Sampler.stop()` behavior.
