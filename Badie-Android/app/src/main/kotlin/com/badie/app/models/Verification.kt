package com.badie.app.models

import com.badie.app.l10n.L10n.tr
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.net.URI
import java.net.URISyntaxException

// MARK: - 高水平认证申请
//
// 7 级起只凭公开可查的证据（赛果、全国排名 / 等级证书、BWF 球员页）由人工审核，
// 并核对证据上的姓名与本人证件。

@Serializable
data class VerificationRequest(
    val id: String,
    val userId: String,
    val kind: VerificationStatus,
    val claimedRating: Double,
    /** 链接，或 15 位电子证书编号 */
    val evidenceURL: String,
    /** 证据上的姓名（和证件核对） */
    val nameOnRecord: String,
    val note: String,
    val submittedAt: Long,
    val status: Status,
    val reviewedAt: Long? = null,
    val reviewNote: String? = null,
    /** 审核通过的档位（可能比申请的低） */
    val approvedRating: Double? = null,
) {
    @Serializable
    enum class Status {
        @SerialName("pending") Pending,
        @SerialName("approved") Approved,
        @SerialName("rejected") Rejected,
    }

    val claimedTier: SkillTier get() = SkillTier.ofRating(claimedRating)

    companion object {
        /** 一般几个工作日内审核 */
        const val REVIEW_DAYS = 3
    }
}

object VerificationEvidence {
    /**
     * 运动员技术等级电子证书（2025 起）：15 位，最后一位是等级码
     * X = 国际级运动健将，0 = 运动健将，1 = 一级，2 = 二级，3 = 三级
     */
    fun certificateMaxTier(text: String): SkillTier? {
        val code = text.trim { it == ' ' || it == '\t' }.uppercase()
        if (code.length != 15 || !code.dropLast(1).all { it in '0'..'9' }) return null
        return when (code.last()) {
            'X', '0' -> SkillTier(8, SkillTier.Modifier.Plus)
            '1' -> SkillTier(8)
            '2' -> SkillTier(7)
            '3' -> SkillTier(7, SkillTier.Modifier.Minus)
            else -> null
        }
    }

    /** 每类证据接受的链接（为空表示任何 https 链接都可以，由人工判断） */
    fun acceptedHosts(kind: VerificationStatus): List<String> = when (kind) {
        VerificationStatus.Bwf -> listOf("bwfbadminton.com", "bwf.tournamentsoftware.com", "bwfworldtour.bwfbadminton.com")
        VerificationStatus.Tournament -> listOf("tournamentsoftware.com")
        VerificationStatus.National, VerificationStatus.Unverified -> emptyList()
    }

    fun placeholder(kind: VerificationStatus): String = when (kind) {
        VerificationStatus.Bwf -> "bwfbadminton.com/player/12345/your-name"
        VerificationStatus.Tournament -> tr("usab.tournamentsoftware.com/… 的成绩页")
        VerificationStatus.National -> tr("USAB 排名页链接，或 15 位电子证书编号")
        VerificationStatus.Unverified -> ""
    }

    /** 检查链接；有问题时返回原因 */
    fun problem(link: String, kind: VerificationStatus): String? {
        val trimmed = link.trim()
        if (trimmed.isEmpty()) return tr("请填写证据链接")
        if (kind == VerificationStatus.National && certificateMaxTier(trimmed) != null) return null
        val withScheme = if ("://" in trimmed) trimmed else "https://$trimmed"
        val url = try {
            URI(withScheme)
        } catch (_: URISyntaxException) {
            null
        }
        val host = url?.host?.lowercase()
        if (url == null || host == null || url.scheme?.lowercase() != "https" || "." !in host) {
            return tr("链接格式不对，请复制完整的网页地址")
        }
        val hosts = acceptedHosts(kind)
        if (hosts.isNotEmpty() && hosts.none { host == it || host.endsWith(".$it") }) {
            return if (kind == VerificationStatus.Bwf) {
                tr("需要 BWF 官网的球员页（bwfbadminton.com/player/…）")
            } else {
                tr("需要 tournamentsoftware.com 上的成绩页")
            }
        }
        if (kind == VerificationStatus.Bwf) {
            val path = (url.path ?: "").lowercase()
            val isPlayerPage = path.startsWith("/player/") || path.startsWith("/player-profile/")
            val hasId = path.split("/").filter { it.isNotEmpty() }.drop(1).firstOrNull()?.isNotEmpty() ?: false
            if (!isPlayerPage || !hasId) return tr("需要具体的球员页，链接里要有球员 ID")
        }
        return null
    }

    /** 补全 https://；证书编号只转大写 */
    fun normalized(link: String): String {
        val trimmed = link.trim()
        if (certificateMaxTier(trimmed) != null) return trimmed.uppercase()
        return if ("://" in trimmed) trimmed else "https://$trimmed"
    }
}
