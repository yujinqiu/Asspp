#if os(macOS)
    import ApplePackage
    import Foundation
    import KeychainAccess

    actor ModernStore {
        static let shared = ModernStore()
        private let keychain = Keychain(service: "cn.yumyu.Asspp.StoreSessions").synchronizable(false)
        private var tail: Task<Void, Never>?
        private var generations: [String: Int] = [:]

        func save(_ state: Data, email: String) throws {
            try keychain.set(state, key: email)
            generations[email, default: 0] += 1
        }

        func remove(email: String) throws {
            generations[email, default: 0] += 1
            try keychain.remove(email)
        }

        func perform(_ request: StoreEngineRequest, email: String, progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> StoreEngineResponse {
            let previous = tail
            let task = Task {
                await previous?.value
                try Task.checkCancellation()
                let generation = generations[email, default: 0]
                guard let state = try keychain.getData(email) else {
                    throw StoreEngineError(message: String(localized: "Sign in to this account again to enable the modern App Store engine."))
                }
                var request = request
                request.state = state
                let result = try await StoreEngineProcess.run(request, progress: progress)
                guard generations[email, default: 0] == generation else { throw CancellationError() }
                if let state = result.state { try save(state, email: email) }
                try Task.checkCancellation()
                try Self.check(result)
                return result
            }
            tail = Task { _ = try? await task.value }
            return try await withTaskCancellationHandler {
                try await task.value
            } onCancel: { task.cancel() }
        }

        static func check(_ result: StoreEngineResponse) throws {
            guard let error = result.error else { return }
            if result.code == "verification_required" { throw ApplePackage.AuthenticationError.verificationCodeRequired }
            if result.code == "license_required" { throw ApplePackageError.licenseRequired }
            throw StoreEngineError(message: error)
        }

        static func platform(_ package: AppStore.AppPackage) -> String {
            (package.entityType ?? .iPhone).rawValue.lowercased()
        }

        func purchase(account: ApplePackage.Account, package: AppStore.AppPackage) async throws {
            _ = try await perform(.init(operation: "purchase", appID: package.software.id, platform: Self.platform(package)), email: account.email)
        }
    }

    extension StoreEngineResponse.Account {
        var publicAccount: ApplePackage.Account {
            .init(email: email, password: "", appleId: email, store: store, firstName: name, lastName: "", passwordToken: "", directoryServicesIdentifier: dsid, cookie: [])
        }
    }
#endif
