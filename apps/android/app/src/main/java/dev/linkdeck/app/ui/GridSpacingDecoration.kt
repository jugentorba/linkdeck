package dev.linkdeck.app.ui

import android.graphics.Rect
import android.view.View
import androidx.recyclerview.widget.GridLayoutManager
import androidx.recyclerview.widget.RecyclerView

/** Even inner gutters for a grid; the screen margins come from RecyclerView padding. */
class GridSpacingDecoration(private val gap: Int) : RecyclerView.ItemDecoration() {

    override fun getItemOffsets(
        outRect: Rect,
        view: View,
        parent: RecyclerView,
        state: RecyclerView.State,
    ) {
        val manager = parent.layoutManager as? GridLayoutManager ?: return
        val position = parent.getChildAdapterPosition(view)
        if (position == RecyclerView.NO_POSITION) return
        val spanCount = manager.spanCount
        val column = position % spanCount
        val row = position / spanCount

        outRect.left = if (column == 0) 0 else gap / 2
        outRect.right = if (column == spanCount - 1) 0 else gap / 2
        outRect.top = if (row == 0) 0 else gap / 2
        outRect.bottom = gap / 2
    }
}
