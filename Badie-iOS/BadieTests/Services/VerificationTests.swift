import XCTest
@testable import Badie

/// 高水平认证：证据链接检查、档位范围、人工审核后的显示
@MainActor
final class VerificationTests: XCTestCase {

    private func makeBackend() -> MockBackend {
        let backend = MockBackend(store: .inMemory)
        backend.latencyEnabled = false
        backend.simulationEnabled = false
        backend.createAccount(phone: "+16265550123", nickname: "阿杰", level: 6, seedsDemoContent: false)
        return backend
    }

    func testBwfEvidenceMustBePlayerPage() {
        XCTAssertNil(VerificationEvidence.problem(with: "bwfbadminton.com/player/57945/demo-player", for: .bwf))
        XCTAssertNil(VerificationEvidence.problem(with: "https://bwf.tournamentsoftware.com/player-profile/abc-123", for: .bwf))
        XCTAssertNotNil(VerificationEvidence.problem(with: "https://bwfbadminton.com/rankings/", for: .bwf), "排名总表不算")
        XCTAssertNotNil(VerificationEvidence.problem(with: "https://example.com/player/1", for: .bwf), "必须是 BWF 官网")
        XCTAssertNotNil(VerificationEvidence.problem(with: "http://bwfbadminton.com/player/1/x", for: .bwf), "只接受 https")
        XCTAssertNil(VerificationEvidence.problem(with: "https://usab.tournamentsoftware.com/sport/player.aspx?id=1", for: .tournament))
        XCTAssertNotNil(VerificationEvidence.problem(with: "https://instagram.com/me", for: .tournament))
    }

    func testClaimMustFitEvidenceKind() throws {
        let backend = makeBackend()
        XCTAssertThrowsError(try backend.submitVerification(
            kind: .tournament, tier: SkillTier(level: 8, modifier: .plus), evidenceURL: "https://usab.tournamentsoftware.com/x",
            nameOnRecord: "Jie Wang"
        ), "赛果最多认证到 8")
        XCTAssertThrowsError(try backend.submitVerification(
            kind: .bwf, tier: SkillTier(level: 9), evidenceURL: "https://bwfbadminton.com/player/1/x", nameOnRecord: ""
        ), "要填证据上的姓名")
        let request = try backend.submitVerification(
            kind: .bwf, tier: SkillTier(level: 9), evidenceURL: "bwfbadminton.com/player/1/x", nameOnRecord: "Jie Wang"
        )
        XCTAssertEqual(request.status, .pending)
        XCTAssertEqual(request.evidenceURL, "https://bwfbadminton.com/player/1/x")
        XCTAssertThrowsError(try backend.submitVerification(
            kind: .bwf, tier: SkillTier(level: 9), evidenceURL: "https://bwfbadminton.com/player/1/x", nameOnRecord: "Jie Wang"
        ), "同一时间只能有一份申请在审核")
        // 审核前不改变显示
        XCTAssertEqual(backend.currentUser?.displayTier, SkillTier(level: 6))
    }

    func testApprovalSetsCapAndBadge() throws {
        let backend = makeBackend()
        let request = try backend.submitVerification(
            kind: .bwf, tier: SkillTier(level: 9, modifier: .plus), evidenceURL: "https://bwfbadminton.com/player/1/x",
            nameOnRecord: "Jie Wang"
        )
        // 审核按证据下调到 9−
        let user = try XCTUnwrap(backend.reviewVerification(id: request.id, approvedTier: SkillTier(level: 9, modifier: .minus)))
        XCTAssertEqual(user.verificationStatus, .bwf)
        XCTAssertEqual(user.displayTier, SkillTier(level: 9, modifier: .minus))
        XCTAssertEqual(user.tierCap, SkillTier(level: 9, modifier: .minus))
        XCTAssertEqual(backend.myVerificationRequest()?.status, .approved)
        // 重新做问卷不影响认证档位
        let retake = try XCTUnwrap(SkillAssessment.evaluate(SkillAssessment.demoAnswers))
        let after = try backend.updateAssessment(retake)
        XCTAssertEqual(after.displayTier, SkillTier(level: 9, modifier: .minus))
    }

    func testRejectionKeepsLevel() throws {
        let backend = makeBackend()
        let request = try backend.submitVerification(
            kind: .tournament, tier: SkillTier(level: 7, modifier: .plus),
            evidenceURL: "https://usab.tournamentsoftware.com/x", nameOnRecord: "Jie Wang"
        )
        let user = try XCTUnwrap(backend.reviewVerification(id: request.id, approvedTier: nil, note: "姓名对不上"))
        XCTAssertEqual(user.verificationStatus, .unverified)
        XCTAssertEqual(user.displayTier, SkillTier(level: 6))
        XCTAssertEqual(backend.myVerificationRequest()?.status, .rejected)
    }

    func testCertificateNumberCapsTier() throws {
        // 15 位电子证书，末位 2 = 二级 → 最高 7（州级）
        XCTAssertEqual(VerificationEvidence.certificateMaxTier("20250440100012"), nil, "位数不对")
        XCTAssertEqual(VerificationEvidence.certificateMaxTier("202504401000122"), SkillTier(level: 7))
        XCTAssertEqual(VerificationEvidence.certificateMaxTier("20250440100012x"), SkillTier(level: 8, modifier: .plus))
        XCTAssertNil(VerificationEvidence.problem(with: "202504401000122", for: .national))
        XCTAssertNotNil(VerificationEvidence.problem(with: "202504401000122", for: .bwf))
        let backend = makeBackend()
        XCTAssertThrowsError(try backend.submitVerification(
            kind: .national, tier: SkillTier(level: 8), evidenceURL: "202504401000122", nameOnRecord: "王杰"
        ), "二级证书认证不到 8")
        let request = try backend.submitVerification(
            kind: .national, tier: SkillTier(level: 7), evidenceURL: "202504401000122", nameOnRecord: "王杰"
        )
        XCTAssertEqual(request.evidenceURL, "202504401000122")
    }

    func testUnverifiedPeersCannotPushPastSevenMinus() {
        var user = User(id: "a", nickname: "测试", phone: "", selfReportedLevel: 7)
        user.selfReportedRating = SkillAssessment.maxTier.rating
        user.reputation = ReputationScore(evaluationCount: 20, peerLevelAverage: 9.3, averageSkillDeviation: 1,
                                          punctualityPercentage: 100, averageCharacterRating: 5)
        XCTAssertEqual(user.displayTier, VerificationStatus.unverifiedMaxTier)
    }
}
