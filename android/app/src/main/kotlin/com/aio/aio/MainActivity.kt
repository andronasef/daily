package com.aio.aio

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "aio/widget")
            .setMethodCallHandler { call, result ->
                if (call.method == "update") {
                    val mgr = AppWidgetManager.getInstance(this)
                    val ids = mgr.getAppWidgetIds(ComponentName(this, VerseWidgetProvider::class.java))
                    VerseWidgetProvider.render(this, mgr, ids)
                    result.success(null)
                } else result.notImplemented()
            }
    }
}
