package dev.linkdeck.app.data

import android.net.Uri

object UrlTools {

    private val SCHEME = Regex("^[a-zA-Z][a-zA-Z0-9+.-]*://.*")

    /** Returns a normalized http(s) URL, or null when the input is not usable. */
    fun normalize(raw: String): String? {
        val trimmed = raw.trim()
        if (trimmed.isEmpty()) return null
        val withScheme = if (SCHEME.matches(trimmed)) trimmed else "https://$trimmed"
        val uri = runCatching { Uri.parse(withScheme) }.getOrNull() ?: return null
        val scheme = uri.scheme?.lowercase()
        if (scheme != "http" && scheme != "https") return null
        val host = uri.host?.lowercase() ?: return null
        if (host.isBlank() || host.startsWith(".") || host.endsWith(".") || !host.contains('.')) return null
        if (host.any { it.isWhitespace() }) return null
        return withScheme
    }

    fun host(url: String): String =
        runCatching { Uri.parse(url).host }.getOrNull().orEmpty().removePrefix("www.")

    /** Suggests a short, human name from a URL: www.arte.tv -> Arte. */
    fun suggestName(url: String): String {
        val host = host(url)
        if (host.isEmpty()) return ""
        val labels = host.split('.').filter { it.isNotEmpty() }
        if (labels.isEmpty()) return ""
        val secondLevel = labels.getOrNull(labels.size - 2) ?: labels.last()
        val generic = setOf("co", "com", "net", "org", "gov", "ac", "edu")
        val label = if (secondLevel in generic && labels.size >= 3) labels[labels.size - 3] else secondLevel
        return label
            .split('-', '_')
            .filter { it.isNotEmpty() }
            .joinToString(" ") { part -> part.replaceFirstChar { it.uppercase() } }
            .take(40)
    }
}
