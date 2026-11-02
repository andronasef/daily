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
            ACTION_TOGGLE -> {
                val id = intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, -1)
                val key = "showPrayed.$id"
                prefs(context).edit().putBoolean(key, !prefs(context).getBoolean(key, false)).apply()
                renderAll(context)
            }
            ACTION_MIDNIGHT, Intent.ACTION_TIME_CHANGED, Intent.ACTION_TIMEZONE_CHANGED,
            Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED -> renderAll(context)
            else -> super.onReceive(context, intent)
        }
    }

    companion object {
        private const val ACTION_TOGGLE = "com.aio.aio.INTERCEDE_TOGGLE"
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

        fun pendingLabel(context: Context, id: String): String? {
            val items = snapshot(context) ?: return null
            val item = (0 until items.length()).mapNotNull { items.optJSONObject(it) }
                .firstOrNull { it.optString("id") == id } ?: return null
            if (sameDay(lastFor(item, queue(context)), System.currentTimeMillis())) return null
            return "${item.optString("t")} — ${item.optString("e")}"
        }

        fun confirmPrayer(context: Context, id: String): Boolean {
            // Recheck at confirmation: another instance may already have recorded it.
            if (pendingLabel(context, id) == null) return true
            val taps = queue(context)
            val previousQueue = taps.toString()
            taps.put(JSONObject().put("id", id).put("at", System.currentTimeMillis())
                .put("k", UUID.randomUUID().toString().replace("-", "")))
            val saved = prefs(context).edit().putString("taps", taps.toString()).commit()
            if (!saved) prefs(context).edit().putString("taps", previousQueue).commit()
            renderAll(context)
            return saved
        }

        private fun mark(context: Context, id: String): PendingIntent = PendingIntent.getActivity(
            context, 0, Intent(context, IntercedeConfirmActivity::class.java)
                .setData(Uri.fromParts("intercede", id, null)),
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
                val showPrayed = prefs(context).getBoolean("showPrayed.$id", false)
                val display = if (showPrayed) all.filter { sameDay(lastFor(it, taps), now) } else pending
                val toggle = PendingIntent.getBroadcast(context, id,
                    Intent(context, IntercedeWidgetProvider::class.java).setAction(ACTION_TOGGLE)
                        .putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id),
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
                views.setTextViewText(R.id.intercede_toggle,
                    if (showPrayed) "عرض اللي لسه متصلاش ليهم" else "عرض اللي اتصلى ليهم النهاردة")
                views.setOnClickPendingIntent(R.id.intercede_toggle, toggle)
                if (showPrayed) {
                    views.setTextViewText(R.id.intercede_message, if (display.isEmpty()) "لسه متصلاش لأي طلب النهاردة" else "")
                    views.setViewVisibility(R.id.intercede_message, if (display.isEmpty()) View.VISIBLE else View.GONE)
                }
                val height = manager.getAppWidgetOptions(id)
                    .getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 360)
                val visibleCount = ((height - 112) / 48).coerceIn(1, 5)
                for ((index, rowId) in rows.withIndex()) {
                    val item = display.getOrNull(index)
                    val visible = item != null && index < visibleCount
                    views.setViewVisibility(rowId, if (visible) View.VISIBLE else View.GONE)
                    if (visible && item != null) {
                        val title = item.optString("t")
                        val entity = item.optString("e")
                        views.setTextViewText(rowId, "${if (showPrayed) "✓" else "☐"}  $title — $entity")
                        views.setContentDescription(rowId, "${if (showPrayed) "تم الصلاة" else "تأكيد الصلاة"}: $title، $entity")
                        views.setOnClickPendingIntent(rowId, if (showPrayed) null else mark(context, item.optString("id")))
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
