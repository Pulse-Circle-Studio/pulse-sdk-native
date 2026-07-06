package studio.pulsecircle.pulse.core

import kotlinx.serialization.json.Json
import java.io.File
import java.io.FileOutputStream

/**
 * Production [PulseQueueStorage]: an append-log (`queue.log`, one JSON item
 * per line) plus a meta file (`queue.meta`) holding the consumed-from-head
 * line count.
 *
 * - Consumption normally just bumps the meta counter (cheap); the log is
 *   compacted (rewritten without the consumed prefix) on load and whenever
 *   the consumed counter exceeds [COMPACT_THRESHOLD].
 * - Corrupted lines (torn writes, external tampering) are skipped with a
 *   debug log.
 * - IO failures degrade gracefully: the in-memory view stays correct for the
 *   life of the process and errors are logged, never thrown to the caller.
 */
class FileQueueStorage(
    private val directory: File,
    private val logger: PulseLogger = PulseLogger.NOOP,
) : PulseQueueStorage {

    private companion object {
        const val COMPACT_THRESHOLD = 100
    }

    private val queueFile = File(directory, "queue.log")
    private val metaFile = File(directory, "queue.meta")

    private var items: MutableList<String>? = null
    private var consumed = 0

    @Synchronized
    override fun loadAll(): List<String> = ensureLoaded().toList()

    @Synchronized
    override fun append(itemJson: String) {
        ensureLoaded().add(itemJson)
        try {
            ensureDirectory()
            FileOutputStream(queueFile, true).use { stream ->
                stream.write((itemJson + "\n").toByteArray(Charsets.UTF_8))
            }
        } catch (e: Exception) {
            logger.error("Pulse: failed to append to queue log: $e")
        }
    }

    @Synchronized
    override fun markConsumed(count: Int) {
        val loaded = ensureLoaded()
        val n = count.coerceIn(0, loaded.size)
        repeat(n) { loaded.removeAt(0) }
        consumed += n
        if (consumed > COMPACT_THRESHOLD) {
            compact()
        } else {
            writeMeta(consumed)
        }
    }

    @Synchronized
    override fun replaceAll(items: List<String>) {
        ensureLoaded()
        this.items = items.toMutableList()
        compact()
    }

    private fun ensureLoaded(): MutableList<String> {
        items?.let { return it }
        val loaded = ArrayList<String>()
        var consumedFromMeta = 0
        var skippedCorrupted = false
        try {
            if (metaFile.exists()) {
                consumedFromMeta = (metaFile.readText(Charsets.UTF_8).trim().toIntOrNull() ?: 0)
                    .coerceAtLeast(0)
            }
            if (queueFile.exists()) {
                val lines = queueFile.readLines(Charsets.UTF_8)
                for (line in lines.drop(consumedFromMeta)) {
                    if (line.isBlank()) continue
                    if (isParseableJson(line)) {
                        loaded.add(line)
                    } else {
                        skippedCorrupted = true
                        logger.debug("Pulse: skipping corrupted queue log line")
                    }
                }
            }
        } catch (e: Exception) {
            logger.error("Pulse: failed to read queue log: $e")
        }
        items = loaded
        consumed = 0
        if (consumedFromMeta > 0 || skippedCorrupted) {
            compact()
        }
        return loaded
    }

    /** Rewrites the log to contain exactly the unconsumed items; resets meta. */
    private fun compact() {
        val current = items ?: return
        try {
            ensureDirectory()
            val tmp = File(directory, "queue.log.tmp")
            val content = StringBuilder()
            for (item in current) {
                content.append(item).append('\n')
            }
            tmp.writeText(content.toString(), Charsets.UTF_8)
            if (!tmp.renameTo(queueFile)) {
                queueFile.delete()
                if (!tmp.renameTo(queueFile)) {
                    logger.error("Pulse: failed to swap compacted queue log into place")
                }
            }
        } catch (e: Exception) {
            logger.error("Pulse: failed to compact queue log: $e")
        }
        consumed = 0
        writeMeta(0)
    }

    private fun writeMeta(value: Int) {
        try {
            ensureDirectory()
            metaFile.writeText(value.toString(), Charsets.UTF_8)
        } catch (e: Exception) {
            logger.error("Pulse: failed to write queue meta: $e")
        }
    }

    private fun ensureDirectory() {
        if (!directory.exists()) {
            directory.mkdirs()
        }
    }

    private fun isParseableJson(line: String): Boolean = try {
        Json.parseToJsonElement(line)
        true
    } catch (_: Exception) {
        false
    }
}
