package com.badie.app.features.onboarding

import com.badie.app.TestSupport
import com.badie.app.TestSupport.serveProfile
import com.badie.app.design.Toast
import com.badie.app.models.GameMode
import com.badie.app.models.Gender
import com.badie.app.models.SkillAssessment
import com.badie.app.models.SkillTier
import com.badie.app.remote.FakeServer
import com.badie.app.remote.HttpResponse
import com.badie.app.shell.AppState
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** 登录和注册的流程：每一步什么时候能继续、发了什么请求、出错怎么走 */
class OnboardingModelTest {
    private val server = FakeServer()

    private fun TestScope.flow(): Pair<OnboardingModel, AppState> {
        val appState = AppState(backgroundScope, TestSupport.backend(server))
        appState.finishLaunch()
        val model = OnboardingModel(appState, CaptchaModel(), passwordLookup = { HttpResponse(200, ByteArray(0)) }, now = { TestSupport.CLOCK })
        return model to appState
    }

    private fun text(index: Int, key: String) = server.json(index)[key]?.jsonPrimitive?.content

    private fun captchaToken(index: Int) = server.json(index)["gotrue_meta_security"]?.jsonObject?.get("captcha_token")?.jsonPrimitive?.content

    @Test
    fun existingAccountSignsIn() = runTest {
        val (model, appState) = flow()
        assertEquals(AppState.Phase.Onboarding, appState.phase)
        assertEquals("邮箱登录 / 注册", model.primaryTitle)
        model.primaryAction()
        assertEquals(OnboardingStep.Email, model.step)
        assertEquals("登录", model.primaryTitle)

        model.email = "alex@example"
        model.password = "shuttle rally"
        assertFalse("人机验证的令牌还没到", model.canContinue)
        model.captcha.receive("""{"token":"cap-1"}""")
        assertTrue(model.canContinue)
        model.primaryAction()
        assertEquals("邮箱地址好像不对。", model.errorText)
        assertTrue("没发请求", server.requests.isEmpty())

        model.email = " Alex@Example.com "
        model.edited()
        assertNull(model.errorText)
        server.on("POST /auth/v1/token", TestSupport.token("pw"))
        server.serveProfile("[${TestSupport.profile()}]")
        model.primaryAction()

        assertEquals("alex@example.com", text(0, "email"))
        assertEquals("cap-1", captchaToken(0))
        assertEquals(AppState.Phase.Main, appState.phase)
        assertEquals("欢迎回来，Alex", appState.toast?.message)
        assertNull("令牌只能用一次，用完换新的", model.captcha.token)
        assertEquals(1, model.captcha.attempt)
        assertFalse(model.isWorking)
    }

    @Test
    fun newAccountGoesThroughAllFiveSteps() = runTest {
        val (model, appState) = flow()
        model.primaryAction()
        model.toggleNewAccount()
        assertEquals("注册", model.primaryTitle)
        model.email = "alex@example.com"
        model.password = "short"
        model.captcha.receive("""{"token":""}""")
        assertFalse("注册要先勾协议", model.canContinue)
        model.agreed = true
        assertTrue(model.canContinue)
        model.primaryAction()
        assertEquals("密码至少要 8 位。", model.errorText)

        // 注册：服务器把确认码发到邮箱
        model.password = "shuttle rally"
        server.on("POST /auth/v1/signup", """{"id":"u","identities":[{"provider":"email"}]}""")
        model.primaryAction()
        assertEquals(OnboardingStep.Code, model.step)
        assertEquals(CodePurpose.Signup, model.codePurpose)
        assertEquals(60, model.resendRemaining)
        assertEquals("验证", model.primaryTitle)
        assertNull("网站没开人机验证时不带令牌", server.json(0)["gotrue_meta_security"])

        // 输满 6 位自动提交；字母和多出来的数字不要
        server.on("POST /auth/v1/verify", TestSupport.token("confirmed"))
        server.serveProfile("[]")
        model.updateCode("12a34")
        assertEquals("1234", model.code)
        model.updateCode("1234567")
        assertEquals("signup", text(1, "type"))
        assertEquals("123456", text(1, "token"))
        assertEquals(OnboardingStep.Profile, model.step)
        assertEquals("还没建资料，不算登录", AppState.Phase.Onboarding, appState.phase)

        // 称呼和性别都要填
        model.nickname = "杰"
        assertFalse(model.canContinue)
        model.nickname = " Alex "
        assertFalse(model.canContinue)
        model.gender = Gender.Male
        assertTrue(model.canContinue)
        model.primaryAction()
        assertEquals(OnboardingStep.Level, model.step)

        // 答完问卷才能下一步
        assertFalse(model.canContinue)
        model.assessmentAnswers.putAll(SkillAssessment.demoAnswers)
        assertEquals(4, model.level)
        model.primaryAction()
        assertEquals(OnboardingStep.Preferences, model.step)
        assertEquals("开始约球", model.primaryTitle)

        model.preferredMode = GameMode.Singles
        model.showsInLobby = true
        server.on("POST /rest/v1/profiles", "", status = 201)
        server.on("POST /rest/v1/rpc/save_assessment", "")
        server.serveProfile("[${TestSupport.profile()}]")
        server.on("PATCH /rest/v1/profiles", "")
        server.on("PATCH /rest/v1/profiles", "")
        val before = server.requests.size
        model.primaryAction()

        assertEquals("Alex", text(before, "nickname"))
        assertEquals("male", text(before, "gender"))
        assertEquals(4.0, server.json(before + 1).getValue("p_rating").jsonPrimitive.content.toDouble(), 0.001)
        assertEquals(14, server.json(before + 1).getValue("p_answers").jsonObject.size)
        val patches = server.requests.indices.filter { server.requests[it].method == "PATCH" }
        assertEquals("true", text(patches[0], "show_as_regular"))
        assertEquals("singles", text(patches[1], "preferred_mode"))
        assertEquals(AppState.Phase.Main, appState.phase)
        assertEquals("注册成功，欢迎加入", appState.toast?.message)
        assertEquals(SkillTier(4), appState.currentUser?.displayTier)
        assertEquals(GameMode.Singles, appState.currentUser?.preferredMode)
    }

    @Test
    fun alreadyRegisteredOrUnconfirmedEmail() = runTest {
        val (model, _) = flow()
        model.primaryAction()
        model.toggleNewAccount()
        model.email = "alex@example.com"
        model.password = "shuttle rally"
        model.agreed = true
        model.captcha.receive("""{"token":"t"}""")
        server.on("POST /auth/v1/signup", """{"id":"u","identities":[]}""")
        model.primaryAction()
        assertFalse("已经注册过：切回登录", model.newAccount)
        assertEquals("这个邮箱已经注册过了，请登录，或找回密码。", model.errorText)

        model.captcha.receive("""{"token":"t2"}""")
        server.on("POST /auth/v1/token", """{"error_code":"email_not_confirmed"}""", status = 400)
        model.primaryAction()
        assertEquals("注册了但没确认邮箱：去输确认码", OnboardingStep.Code, model.step)
        assertEquals(CodePurpose.Signup, model.codePurpose)
        assertEquals("请先确认邮箱：输入注册时邮件里的验证码，或重新发送。", model.errorText)
    }

    @Test
    fun forgotPasswordSetsANewOne() = runTest {
        val (model, appState) = flow()
        model.primaryAction()
        model.sendEmailCode(CodePurpose.Recovery)
        assertEquals("请先填写邮箱。", model.errorText)

        model.email = "alex@example.com"
        model.password = "wrong one"
        model.captcha.receive("""{"token":"t"}""")
        server.on("POST /auth/v1/recover", "{}")
        model.sendEmailCode(CodePurpose.Recovery)
        assertEquals(OnboardingStep.Code, model.step)
        assertEquals("", model.password)
        assertEquals("保存新密码并登录", model.primaryTitle)

        // 还要填新密码，输满验证码不自动提交
        model.updateCode("654321")
        assertEquals(1, server.requests.size)
        assertFalse(model.canContinue)
        model.password = "drop shot at dawn"
        server.on("POST /auth/v1/verify", TestSupport.token("recovered"))
        server.serveProfile("[${TestSupport.profile()}]")
        server.on("PUT /auth/v1/user", "{}")
        model.primaryAction()
        assertEquals("recovery", text(1, "type"))
        assertEquals("drop shot at dawn", text(server.requests.lastIndex, "password"))
        assertEquals("密码已保存", appState.toast?.message)
        assertEquals(Toast.Style.Success, appState.toast?.style)
        assertEquals(AppState.Phase.Main, appState.phase)
    }

    @Test
    fun wrongCodeClearsTheBoxes() = runTest {
        val (model, _) = flow()
        model.primaryAction()
        model.email = "alex@example.com"
        model.captcha.receive("""{"token":"t"}""")
        server.on("POST /auth/v1/otp", "{}")
        model.sendEmailCode(CodePurpose.Email)
        assertEquals("true", text(0, "create_user"))
        server.on("POST /auth/v1/verify", """{"error_code":"otp_expired"}""", status = 403)
        model.updateCode("000000")
        assertEquals("", model.code)
        assertEquals("验证码无效。请查看最新的一封邮件，或重新发送。", model.errorText)
        assertEquals(OnboardingStep.Code, model.step)
    }

    @Test
    fun skippingTheQuizAndGoingBack() = runTest {
        val (model, _) = flow()
        model.primaryAction()
        model.goBack()
        assertEquals(OnboardingStep.Welcome, model.step)
        assertNull(model.level)
        model.skipAssessment()
        assertEquals(OnboardingStep.Preferences, model.step)
        assertEquals("跳过时先按 3 级", SkillAssessment.PROVISIONAL_LEVEL, model.level)
        model.goBack()
        assertEquals(OnboardingStep.Level, model.step)
        model.goBack()
        assertEquals(OnboardingStep.Profile, model.step)
        model.goBack()
        assertEquals("资料那一步往回是邮箱，不回验证码", OnboardingStep.Email, model.step)
    }

    @Test
    fun captchaMessages() {
        val captcha = CaptchaModel()
        assertFalse(captcha.isReady)
        captcha.receive("""{"interactive":true}""")
        assertTrue("Cloudflare 要人点一下：把验证框露出来", captcha.needsInteraction)
        captcha.receive("""{"token":"abc"}""")
        assertEquals("abc", captcha.token)
        assertFalse(captcha.needsInteraction)
        captcha.receive("""{"error":"expired"}""")
        assertNull("过期了重新取", captcha.token)
        assertEquals(1, captcha.attempt)
        captcha.receive("""{"error":"failed"}""")
        assertTrue(captcha.failed)
        captcha.reset()
        assertFalse(captcha.failed)
        captcha.receive("not json")
        captcha.receive("""{"token":""}""")
        assertTrue("空令牌表示网站没开人机验证", captcha.isReady)
    }
}
