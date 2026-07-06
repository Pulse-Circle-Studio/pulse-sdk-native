package studio.pulsecircle.pulse.core

/**
 * Small persistent string store for identity state: the anonymous id, the
 * persisted user id, and the identify-dedup set.
 */
interface PulseKeyValueStorage {
    fun get(key: String): String?
    fun set(key: String, value: String)
    fun remove(key: String)
}
