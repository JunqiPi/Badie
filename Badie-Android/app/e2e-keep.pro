# 只在端到端测试跑压缩包时用（-Pbadie.minify=true，见 app/build.gradle.kts），正式包不用。
# 测试 APK 里不带 App 已有的库，直接调 App 里的：R8 删掉了测试要用、App 自己用不到的方法，测试就会 NoSuchMethodError。
# 所以把测试碰到的整个库留下。App 自己的代码（com.badie.app）照常压缩，只留测试直接调的几个。
# 测试 APK 由 AGP 按 App 的映射表改名，所以库可以混淆的地方留着也没关系，这里为了简单整个不动。

# 测试直接调的：取界面文字、拼 JSON
-keep class com.badie.app.l10n.L10n { *; }
-keep class com.badie.app.remote.RemoteJSONKt { *; }

# Compose 测试库、UiAutomator、AndroidX Test 和测试代码用到的库
-keep class kotlin.** { *; }
-keep class kotlinx.coroutines.** { *; }
-keep class kotlinx.serialization.json.** { *; }
-keep class kotlinx.serialization.KSerializer { *; }
-keep class okhttp3.** { *; }
-keep class okio.** { *; }
-keep class androidx.compose.** { *; }
-keep class androidx.activity.** { *; }
-keep class androidx.lifecycle.** { *; }
-keep class androidx.core.** { *; }
-keep class androidx.tracing.** { *; }
-keep class androidx.annotation.** { *; }
-keep class androidx.concurrent.** { *; }
-keep class com.google.common.util.concurrent.ListenableFuture { *; }
