package dev.linkdeck.app.data

import android.net.Uri

data class DeckApp(
    val id: String,
    val name: String,
    val url: String,
    val addedAt: Long,
    val blocked: Long = 0L,
) {
    val host: String
        get() = runCatching { Uri.parse(url).host }.getOrNull().orEmpty().ifEmpty { url }

    val displayHost: String
        get() = host.removePrefix("www.")
}
