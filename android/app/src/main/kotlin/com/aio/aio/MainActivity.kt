package com.aio.aio

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var widgetChannel: MethodChannel? = null
    private var pendingVerseOpen: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        pendingVerseOpen = savedInstanceState?.getString("verseOpen")
            ?: intent.getStringExtra("verseOpen")
        intent.removeExtra("verseOpen")
        super.onCreate(savedInstanceState)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        intent.getStringExtra("verseOpen")?.let {
            pendingVerseOpen = it
            intent.removeExtra("verseOpen")
            widgetChannel?.invokeMethod("verseOpenAvailable", null)
        }
    }

    override fun onSaveInstanceState(outState: Bundle) {
        outState.putString("verseOpen", pendingVerseOpen)
        super.onSaveInstanceState(outState)
    }
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        widgetChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "aio/widget")
        widgetChannel!!.setMethodCallHandler { call, result ->
                if (call.method == "consumeVerseOpen") {
                    val content = pendingVerseOpen
                    pendingVerseOpen = null
                    result.success(content)
                } else if (call.method == "update") {
                    val mgr = AppWidgetManager.getInstance(this)
                    val ids = mgr.getAppWidgetIds(ComponentName(this, VerseWidgetProvider::class.java))
                    VerseWidgetProvider.render(this, mgr, ids)
                    IntercedeWidgetProvider.renderAll(this)
                    result.success(null)
                } else if (call.method == "peekIntercedeTaps") {
                    result.success(IntercedeWidgetProvider.peek(this))
                } else if (call.method == "ackIntercedeTaps") {
                    val keys = (call.arguments as? List<*>)?.filterIsInstance<String>() ?: emptyList()
                    if (IntercedeWidgetProvider.ack(this, keys)) result.success(null)
                    else result.error("save_failed", "Could not acknowledge prayer events", null)
                } else result.notImplemented()
            }
    }
}
