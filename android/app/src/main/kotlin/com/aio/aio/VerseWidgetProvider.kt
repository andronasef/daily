package com.aio.aio

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.widget.RemoteViews
import org.json.JSONObject
import org.json.JSONArray
import java.util.Calendar
import kotlin.random.Random
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.TimeZone

/** Daily personalized content; each widget retains its own selected category. */
class VerseWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, mgr: AppWidgetManager, ids: IntArray) = render(context, mgr, ids)
    override fun onAppWidgetOptionsChanged(context: Context, mgr: AppWidgetManager,
        id: Int, options: Bundle) = render(context, mgr, intArrayOf(id))

    override fun onDeleted(context: Context, ids: IntArray) {
        val editor = context.getSharedPreferences("verse_widget", Context.MODE_PRIVATE).edit()
        ids.forEach { editor.remove("category.$it").remove("memory.$it") }
        editor.apply()
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == ACTION_CYCLE) {
            val id = intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, -1)
            val mgr = AppWidgetManager.getInstance(context)
            if (mgr.getAppWidgetInfo(id) == null) return
            val prefs = context.getSharedPreferences("verse_widget", Context.MODE_PRIVATE)
            val next = (prefs.getInt("category.$id", 0) + 1) % 4
            val edit = prefs.edit().putInt("category.$id", next)
            if (next == 3) edit.remove("memory.$id") // Pick again on each visit.
            edit.apply()
            render(context, mgr, intArrayOf(id))
        } else super.onReceive(context, intent)
    }

    companion object {
        private fun memoryItem(context: Context, widgetId: Int): JSONObject? {
            val source = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val all = runCatching { JSONArray(source.getString("flutter.memorize-widget", "[]")) }
                .getOrDefault(JSONArray())
            val items = (0 until all.length()).mapNotNull { all.optJSONObject(it) }
            if (items.isEmpty()) return null
            val tomorrow = Calendar.getInstance().apply {
                add(Calendar.DAY_OF_YEAR, 1)
                set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0)
                set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
            }.timeInMillis
            val due = items.filter { it.optBoolean("new") || it.optLong("due") < tomorrow }
            val pool = due.ifEmpty { items }
            val prefs = context.getSharedPreferences("verse_widget", Context.MODE_PRIVATE)
            val selected = prefs.getString("memory.$widgetId", null)
            return pool.firstOrNull { it.optString("id") == selected } ?: pool[Random.nextInt(pool.size)].also {
                prefs.edit().putString("memory.$widgetId", it.optString("id")).apply()
            }
        }

        private const val ACTION_CYCLE = "com.aio.aio.VERSE_CYCLE"
        fun render(context: Context, mgr: AppWidgetManager, ids: IntArray) {
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val day = SimpleDateFormat("yyyy-MM-dd", Locale.US)
                .apply { timeZone = TimeZone.getTimeZone("UTC") }.format(System.currentTimeMillis())
            val entry = runCatching {
                JSONObject(prefs.getString("flutter.verse-widget", "{}") ?: "{}").optJSONObject(day)
            }.getOrNull()
            val selection = context.getSharedPreferences("verse_widget", Context.MODE_PRIVATE)
            for (id in ids) {
                val index = selection.getInt("category.$id", 0).coerceIn(0, 3)
                val label = arrayOf("آية اليوم", "البركة الروحية", "اسم الله", "آية للحفظ")[index]
                // Legacy verse-only snapshots remain readable until Flutter refreshes.
                val item = if (index == 3) memoryItem(context, id) else
                    entry?.optJSONArray("items")?.optJSONObject(index)
                        ?: if (index == 0 && entry?.has("v") == true) entry else null
                val title = item?.optString("t") ?: label
                val text = item?.optString("v") ?: if (index == 3)
                    "مفيش آيات للحفظ دلوقتي. ضيف آيات من حفظ الآيات." else "افتح التطبيق لتحميل $label"
                val payload = JSONObject().put("t", title).put("full",
                    item?.optString("full", text) ?: text).toString()
                val cycle = PendingIntent.getBroadcast(context, id,
                    Intent(context, VerseWidgetProvider::class.java).setAction(ACTION_CYCLE)
                        .putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id),
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
                val open = PendingIntent.getActivity(context, id,
                    Intent(context, MainActivity::class.java)
                        .setData(Uri.parse("daily-widget://verse/$id/$index"))
                        .putExtra("verseOpen", payload),
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
                val views = RemoteViews(context.packageName, R.layout.verse_widget)
                views.setTextViewText(R.id.verse_title, if (label == title || title.startsWith("$label · ")) title else "$label · $title")
                views.setTextViewText(R.id.verse_text, text)
                views.setContentDescription(R.id.verse_text, "$label، $text، اضغط للتبديل")
                views.setOnClickPendingIntent(R.id.verse_root, cycle)
                views.setOnClickPendingIntent(R.id.verse_open, open)
                mgr.updateAppWidget(id, views)
            }
        }
    }
}
