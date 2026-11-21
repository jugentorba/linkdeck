package dev.linkdeck.app.media

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.Typeface
import android.os.Handler
import android.os.Looper
import android.util.LruCache
import java.io.File
import java.net.HttpURLConnection
import java.net.URL

/** Fetches, decodes and caches site icons; falls back to deterministic letter tiles. */
object FaviconLoader {

    private const val MAX_PX = 160
    private const val ENDPOINT = "https://icons.duckduckgo.com/ip3/"
    private const val LETTER_SIZE = 160

    private val memory = object : LruCache<String, Bitmap>(96) {
        override fun sizeOf(key: String, value: Bitmap): Int = value.byteCount / 1024
    }

    private val main = Handler(Looper.getMainLooper())
    private val executor = java.util.concurrent.Executors.newFixedThreadPool(3)
    private var directory: File? = null

    fun init(context: Context) {
        directory = File(context.cacheDir, "favicons").apply { mkdirs() }
    }

    fun letterTile(name: String, host: String): Bitmap {
        val size = LETTER_SIZE
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)

        val hash = host.lowercase().hashCode()
        val hue = ((hash % 360) + 360) % 360
        val start = Color.HSVToColor(floatArrayOf(hue.toFloat(), 0.52f, 0.58f))
        val end = Color.HSVToColor(floatArrayOf(((hue + 46) % 360).toFloat(), 0.68f, 0.32f))
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            shader = LinearGradient(0f, 0f, size.toFloat(), size.toFloat(), start, end, Shader.TileMode.CLAMP)
        }
        val radius = size * 0.24f
        canvas.drawRoundRect(RectF(0f, 0f, size.toFloat(), size.toFloat()), radius, radius, paint)

        val letter = name.trim().firstOrNull { it.isLetterOrDigit() }?.uppercaseChar()?.toString() ?: "?"
        val text = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.WHITE
            textSize = size * 0.46f
            typeface = Typeface.create("sans-serif", Typeface.BOLD)
            textAlign = Paint.Align.CENTER
        }
        val baseline = size / 2f - (text.descent() + text.ascent()) / 2f
        canvas.drawText(letter, size / 2f, baseline, text)
        return bitmap
    }

    /** Immediately available icon: cached favicon or a letter tile. */
    fun cachedOrLetter(name: String, host: String): Bitmap =
        memory.get(host.lowercase()) ?: letterTile(name, host)

    fun load(name: String, host: String, onResult: (Bitmap) -> Unit) {
        val key = host.lowercase()
        memory.get(key)?.let { cached ->
            onResult(cached)
            return
        }
        executor.execute {
            val bitmap = readDisk(key) ?: download(key) ?: letterTile(name, key)
            memory.put(key, bitmap)
            main.post { onResult(bitmap) }
        }
    }

    fun clear() {
        memory.evictAll()
        directory?.listFiles()?.forEach { it.delete() }
    }

    private fun download(host: String): Bitmap? {
        if (host.isBlank()) return null
        return runCatching {
            val connection = URL("$ENDPOINT$host.ico").openConnection() as HttpURLConnection
            connection.connectTimeout = 4_000
            connection.readTimeout = 4_000
            connection.instanceFollowRedirects = true
            connection.setRequestProperty("User-Agent", "Mozilla/5.0 (Linux; Android 14) LinkDeck/1.0")
            try {
                if (connection.responseCode !in 200..299) return null
                val bytes = connection.inputStream.use { it.readBytes() }
                val decoded = IcoDecoder.decode(bytes) ?: return null
                val scaled = scaleDown(decoded)
                writeDisk(host, scaled)
                scaled
            } finally {
                connection.disconnect()
            }
        }.getOrNull()
    }

    private fun scaleDown(source: Bitmap): Bitmap {
        val longest = maxOf(source.width, source.height)
        if (longest <= MAX_PX) return source
        val factor = MAX_PX.toFloat() / longest
        val width = (source.width * factor).toInt().coerceAtLeast(1)
        val height = (source.height * factor).toInt().coerceAtLeast(1)
        val scaled = Bitmap.createScaledBitmap(source, width, height, true)
        if (scaled !== source) source.recycle()
        return scaled
    }

    private fun diskFile(host: String): File? {
        val dir = directory ?: return null
        val safe = host.lowercase().replace(Regex("[^a-z0-9.-]"), "_")
        return File(dir, "$safe.png")
    }

    private fun readDisk(host: String): Bitmap? {
        val file = diskFile(host)?.takeIf { it.isFile } ?: return null
        return runCatching { BitmapFactory.decodeFile(file.absolutePath) }.getOrNull()
            ?: run { file.delete(); null }
    }

    private fun writeDisk(host: String, bitmap: Bitmap) {
        val file = diskFile(host) ?: return
        runCatching {
            file.outputStream().use { out -> bitmap.compress(Bitmap.CompressFormat.PNG, 90, out) }
        }
    }
}
