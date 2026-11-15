package com.badie.app.backend

import com.badie.app.models.Avatar
import com.badie.app.models.ChallengePolicy
import com.badie.app.models.GameMode
import com.badie.app.models.Gender
import com.badie.app.models.PlayStyle
import com.badie.app.models.SkillAssessment
import com.badie.app.models.SkillAssessmentSummary
import com.badie.app.models.SkillTier
import com.badie.app.models.VerificationStatus
import com.badie.app.remote.FakeServer
import com.badie.app.remote.RemoteError
import com.badie.app.remote.RemoteSession
import com.badie.app.remote.SessionStorage
import com.badie.app.remote.SupabaseClient
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.double
import kotlinx.serialization.json.jsonNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.io.IOException

/** 账号：登录以后读资料、第一次登录建资料、本机缓存。对应 iPhone 的 SupabaseClientTests 里“Backend in remote mode”那部分 */
class BackendTest {
    private val server = FakeServer()
    private val userId = "6f1c2c3e-0000-4000-8000-000000000001"
    private val clock = 1_800_000_000_000L
    private var saved: String? = null

    private fun backend(session: RemoteSession? = null, country: String = "US", transport: com.badie.app.remote.Transport = server.transport) = Backend(
        SupabaseClient(SessionStorage({ session }, {}), transport, now = { clock }),
        CacheStore({ saved }, { saved = it }),
        now = { clock }, deviceCountry = { country }, serverLocale = { "zh-Hans" },
    )

    private fun session() = RemoteSession("old", "r-old", clock + 3_600_000, userId, "alex@example.com")

    private fun token(access: String) =
        """{"access_token":"$access","refresh_token":"r-$access","expires_in":3600,"token_type":"bearer","user":{"id":"$userId","email":"alex@example.com"}}"""

    private fun profile(extra: String = "") =
        """{"id":"$userId","nickname":"Alex","country_code":"US","rating":4.33,"self_rating":4.33,"assessed_at":"2026-10-17T23:17:25.123456+00:00","show_on_boards":true,"challenge_policy":"similar","locale":"zh-Hans","created_at":"2026-10-17T23:17:25+00:00"$extra}"""

    /** 读资料要两个请求：资料和收藏的球馆 */
    private fun serveProfile(rows: String) {
        server.on("GET /rest/v1/profiles", rows)
        server.on("GET /rest/v1/favorite_venues", "[]")
    }

    private fun text(index: Int, key: String) = server.json(index)[key]?.jsonPrimitive?.content

    @Test
    fun signUpCreatesProfileAndCachesIt() = runTest {
        val backend = backend()
        server.on("POST /auth/v1/verify", token("fresh"))
        server.on("GET /rest/v1/profiles", "[]")
        val outcome = backend.verify(" Alex@Example.com ", "123456")
        assertEquals(AuthOutcome.NeedsProfile("alex@example.com"), outcome)
        assertEquals("邮箱统一小写、去空格", "alex@example.com", text(0, "email"))
        assertNull(backend.currentUser)

        server.on("POST /rest/v1/profiles", "", status = 201)
        server.on("POST /rest/v1/rpc/save_assessment", profile())
        server.on("GET /rest/v1/profiles", "[${profile()}]")
        server.on("GET /rest/v1/favorite_venues", """[{"venue_id":"v-us-ca-labc"}]""")
        server.on("POST /rest/v1/rpc/is_admin", "false")
        val assessment = SkillAssessmentSummary(4, needsCalibration = false, isReturning = false, assessedAt = clock, rating = 4.33)
        val user = backend.register(" Alex ", Gender.Unspecified, Avatar("🏸", 2), assessment, mapOf("clear" to 3))

        assertEquals("Alex", text(2, "nickname"))
        assertEquals(userId, text(2, "id"))
        assertEquals("US", text(2, "country_code"))
        assertEquals("没选性别发 null", server.json(2).getValue("gender"), server.json(2).getValue("gender").jsonNull)
        assertEquals(4.33, server.json(3).getValue("p_rating").jsonPrimitive.double, 0.01)
        assertEquals("3", server.json(3).getValue("p_answers").jsonObject.getValue("clear").jsonPrimitive.content)
        assertEquals(userId, user.id)
        assertEquals("Alex", backend.currentUser?.nickname)
        assertEquals("头像的表情先存在本机", "🏸", backend.currentUser?.avatar?.symbol)
        assertEquals(ChallengePolicy.SimilarLevel, backend.currentUser?.privacy?.challengePolicy)
        assertEquals(SkillTier.ofRating(4.33), backend.currentUser?.assessment?.tier)
        assertEquals(listOf("v-us-ca-labc"), backend.favoriteVenueIds)
        assertFalse(backend.isAdmin)

        // 存进了本机：下次打开不用等网络
        val reopened = backend(session())
        assertEquals("Alex", reopened.currentUser?.nickname)
        assertEquals("🏸", reopened.currentUser?.avatar?.symbol)
    }

    @Test
    fun existingAccountSignsStraightIn() = runTest {
        val backend = backend()
        val answers = SkillAssessment.levelCardDemoAnswers.entries.joinToString(",") { "\"${it.key}\":${it.value}" }
        server.on("POST /auth/v1/token", token("pw"))
        server.on(
            "GET /rest/v1/profiles",
            "[${profile(""","gender":"female","preferred_mode":"singles","tag":42,"friend_code":"abc","verified_kind":"tournament","verified_rating":7.0,"show_as_regular":true,"card_color":"mint","locale":"en","assessment":{$answers}""")}]",
        )
        server.on("GET /rest/v1/favorite_venues", "[]")
        server.on("POST /rest/v1/rpc/is_admin", "true")
        server.on("PATCH /rest/v1/profiles", "")
        val outcome = backend.signIn("alex@example.com", "shuttle rally", captchaToken = "cap")

        val user = (outcome as AuthOutcome.SignedIn).user
        assertEquals(Gender.Female, user.gender)
        assertEquals(GameMode.Singles, user.preferredMode)
        assertEquals("#0042", user.tagText)
        assertEquals("https://badie.rsvp/add/abc/", user.friendLink)
        assertEquals(VerificationStatus.Tournament, user.verificationStatus)
        assertEquals(SkillTier(7), user.displayTier)
        assertTrue(user.privacy.showsAsRegular)
        assertEquals("mint", user.cardColor.rawValue)
        assertEquals("问卷答案带回来，能算打法", PlayStyle.Cannon, user.assessment?.play?.style)
        assertTrue(backend.isAdmin)
        // 界面语言和服务器记的不一样：改成现在的（通知、邮件跟着换）
        assertEquals("PATCH", server.requests.last().method)
        assertEquals("zh-Hans", server.json(server.requests.lastIndex)["locale"]?.jsonPrimitive?.content)
    }

    @Test
    fun profileWithoutAssessmentCountsAsSkipped() = runTest {
        val backend = backend(session())
        serveProfile("""[{"id":"$userId","nickname":"Sam","rating":3,"show_on_boards":false,"challenge_policy":"nobody","locale":"zh-Hans","assessment":"oops"}]""")
        val user = backend.refreshProfile()!!
        assertTrue(user.needsAssessment)
        assertNull(user.assessment)
        assertEquals(SkillTier(3), user.displayTier)
        assertEquals(ChallengePolicy.Nobody, user.privacy.challengePolicy)
        assertFalse("服务器没给的开关按默认", user.privacy.showsAsRegular)
        assertEquals(Gender.Unspecified, user.gender)
    }

    @Test
    fun restoreKeepsTheCacheOfflineAndSignsOutWhenExpired() = runTest {
        // 先登录一次，留下缓存
        val first = backend(session())
        serveProfile("[${profile()}]")
        assertNotNull(first.refreshProfile())

        // 离线：保持缓存里的登录状态
        val offline = backend(session(), transport = { throw IOException("offline") })
        offline.restoreSession()
        assertEquals("Alex", offline.currentUser?.nickname)

        // 本机没有登录状态了（被清掉）：回到登录页，缓存也清掉
        val signedOut = backend(null)
        signedOut.restoreSession()
        assertNull(signedOut.currentUser)
        assertNull(saved)
    }

    @Test
    fun restoreSignsOutWhenTheProfileIsGone() = runTest {
        saved = null
        val backend = backend(session())
        server.on("GET /rest/v1/profiles", "[]")
        backend.restoreSession()
        assertNull(backend.currentUser)
    }

    @Test
    fun genderAndVisibilityAreSavedAndRolledBackOnFailure() = runTest {
        val backend = backend(session())
        serveProfile("[${profile()}]")
        backend.refreshProfile()
        server.on("PATCH /rest/v1/profiles", "")
        backend.updateGender(Gender.Male)
        assertEquals("male", server.json(server.requests.lastIndex)["gender"]?.jsonPrimitive?.content)
        assertEquals(Gender.Male, backend.currentUser?.gender)

        // 没存上：按服务器的数据恢复
        server.on("PATCH /rest/v1/profiles", """{"message":"not_allowed"}""", status = 400)
        serveProfile("[${profile()}]")
        try {
            backend.updateShowsAsRegular(true)
            fail("应该报错")
        } catch (e: RemoteError) {
            assertEquals(RemoteError.Server("not_allowed"), e)
        }
        assertEquals(false, backend.currentUser?.privacy?.showsAsRegular)
    }

    @Test
    fun rules() {
        assertTrue(Backend.isValidEmail(" Alex@Example.com "))
        assertFalse(Backend.isValidEmail("alex@example"))
        assertFalse(Backend.isValidEmail("alex example@x.co"))
        assertTrue(Backend.isValidNickname("阿杰"))
        assertTrue(Backend.isValidNickname(" 😀😀 "))
        assertFalse(Backend.isValidNickname("杰"))
        assertFalse(Backend.isValidNickname("1234567890123"))
    }

    @Test
    fun unknownCountryRegistersAsDefault() = runTest {
        val backend = backend(session(), country = "BR")
        server.on("POST /rest/v1/profiles", "", status = 201)
        serveProfile("[${profile()}]")
        backend.register("Alex", Gender.Male, Avatar.default(userId), assessment = null, answers = emptyMap())
        assertEquals("US", text(0, "country_code"))
        assertEquals("male", text(0, "gender"))
        assertEquals("没做问卷就不存定级", "/rest/v1/profiles", server.path(1))
    }
}
