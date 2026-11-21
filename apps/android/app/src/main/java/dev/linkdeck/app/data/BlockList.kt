package dev.linkdeck.app.data

import android.content.Context

/**
 * Bundled suffix-matched host blocklist. Immutable set swapped in atomically
 * after background loading so request threads never see a half-built list.
 */
object BlockList {

    private const val ASSET = "blocklist.txt"

    @Volatile
    private var hosts: Set<String>? = null

    val size: Int
        get() = hosts?.size ?: 0

    fun loadAsync(context: Context) {
        if (hosts != null) return
        val appContext = context.applicationContext
        Thread({
            val set = HashSet<String>(8_192)
            runCatching {
                appContext.assets.open(ASSET).bufferedReader().useLines { lines ->
                    lines.forEach { line ->
                        val value = line.trim()
                        if (value.isNotEmpty() && !value.startsWith("#")) {
                            set.add(value.lowercase().trimEnd('.'))
                        }
                    }
                }
            }
            hosts = set
        }, "linkdeck-blocklist").start()
    }

    fun isBlocked(host: String?): Boolean {
        val set = hosts ?: return false
        if (host.isNullOrEmpty()) return false
        var candidate = host.lowercase().trimEnd('.')
        if (candidate.isEmpty()) return false
        if (set.contains(candidate)) return true
        var dot = candidate.indexOf('.')
        while (dot != -1 && dot < candidate.length - 1) {
            candidate = candidate.substring(dot + 1)
            if (set.contains(candidate)) return true
            dot = candidate.indexOf('.')
        }
        return false
    }
}
