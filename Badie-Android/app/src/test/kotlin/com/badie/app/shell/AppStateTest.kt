package com.badie.app.shell

import com.badie.app.design.Toast
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class AppStateTest {
    @Test
    fun toastDisappearsAfterAWhile() = runTest {
        val state = AppState(backgroundScope)
        state.showToast("资料已保存", Toast.Style.Success)
        assertEquals("资料已保存", state.toast?.message)
        advanceTimeBy(AppState.TOAST_MILLIS - 1)
        assertEquals(Toast.Style.Success, state.toast?.style)
        advanceTimeBy(2)
        runCurrent()
        assertNull(state.toast)
    }

    @Test
    fun aNewToastRestartsTheClock() = runTest {
        val state = AppState(backgroundScope)
        state.showToast("一")
        advanceTimeBy(2000)
        state.showToast("二")
        advanceTimeBy(2000)
        assertEquals("二", state.toast?.message)
        advanceTimeBy(700)
        runCurrent()
        assertNull(state.toast)
    }

    @Test
    fun launchEndsOnce() {
        val state = AppState(kotlinx.coroutines.CoroutineScope(kotlinx.coroutines.Dispatchers.Unconfined))
        assertEquals(AppState.Phase.Launching, state.phase)
        state.finishLaunch()
        assertEquals(AppState.Phase.Main, state.phase)
    }
}
