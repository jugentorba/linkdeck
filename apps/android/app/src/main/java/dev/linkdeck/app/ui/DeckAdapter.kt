package dev.linkdeck.app.ui

import android.view.LayoutInflater
import android.view.ViewGroup
import android.widget.PopupMenu
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView
import dev.linkdeck.app.R
import dev.linkdeck.app.data.DeckApp
import dev.linkdeck.app.databinding.ItemAppBinding
import dev.linkdeck.app.media.FaviconLoader
import java.text.NumberFormat
import java.util.Locale

class DeckAdapter(
    private val onOpen: (DeckApp) -> Unit,
    private val onPin: (DeckApp) -> Unit,
    private val onRename: (DeckApp) -> Unit,
    private val onRemove: (DeckApp) -> Unit,
) : ListAdapter<DeckApp, DeckAdapter.Holder>(Diff) {

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): Holder {
        val binding = ItemAppBinding.inflate(LayoutInflater.from(parent.context), parent, false)
        return Holder(binding)
    }

    override fun onBindViewHolder(holder: Holder, position: Int) = holder.bind(getItem(position))

    inner class Holder(private val binding: ItemAppBinding) : RecyclerView.ViewHolder(binding.root) {

        fun bind(app: DeckApp) {
            binding.name.text = app.name
            binding.host.text = app.displayHost
            binding.icon.setImageBitmap(FaviconLoader.cachedOrLetter(app.name, app.host))

            if (app.blocked > 0) {
                binding.blockedRow.visibility = android.view.View.VISIBLE
                binding.blocked.text = formatCount(app.blocked)
            } else {
                binding.blockedRow.visibility = android.view.View.INVISIBLE
            }

            binding.card.contentDescription = buildString {
                append(app.name)
                if (app.blocked > 0) append(", ${formatCount(app.blocked)} blocked")
            }

            FaviconLoader.load(app.name, app.host) { bitmap ->
                if (bindingAdapterPosition != RecyclerView.NO_POSITION &&
                    currentList.getOrNull(bindingAdapterPosition)?.id == app.id
                ) {
                    binding.icon.setImageBitmap(bitmap)
                }
            }

            binding.card.setOnClickListener { onOpen(app) }
            binding.card.setOnLongClickListener {
                showMenu(app)
                true
            }
        }

        private fun showMenu(app: DeckApp) {
            val popup = PopupMenu(binding.card.context, binding.card)
            popup.menu.add(0, MENU_OPEN, 0, R.string.open)
            popup.menu.add(0, MENU_PIN, 1, R.string.pin_home)
            popup.menu.add(0, MENU_RENAME, 2, R.string.rename)
            popup.menu.add(0, MENU_REMOVE, 3, R.string.remove)
            popup.setOnMenuItemClickListener { item ->
                when (item.itemId) {
                    MENU_OPEN -> { onOpen(app); true }
                    MENU_PIN -> { onPin(app); true }
                    MENU_RENAME -> { onRename(app); true }
                    MENU_REMOVE -> { onRemove(app); true }
                    else -> false
                }
            }
            popup.show()
        }
    }

    companion object {
        private const val MENU_OPEN = 1
        private const val MENU_PIN = 2
        private const val MENU_RENAME = 3
        private const val MENU_REMOVE = 4

        fun formatCount(value: Long): String = when {
            value < 10_000 -> NumberFormat.getIntegerInstance().format(value)
            else -> String.format(Locale.US, "%.1fk", value / 1000.0)
        }

        private val Diff = object : DiffUtil.ItemCallback<DeckApp>() {
            override fun areItemsTheSame(oldItem: DeckApp, newItem: DeckApp) = oldItem.id == newItem.id
            override fun areContentsTheSame(oldItem: DeckApp, newItem: DeckApp) = oldItem == newItem
        }
    }
}
