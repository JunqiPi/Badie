import groovy.json.JsonSlurper
import java.security.MessageDigest

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
}

android {
    namespace = "com.badie.app"
    compileSdk = 37

    defaultConfig {
        applicationId = "com.badie.app"
        minSdk = 26
        targetSdk = 37
        versionCode = 1
        versionName = "1.0.5"
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }

    testOptions {
        unitTests {
            // 截图测试和文字测试要读真的资源（译文、图标、字体）
            isIncludeAndroidResources = true
            all {
                // 每次都重新出图，放在 app/build/outputs/roborazzi
                it.systemProperty("roborazzi.test.record", "true")
                it.maxHeapSize = "2g"
                // 截图也算测试的产出：测试从缓存取结果时，截图一起取回来
                it.outputs.dir(it.project.layout.buildDirectory.dir("outputs/roborazzi"))
                // 模拟 Android 环境的测试库要碰 JDK 内部的类
                it.jvmArgs("--add-exports=java.base/jdk.internal.access=ALL-UNNAMED", "--add-opens=java.base/jdk.internal.access=ALL-UNNAMED")
            }
        }
    }

    // 只带我们有译文的 10 种语言；依赖库自带的其他语言不打进包
    androidResources {
        localeFilters += listOf("en", "b+zh+Hans", "b+zh+Hant", "ja", "ko", "in", "ms", "th", "vi", "hi")
    }
}

dependencies {
    implementation(platform(libs.compose.bom))
    implementation(libs.compose.ui)
    implementation(libs.compose.foundation)
    implementation(libs.compose.material3)
    implementation(libs.compose.ui.tooling.preview)
    debugImplementation(libs.compose.ui.tooling)
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.appcompat)
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.navigation3.runtime)
    implementation(libs.androidx.navigation3.ui)
    implementation(libs.kotlinx.coroutines.android)
    implementation(libs.kotlinx.serialization.json)
    implementation(libs.okhttp)

    testImplementation(libs.junit)
    testImplementation(libs.kotlinx.coroutines.test)
    // 截图测试：没有模拟器也能把界面渲染成图（见 src/test/.../ScreenshotTest.kt）
    testImplementation(platform(libs.compose.bom))
    testImplementation(libs.compose.ui.test.junit4)
    debugImplementation(libs.compose.ui.test.manifest)
    testImplementation(libs.robolectric)
    testImplementation(libs.roborazzi)
    testImplementation(libs.roborazzi.compose)
}

// MARK: - 界面文字
// 文字只有一份：iPhone 的 Localizable.xcstrings（key 是简体中文原文）。每次构建把它转成安卓的 strings.xml
// 和一张“原文 → 资源 id”的表，代码里用 tr("原文") 取。改文字只改 xcstrings。

abstract class GenerateStrings : DefaultTask() {
    @get:InputFile
    @get:PathSensitive(PathSensitivity.NONE)
    abstract val catalog: RegularFileProperty

    @get:OutputDirectory
    abstract val resDir: DirectoryProperty

    @get:OutputDirectory
    abstract val kotlinDir: DirectoryProperty

    /// 安卓的资源目录名。values 是找不到对应语言时用的，和 iPhone 一样用英文
    private val folders = linkedMapOf(
        "en" to "values", "zh-Hans" to "values-b+zh+Hans", "zh-Hant" to "values-b+zh+Hant",
        "ja" to "values-ja", "ko" to "values-ko", "id" to "values-in", "ms" to "values-ms",
        "th" to "values-th", "vi" to "values-vi", "hi" to "values-hi",
    )
    private val spec = Regex("""%(?:(\d+)\$)?(@|lld|%)""")

    /// %@、%lld 都换成带序号的 %1$s：译文里可以调换顺序；数字由代码转成文字再填进去
    private fun convert(text: String, key: String, argCount: Int): String {
        var next = 0
        val out = spec.replace(text) { m ->
            if (m.groupValues[2] == "%") return@replace "%%"
            val index = m.groupValues[1].toIntOrNull() ?: ++next
            require(index in 1..argCount) { "“$key” 的译文用了第 $index 个参数，原文只有 $argCount 个：$text" }
            "%$index\$s"
        }
        require(argCount > 0 || !out.contains('%')) { "“$key” 没有参数却带百分号：$text" }
        return out
    }

    private fun xml(text: String): String {
        var s = text.replace("\\", "\\\\").replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
            .replace("\"", "\\\"").replace("'", "\\'").replace("\n", "\\n").replace("\t", "\\t")
        if (s.startsWith("@") || s.startsWith("?")) s = "\\" + s
        return if (s != s.trim() || s.contains("  ")) "\"$s\"" else s
    }

    @TaskAction
    fun run() {
        @Suppress("UNCHECKED_CAST")
        val strings = (JsonSlurper().parse(catalog.get().asFile, "UTF-8") as Map<String, Any?>)["strings"] as Map<String, Map<String, Any?>>
        val keys = strings.keys.filter { it.isNotEmpty() }.sorted()
        val names = HashMap<String, String>()
        val used = HashMap<String, String>()
        for (key in keys) {
            val digest = MessageDigest.getInstance("SHA-1").digest(key.toByteArray())
            val name = "s_" + digest.take(6).joinToString("") { "%02x".format(it) }
            require(used.put(name, key) == null) { "资源名撞了：$key 和 ${used[name]}" }
            names[key] = name
        }

        @Suppress("UNCHECKED_CAST")
        fun unit(node: Any?): String? = ((node as? Map<String, Any?>)?.get("stringUnit") as? Map<String, Any?>)?.get("value") as? String
        @Suppress("UNCHECKED_CAST")
        fun plural(key: String, lang: String): Map<String, Any?>? {
            val loc = (strings[key]?.get("localizations") as? Map<String, Any?>)?.get(lang) as? Map<String, Any?>
            return (loc?.get("variations") as? Map<String, Any?>)?.get("plural") as? Map<String, Any?>
        }
        fun plain(key: String, lang: String): String =
            unit((strings[key]?.get("localizations") as? Map<*, *>)?.get(lang)) ?: key

        val pluralKeys = keys.filter { key -> folders.keys.any { plural(key, it) != null } }.toSet()
        /// 复数跟着原文里第几个参数走（第一个整数）
        val pluralArg = HashMap<String, Int>()
        val argCount = HashMap<String, Int>()
        for (key in keys) {
            val args = spec.findAll(key).map { it.groupValues[2] }.filter { it != "%" }.toList()
            argCount[key] = args.size
            if (key in pluralKeys) {
                val index = args.indexOf("lld")
                require(index >= 0) { "“$key” 分单复数，但原文里没有整数" }
                pluralArg[key] = index
            }
        }

        val res = resDir.get().asFile
        res.deleteRecursively()
        for ((lang, folder) in folders) {
            val out = StringBuilder("<?xml version=\"1.0\" encoding=\"utf-8\"?>\n<!-- 自动生成，不要手改。改文字改 Badie-iOS/Badie/Localizable.xcstrings -->\n<resources>\n")
            for (key in keys) {
                val name = names.getValue(key)
                val count = argCount.getValue(key)
                if (key in pluralKeys) {
                    out.append("    <plurals name=\"$name\">\n")
                    val forms = plural(key, lang)?.mapValues { unit(it.value) ?: key } ?: mapOf("other" to plain(key, lang))
                    require("other" in forms) { "“$key” 的 $lang 复数缺 other" }
                    for ((quantity, text) in forms) {
                        out.append("        <item quantity=\"$quantity\">${xml(convert(text, key, count))}</item>\n")
                    }
                    out.append("    </plurals>\n")
                } else {
                    out.append("    <string name=\"$name\">${xml(convert(plain(key, lang), key, count))}</string>\n")
                }
            }
            out.append("</resources>\n")
            File(res, folder).mkdirs()
            File(res, "$folder/strings.xml").writeText(out.toString())
        }

        fun literal(s: String) = "\"" + s.replace("\\", "\\\\").replace("\"", "\\\"").replace("$", "\\$").replace("\n", "\\n").replace("\t", "\\t") + "\""
        val kt = StringBuilder("// 自动生成，不要手改\npackage com.badie.app.l10n\n\nimport com.badie.app.R\n\n")
        kt.append("internal object L10nTable {\n    val strings = HashMap<String, Int>(${keys.size * 2})\n    val plurals = HashMap<String, Int>()\n")
        kt.append("    /** 复数跟着第几个参数走（从 0 数） */\n    val pluralArg = HashMap<String, Int>()\n\n")
        // 简体中文是原文，但有少数句子在文字表里另写了一遍（调了参数顺序，或改过措辞）。没有界面时（单元测试）用这份
        kt.append("    /** 简体中文和 key 不一样的句子 */\n    val sourceText = HashMap<String, String>()\n\n")
        val chunks = keys.chunked(300)
        kt.append("    init {\n")
        chunks.indices.forEach { kt.append("        fill$it()\n") }
        kt.append("    }\n")
        chunks.forEachIndexed { i, chunk ->
            kt.append("\n    private fun fill$i() {\n")
            for (key in chunk) {
                if (key in pluralKeys) {
                    kt.append("        plurals[${literal(key)}] = R.plurals.${names[key]}\n")
                    kt.append("        pluralArg[${literal(key)}] = ${pluralArg[key]}\n")
                } else {
                    kt.append("        strings[${literal(key)}] = R.string.${names[key]}\n")
                }
                val zh = plain(key, "zh-Hans")
                if (zh != key && key !in pluralKeys) {
                    kt.append("        sourceText[${literal(key)}] = ${literal(convert(zh, key, argCount.getValue(key)))}\n")
                }
            }
            kt.append("    }\n")
        }
        kt.append("}\n")
        val dir = File(kotlinDir.get().asFile, "com/badie/app/l10n")
        kotlinDir.get().asFile.deleteRecursively()
        dir.mkdirs()
        File(dir, "L10nTable.kt").writeText(kt.toString())
    }
}

val generateStrings = tasks.register<GenerateStrings>("generateStrings") {
    catalog = rootProject.layout.projectDirectory.file("../Badie-iOS/Badie/Localizable.xcstrings")
}

androidComponents {
    onVariants { variant ->
        variant.sources.res?.addGeneratedSourceDirectory(generateStrings, GenerateStrings::resDir)
        variant.sources.kotlin?.addGeneratedSourceDirectory(generateStrings, GenerateStrings::kotlinDir)
    }
}
