import Foundation

struct QuestResult: Decodable, Identifiable {
    let id: UUID
    let nickname: String
    let status: String
    let resultText: String?
}

struct QuestTransaction: Decodable, Identifiable {
    let id: UUID
    let questId: UUID
    let title: String
    let amount: Int
    let status: String
    let amPayer: Bool
    let counterparty: String
    let createdAt: String
    let hasTransferDetails: Bool
    var statusTitle: String {
        switch status {
        case "awaiting_transfer": "직접 송금 대기"
        case "transfer_reported": "송금 신고 · 입금 확인 대기"
        case "received": "입금 확인 완료"
        case "disputed": "이의 확인 중"
        default: "거래 확인"
        }
    }
}

struct QuestTransferDetails: Decodable {
    let bankName: String
    let holderName: String
    let accountNumber: String
}

@MainActor
enum QuestAccountAPI {
    static func results(_ quest: Quest) async throws -> [QuestResult] {
        try await AccountStore.shared.rpc("quest_results", ["p_quest_id": quest.id], as: [QuestResult].self)
    }
    static func transactions() async throws -> [QuestTransaction] {
        try await AccountStore.shared.rpc("quest_my_transactions", as: [QuestTransaction].self)
    }
}
