package studio.pulsecircle.pulse.core

import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.TimeUnit

/**
 * The client's serial executor. Every piece of client state is touched only
 * from work items submitted here — this is the entire thread-safety story.
 * Public API methods may be called from any thread; they hand off and return.
 */
fun interface PulseExecutor {
    fun execute(work: () -> Unit)
}

/**
 * Production executor: a single named daemon thread. Work items run in
 * submission order; an exception in one work item never kills the thread.
 */
class SingleThreadPulseExecutor(
    threadName: String = "pulse-sdk",
    private val logger: PulseLogger = PulseLogger.NOOP,
) : PulseExecutor {

    private val delegate = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, threadName).apply { isDaemon = true }
    }

    override fun execute(work: () -> Unit) {
        try {
            delegate.execute {
                try {
                    work()
                } catch (t: Throwable) {
                    logger.error("Pulse: unhandled error on the SDK executor: $t")
                }
            }
        } catch (_: RejectedExecutionException) {
            // Executor has been shut down; drop the work.
        }
    }

    /** Stops the executor. Intended for tests and controlled teardown. */
    fun shutdown(awaitMs: Long = 5_000) {
        delegate.shutdown()
        try {
            delegate.awaitTermination(awaitMs, TimeUnit.MILLISECONDS)
        } catch (_: InterruptedException) {
            Thread.currentThread().interrupt()
        }
    }
}
