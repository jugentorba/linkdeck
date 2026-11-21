package dev.linkdeck.app.ui

import android.os.Bundle
import android.view.View
import android.view.ViewGroup
import android.widget.EditText
import androidx.appcompat.app.AppCompatActivity
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.updatePadding
import androidx.recyclerview.widget.DefaultItemAnimator
import androidx.recyclerview.widget.GridLayoutManager
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import dev.linkdeck.app.R
import dev.linkdeck.app.data.DeckApp
import dev.linkdeck.app.data.DeckStore
import dev.linkdeck.app.databinding.ActivityMainBinding
import dev.linkdeck.app.databinding.DialogRenameBinding
import dev.linkdeck.app.media.FaviconLoader
import java.text.NumberFormat
import java.util.Locale

class MainActivity : AppCompatActivity() {

    private lateinit var binding: ActivityMainBinding
    private lateinit var adapter: DeckAdapter

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        WindowCompat.setDecorFitsSystemWindows(window, false)
        binding = ActivityMainBinding.inflate(layoutInflater)
        setContentView(binding.root)
        applyInsets()

        adapter = DeckAdapter(
            onOpen = { app -> startActivity(BrowserActivity.intent(this, app)) },
            onPin = ::pin,
            onRename = ::rename,
            onRemove = ::confirmRemove,
        )
        binding.deck.layoutManager = GridLayoutManager(this, spanCount())
        binding.deck.adapter = adapter
        binding.deck.itemAnimator = DefaultItemAnimator()
        binding.deck.addItemDecoration(GridSpacingDecoration(dp(12)))

        binding.fab.setOnClickListener { showAdd() }
        binding.emptyAdd.setOnClickListener { showAdd() }
        binding.settings.setOnClickListener { showSettings() }
    }

    override fun onResume() {
        super.onResume()
        refresh()
    }

    private fun refresh() {
        val apps = DeckStore.list().sortedBy { it.addedAt }
        adapter.submitList(apps)
        val empty = apps.isEmpty()
        binding.empty.visibility = if (empty) View.VISIBLE else View.GONE
        binding.fab.visibility = if (empty) View.GONE else View.VISIBLE
        binding.subtitle.text = resources.getQuantityString(
            R.plurals.deck_summary,
            apps.size,
            apps.size,
            number(apps.sumOf { it.blocked }),
        )
    }

    private fun showAdd() {
        AddLinkSheet().apply {
            onAdded = { refresh() }
        }.show(supportFragmentManager, "add")
    }

    private fun showSettings() {
        SettingsSheet().apply {
            onDeckCleared = { refresh() }
        }.show(supportFragmentManager, "settings")
    }

    private fun pin(app: DeckApp) {
        FaviconLoader.load(app.name, app.host) { bitmap -> ShortcutHelper.pin(this, app, bitmap) }
    }

    private fun rename(app: DeckApp) {
        val dialogBinding = DialogRenameBinding.inflate(layoutInflater)
        val input: EditText = dialogBinding.name
        input.setText(app.name)
        input.setSelection(input.text.length)

        val dialog = MaterialAlertDialogBuilder(this)
            .setTitle(R.string.rename_title)
            .setView(dialogBinding.root)
            .setNegativeButton(R.string.cancel, null)
            .setPositiveButton(R.string.save, null)
            .create()

        dialog.setOnShowListener {
            input.requestFocus()
            dialog.window?.setSoftInputMode(android.view.WindowManager.LayoutParams.SOFT_INPUT_STATE_VISIBLE)
            dialog.getButton(android.app.AlertDialog.BUTTON_POSITIVE).setOnClickListener {
                val name = input.text?.toString()?.trim().orEmpty().ifBlank { app.name }.take(40)
                DeckStore.rename(app.id, name)
                refresh()
                dialog.dismiss()
            }
        }
        dialog.show()
    }

    private fun confirmRemove(app: DeckApp) {
        MaterialAlertDialogBuilder(this)
            .setTitle(getString(R.string.remove_confirm_title, app.name))
            .setMessage(R.string.remove_confirm_body)
            .setNegativeButton(R.string.cancel, null)
            .setPositiveButton(R.string.remove) { _, _ ->
                DeckStore.remove(app.id)
                refresh()
            }
            .show()
    }

    private fun applyInsets() {
        ViewCompat.setOnApplyWindowInsetsListener(binding.root) { _, insets ->
            val bars = insets.getInsets(
                WindowInsetsCompat.Type.systemBars() or WindowInsetsCompat.Type.displayCutout()
            )
            binding.header.updatePadding(top = dp(10) + bars.top)
            binding.deck.updatePadding(bottom = dp(112) + bars.bottom)
            (binding.fab.layoutParams as ViewGroup.MarginLayoutParams).bottomMargin = dp(20) + bars.bottom
            insets
        }
    }

    private fun spanCount(): Int {
        val usable = resources.configuration.screenWidthDp - 40
        return ((usable + 12) / 162).coerceIn(2, 6)
    }

    private fun number(value: Long): String =
        if (value < 100_000) NumberFormat.getIntegerInstance().format(value)
        else String.format(Locale.US, "%.0fk", value / 1000.0)

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()
}
