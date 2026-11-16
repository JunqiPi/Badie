package com.badie.app.features.games

import android.content.Context
import androidx.core.content.edit

/**
 * 商店评分弹窗：打过 2 场以上、刚给球友打了好评时才问，120 天最多一次。对应 iPhone 的 Features/Surveys/RatingPrompt.swift。
 * TODO：真正弹 Google Play 的应用内评价要加 com.google.android.play:review 依赖（这里不能加依赖），现在只记时间、不弹
 */
object RatingPrompt {
    private const val PREFS = "rating_prompt"
    private const val KEY = "askedAt"
    const val INTERVAL = 120 * 86_400_000L

    /** [lastAskedAt] 是上次问的时间（毫秒），没问过是 null */
    fun shouldAsk(totalGames: Int, positive: Boolean, now: Long, lastAskedAt: Long?): Boolean {
        if (!positive || totalGames < 2) return false
        return lastAskedAt == null || now - lastAskedAt > INTERVAL
    }

    fun shouldAsk(context: Context, totalGames: Int, positive: Boolean, now: Long = System.currentTimeMillis()): Boolean =
        shouldAsk(totalGames, positive, now, lastAsked(context))

    fun markAsked(context: Context, now: Long = System.currentTimeMillis()) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit { putLong(KEY, now) }
    }

    private fun lastAsked(context: Context): Long? =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getLong(KEY, -1L).takeIf { it >= 0 }
}
