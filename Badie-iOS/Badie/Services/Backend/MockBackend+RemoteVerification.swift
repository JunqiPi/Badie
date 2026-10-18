import Foundation

// MARK: - 正式后端：高水平认证
/// 申请、撤回走服务器，审核由管理员在网页上做；认证结果跟着资料一起拉（profiles.verified_kind / verified_rating）
extension MockBackend {

    private struct RemoteVerification: Decodable {
        let id: String
        let kind: String
        let claimedRating: Double
        let evidence: String
        let nameOnRecord: String
        let note: String
        let status: String
        let createdAt: Date
        let reviewedAt: Date?
        let reviewNote: String?
        let approvedRating: Double?
    }

    /// 拉取我最近的一次申请（撤回的不算）
    func refreshRemoteVerification() async throws {
        guard let remote, let me = currentUserId else { return }
        let latest = try await remote.rpc("my_verification", as: RemoteVerification?.self)
        remoteVerification = latest.flatMap { item in
            guard let kind = VerificationStatus(server: item.kind),
                  let status = VerificationRequest.Status(rawValue: item.status) else { return nil }
            return VerificationRequest(id: item.id, userId: me, kind: kind, claimedRating: item.claimedRating, evidenceURL: item.evidence,
                                       nameOnRecord: item.nameOnRecord, note: item.note, submittedAt: item.createdAt, status: status,
                                       reviewedAt: item.reviewedAt, reviewNote: item.reviewNote, approvedRating: item.approvedRating)
        }
        if let user = currentUser { emit(.userUpdated(user)) }
    }

    func remoteSubmitVerification(kind: VerificationStatus, tier: SkillTier, evidenceURL: String, nameOnRecord: String,
                                  note: String) async throws -> VerificationRequest {
        try await requireRemote().call("request_verification", [
            "p_kind": kind.serverValue,
            "p_rating": tier.rating,
            "p_evidence": evidenceURL.trimmingCharacters(in: .whitespacesAndNewlines),
            "p_name": nameOnRecord.trimmingCharacters(in: .whitespacesAndNewlines),
            "p_note": note.trimmingCharacters(in: .whitespacesAndNewlines),
        ])
        try await refreshRemoteVerification()
        guard let request = remoteVerification else { throw RemoteError.server("bad_response") }
        return request
    }

    func remoteCancelVerification() {
        runRemote({
            remoteVerification = nil
            if let user = currentUser { emit(.userUpdated(user)) }
        }) { try await $0.call("withdraw_verification") }
    }
}

extension VerificationStatus {
    /// 服务器的写法：tournament / national / bwf
    var serverValue: String {
        switch self {
        case .tournament: return "tournament"
        case .national: return "national"
        case .bwf: return "bwf"
        case .unverified: return ""
        }
    }

    init?(server value: String) {
        guard let status = Self.allCases.first(where: { $0 != .unverified && $0.serverValue == value }) else { return nil }
        self = status
    }
}
