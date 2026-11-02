package com.aio.aio

import android.app.Activity
import android.app.AlertDialog
import android.os.Bundle
import android.view.View
import android.widget.Toast

/** A widget launches this small dialog directly; no Flutter engine or network. */
class IntercedeConfirmActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val id = intent.data?.schemeSpecificPart
        val label = id?.let { IntercedeWidgetProvider.pendingLabel(this, it) }
        if (id == null || label == null) {
            finish()
            return
        }
        val dialog = AlertDialog.Builder(this, android.R.style.Theme_Material_Light_Dialog_Alert)
            .setTitle("صليت؟")
            .setMessage("تأكد إنك صليت للطلب ده:\n$label")
            .setNegativeButton("إلغاء") { _, _ -> finish() }
            .setPositiveButton("أيوه، صليت", null)
            .setOnCancelListener { finish() }
            .create()
        dialog.setOnShowListener {
            dialog.window?.decorView?.layoutDirection = View.LAYOUT_DIRECTION_RTL
            dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener {
                if (IntercedeWidgetProvider.confirmPrayer(this, id)) {
                    dialog.dismiss()
                    finish()
                } else {
                    Toast.makeText(this, "تعذر الحفظ، حاول تاني", Toast.LENGTH_SHORT).show()
                }
            }
        }
        dialog.show()
    }
}
