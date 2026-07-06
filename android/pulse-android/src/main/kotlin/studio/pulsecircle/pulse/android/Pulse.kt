package studio.pulsecircle.pulse.android

import android.app.Activity
import android.app.Application
import android.content.Context
import android.os.Bundle
import java.io.File
import studio.pulsecircle.pulse.core.FileQueueStorage
import studio.pulsecircle.pulse.core.HttpUrlConnectionTransport
import studio.pulsecircle.pulse.core.PulseClient
import studio.pulsecircle.pulse.core.PulseLogger
import studio.pulsecircle.pulse.core.PulseOptions
import studio.pulsecircle.pulse.core.SingleThreadPulseExecutor
import studio.pulsecircle.pulse.core.SystemPulseClock

/**
 * Pulse analytics for Android. Two things, done reliably: a persistent,
 * offline-first event queue and identity.
 *
 * ```kotlin
 * Pulse.init(context, "pk_your_key")
 * Pulse.track("subscription_started", mapOf("plan" to "pro"))
 * Pulse.identify("user_42")
 * ```
 *
 * All methods are safe to call from any thread and are no-ops until [init].
 */
object Pulse {

    @Volatile
    private var client: PulseClient? = null
    private val initLock = Any()

    /**
     * Initialize the SDK. Safe to call more than once; only the first call
     * takes effect. Uses the application context, so no leak — pass any
     * Context.
     */
    @JvmStatic
    @JvmOverloads
    fun init(context: Context, apiKey: String, options: PulseOptions = PulseOptions()) {
        synchronized(initLock) {
            if (client != null) {
                if (options.debug) androidLogger.debug("Pulse: init() called more than once — ignored")
                return
            }
            val app = context.applicationContext
            val logger = if (options.debug) androidLogger else PulseLogger.NOOP
            val executor = SingleThreadPulseExecutor(logger = logger)
            val created = PulseClient(
                apiKey = apiKey,
                options = options,
                executor = executor,
                clock = SystemPulseClock(executor),
                transport = HttpUrlConnectionTransport(),
                keyValueStorage = SharedPreferencesKeyValueStorage(app),
                queueStorage = FileQueueStorage(File(app.filesDir, "pulse"), logger),
                logger = logger,
                sdkName = "pulse-android",
            )
            client = created
            registerLifecycleFlush(app, created)
        }
    }

    @JvmStatic
    @JvmOverloads
    fun track(event: String, properties: Map<String, Any?>? = null) {
        client?.track(event, properties) ?: warnUninitialized()
    }

    @JvmStatic
    fun identify(userId: String) {
        client?.identify(userId) ?: warnUninitialized()
    }

    @JvmStatic
    fun reset() {
        client?.reset() ?: warnUninitialized()
    }

    @JvmStatic
    fun flush() {
        client?.flush() ?: warnUninitialized()
    }

    private fun warnUninitialized() {
        androidLogger.error("Pulse: call Pulse.init(context, apiKey) before using the SDK")
    }

    /**
     * Best-effort flush when the app goes to the background: a foreground
     * activity counter that fires flush() as it drops to zero (§7 trigger 4).
     * No WorkManager or background service in v1.
     */
    private fun registerLifecycleFlush(app: Context, client: PulseClient) {
        val application = app as? Application ?: return
        application.registerActivityLifecycleCallbacks(object : Application.ActivityLifecycleCallbacks {
            private var startedActivities = 0

            override fun onActivityStarted(activity: Activity) {
                startedActivities++
            }

            override fun onActivityStopped(activity: Activity) {
                startedActivities--
                if (startedActivities <= 0) {
                    startedActivities = 0
                    client.flush()
                }
            }

            override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) {}
            override fun onActivityResumed(activity: Activity) {}
            override fun onActivityPaused(activity: Activity) {}
            override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) {}
            override fun onActivityDestroyed(activity: Activity) {}
        })
    }

    private val androidLogger: PulseLogger = object : PulseLogger {
        override fun debug(message: String) {
            android.util.Log.d("Pulse", message)
        }

        override fun error(message: String) {
            android.util.Log.e("Pulse", message)
        }
    }
}
