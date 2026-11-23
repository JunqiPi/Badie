package com.badie.app.remote

import com.badie.app.l10n.L10n.tr

/** 服务器返回的错误：数据库函数抛出的错误名（too_soon 等）、登录服务的错误码，或网络问题 */
sealed class RemoteError : Exception() {
    data class Server(val code: String) : RemoteError()
    data object Network : RemoteError() {
        private fun readResolve(): Any = Network
    }
    data object NotSignedIn : RemoteError() {
        private fun readResolve(): Any = NotSignedIn
    }

    /** 显示给用户的话 */
    override val message: String
        get() = when (this) {
            Network -> tr("请检查网络后重试。")
            NotSignedIn -> tr("请先登录")
            is Server -> message(code)
        }

    companion object {
        /** 错误码对应的话，和 iPhone 的 RemoteError.message 一一对应 */
        fun message(code: String): String = when (code) {
            // 登录
            "otp_expired", "otp_disabled" -> tr("验证码无效。请查看最新的一封邮件，或重新发送。")
            "over_email_send_rate_limit", "over_request_rate_limit" -> tr("尝试次数过多，请等一分钟再试。")
            "email_address_invalid", "validation_failed" -> tr("邮箱地址好像不对。")
            "captcha_failed" -> tr("人机验证没有通过，请再试一次。")
            "invalid_credentials" -> tr("邮箱或密码不对。以前用验证码登录的，点“忘记密码？”设置一个密码。")
            "user_already_exists", "email_exists" -> tr("这个邮箱已经注册过了，请登录，或找回密码。")
            "email_not_confirmed" -> tr("请先确认邮箱：输入注册时邮件里的验证码，或重新发送。")
            "weak_password" -> tr("密码至少要 8 位。")
            "same_password" -> tr("和现在的密码一样，请换一个新的。")
            "venue_name_invalid" -> tr("球馆名称需为 2–60 个字符")
            "venue_address_incomplete" -> tr("请补全街道和城市，方便其他球友确认位置")
            "venue_rate_limited" -> tr("今天添加的球馆已达上限，明天再试。")
            "venue_duplicate" -> tr("球馆库里已有这家球馆，请直接选择它。")
            // 爽约处罚
            "suspended" -> tr("因为爽约，你现在不能约球。详情在「我的」页面。")
            "invalid_appeal" -> tr("简单写一下发生了什么。")
            "appeal_closed" -> tr("爽约 48 小时后就不能申诉了。")
            // 约球
            "too_soon" -> tr("开始时间至少要在 30 分钟后。")
            "too_far" -> tr("最多只能提前 30 天安排。")
            "invalid_slot" -> tr("时间段不对：至少 1 小时，约球最长 16 小时，开局最长 8 小时。")
            "invalid_venues" -> tr("请选 1–3 个球馆。")
            "too_many_requests" -> tr("你已有 5 个进行中的约球请求，先取消一个。")
            "overlapping" -> tr("这个时间你已经有约球请求或球局了。")
            "offer_closed" -> tr("这次匹配已失效。")
            "not_available" -> tr("TA 已经约上了，或者暂时约不了。")
            "not_active" -> tr("这个约球请求已结束。")
            "not_paused" -> tr("这个约球请求已无法恢复。")
            "cannot_cancel" -> tr("这场球局已经不能取消了。")
            "cannot_check_in" -> tr("开始前 30 分钟才能签到。")
            "cannot_report" -> tr("从球局开始到结束后 7 天内，都可以填报赛果。")
            "result_locked" -> tr("双方已经确认了这个赛果。")
            "invalid_score" -> tr("比分只能填数字，如 21:18 19:21。")
            "invalid_games" -> tr("填一下两边各赢了几局。")
            "retake_too_soon" -> tr("距上次测试满 90 天后，才能重新测试。")
            // 评价、球友、私信
            "cannot_review" -> tr("评价在球局结束后 48 小时内开放。")
            "already_reviewed" -> tr("你已经评价过这位球友了。")
            "chat_closed" -> tr("这个聊天已关闭。")
            "invalid_message" -> tr("请先输入消息（最多 1000 字）。")
            "too_many_messages" -> tr("发消息太频繁了，请稍等一分钟。")
            "not_allowed" -> tr("只能对匹配过的球友进行这个操作。")
            "blocked" -> tr("请先解除对这位球友的屏蔽。")
            "no_request" -> tr("这条好友申请已失效。")
            "no_contact_info" -> tr("请不要包含电话或链接。")
            // 反馈
            "invalid_feedback" -> tr("多写几个字，说说发生了什么。")
            "too_much_feedback" -> tr("今天发得有点多了，明天再写，或者发邮件给我们。")
            // 球群
            "invalid_schedule" -> tr("每个固定场次要 1–12 小时、在当天结束，名额 4–40 人，最多 7 个。")
            "too_many_groups" -> tr("你的球群数量已达上限。")
            "group_not_found" -> tr("没有找到这个球群。")
            "level_out_of_range" -> tr("你的水平不在 TA 接受的范围内。")
            "gender_restricted" -> tr("这个只限男生或只限女生。")
            "invalid_event" -> tr("混双只有双打，而且要先在设置里填好性别。")
            "mixed_side_full" -> tr("这个混双局里和你同性别的位子已经满了。")
            "objectionable_content" -> tr("这里不能用不当用语，请换个说法。")
            "owner_cannot_leave" -> tr("群主不能退出自己的球群。")
            "signup_not_found" -> tr("已经不在这一场的名单上了。")
            "invalid_guest_limit" -> tr("每场访客最多 1–40 人。")
            "not_organizer" -> tr("只有组织者才能这样操作。")
            "not_member" -> tr("请先加入球群。")
            "session_closed" -> tr("本场已关闭。")
            // 挑战
            "challenge_closed" -> tr("这个挑战已失效。")
            "friends_only" -> tr("TA 只接受球友的挑战。")
            "already_pending" -> tr("你已经挑战过 TA 了，请等 TA 回复。")
            "cooldown" -> tr("距上次挑战满一周后，才能再挑战 TA。")
            "too_many_outgoing" -> tr("同时最多只能有 3 个待回复的挑战。")
            "invalid_partner" -> tr("请选一位那段时间有空的球友当搭档。")
            "invalid_avatar" -> tr("照片上传失败，请重试。")
            // 高水平认证
            "invalid_evidence" -> tr("链接格式不对，请复制完整的网页地址")
            "invalid_level" -> tr("这类证据不能认证这个等级。")
            "invalid_name" -> tr("请填写成绩或证书上的姓名")
            "verification_pending" -> tr("你已有一份申请在审核中。")
            "too_many_verifications" -> tr("30 天内最多申请 3 次。")
            "daily_limit" -> tr("今天的挑战次数已用完。")
            "target_busy" -> tr("TA 待处理的挑战太多了，请稍后再试。")
            "admin_account" -> tr("管理员账号不能在这里注销，请先让其他管理员撤掉你的权限。")
            // 球局（房间）
            "already_started" -> tr("开始时间已经过了，请重新选择。")
            "missing_details" -> tr("公开球局需要设置球馆和时间")
            "invalid_level_range" -> tr("最低水平不能高于最高水平。")
            "too_many_rooms" -> tr("进行中的房间太多了，先结束或解散一个。")
            "room_not_found" -> tr("房间不存在，请检查房间码")
            "room_closed" -> tr("房间已关闭")
            "room_full" -> tr("房间已满")
            "not_room_owner" -> tr("只有房主可以进行此操作")
            "not_enough_players" -> tr("人还没齐，满员后才能开始。")
            "too_many_invites" -> tr("一次最多邀请 10 位好友。")
            "too_many_searches" -> tr("搜索太频繁了，过几分钟再试。")
            // 当晚：排场、比赛、收款
            "court_changed" -> tr("这片场地已经换过了，刷新了。")
            "not_waiting" -> tr("这个人已经不在等候里了，刷新了。")
            "score_taken" -> tr("已经有人填了。")
            "score_changed" -> tr("比分刚被改过，刷新了。")
            "score_invalid" -> tr("比分不对。")
            "nothing_to_undo" -> tr("来不及撤销了。")
            "reminded_recently" -> tr("12 小时内提醒过了。")
            "night_closed" -> tr("不在当晚的时间里。")
            "not_attending" -> tr("帮手要从到场的注册用户里选。")
            "too_many_helpers" -> tr("最多 3 个帮手。")
            "match_running" -> tr("已经有一场比赛在打。")
            "invalid_player_count" -> tr("参赛的人数不对。")
            "invalid_match_name" -> tr("给比赛起个名字（最多 40 字）。")
            "invalid_match" -> tr("比赛设置不对，检查一下。")
            "invalid_teams" -> tr("每队要正好 2 个人。")
            "duplicate_player" -> tr("这个人已经在里面了。")
            "player_not_found" -> tr("加不了这个人。")
            "cannot_add_player" -> tr("开始后只有双打轮换搭档能加人。")
            "knockout_started" -> tr("淘汰赛已经开始了。")
            "invalid_qualifiers" -> tr("选出线的人。")
            "game_cancelled" -> tr("这一场取消了。")
            "invalid_amount" -> tr("金额要大于 \$0，最多 \$1000。")
            "invalid_venmo" -> tr("Venmo 用户名不对。")
            "invalid_cashapp" -> tr("Cash App 的 \$cashtag 不对。")
            "invalid_paypal" -> tr("PayPal.me 用户名不对。")
            "invalid_zelle" -> tr("Zelle 要填邮箱或手机号。")
            else -> tr("出了点问题，请重试。")
        }
    }
}
