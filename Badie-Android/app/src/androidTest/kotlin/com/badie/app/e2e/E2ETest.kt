package com.badie.app.e2e

import android.content.Intent
import android.util.Log
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.SemanticsNodeInteraction
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasSetTextAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.isEnabled
import androidx.compose.ui.test.isRoot
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTextReplacement
import androidx.compose.ui.test.printToString
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.UiDevice
import com.badie.app.MainActivity
import com.badie.app.l10n.L10n
import org.junit.Rule
import org.junit.rules.TestWatcher
import org.junit.runner.Description
import java.io.File

/**
 * 端到端测试的共用部分：起 App、按界面上的字找东西（字用 App 自己的文字表取，跟着模拟器的语言走）、等、点、填，
 * 失败时截图并把界面的结构打到日志里（e2e/run.sh 收走）
 */
abstract class E2ETest {
    @get:Rule(order = 0)
    val failureCapture = object : TestWatcher() {
        override fun failed(e: Throwable?, description: Description) {
            val name = "${description.testClass.simpleName}-${description.methodName}"
            runCatching { device.takeScreenshot(File(outputDir(), "$name.png")) }
            runCatching {
                compose.onAllNodes(isRoot()).fetchSemanticsNodes().indices.forEach { index ->
                    Log.e(TAG, "界面 $index:\n" + compose.onAllNodes(isRoot())[index].printToString(maxDepth = 40))
                }
            }
            runCatching { File(outputDir(), "$name-window.xml").also { device.dumpWindowHierarchy(it) } }
        }
    }

    @get:Rule(order = 1)
    val compose = createEmptyComposeRule()

    val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    val context get() = instrumentation.targetContext
    val device: UiDevice by lazy { UiDevice.getInstance(instrumentation) }

    /** 界面上的字：写简体中文原文（和 App 代码里的 tr 一样），取模拟器当前语言的译文 */
    fun t(key: String, vararg args: Any?): String = L10n.lookup(context.resources, key, args)

    /** 带参数的句子里参数前面那段（按它找） */
    fun prefix(key: String) = t(key, "\u0000").substringBefore("\u0000")

    fun launch(): ActivityScenario<MainActivity> = ActivityScenario.launch(MainActivity::class.java)

    /** 从桌面图标打开（和用户点图标一样：已经开着就回到原来的页面） */
    fun openFromLauncher() {
        val intent = context.packageManager.getLaunchIntentForPackage(context.packageName)!!
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED)
        context.startActivity(intent)
    }

    // MARK: 找、等

    fun text(value: String, substring: Boolean = false) = hasText(value, substring = substring)

    fun desc(value: String) = hasContentDescription(value)

    /** 字里或读屏的描述里提到（有的卡片只放头像，名字在读屏的那句话里） */
    fun mentions(value: String) = hasText(value, substring = true) or hasContentDescription(value, substring = true)

    fun tab(titleKey: String) = desc(t(titleKey)) and SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Tab)

    fun exists(matcher: SemanticsMatcher): Boolean =
        runCatching { compose.onAllNodes(matcher).fetchSemanticsNodes(atLeastOneRootRequired = false).isNotEmpty() }.getOrDefault(false)

    /** 等它出现（界面上任何一层），返回第一个 */
    fun waitFor(matcher: SemanticsMatcher, timeoutMillis: Long = 20_000, what: String = matcher.description): SemanticsNodeInteraction {
        try {
            compose.waitUntil(timeoutMillis) { exists(matcher) }
        } catch (e: Throwable) {
            throw AssertionError("等了 ${timeoutMillis / 1000} 秒，界面上还没有：$what", e)
        }
        return compose.onAllNodes(matcher)[0]
    }

    fun waitGone(matcher: SemanticsMatcher, timeoutMillis: Long = 20_000) {
        try {
            compose.waitUntil(timeoutMillis) { !exists(matcher) }
        } catch (e: Throwable) {
            throw AssertionError("等了 ${timeoutMillis / 1000} 秒，界面上还有：${matcher.description}", e)
        }
    }

    /** 一段时间内一直不出现 */
    fun assertNever(matcher: SemanticsMatcher, millis: Long) {
        val deadline = System.currentTimeMillis() + millis
        while (System.currentTimeMillis() < deadline) {
            check(!exists(matcher)) { "不该出现：${matcher.description}" }
            Thread.sleep(250)
        }
    }

    fun tap(matcher: SemanticsMatcher, timeoutMillis: Long = 20_000) {
        val node = waitFor(matcher and isEnabled(), timeoutMillis)
        runCatching { node.performScrollTo() }
        node.performClick()
        compose.waitForIdle()
    }

    fun tapText(key: String, vararg args: Any?, timeoutMillis: Long = 20_000) = tap(text(t(key, *args)), timeoutMillis)

    /** 第 index 个输入框（按界面上的顺序） */
    fun type(index: Int, value: String) {
        waitFor(hasSetTextAction())
        val node = compose.onAllNodes(hasSetTextAction())[index]
        runCatching { node.performScrollTo() }
        node.performTextReplacement(value)
        compose.waitForIdle()
    }

    fun type(matcher: SemanticsMatcher, value: String) {
        val node = waitFor(matcher)
        runCatching { node.performScrollTo() }
        node.performTextReplacement(value)
        compose.waitForIdle()
    }

    // MARK: 常用的几步

    /** 主界面出来了（底部的标签栏） */
    fun waitMain(timeoutMillis: Long = 30_000) = waitFor(tab("发现"), timeoutMillis, "主界面的标签栏")

    /** 欢迎页 → 邮箱 + 密码登录 → 主界面 */
    fun signInWithPassword(email: String, password: String = Harness.PASSWORD) {
        tapText("邮箱登录 / 注册", timeoutMillis = 30_000)
        waitFor(text(t("用邮箱登录")))
        type(0, email)
        type(1, password)
        tapText("登录")
        waitMain()
        // “欢迎回来”的提示条盖着页头右边的按钮，点了只会收起提示：等它自己消失
        waitGone(text(prefix("欢迎回来，%@"), substring = true))
    }

    fun openTab(titleKey: String) {
        backToTabs()
        tap(tab(titleKey))
    }

    /** 推进去的页面（聊天、设置这些）没有标签栏：按返回直到标签栏出来 */
    fun backToTabs() {
        repeat(5) {
            if (exists(tab("发现"))) return
            device.pressBack()
            compose.waitForIdle()
            Thread.sleep(500)
        }
    }

    /** 我的 → 设置 → 退出登录 → 确认，回到欢迎页 */
    fun signOut() {
        openTab("我的")
        tap(desc(t("设置")))
        tapText("退出登录")
        tapText("退出")
        waitFor(text(t("邮箱登录 / 注册")), 30_000)
    }

    fun pressHome() {
        device.pressHome()
        device.waitForIdle()
    }

    companion object {
        const val TAG = "BadieE2E"

        /** 截图、界面结构放这里，e2e/run.sh 每段跑完拉回电脑 */
        fun outputDir(): File {
            val context = InstrumentationRegistry.getInstrumentation().targetContext
            return File(context.getExternalFilesDir(null), "e2e").apply { mkdirs() }
        }
    }
}
