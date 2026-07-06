package studio.pulsecircle.pulse.core

/**
 * Persistent queue of serialized items (exact wire/envelope JSON strings),
 * head first. The client keeps the authoritative in-memory copy and mirrors
 * every mutation here.
 */
interface PulseQueueStorage {
    /** All unconsumed items, head first. */
    fun loadAll(): List<String>

    /** Append one serialized item at the tail. */
    fun append(itemJson: String)

    /** Mark [count] items, counted from the head, as consumed. */
    fun markConsumed(count: Int)

    /** Replace the whole queue (cap eviction, poison-batch move-to-tail). */
    fun replaceAll(items: List<String>)
}
