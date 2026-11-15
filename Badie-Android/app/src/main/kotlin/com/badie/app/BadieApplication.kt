package com.badie.app

import android.app.Application
import com.badie.app.shell.AppEnvironment
import kotlinx.coroutines.MainScope

class BadieApplication : Application() {
    /** 整个 App 一份，Activity 重建（转屏、换语言）时不丢 */
    val environment: AppEnvironment by lazy { AppEnvironment(MainScope()) }
}
