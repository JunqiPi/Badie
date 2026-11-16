package com.badie.app.features.games

import androidx.compose.runtime.Stable
import com.badie.app.models.AttendanceAnswer
import com.badie.app.models.PendingSurvey
import com.badie.app.models.SkillTier
import com.badie.app.models.SurveyIssue
import com.badie.app.models.SurveyTag
import com.badie.app.shell.ManagerContext

/**
 * 赛后评价。对应 iPhone 的 Managers/SocialManagers.swift 的 SurveyManager。在 shell/AppState.kt 的 AppEnvironment 里已经建好，构造参数不要改。
 * 待评价和球局是同一次 my_games 拉到的，数据在 [GameBook]（和 RoomManager 共用）
 */
@Stable
class SurveyManager(private val context: ManagerContext) {
    val book: GameBook = GameBook.of(context.backend).also { book -> context.android?.let { book.android = it.applicationContext } }

    val pendingSurveys: List<PendingSurvey> get() = book.pendingSurveys

    /** 待评价的份数（球局标签的角标） */
    val pendingCount: Int get() = book.pendingSurveys.size

    fun survey(id: String): PendingSurvey? = book.survey(id)

    fun pending(gameId: String): List<PendingSurvey> = book.pending(gameId)

    /** 下拉刷新：重新读一遍（shell/RefreshEverything.kt 统一调） */
    suspend fun refresh() = book.refresh(GameBook.SHARED_REFRESH_MILLIS)

    suspend fun submit(
        pending: PendingSurvey,
        skillRating: SkillTier,
        attendance: AttendanceAnswer,
        tags: List<SurveyTag>,
        issues: List<SurveyIssue> = emptyList(),
        wantsRematch: Boolean = false,
    ) = book.submitSurvey(pending, skillRating, attendance, tags, issues, wantsRematch)
}
