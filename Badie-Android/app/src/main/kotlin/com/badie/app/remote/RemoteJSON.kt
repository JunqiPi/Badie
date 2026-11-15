package com.badie.app.remote

import kotlinx.serialization.ExperimentalSerializationApi
import kotlinx.serialization.KSerializer
import kotlinx.serialization.Serializable
import kotlinx.serialization.SerializationException
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNamingStrategy
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.serializer
import java.time.Instant
import java.time.OffsetDateTime
import java.time.format.DateTimeParseException

/** 登录状态（加密后存在本机，App 重开后仍保持登录） */
@Serializable
data class RemoteSession(
    val accessToken: String,
    val refreshToken: String,
    /** 过期时间，毫秒 */
    val expiresAt: Long,
    val userId: String,
    val email: String? = null,
)

/** 服务器的时间：Postgres 的 ISO 8601，可能带 1–6 位小数秒 */
object InstantSerializer : KSerializer<Instant> {
    override val descriptor = PrimitiveSerialDescriptor("Instant", PrimitiveKind.STRING)

    override fun deserialize(decoder: Decoder): Instant {
        val text = decoder.decodeString()
        return RemoteJSON.parseDate(text) ?: throw SerializationException("不是时间：$text")
    }

    override fun serialize(encoder: Encoder, value: Instant) = encoder.encodeString(value.toString())
}

/** 服务器的 JSON：字段是 snake_case；没给的字段按空处理，多出来的字段不管 */
object RemoteJSON {
    @OptIn(ExperimentalSerializationApi::class)
    val json = Json {
        ignoreUnknownKeys = true
        explicitNulls = false
        namingStrategy = JsonNamingStrategy.SnakeCase
    }

    inline fun <reified T> decode(data: ByteArray): T = decode(serializer<T>(), data)

    fun <T> decode(serializer: KSerializer<T>, data: ByteArray): T = try {
        json.decodeFromString(serializer, data.decodeToString())
    } catch (_: SerializationException) {
        throw RemoteError.Server("bad_response")
    } catch (_: IllegalArgumentException) {
        throw RemoteError.Server("bad_response")
    }

    private val timeZoneWithoutMinutes = Regex("""[+-]\d\d$""")

    fun parseDate(text: String): Instant? {
        // Postgres 的时区会写成 +00，标准写法是 +00:00
        val value = if (timeZoneWithoutMinutes.containsMatchIn(text)) "$text:00" else text
        return try {
            OffsetDateTime.parse(value).toInstant()
        } catch (_: DateTimeParseException) {
            null
        }
    }

    @Serializable
    private data class TokenResponse(val accessToken: String, val refreshToken: String, val expiresIn: Double, val user: AuthUser) {
        @Serializable
        data class AuthUser(val id: String, val email: String? = null)
    }

    fun session(data: ByteArray, now: Long): RemoteSession {
        val token = decode<TokenResponse>(data)
        return RemoteSession(token.accessToken, token.refreshToken, now + (token.expiresIn * 1000).toLong(), token.user.id, token.user.email)
    }

    /** 错误码：数据库函数用 message（too_soon），登录服务用 error_code，都没有就按 HTTP 状态 */
    fun errorCode(data: ByteArray, status: Int): String {
        val body = try {
            Json.parseToJsonElement(data.decodeToString()) as? JsonObject
        } catch (_: SerializationException) {
            null
        }
        for (key in listOf("error_code", "message", "error")) {
            val code = (body?.get(key) as? JsonPrimitive)?.takeIf { it.isString }?.contentOrNull
            if (!code.isNullOrEmpty()) return code
        }
        return "http_$status"
    }
}

/** 拼请求的 JSON：`json("email" to email, "create_user" to true)`。值可以是文字、数字、布尔、空、列表、字典 */
fun json(vararg pairs: Pair<String, Any?>): JsonObject = JsonObject(pairs.associate { (key, value) -> key to value.toJson() })

fun Any?.toJson(): JsonElement = when (this) {
    null -> JsonNull
    is JsonElement -> this
    is String -> JsonPrimitive(this)
    is Number -> JsonPrimitive(this)
    is Boolean -> JsonPrimitive(this)
    is Map<*, *> -> JsonObject(entries.associate { (key, value) -> key.toString() to value.toJson() })
    is Iterable<*> -> JsonArray(map { it.toJson() })
    is Array<*> -> JsonArray(map { it.toJson() })
    else -> throw IllegalArgumentException("不能放进 JSON：${this::class}")
}
