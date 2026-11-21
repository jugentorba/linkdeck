package dev.linkdeck.app.data

import android.content.Context
import android.content.SharedPreferences

object Settings {

    private const val PREFS = "linkdeck.settings"
    private const val KEY_BLOCK_ADS = "block_ads"
    private const val KEY_BLOCK_POPUPS = "block_popups"

    private lateinit var prefs: SharedPreferences

    fun init(context: Context) {
        prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    }

    var blockAds: Boolean
        get() = prefs.getBoolean(KEY_BLOCK_ADS, true)
        set(value) {
            prefs.edit().putBoolean(KEY_BLOCK_ADS, value).apply()
        }

    var blockPopups: Boolean
        get() = prefs.getBoolean(KEY_BLOCK_POPUPS, true)
        set(value) {
            prefs.edit().putBoolean(KEY_BLOCK_POPUPS, value).apply()
        }
}
