package studio.pulsecircle.pulse.core

/**
 * ISO-8601 UTC formatting (`yyyy-MM-ddTHH:mm:ss.SSSZ`) from epoch millis,
 * computed manually — no java.time (minSdk 24, no desugaring in v1).
 */
internal object IsoTimestamp {

    private const val MS_PER_DAY = 86_400_000L

    fun format(epochMs: Long): String {
        val days = floorDiv(epochMs, MS_PER_DAY)
        val msOfDay = (epochMs - days * MS_PER_DAY).toInt()

        // Civil-from-days (Howard Hinnant's algorithm), proleptic Gregorian.
        val z = days + 719_468L
        val era = floorDiv(z, 146_097L)
        val doe = z - era * 146_097L
        val yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
        var year = yoe + era * 400
        val doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        val mp = (5 * doy + 2) / 153
        val day = (doy - (153 * mp + 2) / 5 + 1).toInt()
        val month = (if (mp < 10) mp + 3 else mp - 9).toInt()
        if (month <= 2) year += 1

        val hour = msOfDay / 3_600_000
        val minute = msOfDay / 60_000 % 60
        val second = msOfDay / 1_000 % 60
        val milli = msOfDay % 1_000

        val sb = StringBuilder(24)
        appendPadded(sb, year.toInt(), 4)
        sb.append('-')
        appendPadded(sb, month, 2)
        sb.append('-')
        appendPadded(sb, day, 2)
        sb.append('T')
        appendPadded(sb, hour, 2)
        sb.append(':')
        appendPadded(sb, minute, 2)
        sb.append(':')
        appendPadded(sb, second, 2)
        sb.append('.')
        appendPadded(sb, milli, 3)
        sb.append('Z')
        return sb.toString()
    }

    private fun floorDiv(a: Long, b: Long): Long {
        var q = a / b
        if ((a xor b) < 0 && q * b != a) q -= 1
        return q
    }

    private fun appendPadded(sb: StringBuilder, value: Int, width: Int) {
        val s = value.toString()
        repeat(width - s.length) { sb.append('0') }
        sb.append(s)
    }
}
