package com.example.keyboard_automation

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import io.flutter.plugin.common.MethodChannel

class KeyboardAutomationService : AccessibilityService() {
    companion object {
        private const val TAG = "KeyboardAutomationService"
        var instance: KeyboardAutomationService? = null
        var activePackageName: String? = null
        var activeClassName: String? = null
        var methodChannel: MethodChannel? = null
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent) {
        when (event.eventType) {
            AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED -> {
                event.packageName?.let { pkg ->
                    val className = event.className?.toString() ?: "Unknown"
                    
                    activePackageName = pkg.toString()
                    activeClassName = className
                    
                    Log.d(TAG, "Active Window: $activePackageName / $activeClassName")
                    
                    sendActiveWindowUpdate()
                }
            }
            else -> {
                // يمكن إضافة أنواع أخرى من الأحداث حسب الحاجة
            }
        }
    }

    override fun onInterrupt() {
        Log.d(TAG, "Service interrupted")
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        
        val info = AccessibilityServiceInfo().apply {
            eventTypes = AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED
            feedbackType = AccessibilityServiceInfo.FEEDBACK_GENERIC
            notificationTimeout = 100
            flags = AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS
        }
        
        serviceInfo = info
        Log.d(TAG, "Accessibility Service Connected")
    }

    override fun onDestroy() {
        instance = null
        super.onDestroy()
    }

    private fun sendActiveWindowUpdate() {
        try {
            val args = hashMapOf(
                "packageName" to (activePackageName ?: ""),
                "className" to (activeClassName ?: "")
            )
            methodChannel?.invokeMethod("onActiveWindowChanged", args)
        } catch (e: Exception) {
            Log.e(TAG, "Error sending active window update: ${e.message}")
        }
    }

    fun getActiveWindow(): Map<String, String> {
        return mapOf(
            "packageName" to (activePackageName ?: ""),
            "className" to (activeClassName ?: "")
        )
    }
}