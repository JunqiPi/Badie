package com.badie.app.remote

import kotlinx.coroutines.suspendCancellableCoroutine
import okhttp3.Call
import okhttp3.Callback
import okhttp3.Headers.Companion.toHeaders
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import java.io.IOException
import java.util.concurrent.TimeUnit
import kotlin.coroutines.resume
import kotlinx.coroutines.CancellableContinuation

/** 正式的发请求方式。整个 App 共用一个，连接可以复用 */
object OkHttpTransport {
    private val client = OkHttpClient.Builder().build()

    val transport: Transport = { request -> send(request) }

    private suspend fun send(request: HttpRequest): HttpResponse = suspendCancellableCoroutine { continuation ->
        val contentType = request.headers["Content-Type"]?.toMediaTypeOrNull()
        // 有的方法（POST、PUT、PATCH）必须带内容，没有就给空的
        val body = request.body?.toRequestBody(contentType)
            ?: if (request.method in listOf("POST", "PUT", "PATCH")) ByteArray(0).toRequestBody(null) else null
        val call = client.newBuilder().callTimeout(request.timeoutMillis, TimeUnit.MILLISECONDS).build().newCall(
            Request.Builder().url(request.url).headers(request.headers.toHeaders()).method(request.method, body).build(),
        )
        continuation.invokeOnCancellation { call.cancel() }
        call.enqueue(object : Callback {
            override fun onFailure(call: Call, e: IOException) = continuation.fail(e)

            override fun onResponse(call: Call, response: Response) {
                try {
                    val bytes = response.use { it.body.bytes() }
                    continuation.resume(HttpResponse(response.code, bytes))
                } catch (e: IOException) {
                    continuation.fail(e)
                }
            }
        })
    }

    private fun CancellableContinuation<HttpResponse>.fail(e: IOException) {
        if (isActive) resumeWith(Result.failure(e))
    }
}
