package com.aio.aio

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.TimeZone

/** Shows today's verse from the JSON Flutter cached in SharedPreferences
 *  ("verse-widget", keyed by UTC day, same key Dart's getPeriodKey uses). */
class VerseWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, mgr: AppWidgetManager, ids: IntArray) =
        render(context, mgr, ids)

    companion object {
        fun render(context: Context, mgr: AppWidgetManager, ids: IntArray) {
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val day = SimpleDateFormat("yyyy-MM-dd", Locale.US)
                .apply { timeZone = TimeZone.getTimeZone("UTC") }
                .format(System.currentTimeMillis())
            val entry = prefs.getString("flutter.verse-widget", null)
                ?.let { runCatching { JSONObject(it).optJSONObject(day) }.getOrNull() }

            val open = PendingIntent.getActivity(
                context, 0,
                Intent(context, MainActivity::class.java),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            for (id in ids) {
                val views = RemoteViews(context.packageName, R.layout.verse_widget)
                views.setTextViewText(R.id.verse_title, entry?.optString("t") ?: "آية اليوم")
                views.setTextViewText(R.id.verse_text, entry?.optString("v") ?: "افتح التطبيق لتحميل آية اليوم")
                views.setOnClickPendingIntent(R.id.verse_root, open)
                mgr.updateAppWidget(id, views)
            }
        }
    }
}
