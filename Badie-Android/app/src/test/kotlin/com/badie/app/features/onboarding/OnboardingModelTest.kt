package com.badie.app.features.onboarding

import com.badie.app.TestSupport
import com.badie.app.TestSupport.serveProfile
import com.badie.app.design.Toast
import com.badie.app.models.GameMode
import com.badie.app.models.Gender
import com.badie.app.models.SkillAssessment
import com.badie.app.models.SkillTier
import com.badie.app.models.VenueStatus
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

    private fun TestScope.flow(signedIn: Boolean = false): Pair<OnboardingModel, AppState> {
        val appState = AppState(backgroundScope, TestSupport.backend(server, if (signedIn) TestSupport.session() else null))
        appState.finishLaunch()
        val model = OnboardingModel(appState, CaptchaModel(), passwordLookup = { HttpResponse(200, ByteArray(0)) }, now = { TestSupport.CLOCK })
        return model to appState
    }

    private val here = com.badie.app.models.Coordinate(34.07, -118.03)

    /** 附近的球馆：最近的一家、远一点的两家，还有一家坐标只是大概的 */
    private val nearby = listOf(
        "v-near" to 34.075, "v-mid" to 34.10, "v-far" to 34.12, "v-rough" to 34.071,
    ).joinToString(",", "[", "]") { (id, lat) ->
        val name = mapOf("v-near" to "Alpha Badminton", "v-mid" to "Mid Club", "v-far" to "Far Gym", "v-rough" to "Somewhere")[id]
        """{"venue":{"id":"$id","name":"$name","lat":$lat,"lon":-118.03,"country_code":"US","status":"confirmed","location_approximate":${id == "v-rough"}},"distance_m":0}"""
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

        // 常去球馆必选：开了定位就先替人选上最近的一家
        model.preferredMode = GameMode.Singles
        assertFalse("还没选常去球馆", model.canContinue)
        server.on("POST /rest/v1/rpc/venues_near", nearby)
        model.locationUpdated(here)
        assertEquals(listOf("v-near"), model.favoriteVenueIds.toList())
        assertTrue(model.canContinue)

        server.on("POST /rest/v1/profiles", "", status = 201)
        server.on("POST /rest/v1/rpc/save_assessment", "")
        server.serveProfile("[${TestSupport.profile()}]")
        server.on("PATCH /rest/v1/profiles", "")
        server.on("POST /rest/v1/favorite_venues", "", status = 201)
        server.on("PATCH /rest/v1/profiles", "")
        val before = server.requests.size
        model.primaryAction()

        assertEquals("Alex", text(before, "nickname"))
        assertEquals("male", text(before, "gender"))
        assertEquals(4.0, server.json(before + 1).getValue("p_rating").jsonPrimitive.content.toDouble(), 0.001)
        assertEquals(14, server.json(before + 1).getValue("p_answers").jsonObject.size)
        val patches = server.requests.indices.filter { server.requests[it].method == "PATCH" }
        assertEquals("注册后默认在附近的人里显示", "true", text(patches[0], "show_as_regular"))
        assertEquals("singles", text(patches[1], "preferred_mode"))
        val favorite = server.requests.indices.first { server.path(it) == "/rest/v1/favorite_venues" && server.requests[it].method == "POST" }
        assertEquals("v-near", text(favorite, "venue_id"))
        assertEquals(listOf("v-near"), appState.backend.favoriteVenueIds)
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
    fun favoriteVenuesNeedOneAndAtMostThree() = runTest {
        // 到最后一步时已经登录了
        val (model, _) = flow(signedIn = true)
        // 没开定位：按默认城市列出附近的，但不替人选
        server.on("POST /rest/v1/rpc/venues_near", nearby)
        model.locationUpdated(null)
        assertEquals(listOf("v-near", "v-mid", "v-far"), model.nearbyVenues.map { it.id })
        assertTrue("没定位不替人选", model.favoriteVenueIds.isEmpty())
        assertEquals("坐标只是大概的不列出来", null, model.nearbyVenues.firstOrNull { it.id == "v-rough" })

        // 有定位：选最近的；用户自己删掉以后不再选回来
        server.on("POST /rest/v1/rpc/venues_near", nearby)
        model.locationUpdated(here)
        assertEquals(listOf("v-near"), model.favoriteVenueIds.toList())
        assertEquals(here.latitude, server.json(server.requests.lastIndex)["lat"]!!.jsonPrimitive.content.toDouble(), 0.0001)
        model.toggleVenue("v-near")
        server.on("POST /rest/v1/rpc/venues_near", nearby)
        model.locationUpdated(here)
        assertTrue(model.favoriteVenueIds.isEmpty())

        // 最多 3 家
        for (id in listOf("v-near", "v-mid", "v-far", "v-extra")) model.toggleVenue(id)
        assertEquals(listOf("v-near", "v-mid", "v-far"), model.favoriteVenueIds.toList())
        assertEquals("Alpha Badminton", model.venue("v-near")?.name)

        // 按名字找
        server.on("GET /rest/v1/venues", """[{"id":"v-s","name":"Sun Badminton","lat":34.1,"lon":-118.1,"country_code":"US"}]""")
        assertEquals(listOf("v-s"), model.searchVenues(" Sun ").map { it.id })
        val query = server.query(server.requests.lastIndex)!!
        assertTrue(query, query.contains("name.ilike.*Sun*"))
        assertTrue(query, query.contains("merged_into=is.null"))
        assertTrue("空的不搜", model.searchVenues("  ").isEmpty())
    }

    @Test
    fun noVenueListedCanStillFinish() = runTest {
        val (model, appState) = flow(signedIn = true)
        model.nickname = "Alex"
        model.gender = Gender.Male
        model.skipAssessment()
        assertFalse("还没选常去球馆", model.canContinue)
        // 我们还没收录的地方：点“列表里没有我的球馆”先继续，以后在球馆页再选
        model.noVenueListed = true
        assertTrue(model.canContinue)

        server.on("POST /rest/v1/profiles", "", status = 201)
        server.serveProfile("[${TestSupport.profile()}]")
        server.on("PATCH /rest/v1/profiles", "")
        model.primaryAction()
        assertTrue("没选就不存常去球馆", server.requests.indices.none { server.path(it) == "/rest/v1/favorite_venues" && server.requests[it].method == "POST" })
        assertTrue(appState.backend.favoriteVenueIds.isEmpty())
        assertEquals(AppState.Phase.Main, appState.phase)
    }

    @Test
    fun nearestPrefersListedVenuesInRange() {
        fun venue(id: String, km: Double, status: VenueStatus = VenueStatus.Confirmed) =
            com.badie.app.models.Venue(id, id, lat = here.latitude + km / 111.0, lon = here.longitude, countryCode = "US", status = status)
        val venues = listOf(venue("close-unconfirmed", 0.5, VenueStatus.Unconfirmed), venue("listed", 2.0), venue("too-far", 30.0))
        assertEquals("listed", com.badie.app.models.Venue.nearest(venues, here, 10.0)?.id)
        assertEquals("范围里只有没核实的也选它", "close-unconfirmed", com.badie.app.models.Venue.nearest(venues.take(1), here, 10.0)?.id)
        assertNull(com.badie.app.models.Venue.nearest(venues.drop(2), here, 10.0))
        val address = com.badie.app.models.Venue("v", "v", lat = 0.0, lon = 0.0, street = "10410 Valley Blvd", unit = "Unit B", city = "El Monte", region = "CA", countryCode = "US")
        assertEquals("10410 Valley Blvd, Unit B, El Monte, CA", address.compactAddress)
        val chinese = com.badie.app.models.Venue("v", "v", lat = 0.0, lon = 0.0, street = "工体北路4号", city = "朝阳区", region = "北京市", countryCode = "CN")
        assertEquals("朝阳区工体北路4号", chinese.compactAddress)
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
