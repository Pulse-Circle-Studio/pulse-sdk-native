package studio.pulsecircle.pulse.core

import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/** Handle for a scheduled timer. Cancelling a fired timer is a no-op. */
fun interface PulseCancellable {
    fun cancel()
}

/**
 * Time source and timer scheduler. Scheduled work is delivered on the
 * client's [PulseExecutor] (implementations must guarantee this).
 */
interface PulseClock {
    fun nowMs(): Long
    fun schedule(afterMs: Long, work: () -> Unit): PulseCancellable
}

/**
 * Production clock: wall-clock time plus a [java.util.concurrent.ScheduledExecutorService]
 * whose firings are re-dispatched onto the client executor.
 */
class SystemPulseClock(private val executor: PulseExecutor) : PulseClock {

    private val scheduler = Executors.newSingleThreadScheduledExecutor { runnable ->
        Thread(runnable, "pulse-sdk-scheduler").apply { isDaemon = true }
    }

    override fun nowMs(): Long = System.currentTimeMillis()

    override fun schedule(afterMs: Long, work: () -> Unit): PulseCancellable {
        val future = scheduler.schedule(
            { executor.execute(work) },
            afterMs.coerceAtLeast(0),
            TimeUnit.MILLISECONDS
        )
        return PulseCancellable { future.cancel(false) }
    }
}
