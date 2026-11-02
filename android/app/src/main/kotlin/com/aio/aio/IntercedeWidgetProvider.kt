package com.aio.aio

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.os.SystemClock
import android.view.View
import android.widget.RemoteViews
import org.json.JSONArray
import org.json.JSONObject
import java.util.Calendar
import java.util.UUID

/** The snapshot is ordered by Dart; native code only filters by local day. */
class IntercedeWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) = renderAll(context)

    override fun onAppWidgetOptionsChanged(context: Context, manager: AppWidgetManager,
        id: Int, options: Bundle) = renderAll(context)

    override fun onDisabled(context: Context) {
        (context.getSystemService(Context.ALARM_SERVICE) as AlarmManager).cancel(alarm(context))
    }

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            ACTION_PRAY -> {
                intent.data?.schemeSpecificPart?.let { enqueue(context, it) }
                renderAll(context)
            }
            ACTION_MIDNIGHT, Intent.ACTION_TIME_CHANGED, Intent.ACTION_TIMEZONE_CHANGED,
            Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED -> renderAll(context)
            else -> super.onReceive(context, intent)
        }
    }

    companion object {
        private const val ACTION_PRAY = "com.aio.aio.INTERCEDE_PRAY"
        private const val ACTION_MIDNIGHT = "com.aio.aio.INTERCEDE_MIDNIGHT"
        private val rows = intArrayOf(R.id.intercede_row_1, R.id.intercede_row_2,
            R.id.intercede_row_3, R.id.intercede_row_4, R.id.intercede_row_5)

        private fun prefs(context: Context) =
            context.getSharedPreferences("intercede_widget", Context.MODE_PRIVATE)

        private fun queue(context: Context): JSONArray =
            runCatching { JSONArray(prefs(context).getString("taps", "[]")) }.getOrDefault(JSONArray())

        fun peek(context: Context): String = queue(context).toString()

        fun ack(context: Context, keys: List<String>): Boolean {
            val keySet = keys.toSet()
            val old = queue(context)
            val remaining = JSONArray()
            for (i in 0 until old.length()) {
                val item = old.optJSONObject(i) ?: continue
                if (item.optString("k") !in keySet) remaining.put(item)
            }
            val saved = prefs(context).edit().putString("taps", remaining.toString()).commit()
            if (saved) renderAll(context)
            return saved
        }

        private fun snapshot(context: Context): JSONArray? = runCatching {
            val value = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                .getString("flutter.intercede-widget", null) ?: return null
            JSONObject(value).getJSONArray("items")
        }.getOrNull()

        private fun sameDay(a: Long, b: Long): Boolean {
            if (a <= 0) return false
            val first = Calendar.getInstance().apply { timeInMillis = a }
            val second = Calendar.getInstance().apply { timeInMillis = b }
            return first.get(Calendar.YEAR) == second.get(Calendar.YEAR) &&
                first.get(Calendar.DAY_OF_YEAR) == second.get(Calendar.DAY_OF_YEAR)
        }

        private fun lastFor(item: JSONObject, taps: JSONArray): Long {
            var last = item.optLong("last", 0)
            for (i in 0 until taps.length()) {
                val tap = taps.optJSONObject(i) ?: continue
                if (tap.optString("id") == item.optString("id")) last = maxOf(last, tap.optLong("at"))
            }
            return last
        }

        private fun enqueue(context: Context, id: String) {
            val items = snapshot(context) ?: return
            val taps = queue(context)
            val now = System.currentTimeMillis()
            val item = (0 until items.length()).mapNotNull { items.optJSONObject(it) }
                .firstOrNull { it.optString("id") == id } ?: return
            if (sameDay(lastFor(item, taps), now)) return
            // Backfill changes the row under the finger; reject a rapid second tap.
            val elapsed = SystemClock.elapsedRealtime()
            val previous = prefs(context).getLong("lastTapElapsed", -1000)
            if (elapsed >= previous && elapsed - previous < 650) return
            val previousQueue = taps.toString()
            taps.put(JSONObject().put("id", id).put("at", now)
                .put("k", UUID.randomUUID().toString().replace("-", "")))
            val saved = prefs(context).edit().putString("taps", taps.toString())
                .putLong("lastTapElapsed", elapsed).commit()
            if (!saved) {
                // SharedPreferences updates its memory map even when disk fails.
                // Restore it so a failed durable write never displays success.
                prefs(context).edit().putString("taps", previousQueue)
                    .putLong("lastTapElapsed", previous).commit()
            }
        }

        private fun mark(context: Context, id: String): PendingIntent = PendingIntent.getBroadcast(
            context, 0, Intent(context, IntercedeWidgetProvider::class.java)
                .setAction(ACTION_PRAY).setData(Uri.fromParts("intercede", id, null)),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

        private fun alarm(context: Context): PendingIntent = PendingIntent.getBroadcast(
            context, 0, Intent(context, IntercedeWidgetProvider::class.java).setAction(ACTION_MIDNIGHT),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

        fun renderAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, IntercedeWidgetProvider::class.java))
            if (ids.isEmpty()) return
            val items = snapshot(context)
            val taps = queue(context)
            val now = System.currentTimeMillis()
            val all = if (items == null) emptyList() else
                (0 until items.length()).mapNotNull { items.optJSONObject(it) }
            val pending = all.filterNot { sameDay(lastFor(it, taps), now) }
            val counted = all.filter { it.optBoolean("c", true) }
            val done = counted.count { sameDay(lastFor(it, taps), now) }
            val open = PendingIntent.getActivity(context, 20,
                Intent(context, MainActivity::class.java),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            for (id in ids) {
                val views = RemoteViews(context.packageName, R.layout.intercede_widget)
                views.setTextViewText(R.id.intercede_title, "تشفع · $done من ${counted.size}")
                views.setOnClickPendingIntent(R.id.intercede_title, open)
                val message = when {
                    items == null -> "افتح التطبيق لتحميل الصلوات"
                    all.isEmpty() -> "لسه مفيش طلبات صلاة"
                    pending.isEmpty() -> "خلصت كل صلوات النهاردة ✓"
                    else -> ""
                }
                views.setViewVisibility(R.id.intercede_message, if (message.isEmpty()) View.GONE else View.VISIBLE)
                views.setTextViewText(R.id.intercede_message, message)
                views.setOnClickPendingIntent(R.id.intercede_message, open)
                val height = manager.getAppWidgetOptions(id)
                    .getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 320)
                val visibleCount = ((height - 64) / 48).coerceIn(1, 5)
                for ((index, rowId) in rows.withIndex()) {
                    val item = pending.getOrNull(index)
                    val visible = item != null && index < visibleCount
                    views.setViewVisibility(rowId, if (visible) View.VISIBLE else View.GONE)
                    if (visible && item != null) {
                        val title = item.optString("t")
                        val entity = item.optString("e")
                        views.setTextViewText(rowId, "☐  $title — $entity")
                        views.setContentDescription(rowId, "صليت: $title، $entity")
                        views.setOnClickPendingIntent(rowId, mark(context, item.optString("id")))
                    }
                }
                manager.updateAppWidget(id, views)
            }
            val midnight = Calendar.getInstance().apply {
                add(Calendar.DAY_OF_YEAR, 1)
                set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0)
                set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
            }
            (context.getSystemService(Context.ALARM_SERVICE) as AlarmManager)
                .setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, midnight.timeInMillis, alarm(context))
        }
    }
}
