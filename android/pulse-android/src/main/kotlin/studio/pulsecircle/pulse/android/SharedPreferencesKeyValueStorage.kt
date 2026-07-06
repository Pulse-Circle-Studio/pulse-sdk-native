package studio.pulsecircle.pulse.android

import android.content.Context
import android.content.SharedPreferences
import studio.pulsecircle.pulse.core.PulseKeyValueStorage

/** Identity persistence backed by a private [SharedPreferences] file. */
internal class SharedPreferencesKeyValueStorage(context: Context) : PulseKeyValueStorage {

    private val prefs: SharedPreferences =
        context.applicationContext.getSharedPreferences("pulse", Context.MODE_PRIVATE)

    override fun get(key: String): String? = prefs.getString(key, null)

    override fun set(key: String, value: String) {
        prefs.edit().putString(key, value).apply()
    }

    override fun remove(key: String) {
        prefs.edit().remove(key).apply()
    }
}
