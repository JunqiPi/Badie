import Foundation

// MARK: - 高水平认证（人工审核）

extension MockBackend {

    /// 我最近的一次认证申请
    func myVerificationRequest() -> VerificationRequest? {
        guard let me = currentUserId else { return nil }
        return db.verificationRequests.filter { $0.userId == me }.max { $0.submittedAt < $1.submittedAt }
    }

    @discardableResult
    func submitVerification(kind: VerificationStatus, tier: SkillTier, evidenceURL: String, nameOnRecord: String,
                            note: String = "", now: Date = Date()) throws -> VerificationRequest {
        let me = try requireUser()
        guard kind != .unverified else { throw BackendError.verificationInvalid("请选择证据类型") }
        if let pending = myVerificationRequest(), pending.status == .pending {
            throw BackendError.verificationInvalid("你已有一份申请在审核中（\(pending.claimedTier.text)）")
        }
        guard tier >= kind.minTier, tier <= kind.maxTier else {
            throw BackendError.verificationInvalid("\(kind.title)可以认证 \(SkillTier.rangeText(kind.minTier, kind.maxTier))")
        }
        if let problem = VerificationEvidence.problem(with: evidenceURL, for: kind) {
            throw BackendError.verificationInvalid(problem)
        }
        if kind == .national, let certificateCap = VerificationEvidence.certificateMaxTier(evidenceURL), tier > certificateCap {
            throw BackendError.verificationInvalid("这张证书最高可以认证到 \(certificateCap.code)")
        }
        let name = nameOnRecord.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name.count >= 2 else { throw BackendError.verificationInvalid("请填写成绩或证书上的姓名") }
        let request = VerificationRequest(
            id: "vr-" + UUID().uuidString.prefix(8).lowercased(),
            userId: me.id, kind: kind, claimedRating: tier.rating,
            evidenceURL: VerificationEvidence.normalized(evidenceURL), nameOnRecord: name,
            note: String(note.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200)),
            submittedAt: now, status: .pending
        )
        db.verificationRequests.append(request)
        scheduleSave()
        emit(.userUpdated(me))
        return request
    }

    func cancelVerificationRequest() {
        guard let me = currentUserId else { return }
        db.verificationRequests.removeAll { $0.userId == me && $0.status == .pending }
        scheduleSave()
        if let user = currentUser { emit(.userUpdated(user)) }
    }

    /// 审核（真实环境由运营在后台操作；这里用于测试和演示）
    @discardableResult
    func reviewVerification(id: String, approvedTier: SkillTier?, note: String? = nil, now: Date = Date()) -> User? {
        guard let index = db.verificationRequests.firstIndex(where: { $0.id == id }),
              db.verificationRequests[index].status == .pending,
              var user = db.users[db.verificationRequests[index].userId] else { return nil }
        var request = db.verificationRequests[index]
        request.reviewedAt = now
        request.reviewNote = note
        if let approvedTier {
            user.applyVerification(request.kind, tier: approvedTier)
            request.status = .approved
            request.approvedRating = user.verifiedRating
            db.users[user.id] = user
            addInbox(InboxItem(kind: .system, title: "认证通过：\(user.tierCap.text)",
                               body: "已显示\(request.kind.badgeText ?? "认证")徽章。之后的等级会结合球友评价，但不会超过认证档位。",
                               relatedId: user.id), to: user.id)
        } else {
            request.status = .rejected
            addInbox(InboxItem(kind: .system, title: "认证没有通过",
                               body: note ?? "证据上的信息无法核实，可以补充材料后重新申请。", relatedId: user.id), to: user.id)
        }
        db.verificationRequests[index] = request
        scheduleSave()
        emit(.userUpdated(user))
        return user
    }
}
