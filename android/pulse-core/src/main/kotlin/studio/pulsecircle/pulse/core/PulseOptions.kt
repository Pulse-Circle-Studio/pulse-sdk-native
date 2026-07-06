package studio.pulsecircle.pulse.core

/**
 * Client configuration. Defaults follow the mobile profile of the Pulse wire
 * protocol v1.
 */
data class PulseOptions(
    val endpoint: String = "https://api.pulse.pulsecircle.studio",
    val flushAt: Int = 20,
    val flushIntervalMs: Long = 30_000,
    val maxQueueEvents: Int = 5_000,
    val debug: Boolean = false,
)
