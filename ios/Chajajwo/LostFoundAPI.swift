import Foundation
import SwiftUI

// Public centers use a bundled fallback until the new Supabase migration is applied.
// Official facility information is never inferred from user-submitted found-item posts.
struct LostFoundCenter: Decodable, Identifiable {
    let id: String
    let name: String
    let building: String
    let room: String
    let latitude: Double
    let longitude: Double
    let phone: String?
    let weekdayHours: String?
    let weekendHolidayNote: String
    let custodyNote: String
    let sourceUrl: String
    let checkedOn: String

    static let verified: [LostFoundCenter] = [
        .init(id: "snu101", name: "서울대학교 분실물센터", building: "101동 아시아연구소", room: "1층 캠퍼스안전반",
              latitude: 37.46328, longitude: 126.95015, phone: "02-880-8114", weekdayHours: "평일 09:00~18:00",
              weekendHolidayNote: "토·일요일 및 공휴일 분실물 접수·수령 운영은 사전 전화 확인",
              custodyNote: "공식 분실물센터. 캠퍼스안전반 당직은 24시간 운영하지만 분실물센터 수령 시간과 다릅니다.",
              sourceUrl: "https://sees.snu.ac.kr/community/notice?bbsidx=17914&md=v", checkedOn: "2026-10-28"),
        .init(id: "snu67", name: "두레문예관 학생지원센터 임시 보관처", building: "67동 두레문예관", room: "201호 학생지원센터",
              latitude: 37.46353, longitude: 126.94973, phone: nil, weekdayHours: nil,
              weekendHolidayNote: "운영시간·휴무일 공식 확인 불가: 방문 전 담당 부서에 확인",
              custodyNote: "67동 내 습득물만 2영업일 임시 보관하고 101동 분실물센터로 이관합니다.",
              sourceUrl: "https://student.snu.ac.kr/%EC%86%8C%EC%8B%9D%C2%B7%EC%95%8C%EB%A6%BC/%EA%B3%B5%EC%A7%80%EC%82%AC%ED%95%AD/?mod=document&pageid=10&uid=153", checkedOn: "2026-10-28"),
        .init(id: "snu331", name: "서울대 셔틀버스 분실물 보관소", building: "331동 차량정비고", room: "차량고 보관처 · 방문 전 확인",
              latitude: 37.44937, longitude: 126.95014, phone: nil, weekdayHours: nil,
              weekendHolidayNote: "현재 운영시간·휴무일 미확인: 셔틀버스 담당 부서에 방문 전 확인",
              custodyNote: "2014년 공식 안내의 셔틀버스 습득물 임시 보관처입니다. 당시에는 해당 주간 차량고 보관 후 학생지원센터로 이관했으며 현재 보관처·이관 일정은 재확인이 필요합니다.",
              sourceUrl: "https://aerospace.snu.ac.kr/board/notice?bbsidx=23230&bm=v", checkedOn: "2026-10-31")
    ]
}

struct LostFoundRecord: Decodable, Identifiable {
    let id: UUID
    let source: String
    let sourceId: String?
    let category: String
    let title: String
    let description: String
    let locationName: String
    let latitude: Double
    let longitude: Double
    let registeredAt: String
    let status: String
    let photoUrl: String?
    let photoBase64: String?
    let mine: Bool
    var eventAt: String { registeredAt }
    var createdAt: String { registeredAt }
    var sourceTitle: String { LostFoundRules.registrantTitle(source: source) }
    var storage: LostFoundStorage { .classify(location: locationName, status: status) }
    var statusTitle: String {
        switch status { case "received": "수령 완료"; case "police": "경찰서 이관"; default: "보관 중" }
    }
}

struct LostFoundClaim: Decodable, Identifiable {
    let id: UUID
    let itemId: UUID
    let title: String
    let proof: String
    let status: String
    let mine: Bool
    let canVerify: Bool
    let createdAt: String
    var statusTitle: String {
        switch status {
        case "pending": "소유자 확인 대기"
        case "accepted": "소유자 확인됨 · 수령 결과를 남겨주세요"
        case "rejected": "소유자 확인 거절"
        case "received": "수령 완료"
        case "not_mine": "내 물건이 아니에요"
        case "not_received": "수령하지 않았어요"
        default: status
        }
    }
}

enum LostFoundKind: String, CaseIterable, Identifiable {
    case wallet = "지갑", electronic = "전자기기", student = "학생증", umbrella = "우산"
    case clothing = "의류", bag = "가방", key = "열쇠", other = "기타"
    var id: String { rawValue }
}
enum LostFoundType: String, Identifiable, CaseIterable {
    case found, lost
    var id: String { rawValue }
    var title: String { "습득물 등록" }
}
struct LostFoundMapPin: Identifiable {
    enum Kind { case center, found, lost }
    let id: String
    let title: String
    let latitude: Double
    let longitude: Double
    let kind: Kind
    let count: Int
    init(id: String, title: String, latitude: Double, longitude: Double, kind: Kind, count: Int = 1) {
        self.id = id; self.title = title; self.latitude = latitude; self.longitude = longitude
        self.kind = kind; self.count = count
    }
}

@MainActor
final class LostFoundAPI: ObservableObject {
    @Published private(set) var centers = LostFoundCenter.verified
    @Published private(set) var found: [LostFoundRecord] = []
    @Published private(set) var claims: [LostFoundClaim] = []
    @Published private(set) var loggedIn = false
    @Published var error: String?
    @Published private(set) var loading = false
    private var account = CommunityAPI()

    var configured: Bool { account.configuration != nil }
    var isModerator: Bool { account.profile?.isModerator == true }
    var lost: [LostFoundRecord] { [] } // Legacy map signature; there are no lost-request records.
    var inbox: [LostFoundClaim] { claims.filter(\.canVerify) }
    var myClaims: [LostFoundClaim] { claims.filter(\.mine) }
    var pins: [LostFoundMapPin] {
        centers.map { .init(id: "center:\($0.id)", title: $0.name, latitude: $0.latitude, longitude: $0.longitude, kind: .center) }
        + found.filter { $0.status == "stored" || $0.status == "police" }.map {
            .init(id: "found:\($0.id.uuidString.lowercased())", title: $0.title, latitude: $0.latitude, longitude: $0.longitude, kind: .found)
        }
    }
    func center(_ id: String) -> LostFoundCenter? { centers.first { "center:\($0.id)" == id } }
    func record(_ id: String) -> LostFoundRecord? {
        found.first { "found:\($0.id.uuidString.lowercased())" == id || $0.id.uuidString.lowercased() == id.lowercased() }
    }
    private var loadedAt = Date.distantPast
    private var preparing = false

    /// 홈·분실물 탭에 들어올 때마다 불린다. 1분 안에 받았고 로그인 상태(사랑방 탭 로그인 포함)가 그대로면 건너뛴다.
    /// 새로고침 버튼·당겨서 새로고침은 force.
    func prepare(force: Bool = false) async {
        guard !preparing,
              force || Date().timeIntervalSince(loadedAt) > 60 || loggedIn != CommunityAPI.hasSavedSession else { return }
        preparing = true; defer { preparing = false }
        account = CommunityAPI() // Read latest Keychain session, including sign-in from 사랑방 tab.
        await account.restore()
        loggedIn = account.authenticated
        await refresh()
        if error == nil && loggedIn == CommunityAPI.hasSavedSession { loadedAt = Date() } // 실패하면 다음 진입 때 다시 받는다
    }
    func refresh() async {
        guard !loading else { return }
        loading = true; defer { loading = false }
        error = nil
        guard configured else { found = []; claims = []; error = "서버 설정이 없어 습득물 목록을 불러올 수 없습니다."; return }
        do {
            centers = try await account.rpc("lf_centers_list", [:], as: [LostFoundCenter].self, authenticated: false)
        } catch { self.error = "센터 데이터를 불러오지 못해 확인된 기본 정보로 표시합니다. \(error.localizedDescription)"; centers = LostFoundCenter.verified }
        guard loggedIn else { found = []; claims = []; return }
        do {
            found = try await account.rpc("lf_items_list", [:], as: [LostFoundRecord].self)
            claims = try await account.rpc("lf_claims_list", [:], as: [LostFoundClaim].self)
        } catch { self.error = "습득물 정보를 불러오지 못했습니다: \(error.localizedDescription)" }
    }
    func signIn(email: String, password: String) async throws {
        try await account.signIn(email: email, password: password)
        loggedIn = true
        await refresh()
    }
    func signUp(email: String, password: String) async throws -> Bool {
        let active = try await account.signUp(email: email, password: password)
        loggedIn = active
        if active { await refresh() }
        return active
    }
    func detail(_ id: UUID) async throws -> LostFoundRecord {
        guard loggedIn else { throw CommunityError.message("로그인이 필요합니다.") }
        return try await account.rpc("lf_item_detail", ["p_item_id": id.uuidString.lowercased()], as: LostFoundRecord.self)
    }
    func add(category: String, title: String, description: String, locationName: String,
             latitude: Double, longitude: Double, photo: Data?) async throws {
        guard loggedIn else { throw CommunityError.message("로그인이 필요합니다.") }
        guard LostFoundRules.categories.contains(category), LostFoundRules.validTitle(title),
              LostFoundRules.validDescription(description, required: false),
              LostFoundRules.validLocation(locationName),
              LostFoundRules.validCampusCoordinate(latitude: latitude, longitude: longitude),
              LostFoundRules.validPhoto(photo) else {
            throw CommunityError.message("입력한 물품 정보나 건물 위치가 올바르지 않습니다.")
        }
        let params: [String: Any] = ["p_category": category, "p_title": title,
            "p_description": description, "p_location_name": locationName,
            "p_latitude": latitude, "p_longitude": longitude,
            "p_photo_base64": photo.map { $0.base64EncodedString() as Any } ?? NSNull()]
        let _: UUID = try await account.rpc("lf_item_create", params, as: UUID.self)
        await refresh()
    }
    func claim(foundID: UUID, proof: String) async throws {
        guard LostFoundRules.validProof(proof) else { throw CommunityError.message("확인 내용을 10~500자로 적어주세요.") }
        let _: UUID = try await account.rpc("lf_claim_interest", ["p_item_id":foundID.uuidString.lowercased(), "p_proof":proof.trimmingCharacters(in: .whitespacesAndNewlines)], as:UUID.self)
        await refresh()
    }
    func resolveClaim(_ id: UUID, accepted: Bool) async throws {
        let ok: Bool = try await account.rpc("lf_claim_verify", ["p_claim_id":id.uuidString.lowercased(), "p_is_owner":accepted], as:Bool.self)
        guard ok else { throw CommunityError.message("확인 권한이나 요청 상태가 변경되었습니다. 새로고침해 주세요.") }
        await refresh()
    }
    func completeClaim(_ id: UUID, outcome: String) async throws {
        guard ["received", "not_mine", "not_received"].contains(outcome) else { throw CommunityError.message("수령 결과가 올바르지 않습니다.") }
        let ok: Bool = try await account.rpc("lf_claim_complete", ["p_claim_id":id.uuidString.lowercased(), "p_outcome":outcome], as:Bool.self)
        guard ok else { throw CommunityError.message("수령 결과를 저장하지 못했습니다. 요청 상태를 확인해 주세요.") }
        await refresh()
    }
    func transfer(_ id: UUID, locationName: String, latitude: Double, longitude: Double) async throws {
        guard LostFoundRules.validLocation(locationName),
              LostFoundRules.validCoordinate(latitude: latitude, longitude: longitude) else {
            throw CommunityError.message("경찰서 이름과 실제 위치를 정확히 입력해 주세요.")
        }
        let ok: Bool = try await account.rpc("lf_item_transfer", ["p_item_id":id.uuidString.lowercased(),
            "p_location_name":locationName, "p_latitude":latitude, "p_longitude":longitude], as:Bool.self)
        guard ok else { throw CommunityError.message("이관 권한이나 물품 상태가 변경되었습니다.") }
        await refresh()
    }
}
