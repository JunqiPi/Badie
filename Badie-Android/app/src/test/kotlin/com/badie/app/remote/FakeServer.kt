package com.badie.app.remote

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import java.net.URI

/** 假服务器：按“方法 路径”依次回应；没配的请求回 404 */
class FakeServer {
    val requests = mutableListOf<HttpRequest>()
    private val routes = mutableListOf<Triple<String, Int, String>>()

    fun on(key: String, body: String, status: Int = 200) {
        routes += Triple(key, status, body)
    }

    /** 路径里有随机部分时按前缀匹配 */
    fun onPrefix(prefix: String, body: String, status: Int = 200) {
        routes += Triple("$prefix*", status, body)
    }

    val transport: Transport = { request ->
        requests += request
        val key = "${request.method} ${URI(request.url).path}"
        val index = routes.indexOfFirst { it.first == key || (it.first.endsWith("*") && key.startsWith(it.first.dropLast(1))) }
        if (index < 0) {
            HttpResponse(404, """{"message":"not_found"}""".encodeToByteArray())
        } else {
            val (_, status, body) = routes.removeAt(index)
            HttpResponse(status, body.encodeToByteArray())
        }
    }

    fun json(index: Int): JsonObject = Json.parseToJsonElement(requests[index].body?.decodeToString() ?: "{}").jsonObject

    fun path(index: Int): String = URI(requests[index].url).path

    fun query(index: Int): String? = URI(requests[index].url).query
}
