package com.badie.app.shell

import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.IOException

class SideloadUpdatesTest {
    private fun release(code: Long, minSdk: Int = 26, url: String = SideloadUpdates.APK_URL) =
        """{"versionCode":$code,"versionName":"1.0.$code","url":"$url","sha256":"ab","minSdk":$minSdk,"size":123}"""

    private class Clock(var time: Long = 1_000_000_000_000L)

    private fun updates(
        installed: Long = 5,
        enabled: Boolean = true,
        sdk: Int = 34,
        store: UpdateStore = MemoryStore(),
        clock: Clock = Clock(),
        fetch: suspend () -> String?,
    ) = SideloadUpdates(enabled, installed, sdk, store, fetch, now = { clock.time })

    @Test
    fun comparesVersionCodes() {
        assertTrue(SideloadUpdates.isNewer(6, 5))
        assertFalse(SideloadUpdates.isNewer(5, 5))
        assertFalse(SideloadUpdates.isNewer(4, 5))
        assertTrue(SideloadUpdates.isNewer(1000, 999))
    }

    @Test
    fun skipsPlayInstallsAndDebugBuilds() {
        assertTrue(SideloadUpdates.installedFromPlay("com.android.vending"))
        assertFalse(SideloadUpdates.installedFromPlay("com.google.android.packageinstaller"))
        assertFalse(SideloadUpdates.installedFromPlay(null))
        assertFalse(SideloadUpdates.shouldCheck(debug = false, installer = "com.android.vending"))
        assertFalse(SideloadUpdates.shouldCheck(debug = true, installer = "com.google.android.packageinstaller"))
        assertTrue(SideloadUpdates.shouldCheck(debug = false, installer = "com.google.android.packageinstaller"))
        // adb 装的、系统说不出来源的，也算自己装的
        assertTrue(SideloadUpdates.shouldCheck(debug = false, installer = null))
    }

    @Test
    fun offersANewerVersion() = runTest {
        val updates = updates { release(6) }
        updates.checkIfDue()
        assertEquals(6L, updates.available?.versionCode)
        assertEquals("1.0.6", updates.available?.versionName)
    }

    @Test
    fun staysQuietWhenUpToDateOrTooNewForThePhone() = runTest {
        val same = updates { release(5) }
        same.checkIfDue()
        assertNull(same.available)
        val needsNewerAndroid = updates(sdk = 26) { release(6, minSdk = 28) }
        needsNewerAndroid.checkIfDue()
        assertNull(needsNewerAndroid.available)
    }

    @Test
    fun doesNothingWhenDisabled() = runTest {
        var calls = 0
        val updates = updates(enabled = false) { calls++; release(9) }
        updates.checkIfDue()
        assertEquals(0, calls)
        assertNull(updates.available)
    }

    @Test
    fun checksAtMostOnceADay() = runTest {
        val clock = Clock()
        val store = MemoryStore()
        var calls = 0
        var latest = 6L
        val fetch: suspend () -> String? = { calls++; release(latest) }
        updates(store = store, clock = clock, fetch = fetch).checkIfDue()
        // 同一天再打开：不再下载，用上次的结果
        latest = 7
        clock.time += SideloadUpdates.DAY_MILLIS - 1
        val again = updates(store = store, clock = clock, fetch = fetch)
        again.checkIfDue()
        assertEquals(1, calls)
        assertEquals(6L, again.available?.versionCode)
        // 过了一天：再查
        clock.time += 1
        val nextDay = updates(store = store, clock = clock, fetch = fetch)
        nextDay.checkIfDue()
        assertEquals(2, calls)
        assertEquals(7L, nextDay.available?.versionCode)
    }

    @Test
    fun retriesNextLaunchWhenOffline() = runTest {
        val store = MemoryStore()
        var offline = true
        val fetch: suspend () -> String? = { if (offline) throw IOException("offline") else release(6) }
        val first = updates(store = store, fetch = fetch)
        first.checkIfDue()
        assertNull(first.available)
        offline = false
        val second = updates(store = store, fetch = fetch)
        second.checkIfDue()
        assertEquals(6L, second.available?.versionCode)
    }

    @Test
    fun ignoresMissingOrBrokenFiles() = runTest {
        val notFound = updates { null }
        notFound.checkIfDue()
        assertNull(notFound.available)
        val broken = updates { "<html>" }
        broken.checkIfDue()
        assertNull(broken.available)
        assertNull(SideloadUpdates.parse("""{"versionCode":0,"versionName":"","url":""}"""))
    }

    @Test
    fun dismissingHidesThisVersionUntilANewerOne() = runTest {
        val clock = Clock()
        val store = MemoryStore()
        var latest = 6L
        val fetch: suspend () -> String? = { release(latest) }
        val updates = updates(store = store, clock = clock, fetch = fetch)
        updates.checkIfDue()
        updates.dismiss()
        assertNull(updates.available)
        clock.time += SideloadUpdates.DAY_MILLIS
        val later = updates(store = store, clock = clock, fetch = fetch)
        later.checkIfDue()
        assertNull(later.available)
        latest = 7
        clock.time += SideloadUpdates.DAY_MILLIS
        val newer = updates(store = store, clock = clock, fetch = fetch)
        newer.checkIfDue()
        assertEquals(7L, newer.available?.versionCode)
    }

    @Test
    fun onlyOpensOurOwnDownloadLink() {
        val ours = SideloadUpdates.parse(release(6, url = "https://badie.rsvp/android/badie.apk"))!!
        assertEquals("https://badie.rsvp/android/badie.apk", SideloadUpdates.downloadUrl(ours))
        val other = SideloadUpdates.parse(release(6, url = "https://example.com/badie.apk"))!!
        assertEquals(SideloadUpdates.APK_URL, SideloadUpdates.downloadUrl(other))
    }
}
