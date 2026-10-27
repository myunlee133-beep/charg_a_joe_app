import Foundation
import Security
import SwiftUI

// Database access: only explicitly granted Supabase RPCs. No direct table access.
// Supabase URL and public/publishable key are configured in Info.plist at build time.
struct CommunityConfiguration {
    let url: URL
    let publishableKey: String

    static var current: CommunityConfiguration? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "COMMUNITY_SUPABASE_URL") as? String,
              let url = URL(string: raw), url.scheme == "https", url.host != nil,
              let key = Bundle.main.object(forInfoDictionaryKey: "COMMUNITY_SUPABASE_PUBLISHABLE_KEY") as? String,
              !key.isEmpty, !key.contains("YOUR_") else { return nil }
        return CommunityConfiguration(url: url, publishableKey: key)
    }
}

struct CommunityProfile: Decodable {
    let nickname: String
    let role: String
    var isModerator: Bool { role == "moderator" }
}

struct CommunityPost: Decodable, Identifiable, Equatable {
    let id: UUID
    let board: String
    let title: String
    let body: String
    let displayMode: String
    let authorDisplay: String
    let createdAt: String
    let updatedAt: String
    let tags: [String]
    let infoKind: String?
    let sourceUrl: String?
    let expiresAt: String?
    let reviewState: String
    let mine: Bool
    let isSaved: Bool
    let isLiked: Bool
    let saveCount: Int
    let likeCount: Int
    let commentCount: Int
}

struct CommunityComment: Decodable, Identifiable {
    let id: UUID
    let postId: UUID
    let body: String
    let displayMode: String
    let authorDisplay: String
    let mine: Bool
    let createdAt: String
}

struct CommunityContribution: Decodable, Identifiable {
    let postId: UUID
    let kind: String
    let title: String
    let recordedAt: String
    var id: UUID { postId }
}

struct CommunityBlock: Decodable, Identifiable {
    let id: UUID
    let createdAt: String
}

struct CommunityReport: Decodable, Identifiable {
    let id: UUID
    let postId: UUID?
    let commentId: UUID?
    let reason: String
    let createdAt: String
}

enum CommunityBoard: String, CaseIterable, Identifiable {
    case all, free, question, goodwill
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: "전체"
        case .free: "자유 이야기"
        case .question: "질문·답변"
        case .goodwill: "선의"
        }
    }
}

enum CommunityIdentity: String, CaseIterable, Identifiable {
    case anonymous, nickname
    var id: String { rawValue }
    var title: String { self == .anonymous ? "익명" : "닉네임" }
}

enum CommunityInfoKind: String, CaseIterable, Identifiable {
    case experience, study, official, practical
    var id: String { rawValue }
    var title: String {
        switch self {
        case .experience: "경험 공유"
        case .study: "학습 자료"
        case .official: "공식 정보"
        case .practical: "생활 정보"
        }
    }
}

enum CommunityError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let value): value }
    }
}

private struct CommunityAuthSession: Codable {
    let accessToken: String
    let refreshToken: String
}

private struct CommunityAuthResponse: Decodable {
    let accessToken: String?
    let refreshToken: String?
}

private enum CommunityKeychain {
    private static let service = "org.chargajoe.chajajwo.community"
    private static let account = "session"
    static func save(_ value: CommunityAuthSession) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }
    static func load() -> CommunityAuthSession? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: service,
                                kSecAttrAccount as String: account,
                                kSecReturnData as String: true,
                                kSecMatchLimit as String: kSecMatchLimitOne]
        var value: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &value) == errSecSuccess,
              let data = value as? Data else { return nil }
        return try? JSONDecoder().decode(CommunityAuthSession.self, from: data)
    }
    static func clear() {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword,
                       kSecAttrService as String: service,
                       kSecAttrAccount as String: account] as CFDictionary)
    }
}

@MainActor
final class CommunityAPI: ObservableObject {
    @Published private(set) var profile: CommunityProfile?
    @Published private(set) var authenticated = false
    @Published private(set) var busy = false

    let configuration: CommunityConfiguration?
    private var session: CommunityAuthSession?
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    init() {
        configuration = CommunityConfiguration.current
        session = CommunityKeychain.load()
    }

    private func url(_ path: String) throws -> URL {
        guard let config = configuration,
              let url = URL(string: path, relativeTo: config.url)?.absoluteURL else {
            throw CommunityError.message("커뮤니티 서버 연결 정보가 설정되지 않았어요.")
        }
        return url
    }

    private func request(_ path: String, json: [String: Any]? = nil,
                         authenticated: Bool = true, retryOnUnauthorized: Bool = true) async throws -> Data {
        guard let config = configuration else { throw CommunityError.message("Supabase 서버 연결이 필요해요.") }
        var r = URLRequest(url: try url(path))
        r.httpMethod = "POST"
        r.setValue(config.publishableKey, forHTTPHeaderField: "apikey")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if authenticated {
            guard let session else { throw CommunityError.message("먼저 로그인해 주세요.") }
            r.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        } // Auth endpoints use only the public apikey; no stale bearer token.

        if let json { r.httpBody = try JSONSerialization.data(withJSONObject: json) }
        let (data, response) = try await URLSession.shared.data(for: r)
        guard let http = response as? HTTPURLResponse else { throw CommunityError.message("서버 응답을 확인할 수 없어요.") }
        if http.statusCode == 401 && authenticated && retryOnUnauthorized {
            try await refresh()
            return try await request(path, json: json, authenticated: true, retryOnUnauthorized: false)
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                .flatMap { $0["msg"] as? String ?? $0["error_description"] as? String ?? $0["message"] as? String }
            throw CommunityError.message(message ?? "서버 요청 실패 (\(http.statusCode))")
        }
        return data
    }

    private func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        do { return try decoder.decode(type, from: data) }
        catch { throw CommunityError.message("서버 데이터 형식이 올바르지 않습니다: \(error.localizedDescription)") }
    }

    private func updateSession(_ data: Data) throws -> Bool {
        let auth = try decode(CommunityAuthResponse.self, data)
        guard let access = auth.accessToken, let refresh = auth.refreshToken else { return false }
        session = CommunityAuthSession(accessToken: access, refreshToken: refresh)
        CommunityKeychain.save(session!)
        authenticated = true
        return true
    }

    func restore() async {
        guard configuration != nil, session != nil else { return }
        do {
            try await refresh()
            profile = try await rpc("community_ensure_profile", [:], as: CommunityProfile.self)
            authenticated = true
        } catch {
            session = nil; authenticated = false; profile = nil
            CommunityKeychain.clear()
        }
    }

    private func refresh() async throws {
        guard let old = session else { throw CommunityError.message("로그인 정보가 없습니다.") }
        let data = try await request("/auth/v1/token?grant_type=refresh_token",
                                     json: ["refresh_token": old.refreshToken], authenticated: false)
        guard try updateSession(data) else { throw CommunityError.message("로그인 갱신에 실패했어요.") }
    }

    func signIn(email: String, password: String) async throws {
        let data = try await request("/auth/v1/token?grant_type=password",
                                     json: ["email": email, "password": password], authenticated: false)
        guard try updateSession(data) else { throw CommunityError.message("로그인할 수 없습니다.") }
        profile = try await rpc("community_ensure_profile", [:], as: CommunityProfile.self)
    }

    func signUp(email: String, password: String) async throws -> Bool {
        let data = try await request("/auth/v1/signup",
                                     json: ["email": email, "password": password], authenticated: false)
        if try updateSession(data) {
            profile = try await rpc("community_ensure_profile", [:], as: CommunityProfile.self)
            return true
        }
        return false // Supabase email confirmation required; sign in after verifying email.
    }

    private func clearLocalSession() {
        session = nil; authenticated = false; profile = nil
        CommunityKeychain.clear()
    }

    func signOut() async {
        if session != nil {
            _ = try? await request("/auth/v1/logout", json: [:], authenticated: true, retryOnUnauthorized: false)
        }
        clearLocalSession()
    }

    func setNickname(_ nickname: String) async throws {
        profile = try await rpc("community_set_nickname", ["p_nickname": nickname], as: CommunityProfile.self)
    }

    func deleteAccount() async throws {
        let ok: Bool = try await rpc("community_delete_account", ["p_confirm": "사랑방 계정 삭제"], as: Bool.self)
        guard ok else { throw CommunityError.message("계정을 삭제하지 못했어요.") }
        clearLocalSession()
    }

    func rpc<T: Decodable>(_ name: String, _ parameters: [String: Any], as type: T.Type, authenticated: Bool = true) async throws -> T {
        try decode(type, try await request("/rest/v1/rpc/\(name)", json: parameters, authenticated: authenticated))
    }

    func feed(board: CommunityBoard, query: String, tag: String?, savedOnly: Bool = false,
              offset: Int = 0) async throws -> [CommunityPost] {
        try await rpc("community_feed", ["p_board": board == .all ? (NSNull() as Any) : (board.rawValue as Any),
                                         "p_query": query.isEmpty ? NSNull() : query,
                                         "p_tag": tag.map { $0 as Any } ?? NSNull(),
                                         "p_saved_only": savedOnly, "p_limit": 30, "p_offset": offset],
                      as: [CommunityPost].self)
    }
    func post(_ id: UUID) async throws -> CommunityPost {
        let maybePost: CommunityPost? = try await rpc("community_post_view", ["p_post_id": id.uuidString.lowercased()], as: CommunityPost?.self)
        guard let result = maybePost else {
            throw CommunityError.message("게시물이 삭제되거나 접근할 수 없어요.")
        }
        return result
    }
    func createPost(board: CommunityBoard, title: String, body: String, identity: CommunityIdentity,
                    tags: [String], kind: CommunityInfoKind?, sourceURL: String?, expires: Date?) async throws -> CommunityPost {
        let date = expires.map { ISO8601DateFormatter().string(from: $0).prefix(10).description }
        return try await rpc("community_create_post", [
            "p_board": board.rawValue, "p_title": title, "p_body": body,
            "p_display_mode": identity.rawValue, "p_tags": tags,
            "p_info_kind": kind.map { $0.rawValue as Any } ?? NSNull(),
            "p_source_url": sourceURL.flatMap { $0.isEmpty ? nil : $0 }.map { $0 as Any } ?? NSNull(),
            "p_expires_at": date.map { $0 as Any } ?? NSNull()
        ], as: CommunityPost.self)
    }
    func deletePost(_ id: UUID) async throws {
        let ok: Bool = try await rpc("community_delete_post", ["p_post_id": id.uuidString.lowercased()], as: Bool.self)
        if !ok { throw CommunityError.message("삭제 권한이 없어요.") }
    }
    func comments(_ id: UUID) async throws -> [CommunityComment] {
        try await rpc("community_comments_list", ["p_post_id": id.uuidString.lowercased()], as: [CommunityComment].self)
    }
    func addComment(postID: UUID, body: String, identity: CommunityIdentity) async throws {
        let _: Bool = try await rpc("community_create_comment", ["p_post_id": postID.uuidString.lowercased(),
                                           "p_body": body, "p_display_mode": identity.rawValue], as: Bool.self)
    }
    func deleteComment(_ id: UUID) async throws {
        let _: Bool = try await rpc("community_delete_comment", ["p_comment_id": id.uuidString.lowercased()], as: Bool.self)
    }
    func toggleSave(_ id: UUID) async throws {
        let _: Bool = try await rpc("community_toggle_save", ["p_post_id": id.uuidString.lowercased()], as: Bool.self)
    }
    func toggleLike(_ id: UUID) async throws {
        let _: Bool = try await rpc("community_toggle_like", ["p_post_id": id.uuidString.lowercased()], as: Bool.self)
    }
    func report(postID: UUID?, commentID: UUID?, reason: String) async throws {
        let _: Bool = try await rpc("community_report", ["p_post_id": postID.map { $0.uuidString.lowercased() as Any } ?? NSNull(),
                               "p_comment_id": commentID.map { $0.uuidString.lowercased() as Any } ?? NSNull(),
                               "p_reason": reason], as: Bool.self)
    }
    func blockAuthor(of postID: UUID) async throws {
        let _: Bool = try await rpc("community_block_author", ["p_post_id": postID.uuidString.lowercased()], as: Bool.self)
    }
    func myBlocks() async throws -> [CommunityBlock] {
        try await rpc("community_my_blocks", [:], as: [CommunityBlock].self)
    }
    func unblock(_ id: UUID) async throws {
        let _: Bool = try await rpc("community_unblock", ["p_block_id": id.uuidString.lowercased()], as: Bool.self)
    }
    func myContributions() async throws -> [CommunityContribution] {
        try await rpc("community_my_contributions", [:], as: [CommunityContribution].self)
    }
    func pending() async throws -> [CommunityPost] {
        try await rpc("community_admin_pending", [:], as: [CommunityPost].self)
    }
    func review(postID: UUID, state: String, note: String = "") async throws {
        let _: Bool = try await rpc("community_admin_review", ["p_post_id": postID.uuidString.lowercased(),
                                                  "p_state": state, "p_note": note], as: Bool.self)
    }
    func reports() async throws -> [CommunityReport] {
        try await rpc("community_admin_reports", [:], as: [CommunityReport].self)
    }
    func resolveReport(_ id: UUID, hide: Bool, dismiss: Bool) async throws {
        let _: Bool = try await rpc("community_admin_resolve_report", ["p_report_id": id.uuidString.lowercased(),
                                 "p_hide": hide, "p_dismiss": dismiss], as: Bool.self)
    }
}
