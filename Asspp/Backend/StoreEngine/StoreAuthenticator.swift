import ApplePackage
import Foundation

#if os(macOS)
    actor StoreAuthenticator {
        private var state: Data?

        init() async throws {}

        func authenticate(email: String, password: String, code: String) async throws -> ApplePackage.Account {
            let result = try await StoreEngineProcess.run(.init(operation: "login", state: state, email: email, password: password, code: code))
            state = result.state
            try Task.checkCancellation()
            try ModernStore.check(result)
            return try await persist(result)
        }

        func importAccount() async throws -> ApplePackage.Account {
            let result = try await StoreEngineProcess.run(.init(operation: "import"))
            try Task.checkCancellation()
            try ModernStore.check(result)
            return try await persist(result)
        }

        private func persist(_ result: StoreEngineResponse) async throws -> ApplePackage.Account {
            guard let account = result.account, let state = result.state else {
                throw StoreEngineError(message: "The App Store engine returned no account.")
            }
            try await ModernStore.shared.save(state, email: account.email)
            return account.publicAccount
        }
    }
#else
    typealias StoreAuthenticator = ApplePackage.Authenticator
#endif
