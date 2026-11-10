#if os(macOS)
    import Foundation

    extension Downloads {
        func resumeStoreEngine(_ request: PackageManifest) {
            engineDownloads.removeValue(forKey: request.id)?.task.cancel()
            let token = UUID()
            request.state.status = .downloading
            let task = Task {
                let staging = temporaryDirectory.appendingPathComponent("store-\(request.id).ipa")
                defer {
                    let current = engineDownloads[request.id]?.token
                    if current == nil || current == token {
                        if request.completed || request.state.status == .failed || !manifests.contains(where: { $0.id == request.id }) {
                            try? FileManager.default.removeItem(at: staging)
                            try? FileManager.default.removeItem(atPath: staging.path + ".tmp")
                        }
                    }
                    if current == token {
                        engineDownloads.removeValue(forKey: request.id)
                        storeEngineStateDidChange()
                    }
                }
                do {
                    _ = try await ModernStore.shared.perform(.init(
                        operation: "download", appID: request.package.software.id,
                        platform: ModernStore.platform(request.package), versionID: request.package.externalVersionID,
                        output: staging.path,
                    ), email: request.account.id) { fraction in
                        Task { @MainActor in
                            guard self.engineDownloads[request.id]?.token == token, request.state.status == .downloading else { return }
                            request.state.percent = fraction
                        }
                    }
                    try Task.checkCancellation()
                    guard engineDownloads[request.id]?.token == token else { return }
                    try StorePackageValidator.validate(at: staging, package: request.package)
                    try FileManager.default.createDirectory(at: request.targetLocation.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try? FileManager.default.removeItem(at: request.targetLocation)
                    try FileManager.default.moveItem(at: staging, to: request.targetLocation)
                    request.state.complete()
                } catch {
                    guard engineDownloads[request.id]?.token == token else { return }
                    if error is CancellationError { request.state.status = .paused }
                    else { request.state.error = error.localizedDescription }
                }
            }
            engineDownloads[request.id] = (token, task)
            storeEngineStateDidChange()
        }
    }
#endif
