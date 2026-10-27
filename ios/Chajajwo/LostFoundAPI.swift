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
              sourceUrl: "https://student.snu.ac.kr/%EC%86%8C%EC%8B%9D%C2%B7%EC%95%8C%EB%A6%BC/%EA%B3%B5%EC%A7%80%EC%82%AC%ED%95%AD/?mod=document&pageid=10&uid=153", checkedOn: "2026-10-28")
    ]
}

struct LostFoundRecord: Decodable, Identifiable {
    let id: UUID
    let category: String
    let title: String
    let description: String
    let locationName: String
    let latitude: Double
    let longitude: Double
    let eventAt: String
    let custody: String?
    let centerId: String?
    let status: String
    let createdAt: String
    let mine: Bool
}

struct LostFoundClaim: Decodable, Identifiable {
    let id: UUID
    let foundId: UUID
    let foundTitle: String
    let proofNote: String
    let status: String
    let createdAt: String
}
struct LostFoundLead: Decodable {
    let requestId: UUID
    let foundId: UUID
    let foundTitle: String
    let createdAt: String
}

enum LostFoundKind: String, CaseIterable, Identifiable {
    case wallet = "지갑", electronic = "전자기기", student = "학생증", umbrella = "우산"
    case clothing = "의류", bag = "가방", key = "열쇠", other = "기타"
    var id: String { rawValue }
}
enum LostFoundType: String, Identifiable, CaseIterable {
    case found, lost
    var id: String { rawValue }
    var title: String { self == .found ? "분실물을 발견했어요" : "물건을 잃어버렸어요" }
}
struct LostFoundMapPin: Identifiable {
    enum Kind { case center, found, lost }
    let id: String
    let title: String
    let latitude: Double
    let longitude: Double
    let kind: Kind
}

@MainActor
final class LostFoundAPI: ObservableObject {
    @Published private(set) var centers = LostFoundCenter.verified
    @Published private(set) var found: [LostFoundRecord] = []
    @Published private(set) var lost: [LostFoundRecord] = []
    @Published private(set) var inbox: [LostFoundClaim] = []
    @Published private(set) var myClaims: [LostFoundClaim] = []
    @Published private(set) var leads: [LostFoundLead] = []
    @Published private(set) var loggedIn = false
    @Published var error: String?
    @Published private(set) var loading = false
    private var account = CommunityAPI()

    var configured: Bool { account.configuration != nil }
    var pins: [LostFoundMapPin] {
        centers.map { .init(id: "center:\($0.id)", title: $0.name, latitude: $0.latitude, longitude: $0.longitude, kind: .center) }
        + found.map { .init(id: "found:\($0.id.uuidString.lowercased())", title: $0.title, latitude: $0.latitude, longitude: $0.longitude, kind: .found) }
        + lost.map { .init(id: "lost:\($0.id.uuidString.lowercased())", title: $0.title, latitude: $0.latitude, longitude: $0.longitude, kind: .lost) }
    }
    func center(_ id: String) -> LostFoundCenter? { centers.first { "center:\($0.id)" == id } }
    func record(_ id: String) -> LostFoundRecord? {
        if id.hasPrefix("found:") { return found.first { "found:\($0.id.uuidString.lowercased())" == id } }
        return lost.first { "lost:\($0.id.uuidString.lowercased())" == id }
    }
    func prepare() async {
        account = CommunityAPI() // Read latest Keychain session, including sign-in from 사랑방 tab.
        await account.restore()
        loggedIn = account.authenticated
        await refresh()
    }
    func refresh() async {
        guard !loading else { return }
        loading = true; defer { loading = false }
        error = nil
        guard configured else { return }
        do {
            centers = try await account.rpc("lf_centers_list", [:], as: [LostFoundCenter].self, authenticated: false)
        } catch { self.error = "센터 데이터를 불러오지 못해 확인된 기본 정보로 표시합니다. \(error.localizedDescription)"; centers = .verified }
        guard loggedIn else { found = []; lost = []; inbox = []; myClaims = []; leads = []; return }
        do {
            async let a: [LostFoundRecord] = account.rpc("lf_found_list", [:], as: [LostFoundRecord].self)
            async let b: [LostFoundRecord] = account.rpc("lf_lost_list", [:], as: [LostFoundRecord].self)
            found = try await a; lost = try await b
            inbox = (try? await account.rpc("lf_my_claims_inbox", [:], as: [LostFoundClaim].self)) ?? []
            myClaims = (try? await account.rpc("lf_my_claims", [:], as: [LostFoundClaim].self)) ?? []
            leads = (try? await account.rpc("lf_my_leads", [:], as: [LostFoundLead].self)) ?? []
        } catch { self.error = "습득물·분실 의뢰를 불러오지 못했습니다: \(error.localizedDescription)" }
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
    func add(_ type: LostFoundType, category: String, title: String, description: String,
             building: CampusBuilding, eventAt: Date, custody: String = "finder", centerID: String? = nil) async throws {
        guard loggedIn else { throw CommunityError.message("로그인이 필요합니다.") }
        guard LostFoundRules.categories.contains(category), LostFoundRules.validTitle(title),
              LostFoundRules.validDescription(description, required: type == .lost),
              LostFoundRules.validCampusCoordinate(latitude: building.latitude, longitude: building.longitude),
              LostFoundRules.validEventDate(eventAt) else {
            throw CommunityError.message("입력한 물품 정보나 건물 위치가 올바르지 않습니다.")
        }
        let iso = ISO8601DateFormatter().string(from: eventAt)
        let common: [String: Any] = ["p_category": category, "p_title": title,
            "p_description": description, "p_location_name": building.name,
            "p_latitude": building.latitude, "p_longitude": building.longitude, "p_event_at": iso]
        var params = common
        let fn: String
        if type == .found {
            fn = "lf_found_create"
            params["p_custody"] = custody
            params["p_center_id"] = centerID ?? (NSNull() as Any)
        } else { fn = "lf_lost_create" }
        let _: UUID = try await account.rpc(fn, params, as: UUID.self)
        await refresh()
    }
    func setStatus(_ type: LostFoundType, id: UUID, status: String) async throws {
        let _: Bool = try await account.rpc(type == .found ? "lf_found_status" : "lf_lost_status",
             ["p_id":id.uuidString.lowercased(),"p_status":status],as:Bool.self)
        await refresh()
    }
    func claim(foundID: UUID, proof: String) async throws {
        guard LostFoundRules.validProof(proof) else { throw CommunityError.message("확인 내용을 10~500자로 적어주세요.") }
        let _: Bool = try await account.rpc("lf_claim_create", ["p_found_id":foundID.uuidString.lowercased(),"p_proof_note":proof],as:Bool.self)
        await refresh()
    }
    func resolveClaim(_ id: UUID, accepted: Bool) async throws {
        let _: Bool = try await account.rpc("lf_claim_resolve", ["p_claim_id":id.uuidString.lowercased(),"p_status":accepted ? "accepted":"rejected"],as:Bool.self)
        await refresh()
    }
    func link(foundID: UUID, requestID: UUID) async throws {
        let _: Bool = try await account.rpc("lf_lead_create", ["p_found_id":foundID.uuidString.lowercased(),"p_request_id":requestID.uuidString.lowercased()],as:Bool.self)
        await refresh()
    }
}
