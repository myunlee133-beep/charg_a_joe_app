import AuthenticationServices
import Combine
import CryptoKit
import Foundation
import Security
import SwiftUI

struct AccountDetails: Decodable {
    let userId: UUID
    let nickname: String
    let role: String
    let ready: Bool
    let transactionConsent: Bool
}

struct AccountPolicy: Codable, Identifiable {
    let kind: String
    let version: String
    let title: String
    let body: String
    let sha256: String
    let context: String
    var id: String { kind + ":" + version }
    static var bundled: [Self] {
        guard let url = Bundle.main.url(forResource: "account-policies", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([Self].self, from: data)) ?? []
    }
}

private struct AccountSession: Codable {
    let accessToken: String
    let refreshToken: String
    var userId: UUID?
    var email: String?
    var expiresAt: TimeInterval?
    var isRecovery: Bool?
}

private struct EmailAuthFlow: Codable {
    let verifier: String
    let recovery: Bool
    let expiresAt: TimeInterval
    var challenge: String { Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded }
}

private struct AuthUser: Decodable { let id: UUID; let email: String? }
private struct AuthResponse: Decodable {
    let accessToken: String?
    let refreshToken: String?
    let expiresAt: TimeInterval?
    let user: AuthUser?
}

private struct AccountHTTPError: LocalizedError {
    let status: Int
    let message: String
    var errorDescription: String? { message }
}

private enum AccountKeychain {
    // Preserves sessions saved by the earlier CommunityAPI implementation.
    static let identity: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "org.chargajoe.chajajwo.community", kSecAttrAccount as String: "session"]
    static func load() -> AccountSession? {
        var query = identity
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &value) == errSecSuccess,
              let data = value as? Data else { return nil }
        return try? JSONDecoder().decode(AccountSession.self, from: data)
    }
    static func save(_ session: AccountSession) throws {
        let data = try JSONEncoder().encode(session)
        let changes: [String: Any] = [kSecValueData as String: data]
        var result = SecItemUpdate(identity as CFDictionary, changes as CFDictionary)
        if result == errSecItemNotFound {
            var item = identity
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            result = SecItemAdd(item as CFDictionary, nil)
        }
        guard result == errSecSuccess else { throw CommunityError.message("로그인 정보를 안전하게 저장하지 못했어요. 다시 시도해 주세요.") }
    }
    static func clear() { SecItemDelete(identity as CFDictionary) }
    private static var flowIdentity: [String: Any] {
        var value = identity; value[kSecAttrAccount as String] = "email-pkce-flow"; return value
    }
    static func saveFlow(_ flow: EmailAuthFlow) throws {
        let data = try JSONEncoder().encode(flow)
        let changes: [String: Any] = [kSecValueData as String: data]
        var result = SecItemUpdate(flowIdentity as CFDictionary, changes as CFDictionary)
        if result == errSecItemNotFound {
            var item = flowIdentity
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            result = SecItemAdd(item as CFDictionary, nil)
        }
        guard result == errSecSuccess else { throw CommunityError.message("이메일 인증 준비에 실패했어요. 다시 시도해 주세요.") }
    }
    static func loadFlow() -> EmailAuthFlow? {
        var query = flowIdentity
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &value) == errSecSuccess, let data = value as? Data else { return nil }
        return try? JSONDecoder().decode(EmailAuthFlow.self, from: data)
    }
    static func clearFlow() { SecItemDelete(flowIdentity as CFDictionary) }
}

/// The sole app-wide session owner. Community, lost-and-found and quests share it.
@MainActor
final class AccountStore: ObservableObject {
    static let shared = AccountStore()
    static let callbackURL = "org.chargajoe.chajajwo://auth/callback"
    @Published private(set) var authenticated = false
    @Published private(set) var details: AccountDetails?
    @Published private(set) var policies = AccountPolicy.bundled
    @Published private(set) var policiesVerified = false
    @Published private(set) var providers: [String] = []
    @Published private(set) var restoring = false
    @Published var recoveryRequired = false
    @Published var error: String?
    @Published var authFormFocused = false
    let configuration = CommunityConfiguration.current
    private var session: AccountSession? = AccountKeychain.load()
    private var refreshTask: Task<Void, Error>?
    private var restoreTask: Task<Void, Never>?
    private var generation = 0
    private let webFlow = AccountWebFlow()
    private let decoder: JSONDecoder = {
        let value = JSONDecoder(); value.keyDecodingStrategy = .convertFromSnakeCase; return value
    }()

    var userID: UUID? { authenticated ? details?.userId ?? session?.userId : nil }
    var email: String? { session?.email }
    var needsOnboarding: Bool { authenticated && details != nil && details?.ready != true }
    var profile: CommunityProfile? { details.map { .init(nickname: $0.nickname, role: $0.role) } }
    static var hasSavedSession: Bool { AccountKeychain.load() != nil }

    func request(_ path: String, method: String = "POST", json: [String: Any]? = nil,
                 authenticated: Bool = true, retry: Bool = true) async throws -> Data {
        guard let config = configuration, let url = URL(string: path, relativeTo: config.url) else {
            throw CommunityError.message("서버 연결 정보를 확인해 주세요.")
        }
        let epoch = generation
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(config.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if authenticated {
            guard let session else { throw CommunityError.message("먼저 로그인해 주세요.") }
            request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        }
        if let json { request.httpBody = try JSONSerialization.data(withJSONObject: json) }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard epoch == generation else { throw CancellationError() }
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        if http.statusCode == 401 && authenticated && retry {
            try await refresh()
            return try await self.request(path, method: method, json: json, authenticated: true, retry: false)
        }
        guard (200..<300).contains(http.statusCode) else {
            let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let code = payload?["error_code"] as? String ?? payload?["code"] as? String ?? ""
            let raw = payload?["msg"] as? String ?? payload?["message"] as? String ?? payload?["error_description"] as? String
            let message: String
            switch code {
            case "invalid_credentials": message = "이메일과 비밀번호를 확인해 주세요."
            case "email_not_confirmed": message = "이메일 인증을 먼저 완료해 주세요."
            case "over_email_send_rate_limit", "over_request_rate_limit": message = "요청이 많아요. 잠시 후 다시 시도해 주세요."
            default: message = raw ?? "요청을 처리하지 못했어요. (\(http.statusCode))"
            }
            throw AccountHTTPError(status: http.statusCode, message: message)
        }
        return data
    }

    func rpc<T: Decodable>(_ name: String, _ parameters: [String: Any] = [:], as type: T.Type, authenticated: Bool = true) async throws -> T {
        let data = try await request("/rest/v1/rpc/\(name)", json: parameters, authenticated: authenticated)
        return try decoder.decode(type, from: data)
    }

    func loadPolicies() async throws {
        let documents: [AccountPolicy] = try await rpc("account_policies", as: [AccountPolicy].self, authenticated: false)
        let expected = Set(["terms", "privacy", "overseas", "transaction", "transfer_disclosure"])
        guard Set(documents.map(\.kind)) == expected, documents.allSatisfy({ document in
            SHA256.hash(data: Data(document.body.utf8)).map { String(format: "%02x", $0) }.joined() == document.sha256
        }) else { throw CommunityError.message("약관 문서를 확인하지 못했어요. 다시 불러와 주세요.") }
        policies = documents; policiesVerified = true
    }

    func loadProviders() async {
        guard let data = try? await request("/auth/v1/settings", method: "GET", authenticated: false),
              let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let external = payload["external"] as? [String: Bool] else { return }
        providers = ["google", "apple", "kakao"].filter { external[$0] == true }
    }

    func restore() async {
        if let task = restoreTask { await task.value; return }
        guard session != nil else { return }
        let task = Task { @MainActor in
            restoring = true; defer { restoring = false }
            do {
                if (session?.expiresAt ?? 0) < Date().timeIntervalSince1970 + 60 { try await refresh() }
                try await loadAccount()
            } catch is URLError { /* Keep the saved session on a transient connection failure. */ }
              catch is CancellationError { }
              catch let failure as AccountHTTPError where [400, 401, 403].contains(failure.status) { clear() }
              catch { self.error = error.localizedDescription }
        }
        restoreTask = task
        await task.value
        restoreTask = nil
    }

    private func refresh() async throws {
        if let task = refreshTask { try await task.value; return }
        let task = Task { @MainActor in
            guard let old = session else { throw CommunityError.message("로그인이 필요해요.") }
            let data = try await request("/auth/v1/token?grant_type=refresh_token", json: ["refresh_token": old.refreshToken], authenticated: false)
            guard try updateSession(data) else { throw CommunityError.message("로그인 갱신에 실패했어요.") }
        }
        refreshTask = task
        defer { refreshTask = nil }
        try await task.value
    }

    @discardableResult private func updateSession(_ data: Data) throws -> Bool {
        let value = try decoder.decode(AuthResponse.self, from: data)
        guard let access = value.accessToken, let refresh = value.refreshToken else { return false }
        let next = AccountSession(accessToken: access, refreshToken: refresh, userId: value.user?.id ?? session?.userId,
                                  email: value.user?.email ?? session?.email, expiresAt: value.expiresAt, isRecovery: session?.isRecovery)
        try AccountKeychain.save(next)
        session = next
        return true
    }

    func loadAccount() async throws {
        // Fetch the authoritative identity; never parse a user-editable nickname as an ID.
        let userData = try await request("/auth/v1/user", method: "GET")
        let user = try decoder.decode(AuthUser.self, from: userData)
        session?.userId = user.id; session?.email = user.email
        if let session { try AccountKeychain.save(session) }
        let value: AccountDetails = try await rpc("account_me", as: AccountDetails.self)
        guard value.userId == user.id else { throw CommunityError.message("계정 정보를 확인할 수 없어요.") }
        details = value; authenticated = true
        recoveryRequired = session?.isRecovery == true
    }

    func signIn(email: String, password: String) async throws {
        generation += 1
        let data = try await request("/auth/v1/token?grant_type=password", json: ["email": email, "password": password], authenticated: false)
        guard try updateSession(data) else { throw CommunityError.message("로그인할 수 없어요.") }
        try await loadAccount()
    }

    func signUp(email: String, password: String) async throws -> Bool {
        guard policiesVerified else { throw CommunityError.message("약관을 먼저 불러와 주세요.") }
        generation += 1
        let flow = try prepareEmailFlow(recovery: false)
        let redirect = Self.callbackURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let data = try await request("/auth/v1/signup?redirect_to=\(redirect)", json: ["email": email, "password": password,
            "code_challenge": flow.challenge, "code_challenge_method": "s256"], authenticated: false)
        if try updateSession(data) { AccountKeychain.clearFlow(); try await loadAccount(); return true }
        return false
    }

    func resendConfirmation(email: String) async throws {
        let flow = try prepareEmailFlow(recovery: false)
        let redirect = Self.callbackURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        _ = try await request("/auth/v1/resend?redirect_to=\(redirect)", json: ["type": "signup", "email": email,
            "code_challenge": flow.challenge, "code_challenge_method": "s256"], authenticated: false)
    }

    func sendPasswordReset(email: String) async throws {
        let flow = try prepareEmailFlow(recovery: true)
        let redirect = Self.callbackURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        _ = try await request("/auth/v1/recover?redirect_to=\(redirect)", json: ["email": email,
            "code_challenge": flow.challenge, "code_challenge_method": "s256"], authenticated: false)
    }

    func updatePassword(_ password: String) async throws {
        _ = try await request("/auth/v1/user", method: "PUT", json: ["password": password])
        session?.isRecovery = false
        if let session { try AccountKeychain.save(session) }
        recoveryRequired = false
    }

    func signIn(provider: String) async throws {
        await loadProviders()
        guard ["google", "apple", "kakao"].contains(provider), providers.contains(provider) else {
            throw CommunityError.message("이 로그인 방법은 아직 준비 중이에요. 이메일로 이용해 주세요.")
        }
        guard let configuration else { throw CommunityError.message("서버 연결 정보를 확인해 주세요.") }
        var random = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, random.count, &random) == errSecSuccess else { throw URLError(.unknown) }
        let verifier = Data(random).base64URLEncoded
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded
        var components = URLComponents(url: configuration.url.appendingPathComponent("auth/v1/authorize"), resolvingAgainstBaseURL: false)!
        components.queryItems = [.init(name: "provider", value: provider), .init(name: "redirect_to", value: Self.callbackURL),
            .init(name: "code_challenge", value: challenge), .init(name: "code_challenge_method", value: "s256")]
        // GoTrue forwards `scope` to the provider. Its `scopes` parameter appends
        // to defaults, which would request Kakao email/image without permission.
        if provider == "kakao" { components.queryItems?.append(.init(name: "scope", value: "profile_nickname")) }
        if provider == "google" { components.queryItems?.append(.init(name: "scope", value: "openid email")) }
        let callback = try await webFlow.authenticate(components.url!)
        guard callback.scheme == "org.chargajoe.chajajwo", callback.host == "auth", callback.path == "/callback" else {
            throw CommunityError.message("인증 응답을 확인하지 못했어요. 다시 시도해 주세요.")
        }
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard let code = items.first(where: { $0.name == "code" })?.value else { throw CommunityError.message("인증을 완료하지 못했어요.") }
        generation += 1
        let data = try await request("/auth/v1/token?grant_type=pkce", json: ["auth_code": code, "code_verifier": verifier], authenticated: false)
        guard try updateSession(data) else { throw CommunityError.message("로그인할 수 없어요.") }
        try await loadAccount()
    }

    func handleCallback(_ url: URL) async {
        guard url.scheme == "org.chargajoe.chajajwo", url.host == "auth", url.path == "/callback" else { return }
        // Email links are bound to a verifier in this device's Keychain. Arbitrary
        // deep links containing someone else's access token must never switch accounts.
        guard let code = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "code" })?.value else { return }
        guard let flow = AccountKeychain.loadFlow(), flow.expiresAt > Date().timeIntervalSince1970 else {
            error = "인증을 요청한 기기에서 메일을 열어 주세요. 이메일 인증이 끝났다면 비밀번호로 로그인할 수 있어요."
            return
        }
        do {
            generation += 1
            let data = try await request("/auth/v1/token?grant_type=pkce", json: ["auth_code": code, "code_verifier": flow.verifier], authenticated: false)
            guard try updateSession(data) else { throw CommunityError.message("메일 인증을 완료하지 못했어요.") }
            session?.isRecovery = flow.recovery
            if let session { try AccountKeychain.save(session) }
            AccountKeychain.clearFlow()
            try await loadAccount()
        } catch { self.error = error.localizedDescription }
    }

    private func prepareEmailFlow(recovery: Bool) throws -> EmailAuthFlow {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw URLError(.unknown) }
        let value = EmailAuthFlow(verifier: Data(bytes).base64URLEncoded, recovery: recovery, expiresAt: Date().timeIntervalSince1970 + 3600)
        try AccountKeychain.saveFlow(value)
        return value
    }

    func completeOnboarding(nickname: String, adult: Bool) async throws {
        guard policiesVerified else { throw CommunityError.message("약관을 다시 불러와 주세요.") }
        details = try await rpc("account_complete_onboarding", ["p_nickname": nickname,
            "p_adult": adult, "p_versions": versions(context: "account")], as: AccountDetails.self)
    }

    func acceptTransactionPolicies() async throws {
        guard policiesVerified else { throw CommunityError.message("최신 거래 약관을 불러와 주세요.") }
        let _: Bool = try await rpc("account_accept_policies", ["p_versions": versions(context: "transaction"), "p_context": "transaction"], as: Bool.self)
        try await loadAccount()
    }

    func setNickname(_ nickname: String) async throws {
        let _: CommunityProfile = try await rpc("community_set_nickname", ["p_nickname": nickname], as: CommunityProfile.self)
        try await loadAccount()
    }

    func versions(context: String) -> [String: String] {
        Dictionary(uniqueKeysWithValues: policies.filter { $0.context == context }.map { ($0.kind, $0.version) })
    }

    func signOut() async {
        // Clear first: an old in-flight response must never restore the previous account.
        let old = session
        clear()
        guard let old, let config = configuration else { return }
        var request = URLRequest(url: config.url.appendingPathComponent("auth/v1/logout"))
        request.httpMethod = "POST"
        request.setValue(config.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(old.accessToken)", forHTTPHeaderField: "Authorization")
        _ = try? await URLSession.shared.data(for: request)
    }

    func deleteAccount() async throws {
        let _: Bool = try await rpc("account_delete", ["p_confirm": "찾아줘 계정 삭제"], as: Bool.self)
        clear()
    }

    private func clear() {
        generation += 1; refreshTask?.cancel(); refreshTask = nil
        session = nil; details = nil; authenticated = false; recoveryRequired = false
        AccountKeychain.clear()
        AccountKeychain.clearFlow()
    }
}

private extension Data {
    var base64URLEncoded: String { base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
}

@MainActor
private final class AccountWebFlow: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?
    func authenticate(_ url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let next = ASWebAuthenticationSession(url: url, callbackURLScheme: "org.chargajoe.chajajwo") { [weak self] url, error in
                Task { @MainActor in
                    self?.session = nil
                    if let url { continuation.resume(returning: url) }
                    else if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin { continuation.resume(throwing: CancellationError()) }
                    else { continuation.resume(throwing: error ?? CancellationError()) }
                }
            }
            next.presentationContextProvider = self
            session = next
            if !next.start() { session = nil; continuation.resume(throwing: URLError(.cannotConnectToHost)) }
        }
    }
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }
}
