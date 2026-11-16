package com.badie.app.features.profile

import com.badie.app.TestSupport
import com.badie.app.TestSupport.serveProfile
import com.badie.app.backend.BackendError
import com.badie.app.backend.ProfileApi
import com.badie.app.backend.ProfileStore
import com.badie.app.models.ChallengePolicy
import com.badie.app.models.GameMode
import com.badie.app.models.Gender
import com.badie.app.models.RecurringTimeSlot
import com.badie.app.models.SkillTier
import com.badie.app.models.VerificationRequest
import com.badie.app.models.VerificationStatus
import com.badie.app.remote.FakeServer
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.double
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

/** “我的”这一块调服务器和存本机的部分。对应 iPhone 的 MockBackendTests、RankingTests、SupabaseClientTests 里相关的几条 */
class ProfileApiTest {
    private val server = FakeServer()
    private val store = ProfileStore.memory

    private suspend fun signedIn(extra: String = ""): ProfileApi {
        val backend = TestSupport.backend(server, TestSupport.session())
        server.serveProfile("[${TestSupport.profile(extra)}]")
        backend.refreshProfile()
        server.requests.clear()
        return ProfileApi(backend, store, CoroutineScope(Dispatchers.Unconfined), now = { TestSupport.CLOCK })
    }

    private fun slot(day: Int, start: Int = 19, end: Int = 21, active: Boolean = true) =
        RecurringTimeSlot.create(day, start, endHour = end, isActive = active, id = "slot-$day-$start")

    private fun lastPatch(): Pair<String, kotlinx.serialization.json.JsonObject> {
        val index = server.requests.indexOfLast { it.method == "PATCH" }
        return server.path(index) to server.json(index)
    }

    @Test
    fun recurringSlotLimit() = runTest {
        val api = signedIn()
        server.on("PATCH /rest/v1/profiles", "")
        val six = (1..6).map { slot(it % 7 + 1) }
        try {
            api.saveRecurringSlots(six)
            fail("最多 5 个")
        } catch (_: BackendError) {
        }
        api.saveRecurringSlots(six.take(5))
        assertEquals(5, api.recurringSlots().size)
        // 打开的几段传到资料里，附近的人能看到
        val (path, body) = lastPatch()
        assertEquals("/rest/v1/profiles", path)
        assertEquals(5, body.getValue("usual_times").jsonArray.size)
        assertEquals("19:00", body.getValue("usual_times").jsonArray[0].jsonObject.getValue("start").jsonPrimitive.content)
    }

    @Test
    fun slotDurationAndInactiveSlots() = runTest {
        val api = signedIn()
        server.on("PATCH /rest/v1/profiles", "")
        try {
            api.saveRecurringSlots(listOf(slot(2, start = 19, end = 19)))
            fail("每段 1–8 小时")
        } catch (_: BackendError) {
        }
        server.on("PATCH /rest/v1/profiles", "")
        api.saveRecurringSlots(listOf(slot(2), slot(3, active = false)))
        assertEquals("关掉的一段只在本机", 1, lastPatch().second.getValue("usual_times").jsonArray.size)
        // 存在本机：换一个实例（重开 App）还在
        val again = ProfileApi(api.backend, store, CoroutineScope(Dispatchers.Unconfined))
        assertEquals(listOf("slot-2-19", "slot-3-19"), again.recurringSlots().map { it.id })
    }

    @Test
    fun usualTimesFromServerWin() = runTest {
        val api = signedIn()
        server.on("PATCH /rest/v1/profiles", "")
        api.saveRecurringSlots(listOf(slot(2), slot(4, active = false)))
        // 网站上改成了周六下午：用服务器的，本机关掉的那段留着
        server.on("GET /rest/v1/profiles", """[{"usual_times":[{"weekday":7,"start":"14:00","end":"17:00"}]}]""")
        api.syncUsualTimes()
        val slots = api.recurringSlots()
        assertEquals(listOf(7, 4), slots.map { it.dayOfWeek })
        assertEquals(listOf(true, false), slots.map { it.isActive })
    }

    @Test
    fun localUsualTimesAreUploadedOnce() = runTest {
        val api = signedIn()
        server.on("PATCH /rest/v1/profiles", "")
        api.saveRecurringSlots(listOf(slot(2)))
        server.requests.clear()
        server.on("GET /rest/v1/profiles", """[{"usual_times":null}]""")
        server.on("PATCH /rest/v1/profiles", "")
        api.syncUsualTimes()
        assertEquals(1, lastPatch().second.getValue("usual_times").jsonArray.size)
        server.requests.clear()
        server.on("GET /rest/v1/profiles", """[{"usual_times":[]}]""")
        api.syncUsualTimes()
        assertTrue("只补传一次", server.requests.none { it.method == "PATCH" })
    }

    @Test
    fun profileRejectsAdvertising() = runTest {
        val api = signedIn()
        val me = api.backend.currentUser!!
        try {
            api.saveProfile(me.copy(bio = "加微信 abc123 约球"))
            fail("简介不能留联系方式")
        } catch (error: BackendError) {
            assertEquals("昵称和简介里不能留联系方式或链接", error.message)
        }
        try {
            api.saveProfile(me.copy(nickname = "A"))
            fail("昵称 2–12 个字")
        } catch (_: BackendError) {
        }
        assertTrue(server.requests.isEmpty())
    }

    @Test
    fun saveProfileSendsOnlyServerFields() = runTest {
        val api = signedIn()
        val me = api.backend.currentUser!!
        server.on("PATCH /rest/v1/profiles", "")
        api.saveProfile(me.copy(bio = "周末双打", preferredMode = GameMode.Doubles, avatar = me.avatar.copy(symbol = "🏸", paletteIndex = 4)))
        var body = lastPatch().second
        assertEquals("doubles", body.getValue("preferred_mode").jsonPrimitive.content)
        assertFalse("昵称没改不传", "nickname" in body)
        assertFalse("bio" in body)
        assertEquals("一句话介绍只存在本机", "周末双打", api.backend.currentUser?.bio)
        assertEquals("🏸", api.backend.currentUser?.avatar?.symbol)

        server.on("PATCH /rest/v1/profiles", "")
        api.saveProfile(api.backend.currentUser!!.copy(nickname = " 阿杰 ", gender = Gender.Female, preferredMode = null))
        body = lastPatch().second
        assertEquals("阿杰", body.getValue("nickname").jsonPrimitive.content)
        assertEquals("female", body.getValue("gender").jsonPrimitive.content)
        assertEquals("“都行”传空", JsonNull, body.getValue("preferred_mode"))
        assertEquals("阿杰", api.backend.currentUser?.nickname)
    }

    @Test
    fun privacyGoesToProfileColumns() = runTest {
        val api = signedIn()
        val privacy = api.backend.currentUser!!.privacy
        server.on("PATCH /rest/v1/profiles", "")
        api.updatePrivacy(privacy.copy(challengePolicy = ChallengePolicy.SimilarLevel, emailAlerts = true, showsWhenSearching = false))
        val body = lastPatch().second
        assertEquals("similar", body.getValue("challenge_policy").jsonPrimitive.content)
        assertEquals("true", body.getValue("email_alerts").jsonPrimitive.content)
        assertEquals("false", body.getValue("show_searching").jsonPrimitive.content)
        assertEquals(7, body.size)
        assertEquals(ChallengePolicy.SimilarLevel, api.backend.currentUser?.privacy?.challengePolicy)
    }

    @Test
    fun verificationGoesThroughTheServer() = runTest {
        val api = signedIn()
        server.on("POST /rest/v1/rpc/request_verification", "\"v1\"")
        server.on(
            "POST /rest/v1/rpc/my_verification",
            """{"id":"v1","kind":"tournament","claimed_rating":7,"evidence":"https://usab.tournamentsoftware.com/x","name_on_record":"Alex Chen","note":"","status":"pending","created_at":"2026-10-17T10:00:00+00:00","reviewed_at":null,"review_note":null,"approved_rating":null}""",
        )
        api.submitVerification(VerificationStatus.Tournament, SkillTier(7), " usab.tournamentsoftware.com/x ", "Alex Chen", "")
        val body = server.json(0)
        assertEquals("tournament", body.getValue("p_kind").jsonPrimitive.content)
        assertEquals(7.0, body.getValue("p_rating").jsonPrimitive.double, 0.01)
        assertEquals("usab.tournamentsoftware.com/x", body.getValue("p_evidence").jsonPrimitive.content)
        assertEquals(VerificationRequest.Status.Pending, api.verification?.status)
        assertEquals(VerificationStatus.Tournament, api.verification?.kind)

        server.on("POST /rest/v1/rpc/withdraw_verification", "")
        api.withdrawVerification()
        assertNull(api.verification)
        server.on("POST /rest/v1/rpc/my_verification", "null")
        api.refreshVerification()
        assertNull(api.verification)
    }

    @Test
    fun feedbackCarriesContext() = runTest {
        val api = signedIn()
        server.on("POST /rest/v1/rpc/submit_feedback", "")
        api.submitFeedback("bug", "按钮点不动", mapOf("platform" to "android", "app" to "1.0 (1)"))
        val body = server.json(0)
        assertEquals("bug", body.getValue("p_kind").jsonPrimitive.content)
        assertEquals("按钮点不动", body.getValue("p_body").jsonPrimitive.content)
        assertEquals("android", body.getValue("p_context").jsonObject.getValue("platform").jsonPrimitive.content)
    }

    @Test
    fun record() = runTest {
        val api = signedIn()
        server.on("POST /rest/v1/rpc/my_record", """{"games":6,"wins":4,"draws":0,"rounds":14,"round_wins":9,"opponents":3,"gap":0.42,"public":true,"losses":2}""")
        api.refreshRecord()
        assertEquals(true, api.winRate?.isPublic)
        assertEquals("胜率按局算", 64, api.winRate?.percentage)
    }

    @Test
    fun deleteAccountClearsPhotosThenDeletes() = runTest {
        val api = signedIn(""","avatar_path":"${TestSupport.USER_ID}/a.jpg"""")
        server.on("PATCH /rest/v1/profiles", "")
        api.saveRecurringSlots(listOf(slot(2)))
        server.requests.clear()
        server.on("POST /rest/v1/rpc/set_avatar", "")
        server.on("POST /storage/v1/object/list/avatars", """[{"name":"a.jpg"}]""")
        server.onPrefix("DELETE /storage/v1/object/avatars/", "{}")
        server.on("POST /rest/v1/rpc/delete_account", "")
        server.on("POST /auth/v1/logout", "")
        api.deleteAccount()
        val paths = server.requests.map { "${it.method} ${java.net.URI(it.url).path}" }
        assertEquals("POST /rest/v1/rpc/set_avatar", paths.first())
        assertEquals(JsonNull, server.json(0).getValue("p_path"))
        assertTrue(paths.indexOf("POST /rest/v1/rpc/delete_account") > paths.indexOfFirst { it.startsWith("DELETE /storage") })
        assertNull(api.backend.currentUser)
        assertNull(store.load("recurringSlots-${TestSupport.USER_ID}"))
    }


    @Test
    fun favoriteVenueNames() = runTest {
        val backend = TestSupport.backend(server, TestSupport.session())
        server.on("GET /rest/v1/profiles", "[${TestSupport.profile()}]")
        server.on("GET /rest/v1/favorite_venues", """[{"venue_id":"v1"},{"venue_id":"v2"}]""")
        backend.refreshProfile()
        val api = ProfileApi(backend, store, CoroutineScope(Dispatchers.Unconfined))
        server.requests.clear()
        // venues_by_ids 返回整行：只取名字和城市
        server.on(
            "POST /rest/v1/rpc/venues_by_ids",
            """[{"id":"v2","name":"LABC","city":"Los Angeles","lat":34.0,"lon":-118.0,"country_code":"US","amenities":[]},""" +
                """{"id":"v1","name":"Arcadia","city":null}]""",
        )
        api.refreshFavoriteVenues()
        assertEquals("/rest/v1/rpc/venues_by_ids", server.path(0))
        assertEquals("""["v1","v2"]""", server.json(0).getValue("p_ids").toString())
        assertEquals("按收藏的先后", listOf("Arcadia", "LABC"), api.favoriteVenues().map { it.name })
    }
}
