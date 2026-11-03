import Foundation
import Combine
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

/// Community data access delegates authentication to the single app account.
@MainActor
final class CommunityAPI: ObservableObject {
    private let account: AccountStore
    private var observation: AnyCancellable?
    var profile: CommunityProfile? { account.profile }
    var authenticated: Bool { account.authenticated }
    var busy: Bool { account.restoring }
    var configuration: CommunityConfiguration? { account.configuration }
    static var hasSavedSession: Bool { AccountStore.hasSavedSession }

    init(account: AccountStore? = nil) {
        self.account = account ?? .shared
        observation = self.account.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
    }
    func restore() async { await account.restore() }
    func signIn(email: String, password: String) async throws { try await account.signIn(email: email, password: password) }
    func signUp(email: String, password: String) async throws -> Bool { try await account.signUp(email: email, password: password) }
    func signOut() async { await account.signOut() }
    func setNickname(_ nickname: String) async throws { try await account.setNickname(nickname) }
    func deleteAccount() async throws { try await account.deleteAccount() }
    func rpc<T: Decodable>(_ name: String, _ parameters: [String: Any], as type: T.Type, authenticated: Bool = true) async throws -> T {
        try await account.rpc(name, parameters, as: type, authenticated: authenticated)
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
