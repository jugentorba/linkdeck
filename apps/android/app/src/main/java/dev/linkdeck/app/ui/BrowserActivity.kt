package dev.linkdeck.app.ui

import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.webkit.CookieManager
import android.webkit.PermissionRequest
import android.webkit.WebChromeClient
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import android.widget.PopupMenu
import android.widget.Toast
import androidx.activity.addCallback
import androidx.appcompat.app.AppCompatActivity
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.core.view.updatePadding
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import dev.linkdeck.app.R
import dev.linkdeck.app.data.BlockList
import dev.linkdeck.app.data.DeckApp
import dev.linkdeck.app.data.DeckStore
import dev.linkdeck.app.data.Settings
import dev.linkdeck.app.data.UrlTools
import dev.linkdeck.app.databinding.ActivityBrowserBinding
import dev.linkdeck.app.media.FaviconLoader
import java.io.ByteArrayInputStream
import java.util.concurrent.atomic.AtomicInteger

class BrowserActivity : AppCompatActivity() {

    companion object {
        const val EXTRA_URL = "dev.linkdeck.app.URL"
        const val EXTRA_NAME = "dev.linkdeck.app.NAME"
        const val EXTRA_ID = "dev.linkdeck.app.ID"

        private const val DESKTOP_UA =
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " +
                "(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
        private const val UA_SUFFIX = " LinkDeck/1.0"

        private const val MENU_RELOAD = 1
        private const val MENU_DESKTOP = 2
        private const val MENU_BLOCKING = 3
        private const val MENU_EXTERNAL = 4
        private const val MENU_PIN = 5
        private const val MENU_REMOVE = 6

        fun intent(context: Context, app: DeckApp): Intent =
            Intent(context, BrowserActivity::class.java).apply {
                putExtra(EXTRA_ID, app.id)
                putExtra(EXTRA_NAME, app.name)
                putExtra(EXTRA_URL, app.url)
            }
    }

    private lateinit var binding: ActivityBrowserBinding
    private lateinit var webView: WebView

    private var appId: String? = null
    private var appName: String = ""
    private var startUrl: String = ""

    private val sessionBlocked = AtomicInteger(0)
    private var flushedBlocked = 0
    private var blocking = true
    private var desktopMode = false
    private var chromeVisible = true
    private var customView: View? = null
    private var customViewCallback: WebChromeClient.CustomViewCallback? = null
    private var defaultUserAgent = ""
    private var documentStartSupported = false
    private var cosmeticScript = ""

    private val handler = Handler(Looper.getMainLooper())
    private var shieldScheduled = false
    private val shieldUpdate = Runnable {
        shieldScheduled = false
        renderShield()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        WindowCompat.setDecorFitsSystemWindows(window, false)
        binding = ActivityBrowserBinding.inflate(layoutInflater)
        setContentView(binding.root)

        val args = parseIntent(intent)
        if (args == null) {
            finish()
            return
        }
        startUrl = args.first
        appName = args.second
        appId = args.third
        DeckStore.get(appId)?.let { stored ->
            appName = stored.name
            startUrl = stored.url
        }
        blocking = Settings.blockAds

        cosmeticScript = runCatching {
            assets.open("cosmetic.js").bufferedReader().use { it.readText() }
        }.getOrDefault("")

        applyInsets()
        setupWebView()
        setupChrome()
        binding.host.text = UrlTools.host(startUrl).ifEmpty { appName }
        binding.progress.max = 100
        renderShield()
        webView.loadUrl(startUrl)
    }

    override fun onResume() {
        super.onResume()
        webView.onResume()
    }

    override fun onPause() {
        webView.onPause()
        flushBlocked()
        super.onPause()
    }

    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        flushBlocked()
        binding.fullscreen.removeAllViews()
        webView.apply {
            stopLoading()
            loadUrl("about:blank")
            clearHistory()
            removeAllViews()
            destroy()
        }
        super.onDestroy()
    }

    private fun parseIntent(intent: Intent?): Triple<String, String, String?>? {
        if (intent?.data?.scheme == "linkdeck") {
            val raw = intent.data?.getQueryParameter("url") ?: return null
            val url = UrlTools.normalize(raw) ?: return null
            val name = intent.data?.getQueryParameter("name") ?: UrlTools.suggestName(url)
            return Triple(url, name, null)
        }
        val raw = intent?.getStringExtra(EXTRA_URL) ?: return null
        val url = UrlTools.normalize(raw) ?: return null
        val name = intent.getStringExtra(EXTRA_NAME)?.takeIf { it.isNotBlank() }
            ?: UrlTools.suggestName(url)
        return Triple(url, name, intent.getStringExtra(EXTRA_ID))
    }

    private fun applyInsets() {
        ViewCompat.setOnApplyWindowInsetsListener(binding.root) { _, insets ->
            val bars = insets.getInsets(
                WindowInsetsCompat.Type.systemBars() or WindowInsetsCompat.Type.displayCutout()
            )
            binding.chrome.updatePadding(top = bars.top)
            binding.webView.updatePadding(bottom = bars.bottom)
            insets
        }
    }

    private fun setupChrome() {
        binding.back.setOnClickListener { goBack() }
        binding.menu.setOnClickListener { showMenu() }
        binding.shield.setOnClickListener { toggleBlocking() }
        binding.hotspot.setOnClickListener { setChromeVisible(true) }
        binding.retry.setOnClickListener {
            binding.errorPanel.visibility = View.GONE
            webView.reload()
        }
    }

    private fun setupWebView() {
        webView = binding.webView
        webView.setBackgroundColor(Color.BLACK)

        val settings = webView.settings
        settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            databaseEnabled = true
            mediaPlaybackRequiresUserGesture = false
            loadWithOverviewMode = true
            useWideViewPort = true
            displayZoomControls = false
            builtInZoomControls = true
            setSupportMultipleWindows(false)
            javaScriptCanOpenWindowsAutomatically = false
            mixedContentMode = WebSettings.MIXED_CONTENT_COMPATIBILITY_MODE
            allowFileAccess = false
            allowContentAccess = false
            cacheMode = WebSettings.LOAD_DEFAULT
        }
        defaultUserAgent = settings.userAgentString + UA_SUFFIX
        settings.userAgentString = defaultUserAgent

        CookieManager.getInstance().apply {
            setAcceptCookie(true)
            setAcceptThirdPartyCookies(webView, true)
        }

        documentStartSupported = WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT)
        if (documentStartSupported && cosmeticScript.isNotEmpty()) {
            val source = "window.__linkdeckBlockAds = $blocking;\n" +
                "window.__linkdeckBlockPopups = ${Settings.blockPopups};\n$cosmeticScript"
            WebViewCompat.addDocumentStartJavaScript(webView, source, setOf("*"))
        }

        webView.webViewClient = object : WebViewClient() {
            override fun shouldInterceptRequest(view: WebView, request: WebResourceRequest): WebResourceResponse? {
                if (!blocking || request.isForMainFrame) return null
                if (!BlockList.isBlocked(request.url.host)) return null
                countBlocked()
                return WebResourceResponse("text/plain", "UTF-8", ByteArrayInputStream(ByteArray(0)))
            }

            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                val url = request.url
                val scheme = url.scheme?.lowercase()
                if (scheme == "http" || scheme == "https") {
                    if (blocking && !request.hasGesture() && BlockList.isBlocked(url.host)) {
                        countBlocked()
                        return true
                    }
                    return false
                }
                openExternal(url)
                return true
            }

            override fun onPageStarted(view: WebView, url: String?, favicon: android.graphics.Bitmap?) {
                binding.errorPanel.visibility = View.GONE
                UrlTools.host(url.orEmpty()).takeIf { it.isNotEmpty() }?.let { binding.host.text = it }
            }

            override fun onPageFinished(view: WebView, url: String?) {
                binding.progress.visibility = View.GONE
                if (!documentStartSupported && cosmeticScript.isNotEmpty()) {
                    view.evaluateJavascript(cosmeticScript, null)
                }
                setChromeVisible(true)
                updateBackButton()
            }

            override fun onReceivedError(view: WebView, request: WebResourceRequest, error: WebResourceError) {
                if (request.isForMainFrame) {
                    binding.progress.visibility = View.GONE
                    binding.errorPanel.visibility = View.VISIBLE
                }
            }

            override fun doUpdateVisitedHistory(view: WebView, url: String?, isReload: Boolean) {
                updateBackButton()
            }
        }

        webView.webChromeClient = object : WebChromeClient() {
            override fun onProgressChanged(view: WebView, newProgress: Int) {
                if (newProgress >= 100) {
                    binding.progress.visibility = View.GONE
                } else {
                    binding.progress.visibility = View.VISIBLE
                    binding.progress.setProgressCompat(newProgress, true)
                }
            }

            override fun onShowCustomView(view: View, callback: CustomViewCallback) {
                if (customView != null) {
                    callback.onCustomViewHidden()
                    return
                }
                customView = view
                customViewCallback = callback
                binding.fullscreen.addView(
                    view,
                    FrameLayout.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT,
                        ViewGroup.LayoutParams.MATCH_PARENT
                    )
                )
                binding.fullscreen.visibility = View.VISIBLE
                window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                applyImmersive(true)
                setChromeVisible(false)
            }

            override fun onHideCustomView() {
                customView?.let { binding.fullscreen.removeView(it) }
                customView = null
                customViewCallback?.onCustomViewHidden()
                customViewCallback = null
                binding.fullscreen.visibility = View.GONE
                window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                applyImmersive(false)
                setChromeVisible(true)
            }

            override fun onPermissionRequest(request: PermissionRequest) {
                request.deny()
            }
        }

        webView.setDownloadListener { url, _, _, _, _ ->
            openExternal(Uri.parse(url))
        }

        webView.setOnScrollChangeListener { _, _, scrollY, _, oldScrollY ->
            if (customView != null) return@setOnScrollChangeListener
            val delta = scrollY - oldScrollY
            if (delta > 18 && scrollY > 140) {
                setChromeVisible(false)
            } else if (delta < -18) {
                setChromeVisible(true)
            }
        }

        onBackPressedDispatcher.addCallback(this) { goBack() }
    }

    private fun goBack() {
        when {
            customView != null -> (webView.webChromeClient as? WebChromeClient)?.onHideCustomView()
            webView.canGoBack() -> webView.goBack()
            else -> finish()
        }
    }

    private fun updateBackButton() {
        val canGoBack = webView.canGoBack()
        binding.back.isEnabled = canGoBack
        binding.back.alpha = if (canGoBack) 1f else 0.4f
    }

    private fun toggleBlocking() {
        blocking = !blocking
        Toast.makeText(
            this,
            if (blocking) R.string.blocking_on_toast else R.string.blocking_off_toast,
            Toast.LENGTH_SHORT
        ).show()
        if (blocking) webView.reload()
        renderShield()
    }

    private fun countBlocked() {
        sessionBlocked.incrementAndGet()
        if (!shieldScheduled) {
            shieldScheduled = true
            handler.postDelayed(shieldUpdate, 280)
        }
    }

    private fun renderShield() {
        val count = sessionBlocked.get()
        binding.shield.text = if (count > 0) DeckAdapter.formatCount(count.toLong()) else ""
        binding.shield.contentDescription = getString(R.string.shield_label, count.toString())
    }

    private fun flushBlocked() {
        val id = appId ?: return
        val total = sessionBlocked.get()
        val delta = total - flushedBlocked
        if (delta > 0) {
            DeckStore.addBlocked(id, delta.toLong())
            flushedBlocked = total
        }
    }

    private fun setChromeVisible(visible: Boolean) {
        if (chromeVisible == visible) return
        chromeVisible = visible
        binding.chrome.animate().cancel()
        if (visible) {
            binding.chrome.visibility = View.VISIBLE
            binding.hotspot.visibility = View.GONE
            binding.chrome.animate().translationY(0f).alpha(1f).setDuration(170).start()
        } else {
            binding.hotspot.visibility = View.VISIBLE
            binding.chrome.animate()
                .translationY(-(binding.chrome.height + dp(28)).toFloat())
                .alpha(0f)
                .setDuration(170)
                .withEndAction {
                    if (!chromeVisible) binding.chrome.visibility = View.INVISIBLE
                }
                .start()
        }
    }

    private fun applyImmersive(enabled: Boolean) {
        val controller = WindowCompat.getInsetsController(window, window.decorView)
        if (enabled) {
            controller.hide(WindowInsetsCompat.Type.systemBars())
            controller.systemBarsBehavior =
                WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        } else {
            controller.show(WindowInsetsCompat.Type.systemBars())
        }
    }

    private fun showMenu() {
        val popup = PopupMenu(this, binding.menu)
        popup.menu.add(0, MENU_RELOAD, 0, R.string.reload)
        popup.menu.add(0, MENU_DESKTOP, 1, R.string.desktop_site).apply { isCheckable = true; isChecked = desktopMode }
        popup.menu.add(0, MENU_BLOCKING, 2, if (blocking) R.string.blocking_on else R.string.blocking_off)
        popup.menu.add(0, MENU_EXTERNAL, 3, R.string.open_in_browser)
        if (appId != null) {
            popup.menu.add(0, MENU_PIN, 4, R.string.pin_home)
            popup.menu.add(0, MENU_REMOVE, 5, R.string.remove_from_deck)
        }
        popup.setOnMenuItemClickListener { item ->
            when (item.itemId) {
                MENU_RELOAD -> webView.reload()
                MENU_DESKTOP -> toggleDesktopMode()
                MENU_BLOCKING -> toggleBlocking()
                MENU_EXTERNAL -> openExternal(null)
                MENU_PIN -> pinCurrent()
                MENU_REMOVE -> confirmRemove()
            }
            true
        }
        popup.show()
    }

    private fun toggleDesktopMode() {
        desktopMode = !desktopMode
        webView.settings.userAgentString =
            if (desktopMode) DESKTOP_UA + UA_SUFFIX else defaultUserAgent
        webView.reload()
    }

    private fun pinCurrent() {
        val app = DeckStore.get(appId) ?: return
        FaviconLoader.load(app.name, app.host) { bitmap -> ShortcutHelper.pin(this, app, bitmap) }
    }

    private fun confirmRemove() {
        val id = appId ?: return
        MaterialAlertDialogBuilder(this)
            .setTitle(getString(R.string.remove_confirm_title, appName))
            .setMessage(R.string.remove_confirm_body)
            .setNegativeButton(R.string.cancel, null)
            .setPositiveButton(R.string.remove) { _, _ ->
                DeckStore.remove(id)
                finish()
            }
            .show()
    }

    private fun openExternal(uri: Uri?) {
        val target = uri ?: runCatching { Uri.parse(webView.url ?: startUrl) }.getOrNull() ?: return
        runCatching { startActivity(Intent(Intent.ACTION_VIEW, target)) }
            .onFailure { Toast.makeText(this, R.string.open_in_browser, Toast.LENGTH_SHORT).show() }
    }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()
}
