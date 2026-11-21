package dev.linkdeck.app

import android.app.Application
import dev.linkdeck.app.data.BlockList
import dev.linkdeck.app.data.DeckStore
import dev.linkdeck.app.data.Settings
import dev.linkdeck.app.media.FaviconLoader

class LinkDeckApp : Application() {
    override fun onCreate() {
        super.onCreate()
        Settings.init(this)
        DeckStore.init(this)
        FaviconLoader.init(this)
        BlockList.loadAsync(this)
    }
}
