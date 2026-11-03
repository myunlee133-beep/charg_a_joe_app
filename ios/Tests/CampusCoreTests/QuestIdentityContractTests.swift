import XCTest
@testable import CampusCore

final class QuestIdentityContractTests: XCTestCase {
    func testServerPayloadKeepsParticipationAndOwnershipSeparate() throws {
        let payload = #"{"id":"00000000-0000-4000-8000-000000000001","title":"캠퍼스 의뢰","category":"errand","mode":"firstCome","reward":3000,"place":"학생회관","building":"63동","coordinate":{"latitude":37.45925,"longitude":126.9506},"distance":120,"details":"의뢰 내용을 충분히 작성했습니다","requester":"의뢰자","participants":1,"status":"assigned","is_mine":false,"my_participation_id":"00000000-0000-4000-8000-000000000002","my_participation_status":"accepted"}"#
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        let quest = try decoder.decode(Quest.self, from: Data(payload.utf8))
        XCTAssertFalse(quest.isMine)
        XCTAssertEqual(quest.myParticipationId?.uuidString, "00000000-0000-4000-8000-000000000002")
        XCTAssertEqual(quest.myParticipationStatus, "accepted")
        XCTAssertEqual(quest.status, "assigned")
        XCTAssertTrue(quest.isValid)
    }
}
