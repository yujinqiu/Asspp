# Changelog

## 4.3.0 - 2026-11-10

### Features

- Bundle a modern ipatool engine in the Apple Silicon Mac app, including native Apple authentication, AMD provisioning and the restore-image HTTP 403 fix.
- Add explicit import of an existing local ipatool login and account sign-in from the graphical interface.
- Store each account's session in a separate local Keychain entry. Download manifests contain public account metadata only.
- Route Mac downloads, free-license acquisition and version history through the bundled engine. Preserve paused downloads for HTTP range resume.

### Fixes

- Include app version and platform when reusing downloaded packages, so updates cannot select an older cached release.
- Use the shared version configuration for the Mac app's displayed version.
- Preserve local signing configuration during packaging and include the engine's MIT license in the app.

### Distribution

- macOS 15 or newer on Apple Silicon. The iOS app is outside this fork's release scope.
- The ZIP is ad-hoc signed. Developer ID signing and notarization are not configured.
- Based on Lakr233/Asspp; the bundled engine uses majd/ipatool commit `f137223276dd`.
