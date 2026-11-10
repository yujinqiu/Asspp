# Bundled App Store engine

This Go module accepts one JSON request on stdin and emits newline-delimited JSON progress/result events on stdout. A process handles one request and exits. There are no network listeners, credential arguments, shell commands, or automatic account discovery.

Swift `ModernStore` serializes operations and stores the opaque returned state in a separate local Keychain entry for each account. State contains Store tokens, AMD provisioning and cookies. The Go keychain is memory-only; the original Apple password is removed before returning a session. Account replacement or deletion invalidates in-flight state writes.

Operations include login, explicit import of the existing ipatool session, account inspection, free-license acquisition, official package download, version history and version metadata. Import only reads the original ipatool Keychain/cookie storage. Authentication and signing use the pinned upstream library; this module does not implement Apple's algorithms.

Downloads report progress, receive cancellation through SIGTERM/context and preserve upstream HTTP range validation. Swift validates package identity/platform before final placement and keeps partial files for paused downloads.

Build with `go build -trimpath`. `Resources/Scripts/build.store-engine.sh` embeds the result in `Asspp.app/Contents/Helpers`. CI pins dependencies with go.mod/go.sum and runs `go test -race ./...`. Never print or commit a real helper response: opaque state is private authentication data.

Upstream: https://github.com/majd/ipatool (MIT). The pinned commit includes local modern authentication and the restore-image User-Agent compatibility fix.
