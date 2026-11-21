package dev.linkdeck.app.ui

import android.content.Context
import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.webkit.CookieManager
import android.webkit.WebStorage
import android.webkit.WebView
import com.google.android.material.bottomsheet.BottomSheetDialogFragment
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import dev.linkdeck.app.R
import dev.linkdeck.app.data.BlockList
import dev.linkdeck.app.data.DeckStore
import dev.linkdeck.app.data.Settings
import dev.linkdeck.app.databinding.SheetSettingsBinding
import dev.linkdeck.app.media.FaviconLoader
import java.text.NumberFormat

class SettingsSheet : BottomSheetDialogFragment() {

    private var binding: SheetSettingsBinding? = null
    var onDeckCleared: (() -> Unit)? = null

    override fun getTheme(): Int = R.style.ThemeOverlay_LinkDeck_Sheet

    override fun onCreateView(inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?): View {
        val created = SheetSettingsBinding.inflate(inflater, container, false)
        binding = created
        return created.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        val binding = binding ?: return
        binding.blockAds.isChecked = Settings.blockAds
        binding.blockPopups.isChecked = Settings.blockPopups
        binding.blockAds.setOnCheckedChangeListener { _, checked -> Settings.blockAds = checked }
        binding.blockPopups.setOnCheckedChangeListener { _, checked -> Settings.blockPopups = checked }

        val domains = BlockList.size
        binding.blocklistInfo.text = if (domains > 0) {
            getString(R.string.blocklist_info, NumberFormat.getIntegerInstance().format(domains))
        } else {
            getString(R.string.blocklist_loading)
        }

        binding.version.text = getString(R.string.version_line, versionName())
        binding.clearData.setOnClickListener { confirmClear() }
    }

    override fun onStart() {
        super.onStart()
        dialog?.window?.setLayout(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT)
    }

    override fun onDestroyView() {
        binding = null
        super.onDestroyView()
    }

    private fun confirmClear() {
        MaterialAlertDialogBuilder(requireContext())
            .setTitle(R.string.clear_confirm_title)
            .setMessage(R.string.clear_confirm_body)
            .setNegativeButton(R.string.cancel, null)
            .setPositiveButton(R.string.clear) { _, _ -> clearEverything() }
            .show()
    }

    private fun clearEverything() {
        val context = requireContext()
        WebStorage.getInstance().deleteAllData()
        CookieManager.getInstance().removeAllCookies(null)
        CookieManager.getInstance().flush()
        WebView(context).apply {
            clearCache(true)
            clearFormData()
            clearHistory()
            destroy()
        }
        DeckStore.clear()
        FaviconLoader.clear()
        onDeckCleared?.invoke()
        dismiss()
    }

    private fun versionName(): String = runCatching {
        val info = requireContext().packageManager.getPackageInfo(requireContext().packageName, 0)
        info.versionName.orEmpty()
    }.getOrDefault("1.0")
}
