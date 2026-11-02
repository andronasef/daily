package com.aio.aio

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.util.TypedValue
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import org.json.JSONObject
import kotlin.math.min

/** Compatibility adapter for Android versions before RemoteCollectionItems. */
class IntercedeListService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory = Factory(this,
        intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, -1))

    private class Factory(val context: Context, val widgetId: Int) : RemoteViewsFactory {
        private var items = emptyList<JSONObject>()
        private var done = false
        override fun onCreate() { onDataSetChanged() }
        override fun onDataSetChanged() {
            done = IntercedeWidgetProvider.showPrayed(context, widgetId)
            items = IntercedeWidgetProvider.displayItems(context, done)
        }
        override fun getCount() = items.size
        override fun getViewAt(position: Int): RemoteViews? = items.getOrNull(position)?.let {
            prayerRow(context, widgetId, it, done)
        }
        override fun getLoadingView(): RemoteViews? = null
        override fun getViewTypeCount() = 1
        override fun getItemId(position: Int) = position.toLong()
        override fun hasStableIds() = false
        override fun onDestroy() { items = emptyList() }
    }
}

fun prayerRow(context: Context, widgetId: Int, item: JSONObject, done: Boolean): RemoteViews {
    val options = AppWidgetManager.getInstance(context).getAppWidgetOptions(widgetId)
    val width = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 250)
    val height = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 360)
    val size = (14f * min(width / 250f, height / 300f)).coerceIn(10f, 22f)
    return RemoteViews(context.packageName, R.layout.intercede_widget_row).apply {
        val title = item.optString("t")
        val entity = item.optString("e")
        setTextViewText(R.id.intercede_row, "${if (done) "✓" else "☐"}  $title — $entity")
        setTextViewTextSize(R.id.intercede_row, TypedValue.COMPLEX_UNIT_SP, size)
        setContentDescription(R.id.intercede_row, "${if (done) "تم الصلاة" else "تأكيد الصلاة"}: $title، $entity")
        // Explicitly reset click state when a host recycles pending/done rows.
        setBoolean(R.id.intercede_row, "setEnabled", !done)
        setOnClickFillInIntent(R.id.intercede_row,
            Intent().setData(Uri.fromParts("intercede", item.optString("id"), null)))
    }
}
