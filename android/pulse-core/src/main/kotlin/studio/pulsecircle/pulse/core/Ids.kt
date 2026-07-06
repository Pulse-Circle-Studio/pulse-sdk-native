package studio.pulsecircle.pulse.core

import java.util.Random

/** ULID and UUIDv4 generation. No java.time, minSdk-24 safe. */
internal object Ids {

    private const val ULID_ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
    private const val HEX = "0123456789abcdef"

    /**
     * 26-char Crockford-base32 ULID: 48-bit timestamp (ms) + 80 random bits.
     */
    fun ulid(timeMs: Long, random: Random): String {
        val chars = CharArray(26)
        var t = timeMs and 0xFFFFFFFFFFFFL
        for (i in 9 downTo 0) {
            chars[i] = ULID_ALPHABET[(t and 31L).toInt()]
            t = t ushr 5
        }
        val randomBytes = ByteArray(10)
        random.nextBytes(randomBytes)
        var acc = 0L
        var accBits = 0
        var index = 10
        for (b in randomBytes) {
            acc = (acc shl 8) or (b.toLong() and 0xFF)
            accBits += 8
            while (accBits >= 5) {
                accBits -= 5
                chars[index++] = ULID_ALPHABET[((acc ushr accBits) and 31L).toInt()]
            }
        }
        return String(chars)
    }

    /** Random (version 4, variant 1) UUID in canonical lowercase form. */
    fun uuid4(random: Random): String {
        val bytes = ByteArray(16)
        random.nextBytes(bytes)
        bytes[6] = ((bytes[6].toInt() and 0x0F) or 0x40).toByte()
        bytes[8] = ((bytes[8].toInt() and 0x3F) or 0x80).toByte()
        val sb = StringBuilder(36)
        for (i in 0 until 16) {
            when (i) {
                4, 6, 8, 10 -> sb.append('-')
            }
            val v = bytes[i].toInt() and 0xFF
            sb.append(HEX[v ushr 4]).append(HEX[v and 0x0F])
        }
        return sb.toString()
    }
}
