package studio.pulsecircle.pulse.core.testkit

import studio.pulsecircle.pulse.core.HttpRequest
import studio.pulsecircle.pulse.core.HttpResult
import studio.pulsecircle.pulse.core.PulseCancellable
import studio.pulsecircle.pulse.core.PulseClock
import studio.pulsecircle.pulse.core.PulseExecutor
import studio.pulsecircle.pulse.core.PulseKeyValueStorage
import studio.pulsecircle.pulse.core.PulseLogger
import studio.pulsecircle.pulse.core.PulseQueueStorage
import studio.pulsecircle.pulse.core.PulseTransport

/** Immediate synchronous executor: deterministic single-threaded test runs. */
class ImmediateExecutor : PulseExecutor {
    override fun execute(work: () -> Unit) = work()
}

/**
 * Virtual clock per FIXTURES.md: starts at 2026-01-01T00:00:00.000Z and only
 * moves via [advance], which fires due timers in chronological (then
 * scheduling) order.
 */
class VirtualClock(startMs: Long = FIXTURE_EPOCH_MS) : PulseClock {

    companion object {
        /** 2026-01-01T00:00:00.000Z */
        const val FIXTURE_EPOCH_MS = 1_767_225_600_000L
    }

    private class Timer(val due: Long, val seq: Long, val work: () -> Unit) {
        var cancelled = false
    }

    private var now = startMs
    private var nextSeq = 0L
    private val timers = mutableListOf<Timer>()

    override fun nowMs(): Long = now

    override fun schedule(afterMs: Long, work: () -> Unit): PulseCancellable {
        val timer = Timer(now + afterMs.coerceAtLeast(0), nextSeq++, work)
        timers.add(timer)
        return PulseCancellable { timer.cancelled = true }
    }

    fun advance(ms: Long) {
        val target = now + ms
        while (true) {
            timers.removeAll { it.cancelled }
            val next = timers
                .filter { it.due <= target }
                .minWithOrNull(compareBy({ it.due }, { it.seq }))
                ?: break
            timers.remove(next)
            if (next.due > now) now = next.due
            next.work()
        }
        now = target
    }

    /** Simulates process death: pending timers die with the process. */
    fun cancelAllTimers() {
        timers.clear()
    }
}

/**
 * Mock transport per FIXTURES.md: captures outgoing requests into a FIFO of
 * pending requests; the client's in-flight request stays unresolved until a
 * fixture step (or test) explicitly responds.
 */
class MockTransport : PulseTransport {
    class Pending(val request: HttpRequest, val callback: (HttpResult) -> Unit)

    val pending = ArrayDeque<Pending>()

    override fun send(request: HttpRequest, callback: (HttpResult) -> Unit) {
        pending.addLast(Pending(request, callback))
    }

    fun takeOldest(): Pending? = pending.removeFirstOrNull()
}

class InMemoryKeyValueStorage : PulseKeyValueStorage {
    val map = LinkedHashMap<String, String>()
    override fun get(key: String): String? = map[key]
    override fun set(key: String, value: String) {
        map[key] = value
    }

    override fun remove(key: String) {
        map.remove(key)
    }
}

class InMemoryQueueStorage : PulseQueueStorage {
    val items = mutableListOf<String>()

    override fun loadAll(): List<String> = items.toList()

    override fun append(itemJson: String) {
        items.add(itemJson)
    }

    override fun markConsumed(count: Int) {
        repeat(count.coerceIn(0, items.size)) { items.removeAt(0) }
    }

    override fun replaceAll(items: List<String>) {
        this.items.clear()
        this.items.addAll(items)
    }
}

class RecordingLogger : PulseLogger {
    val debugMessages = mutableListOf<String>()
    val errorMessages = mutableListOf<String>()

    override fun debug(message: String) {
        debugMessages.add(message)
    }

    override fun error(message: String) {
        errorMessages.add(message)
    }
}
