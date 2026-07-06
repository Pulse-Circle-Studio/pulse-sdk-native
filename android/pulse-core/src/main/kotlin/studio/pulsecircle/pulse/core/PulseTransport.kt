package studio.pulsecircle.pulse.core

import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors

class HttpRequest(
    val url: String,
    val headers: Map<String, String>,
    val body: String,
)

sealed class HttpResult {
    /** Any HTTP response, including non-2xx statuses. */
    class Response(val status: Int, val body: String) : HttpResult()

    /** Transport-level failure — no HTTP status was received. */
    class NetworkError(val cause: Throwable) : HttpResult()
}

/**
 * HTTP seam. Implementations invoke [send]'s callback on any thread; the
 * client re-dispatches onto its executor.
 */
interface PulseTransport {
    fun send(request: HttpRequest, callback: (HttpResult) -> Unit)
}

/**
 * Production transport built on [HttpURLConnection] (pure `java.net`, works on
 * Android API 24+ and the JVM). Runs each request on a background daemon
 * thread. IOExceptions become [HttpResult.NetworkError]; every received HTTP
 * status — 2xx or not — becomes [HttpResult.Response].
 */
class HttpUrlConnectionTransport(
    private val connectTimeoutMs: Int = 10_000,
    private val readTimeoutMs: Int = 30_000,
) : PulseTransport {

    private val ioExecutor = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "pulse-sdk-http").apply { isDaemon = true }
    }

    override fun send(request: HttpRequest, callback: (HttpResult) -> Unit) {
        ioExecutor.execute {
            callback(performRequest(request))
        }
    }

    private fun performRequest(request: HttpRequest): HttpResult {
        return try {
            val connection = URL(request.url).openConnection() as HttpURLConnection
            try {
                connection.requestMethod = "POST"
                connection.connectTimeout = connectTimeoutMs
                connection.readTimeout = readTimeoutMs
                connection.doOutput = true
                connection.useCaches = false
                for ((name, value) in request.headers) {
                    connection.setRequestProperty(name, value)
                }
                connection.outputStream.use { it.write(request.body.toByteArray(Charsets.UTF_8)) }
                val status = connection.responseCode
                val stream = if (status >= 400) connection.errorStream else connection.inputStream
                val body = try {
                    stream?.use { String(it.readBytes(), Charsets.UTF_8) } ?: ""
                } catch (_: IOException) {
                    ""
                }
                HttpResult.Response(status, body)
            } finally {
                connection.disconnect()
            }
        } catch (e: IOException) {
            HttpResult.NetworkError(e)
        } catch (e: Exception) {
            HttpResult.NetworkError(e)
        }
    }
}
