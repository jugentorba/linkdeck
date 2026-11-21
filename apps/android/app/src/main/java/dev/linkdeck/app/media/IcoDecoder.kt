package dev.linkdeck.app.media

import android.graphics.Bitmap
import android.graphics.BitmapFactory

/**
 * Minimal decoder for Windows .ico favicons. Modern sites ship PNG payloads
 * inside the container; older ones use uncompressed 24/32-bit DIBs, which
 * BitmapFactory cannot parse. Handles both, ignores palettes.
 */
object IcoDecoder {

    fun decode(bytes: ByteArray): Bitmap? {
        if (bytes.isEmpty()) return null
        if (isRaster(bytes)) {
            return BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
        }
        if (!isIco(bytes)) return null
        val count = u16(bytes, 4)
        if (count <= 0 || bytes.size < 6 + 16 * count) return null

        var best: Bitmap? = null
        var bestScore = -1
        for (index in 0 until count) {
            val entry = 6 + index * 16
            val width = u8(bytes, entry).let { if (it == 0) 256 else it }
            val height = u8(bytes, entry + 1).let { if (it == 0) 256 else it }
            val bits = u16(bytes, entry + 6)
            val size = u32(bytes, entry + 8)
            val offset = u32(bytes, entry + 12)
            if (size <= 0 || offset < 0 || offset.toLong() + size > bytes.size) continue
            val payload = bytes.copyOfRange(offset, offset + size)
            val bitmap = if (isRaster(payload)) {
                BitmapFactory.decodeByteArray(payload, 0, payload.size)
            } else {
                decodeDib(payload, bits)
            } ?: continue
            val score = bitmap.width * bitmap.height * if (bits >= 32) 2 else 1
            if (score > bestScore) {
                if (best != null && best !== bitmap) best.recycle()
                best = bitmap
                bestScore = score
            } else if (bitmap !== best) {
                bitmap.recycle()
            }
        }
        return best
    }

    private fun decodeDib(data: ByteArray, declaredBits: Int): Bitmap? {
        if (data.size < 40) return null
        val headerSize = u32(data, 0)
        val width = s32(data, 4)
        val fullHeight = s32(data, 8)
        val bits = u16(data, 14).takeIf { it > 0 } ?: declaredBits
        val compression = u32(data, 16)
        if (width <= 0 || fullHeight <= 0 || width > 1024) return null
        val height = if (fullHeight % 2 == 0) fullHeight / 2 else fullHeight
        if (height <= 0 || height > 1024) return null
        if (compression != 0) return null
        if (bits != 32 && bits != 24) return null
        if (headerSize < 40 || data.size < headerSize) return null

        val bytesPerPixel = bits / 8
        val rowSize = ((width * bits + 31) / 32) * 4
        if (headerSize.toLong() + rowSize.toLong() * height > data.size) return null

        val pixels = IntArray(width * height)
        var anyAlpha = false
        for (y in 0 until height) {
            val srcRow = headerSize + (height - 1 - y) * rowSize
            for (x in 0 until width) {
                val p = srcRow + x * bytesPerPixel
                val b = u8(data, p)
                val g = u8(data, p + 1)
                val r = u8(data, p + 2)
                val a = if (bits == 32) u8(data, p + 3) else 255
                if (a != 0) anyAlpha = true
                pixels[y * width + x] = (a shl 24) or (r shl 16) or (g shl 8) or b
            }
        }
        if (bits == 32 && !anyAlpha) {
            for (i in pixels.indices) pixels[i] = pixels[i] or (0xFF shl 24)
        }
        return runCatching { Bitmap.createBitmap(pixels, width, height, Bitmap.Config.ARGB_8888) }.getOrNull()
    }

    private fun isPng(b: ByteArray): Boolean =
        b.size >= 8 && b[0] == 0x89.toByte() && b[1] == 0x50.toByte() && b[2] == 0x4E.toByte() && b[3] == 0x47.toByte()

    private fun isRaster(b: ByteArray): Boolean {
        if (isPng(b)) return true
        if (b.size >= 3 && b[0] == 0xFF.toByte() && b[1] == 0xD8.toByte()) return true
        if (b.size >= 4 && b[0] == 0x47.toByte() && b[1] == 0x49.toByte() && b[2] == 0x46.toByte()) return true
        return b.size >= 12 && b[0] == 0x52.toByte() && b[8] == 0x57.toByte() && b[9] == 0x45.toByte() && b[10] == 0x42.toByte()
    }

    private fun isIco(b: ByteArray): Boolean =
        b.size >= 6 && b[0] == 0.toByte() && b[1] == 0.toByte() && b[2] == 1.toByte() && b[3] == 0.toByte()

    private fun u8(b: ByteArray, offset: Int): Int =
        if (offset in b.indices) b[offset].toInt() and 0xFF else 0

    private fun u16(b: ByteArray, offset: Int): Int =
        u8(b, offset) or (u8(b, offset + 1) shl 8)

    private fun u32(b: ByteArray, offset: Int): Int =
        u8(b, offset) or (u8(b, offset + 1) shl 8) or (u8(b, offset + 2) shl 16) or (u8(b, offset + 3) shl 24)

    private fun s32(b: ByteArray, offset: Int): Int = u32(b, offset)
}
