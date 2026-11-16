package com.badie.app.e2e

import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasSetTextAction
import androidx.compose.ui.test.performTextInput
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Test
import org.junit.runner.RunWith

/**
 * 账号：注册（邮箱 + 密码，输入邮件里的验证码）→ 填资料 → 主界面；退出登录；用密码再登录。
 * e2e/run.sh 先清掉 App 的数据再跑这一段，跑完接着跑 [ColdStartTest]（同一个账号，不清数据）
 */
@RunWith(AndroidJUnit4::class)
class AccountTest : E2ETest() {
    @Test
    fun signUpSignOutAndSignInAgain() {
        val email = Harness.email("signup")
        launch()

        // 欢迎页 → 注册
        tapText("邮箱登录 / 注册", timeoutMillis = 30_000)
        tapText("还没有账号？注册一个")
        waitFor(text(t("注册 Badie")))
        type(0, email)
        type(1, Harness.PASSWORD)
        tapText("我已阅读并同意《用户协议》和《隐私政策》，了解邮箱仅用于登录与安全验证，不会展示给其他球友。")
        tapText("注册")

        // 邮件里的验证码，输满 6 位自动提交
        waitFor(text(t("输入验证码")), 30_000)
        val code = Harness.emailedCode(email)
        waitFor(hasContentDescription(t("验证码"))).performTextInput(code)

        // 怎么称呼你
        waitFor(text(t("怎么称呼你？")), 30_000)
        type(hasSetTextAction(), "Ada")
        tapText("女")
        tapText("下一步")

        // 定级先跳过
        tapText("先跳过")

        // 最后一步：常去球馆按名字搜一家
        waitFor(text(t("最后一步")))
        tapText("添加球馆")
        waitFor(text(t("选择球馆")))
        type(hasSetTextAction(), "21 Badminton")
        tap(text("21 Badminton Club", substring = true), 30_000)
        tapText("完成")
        tapText("开始约球")
        waitMain()
        waitFor(text(t("注册成功，欢迎加入")), what = "注册成功的提示")
        waitGone(text(t("注册成功，欢迎加入")))

        // 退出登录，再用密码登录
        signOut()
        signInWithPassword(email)
        openTab("我的")
        waitFor(text("Ada"), what = "“我的”里的昵称")
    }
}

/** 冷启动（新的进程）：登录状态还在，直接进主界面，不经过欢迎页 */
@RunWith(AndroidJUnit4::class)
class ColdStartTest : E2ETest() {
    @Test
    fun coldStartKeepsSession() {
        launch()
        waitMain()
        check(!exists(text(t("邮箱登录 / 注册")))) { "冷启动后回到了欢迎页" }
        openTab("我的")
        waitFor(text("Ada"), what = "“我的”里的昵称")
    }
}
