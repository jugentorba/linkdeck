package dev.linkdeck.app.ui

import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.widget.Toast
import androidx.core.content.pm.ShortcutInfoCompat
import androidx.core.content.pm.ShortcutManagerCompat
import androidx.core.graphics.drawable.IconCompat
import dev.linkdeck.app.R
import dev.linkdeck.app.data.DeckApp
import dev.linkdeck.app.media.FaviconLoader

/** Creates real launcher shortcuts that boot straight into a saved site. */
object ShortcutHelper {

    fun pin(context: Context, app: DeckApp, icon: Bitmap? = null) {
        if (!ShortcutManagerCompat.isRequestPinShortcutSupported(context)) {
            Toast.makeText(context, R.string.pin_unsupported, Toast.LENGTH_LONG).show()
            return
        }
        val launch = Intent(context, BrowserActivity::class.java).apply {
            action = Intent.ACTION_VIEW
            putExtra(BrowserActivity.EXTRA_ID, app.id)
            putExtra(BrowserActivity.EXTRA_NAME, app.name)
            putExtra(BrowserActivity.EXTRA_URL, app.url)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
        val bitmap = icon ?: FaviconLoader.cachedOrLetter(app.name, app.host)
        val shortcut = ShortcutInfoCompat.Builder(context, "linkdeck-${app.id}")
            .setShortLabel(app.name.take(40))
            .setLongLabel(app.name.take(40))
            .setIcon(IconCompat.createWithBitmap(bitmap))
            .setIntent(launch)
            .build()
        ShortcutManagerCompat.requestPinShortcut(context, shortcut, null)
        Toast.makeText(context, R.string.pin_added, Toast.LENGTH_SHORT).show()
    }
}
