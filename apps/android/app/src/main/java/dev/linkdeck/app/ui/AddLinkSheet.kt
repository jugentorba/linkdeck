package dev.linkdeck.app.ui

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.Toast
import androidx.core.widget.doAfterTextChanged
import com.google.android.material.bottomsheet.BottomSheetDialogFragment
import dev.linkdeck.app.R
import dev.linkdeck.app.data.DeckStore
import dev.linkdeck.app.data.UrlTools
import dev.linkdeck.app.databinding.SheetAddBinding

class AddLinkSheet : BottomSheetDialogFragment() {

    private var binding: SheetAddBinding? = null
    var onAdded: (() -> Unit)? = null

    private var lastSuggestion = ""
    private var nameEdited = false

    override fun getTheme(): Int = R.style.ThemeOverlay_LinkDeck_Sheet

    override fun onCreateView(inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?): View {
        val created = SheetAddBinding.inflate(inflater, container, false)
        binding = created
        return created.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        val binding = binding ?: return
        binding.error.visibility = View.GONE

        binding.url.doAfterTextChanged { editable ->
            if (binding.error.visibility == View.VISIBLE) {
                binding.error.visibility = View.GONE
                binding.urlLayout.setBoxStrokeColor(requireContext().getColor(R.color.stroke))
            }
            suggestName(editable?.toString().orEmpty())
        }

        binding.name.doAfterTextChanged {
            if (binding.name.hasFocus()) nameEdited = true
        }

        binding.add.setOnClickListener { submit() }
        binding.name.setOnEditorActionListener { _, _, _ ->
            submit()
            true
        }
    }

    override fun onStart() {
        super.onStart()
        val dialog = dialog ?: return
        dialog.window?.setLayout(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT)
        dialog.window?.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_STATE_ALWAYS_VISIBLE)
        binding?.url?.requestFocus()
    }

    override fun onDestroyView() {
        binding = null
        super.onDestroyView()
    }

    private fun suggestName(raw: String) {
        val binding = binding ?: return
        val normalized = UrlTools.normalize(raw) ?: return
        val suggestion = UrlTools.suggestName(normalized)
        val current = binding.name.text?.toString().orEmpty()
        if (suggestion.isNotEmpty() && (!nameEdited || current.isBlank() || current == lastSuggestion)) {
            lastSuggestion = suggestion
            binding.name.setText(suggestion)
            binding.name.setSelection(suggestion.length)
        }
    }

    private fun submit() {
        val binding = binding ?: return
        val normalized = UrlTools.normalize(binding.url.text?.toString().orEmpty())
        if (normalized == null) {
            binding.urlLayout.setBoxStrokeColor(requireContext().getColor(R.color.danger))
            binding.error.visibility = View.VISIBLE
            return
        }
        val typedName = binding.name.text?.toString()?.trim().orEmpty()
        val name = typedName
            .ifBlank { UrlTools.suggestName(normalized) }
            .ifBlank { UrlTools.host(normalized) }
            .take(40)
        DeckStore.add(name, normalized)
        Toast.makeText(requireContext(), R.string.added_toast, Toast.LENGTH_SHORT).show()
        onAdded?.invoke()
        dismiss()
    }
}
