package com.badie.app.l10n

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/** 代码里用到的每一句文字，iPhone 的文字表里都要有（10 种语言的译文都在那一份里） */
class CatalogTest {
    private val catalog: Set<String> by lazy {
        val file = File("../../Badie-iOS/Badie/Localizable.xcstrings")
        Json.parseToJsonElement(file.readText()).jsonObject.getValue("strings").jsonObject.keys - ""
    }

    @Test
    fun generatedTableCoversTheCatalog() {
        assertEquals(catalog, L10nTable.strings.keys + L10nTable.plurals.keys)
    }

    @Test
    fun everyKeyUsedInCodeIsInTheCatalog() {
        val call = Regex("""\btr\(\s*"((?:[^"\\]|\\.)*)"""")
        val titleKey = Regex("""\((?:titleKey = )?"((?:[^"\\]|\\.)*)", Sym\.""")
        val missing = sortedSetOf<String>()
        var found = 0
        File("src/main/kotlin").walkTopDown().filter { it.extension == "kt" }.forEach { file ->
            val text = file.readText()
            (call.findAll(text) + titleKey.findAll(text)).forEach { match ->
                found += 1
                val key = match.groupValues[1].replace("\\$", "$").replace("\\n", "\n").replace("\\\"", "\"").replace("\\\\", "\\")
                if (key !in catalog) missing += "${file.name}: $key"
            }
        }
        assertTrue("没扫到任何文字，检查这个测试", found > 10)
        assertTrue("文字表里没有这些：\n" + missing.joinToString("\n"), missing.isEmpty())
    }
}
