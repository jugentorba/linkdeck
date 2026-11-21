package dev.linkdeck.app.data

import android.content.Context
import android.content.SharedPreferences
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

/** Small JSON-backed deck store. Everything stays on the device. */
object DeckStore {

    private const val PREFS = "linkdeck.deck"
    private const val KEY = "apps"
    private val lock = Any()
    private lateinit var prefs: SharedPreferences

    fun init(context: Context) {
        prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    }

    fun list(): List<DeckApp> = synchronized(lock) {
        val raw = prefs.getString(KEY, null) ?: return emptyList()
        runCatching {
            val array = JSONArray(raw)
            buildList {
                for (i in 0 until array.length()) {
                    val json = array.getJSONObject(i)
                    add(
                        DeckApp(
                            id = json.getString("id"),
                            name = json.getString("name"),
                            url = json.getString("url"),
                            addedAt = json.optLong("addedAt", 0L),
                            blocked = json.optLong("blocked", 0L),
                        )
                    )
                }
            }
        }.getOrDefault(emptyList())
    }

    fun get(id: String?): DeckApp? = id?.let { wanted -> list().firstOrNull { it.id == wanted } }

    fun add(name: String, url: String): DeckApp {
        val app = DeckApp(
            id = UUID.randomUUID().toString(),
            name = name,
            url = url,
            addedAt = System.currentTimeMillis(),
        )
        synchronized(lock) { write(list() + app) }
        return app
    }

    fun rename(id: String, name: String) = update(id) { it.copy(name = name) }

    fun remove(id: String) = synchronized(lock) { write(list().filterNot { it.id == id }) }

    fun addBlocked(id: String, count: Long) {
        if (count <= 0L) return
        update(id) { it.copy(blocked = it.blocked + count) }
    }

    fun clear() = synchronized(lock) { prefs.edit().remove(KEY).apply() }

    private fun update(id: String, transform: (DeckApp) -> DeckApp) = synchronized(lock) {
        write(list().map { if (it.id == id) transform(it) else it })
    }

    private fun write(apps: List<DeckApp>) {
        val array = JSONArray()
        apps.forEach { app ->
            array.put(
                JSONObject()
                    .put("id", app.id)
                    .put("name", app.name)
                    .put("url", app.url)
                    .put("addedAt", app.addedAt)
                    .put("blocked", app.blocked)
            )
        }
        prefs.edit().putString(KEY, array.toString()).apply()
    }
}
