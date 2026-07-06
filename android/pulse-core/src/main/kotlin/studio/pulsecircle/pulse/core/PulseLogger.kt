package studio.pulsecircle.pulse.core

/** Minimal logging seam so hosts can route SDK logs and tests can assert on them. */
interface PulseLogger {
    fun debug(message: String)
    fun error(message: String)

    companion object {
        val NOOP: PulseLogger = object : PulseLogger {
            override fun debug(message: String) {}
            override fun error(message: String) {}
        }
    }
}
