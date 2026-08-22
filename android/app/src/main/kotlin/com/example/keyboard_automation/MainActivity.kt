package com.example.keyboard_automation

import android.content.pm.PackageManager
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodCall
import java.util.*

class MainActivity : FlutterActivity() {
    private val CHANNEL = "keyboard_automation/keyboard"
    private val ACCESSIBILITY_CHANNEL = "keyboard_automation/accessibility"
    
    private var methodChannel: MethodChannel? = null
    private var accessibilityChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "get_mouse_position" -> {
                    result.success(mapOf("x" to 0, "y" to 0))
                }
                "mouse_click" -> {
                    result.success(null)
                }
                "text" -> {
                    result.success(null)
                }
                "key" -> {
                    result.success(null)
                }
                "get_clipboard" -> {
                    result.success("")
                }
                else -> result.notImplemented()
            }
        }

        accessibilityChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ACCESSIBILITY_CHANNEL)
        accessibilityChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getActiveWindow" -> {
                    val service = KeyboardAutomationService.instance
                    if (service != null) {
                        val windowInfo = service.getActiveWindow()
                        result.success(windowInfo)
                    } else {
                        result.error("SERVICE_NOT_ACTIVE", "Accessibility service is not active", null)
                    }
                }
                "getInstalledApps" -> {
                    try {
                        val apps = getInstalledApplications()
                        result.success(apps)
                    } catch (e: Exception) {
                        result.error("GET_APPS_ERROR", e.message, null)
                    }
                }
                "checkPackageActive" -> {
                    val packageName = call.argument<String>("packageName")
                    if (packageName != null) {
                        val service = KeyboardAutomationService.instance
                        if (service != null) {
                            val activePkg = service.activePackageName
                            result.success(activePkg == packageName)
                        } else {
                            result.error("SERVICE_NOT_ACTIVE", "Accessibility service is not active", null)
                        }
                    } else {
                        result.error("INVALID_ARGUMENT", "packageName is required", null)
                    }
                }
                "getActiveWindowInfo" -> {
                    val service = KeyboardAutomationService.instance
                    if (service != null) {
                        val windowInfo = service.getActiveWindow()
                        result.success(windowInfo)
                    } else {
                        result.error("SERVICE_NOT_ACTIVE", "Accessibility service is not active", null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        KeyboardAutomationService.methodChannel = accessibilityChannel
    }

    private fun getInstalledApplications(): List<Map<String, String>> {
        val packageManager = packageManager
        val packages = packageManager.getInstalledApplications(PackageManager.GET_META_DATA)
        val apps = mutableListOf<Map<String, String>>()
        
        for (app in packages) {
            try {
                val appName = packageManager.getApplicationLabel(app).toString()
                val packageName = app.packageName
                if (!packageName.startsWith("com.android.") && 
                    !packageName.startsWith("android.") &&
                    !packageName.startsWith("com.google.android.") &&
                    !packageName.startsWith("com.google.android.gms") &&
                    !packageName.startsWith("com.google.android.setupwizard") &&
                    !packageName.startsWith("com.android.providers") &&
                    !packageName.startsWith("com.google.android.apps.maps") &&
                    packageName != "android" &&
                    packageName != "com.google.android.gsf") {
                    apps.add(mapOf(
                        "name" to appName,
                        "packageName" to packageName
                    ))
                }
            } catch (e: Exception) {
                // تجاهل التطبيقات التي لا يمكن قراءة اسمها
            }
        }
        
        return apps.sortedBy { it["name"] }
    }
}