package com.cloudpocket.app.cloud_pocket

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.net.wifi.WifiManager
import android.os.Build
import android.os.PowerManager
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.provider.Settings
import android.webkit.MimeTypeMap
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity: FlutterActivity() {
    companion object {
        private var wifiLock: WifiManager.WifiLock? = null
        private var wifiLowLatencyLock: WifiManager.WifiLock? = null
        private var multicastLock: WifiManager.MulticastLock? = null
        private var wakeLock: PowerManager.WakeLock? = null
    }

    private val CHANNEL = "com.cloudpocket.app/wifi_lock"
    private val SHARE_CHANNEL = "com.cloudpocket.app/sharing_intent"
    private val ROOM_MEDIA_CHANNEL = "com.cloudpocket.app/room_media"
    private var shareMethodChannel: MethodChannel? = null
    private var roomMediaPlayer: android.media.MediaPlayer? = null
    private var roomVideoSurface: android.view.Surface? = null
    private var roomSurfaceTextureEntry: io.flutter.view.TextureRegistry.SurfaceTextureEntry? = null

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "openExternalUrl" -> {
                    val uri = Uri.parse(call.argument<String>("url") ?: "")
                    if (uri.scheme !in listOf("http", "https") || uri.host.isNullOrBlank() || !uri.userInfo.isNullOrEmpty()) {
                        result.success(false)
                    } else {
                        try {
                            startActivity(Intent(Intent.ACTION_VIEW, uri))
                            result.success(true)
                        } catch (_: Exception) {
                            result.success(false)
                        }
                    }
                }
                "getNativeBinaryPath" -> {
                    try {
                        val binaryName = call.argument<String>("name") ?: "libcloudflared.so"
                        val nativeDir = applicationInfo.nativeLibraryDir
                        val nativeFile = java.io.File(nativeDir, binaryName)
                        if (nativeFile.exists() && nativeFile.length() > 0) {
                            try { nativeFile.setExecutable(true, false) } catch (_: Exception) {}
                            result.success(nativeFile.absolutePath)
                            return@setMethodCallHandler
                        }

                        // Fallback: Check or extract to filesDir/bin
                        val binDir = java.io.File(filesDir, "bin")
                        if (!binDir.exists()) binDir.mkdirs()
                        val fallbackFile = java.io.File(binDir, binaryName)

                        if (!fallbackFile.exists() || fallbackFile.length() == 0L) {
                            try {
                                java.util.zip.ZipFile(java.io.File(packageCodePath)).use { zip ->
                                    val entry = zip.getEntry("lib/arm64-v8a/$binaryName")
                                        ?: zip.entries().asSequence().firstOrNull { it.name.endsWith(binaryName) }
                                    if (entry != null) {
                                        zip.getInputStream(entry).use { input ->
                                            java.io.FileOutputStream(fallbackFile).use { output ->
                                                input.copyTo(output)
                                            }
                                        }
                                    }
                                }
                            } catch (_: Exception) {}
                        }

                        if (fallbackFile.exists() && fallbackFile.length() > 0) {
                            try { fallbackFile.setExecutable(true, false) } catch (_: Exception) {}
                            result.success(fallbackFile.absolutePath)
                        } else {
                            result.success(null)
                        }
                    } catch (e: Exception) {
                        result.error("ERROR", "Failed to resolve native binary: ${e.message}", null)
                    }
                }
                "acquireWifiLock" -> {
                    val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
                    if (wifiManager == null) {
                        result.error("UNAVAILABLE", "WifiManager not available", null)
                        return@setMethodCallHandler
                    }
                    try {
                        if (wifiLock == null) {
                            @Suppress("DEPRECATION")
                            wifiLock = wifiManager.createWifiLock(
                                WifiManager.WIFI_MODE_FULL_HIGH_PERF,
                                "CloudPocket:WifiLock"
                            ).apply {
                                setReferenceCounted(false)
                            }
                        }
                        if (wifiLock?.isHeld == false) {
                            wifiLock?.acquire()
                        }
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                            if (wifiLowLatencyLock == null) {
                                wifiLowLatencyLock = wifiManager.createWifiLock(
                                    WifiManager.WIFI_MODE_FULL_LOW_LATENCY,
                                    "CloudPocket:WifiLowLatencyLock"
                                ).apply {
                                    setReferenceCounted(false)
                                }
                            }
                            if (wifiLowLatencyLock?.isHeld == false) {
                                wifiLowLatencyLock?.acquire()
                            }
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("ERROR", "Failed to acquire WifiLock: ${e.message}", null)
                    }
                }
                "releaseWifiLock" -> {
                    val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
                    if (wifiManager == null) {
                        result.error("UNAVAILABLE", "WifiManager not available", null)
                        return@setMethodCallHandler
                    }
                    try {
                        if (wifiLock?.isHeld == true) {
                            wifiLock?.release()
                        }
                        if (wifiLowLatencyLock?.isHeld == true) {
                            wifiLowLatencyLock?.release()
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("ERROR", "Failed to release WifiLock: ${e.message}", null)
                    }
                }
                "acquireMulticastLock" -> {
                    val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
                    if (wifiManager == null) {
                        result.error("UNAVAILABLE", "WifiManager not available", null)
                        return@setMethodCallHandler
                    }
                    try {
                        if (multicastLock == null) {
                            multicastLock = wifiManager.createMulticastLock("CloudPocket:MulticastLock").apply {
                                setReferenceCounted(false)
                            }
                        }
                        if (multicastLock?.isHeld == false) {
                            multicastLock?.acquire()
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("ERROR", "Failed to acquire MulticastLock: ${e.message}", null)
                    }
                }
                "releaseMulticastLock" -> {
                    val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
                    if (wifiManager == null) {
                        result.error("UNAVAILABLE", "WifiManager not available", null)
                        return@setMethodCallHandler
                    }
                    try {
                        if (multicastLock?.isHeld == true) {
                            multicastLock?.release()
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("ERROR", "Failed to release MulticastLock: ${e.message}", null)
                    }
                }
                "openHotspotSettings" -> {
                    try {
                        val intent = android.content.Intent().apply {
                            action = "android.settings.TETHER_SETTINGS"
                            flags = android.content.Intent.FLAG_ACTIVITY_NEW_TASK
                        }
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        try {
                            val fallbackIntent = android.content.Intent().apply {
                                action = android.provider.Settings.ACTION_WIRELESS_SETTINGS
                                flags = android.content.Intent.FLAG_ACTIVITY_NEW_TASK
                            }
                            startActivity(fallbackIntent)
                            result.success(true)
                        } catch (e2: Exception) {
                            result.error("ERROR", "Failed to open hotspot settings: ${e2.message}", null)
                        }
                    }
                }
                "acquireWakeLock" -> {
                    val powerManager = applicationContext.getSystemService(Context.POWER_SERVICE) as? PowerManager
                    if (powerManager == null) {
                        result.error("UNAVAILABLE", "PowerManager not available", null)
                        return@setMethodCallHandler
                    }
                    try {
                        if (wakeLock == null) {
                            wakeLock = powerManager.newWakeLock(
                                PowerManager.PARTIAL_WAKE_LOCK,
                                "CloudPocket:ServerWakeLock"
                            ).apply {
                                setReferenceCounted(false)
                            }
                        }
                        if (wakeLock?.isHeld == false) {
                            wakeLock?.acquire()
                        }
                        try {
                            activity.runOnUiThread {
                                activity.window?.addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                            }
                        } catch (_: Exception) {}
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("ERROR", "Failed to acquire WakeLock: ${e.message}", null)
                    }
                }
                "releaseWakeLock" -> {
                    try {
                        if (wakeLock?.isHeld == true) {
                            wakeLock?.release()
                        }
                        try {
                            activity.runOnUiThread {
                                activity.window?.clearFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                            }
                        } catch (_: Exception) {}
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("ERROR", "Failed to release WakeLock: ${e.message}", null)
                    }
                }
                "updateForegroundNotification" -> {
                    try {
                        val title = call.argument<String>("title") ?: "CloudPocket Sharing Active"
                        val text = call.argument<String>("text") ?: ""
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            val nm = applicationContext.getSystemService(android.app.NotificationManager::class.java)
                            if (nm != null && nm.getNotificationChannel("cloud_pocket_server_v2") != null) {
                                val launchIntent = applicationContext.packageManager.getLaunchIntentForPackage(applicationContext.packageName)
                                val pendingIntent = android.app.PendingIntent.getActivity(
                                    applicationContext,
                                    200,
                                    launchIntent,
                                    android.app.PendingIntent.FLAG_IMMUTABLE
                                )
                                val builder = android.app.Notification.Builder(applicationContext, "cloud_pocket_server_v2")
                                    .setOngoing(true)
                                    .setSmallIcon(applicationInfo.icon)
                                    .setContentIntent(pendingIntent)
                                    .setContentTitle(title)
                                    .setContentText(text)
                                nm.notify(1000, builder.build())
                            }
                        }
                        result.success(true)
                    } catch (_: Exception) {
                        result.success(false)
                    }
                }
                "openBatterySettings" -> {
                    try {
                        val intent = Intent().apply {
                            action = Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS
                            data = Uri.parse("package:$packageName")
                            flags = Intent.FLAG_ACTIVITY_NEW_TASK
                        }
                        startActivity(intent)
                        result.success(true)
                    } catch (_: Exception) {
                        try {
                            val intent = Intent().apply {
                                action = Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS
                                flags = Intent.FLAG_ACTIVITY_NEW_TASK
                            }
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            try {
                                val intent = Intent().apply {
                                    action = Settings.ACTION_APPLICATION_DETAILS_SETTINGS
                                    data = Uri.parse("package:$packageName")
                                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                                }
                                startActivity(intent)
                                result.success(true)
                            } catch (e2: Exception) {
                                result.error("ERROR", "Failed to open battery settings: ${e2.message}", null)
                            }
                        }
                    }
                }
                "isServiceRunning" -> {
                    try {
                        val running = com.pravera.flutter_foreground_task.service.ForegroundService.isRunningService
                        result.success(running)
                    } catch (_: Exception) {
                        result.success(false)
                    }
                }
                "isBatteryOptimizationIgnored" -> {
                    try {
                        val pm = applicationContext.getSystemService(Context.POWER_SERVICE) as? PowerManager
                        val ignored = pm?.isIgnoringBatteryOptimizations(packageName) ?: false
                        result.success(ignored)
                    } catch (_: Exception) {
                        result.success(false)
                    }
                }
                "isNotificationPermissionGranted" -> {
                    try {
                        val nm = androidx.core.app.NotificationManagerCompat.from(applicationContext)
                        result.success(nm.areNotificationsEnabled())
                    } catch (_: Exception) {
                        result.success(true)
                    }
                }
                "isWatchdogActive" -> {
                    try {
                        val scheduled = BackgroundWatchdogReceiver.isWatchdogScheduled(applicationContext)
                        result.success(scheduled)
                    } catch (_: Exception) {
                        result.success(false)
                    }
                }
                "setWatchdogActive" -> {
                    try {
                        val active = call.argument<Boolean>("active") ?: true
                        if (active) {
                            BackgroundWatchdogReceiver.scheduleWatchdog(applicationContext)
                        } else {
                            BackgroundWatchdogReceiver.cancelWatchdog(applicationContext)
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("ERROR", "Failed to set watchdog: ${e.message}", null)
                    }
                }
                "setScreenBrightness" -> {
                    try {
                        val brightness = call.argument<Double>("brightness")?.toFloat() ?: -1.0f
                        activity.runOnUiThread {
                            val lp = activity.window.attributes
                            lp.screenBrightness = brightness
                            activity.window.attributes = lp
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("ERROR", "Failed to set screen brightness: ${e.message}", null)
                    }
                }
                "copySensitiveClipboard" -> {
                    try {
                        val text = call.argument<String>("text") ?: ""
                        val label = call.argument<String>("label") ?: "CloudPocket"
                        val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as? android.content.ClipboardManager
                        if (clipboard != null) {
                            val clip = android.content.ClipData.newPlainText(label, text)
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                                clip.description.extras = android.os.PersistableBundle().apply {
                                    putBoolean(android.content.ClipDescription.EXTRA_IS_SENSITIVE, true)
                                }
                            }
                            clipboard.setPrimaryClip(clip)
                            result.success(true)
                        } else {
                            result.error("UNAVAILABLE", "ClipboardManager unavailable", null)
                        }
                    } catch (e: Exception) {
                        result.error("ERROR", "Failed to copy sensitive clipboard: ${e.message}", null)
                    }
                }
                "getOemExplanation" -> {
                    val m = Build.MANUFACTURER.lowercase()
                    val explanation = when {
                        m.contains("xiaomi") || m.contains("redmi") || m.contains("poco") ->
                            "Enable CloudPocket in Auto-start so transfers continue when the screen is locked."
                        m.contains("samsung") ->
                            "Set CloudPocket battery usage to 'Unrestricted' in App info so the server isn't put to sleep."
                        m.contains("oppo") || m.contains("realme") ->
                            "Allow CloudPocket in Auto-launch and background activity."
                        m.contains("vivo") || m.contains("iqoo") ->
                            "Allow High background power consumption for CloudPocket."
                        m.contains("huawei") || m.contains("honor") ->
                            "Set CloudPocket to 'Manage manually' and allow Auto-launch and Run in background."
                        else ->
                            "Allow CloudPocket to run in the background without battery restrictions."
                    }
                    result.success(explanation)
                }
                "openOemDeepLink", "openOemAutoStartSettings" -> {
                    val manufacturer = Build.MANUFACTURER.lowercase()
                    var success = false

                    try {
                        val intent = Intent()
                        when {
                            manufacturer.contains("xiaomi") || manufacturer.contains("redmi") || manufacturer.contains("poco") -> {
                                intent.setComponent(android.content.ComponentName("com.miui.securitycenter", "com.miui.permcenter.autostart.AutoStartManagementActivity"))
                            }
                            manufacturer.contains("oppo") || manufacturer.contains("realme") -> {
                                intent.setComponent(android.content.ComponentName("com.coloros.safecenter", "com.coloros.safecenter.permission.startup.StartupAppListActivity"))
                            }
                            manufacturer.contains("vivo") || manufacturer.contains("iqoo") -> {
                                intent.setComponent(android.content.ComponentName("com.vivo.permissionmanager", "com.vivo.permissionmanager.activity.BgStartUpManagerActivity"))
                            }
                            manufacturer.contains("huawei") || manufacturer.contains("honor") -> {
                                intent.setComponent(android.content.ComponentName("com.huawei.systemmanager", "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity"))
                            }
                            manufacturer.contains("samsung") -> {
                                intent.setComponent(android.content.ComponentName("com.samsung.android.lool", "com.samsung.android.sm.ui.battery.BatteryActivity"))
                            }
                        }
                        intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                        startActivity(intent)
                        success = true
                    } catch (_: Exception) {
                        // Fallback to app details
                        try {
                            val fallback = Intent().apply {
                                action = Settings.ACTION_APPLICATION_DETAILS_SETTINGS
                                data = Uri.parse("package:$packageName")
                                flags = Intent.FLAG_ACTIVITY_NEW_TASK
                            }
                            startActivity(fallback)
                            success = true
                        } catch (_: Exception) {}
                    }
                    result.success(success)
                }
                "getTetheringAddress" -> {
                    Thread {
                        try {
                            var tetheringIp: String? = null
                            val interfaces = java.net.NetworkInterface.getNetworkInterfaces()
                            if (interfaces != null) {
                                for (iface in interfaces) {
                                    if (!iface.isUp || iface.isLoopback) continue
                                    val name = iface.name.lowercase()
                                    val isTetheringIface = name.contains("ap") ||
                                        name.contains("softap") ||
                                        name.contains("swlan") ||
                                        name == "wlan1" ||
                                        name.contains("rndis") ||
                                        name.contains("ncm") ||
                                        name.contains("bridge") ||
                                        name.contains("teth") ||
                                        name.contains("usb")

                                    for (addr in iface.inetAddresses) {
                                        if (addr is java.net.Inet4Address && !addr.isLoopbackAddress) {
                                            val ip = addr.hostAddress ?: continue
                                            if (isTetheringIface) {
                                                tetheringIp = ip
                                                break
                                            }
                                            if (name.contains("wlan") && ip.endsWith(".1")) {
                                                val parts = ip.split(".")
                                                if (parts.size == 4) {
                                                    val a = parts[0].toIntOrNull() ?: 0
                                                    val b = parts[1].toIntOrNull() ?: 0
                                                    if (a == 192 && b == 168) {
                                                        tetheringIp = ip
                                                    }
                                                }
                                            }
                                        }
                                    }
                                    if (tetheringIp != null) break
                                }
                            }
                            activity.runOnUiThread { result.success(tetheringIp) }
                        } catch (e: Exception) {
                            activity.runOnUiThread { result.success(null) }
                        }
                    }.start()
                }
                else -> result.notImplemented()
            }
        }

        val shareChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SHARE_CHANNEL)
        this.shareMethodChannel = shareChannel
        shareChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialSharedData" -> {
                    val payload = extractSharedPayload(intent)
                    intent?.action = null
                    result.success(payload)
                }
                else -> result.notImplemented()
            }
        }

        val securityChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.cloudpocket.app/security")
        securityChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "enableSecureMode" -> {
                    activity.runOnUiThread {
                        try {
                            window.addFlags(android.view.WindowManager.LayoutParams.FLAG_SECURE)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("ERROR", "Failed to enable secure mode: ${e.message}", null)
                        }
                    }
                }
                "disableSecureMode" -> {
                    activity.runOnUiThread {
                        try {
                            window.clearFlags(android.view.WindowManager.LayoutParams.FLAG_SECURE)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("ERROR", "Failed to disable secure mode: ${e.message}", null)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }

        val roomMediaChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ROOM_MEDIA_CHANNEL)
        roomMediaChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "pdfGetPageCount" -> {
                    val path = call.argument<String>("path")
                    if (path.isNullOrBlank()) {
                        result.error("INVALID_ARG", "Missing PDF path", null)
                        return@setMethodCallHandler
                    }
                    Thread {
                        try {
                            val file = File(path)
                            if (!file.exists()) {
                                activity.runOnUiThread { result.error("NOT_FOUND", "PDF file not found", null) }
                                return@Thread
                            }
                            android.os.ParcelFileDescriptor.open(file, android.os.ParcelFileDescriptor.MODE_READ_ONLY).use { pfd ->
                                android.graphics.pdf.PdfRenderer(pfd).use { renderer ->
                                    val count = renderer.pageCount
                                    activity.runOnUiThread { result.success(count) }
                                }
                            }
                        } catch (e: Exception) {
                            activity.runOnUiThread { result.error("PDF_ERROR", e.message, null) }
                        }
                    }.start()
                }
                "pdfRenderPage" -> {
                    val path = call.argument<String>("path")
                    val pageIndex = call.argument<Int>("pageIndex") ?: 0
                    val targetWidth = (call.argument<Int>("width") ?: 1200).coerceIn(300, 2400)
                    if (path.isNullOrBlank()) {
                        result.error("INVALID_ARG", "Missing PDF path", null)
                        return@setMethodCallHandler
                    }
                    Thread {
                        try {
                            val file = File(path)
                            if (!file.exists()) {
                                activity.runOnUiThread { result.error("NOT_FOUND", "PDF file not found", null) }
                                return@Thread
                            }
                            android.os.ParcelFileDescriptor.open(file, android.os.ParcelFileDescriptor.MODE_READ_ONLY).use { pfd ->
                                android.graphics.pdf.PdfRenderer(pfd).use { renderer ->
                                    if (pageIndex < 0 || pageIndex >= renderer.pageCount) {
                                        activity.runOnUiThread { result.error("OUT_OF_RANGE", "Invalid page index", null) }
                                        return@Thread
                                    }
                                    renderer.openPage(pageIndex).use { page ->
                                        val scale = targetWidth.toFloat() / page.width.coerceAtLeast(1)
                                        val targetHeight = (page.height * scale).toInt().coerceAtLeast(1)
                                        val bitmap = android.graphics.Bitmap.createBitmap(
                                            targetWidth,
                                            targetHeight,
                                            android.graphics.Bitmap.Config.ARGB_8888
                                        )
                                        bitmap.eraseColor(android.graphics.Color.WHITE)
                                        page.render(
                                            bitmap,
                                            null,
                                            null,
                                            android.graphics.pdf.PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY
                                        )
                                        val out = java.io.ByteArrayOutputStream()
                                        bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 90, out)
                                        bitmap.recycle()
                                        val bytes = out.toByteArray()
                                        activity.runOnUiThread { result.success(bytes) }
                                    }
                                }
                            }
                        } catch (e: Exception) {
                            activity.runOnUiThread { result.error("PDF_RENDER_ERROR", e.message, null) }
                        }
                    }.start()
                }
                "mediaPrepare" -> {
                    val source = call.argument<String>("source")
                    val isVideo = call.argument<Boolean>("isVideo") ?: false
                    val headers = call.argument<Map<String, String>>("headers")
                    if (source.isNullOrBlank()) {
                        result.error("INVALID_ARG", "Missing media source", null)
                        return@setMethodCallHandler
                    }
                    try {
                        releaseRoomMedia()
                        val mp = android.media.MediaPlayer()
                        if (isVideo) {
                            val entry = flutterEngine.renderer.createSurfaceTexture()
                            val surface = android.view.Surface(entry.surfaceTexture())
                            mp.setSurface(surface)
                            roomSurfaceTextureEntry = entry
                            roomVideoSurface = surface
                        }
                        if (source.startsWith("http://") || source.startsWith("https://")) {
                            mp.setDataSource(applicationContext, Uri.parse(source), headers ?: emptyMap())
                        } else {
                            mp.setDataSource(source)
                        }
                        roomMediaPlayer = mp
                        var replied = false
                        mp.setOnPreparedListener { player ->
                            if (!replied) {
                                replied = true
                                val w = try { player.videoWidth } catch (_: Exception) { 0 }
                                val h = try { player.videoHeight } catch (_: Exception) { 0 }
                                val dur = try { player.duration.coerceAtLeast(0) } catch (_: Exception) { 0 }
                                if (isVideo && w > 0 && h > 0) {
                                    try {
                                        roomSurfaceTextureEntry?.surfaceTexture()?.setDefaultBufferSize(w, h)
                                    } catch (_: Exception) {}
                                }
                                result.success(
                                    mapOf(
                                        "textureId" to (roomSurfaceTextureEntry?.id() ?: -1L),
                                        "durationMs" to dur,
                                        "width" to w,
                                        "height" to h
                                    )
                                )
                            }
                        }
                        mp.setOnErrorListener { _, what, extra ->
                            if (!replied) {
                                replied = true
                                result.error("MEDIA_ERROR", "Media playback error ($what, $extra)", null)
                            }
                            true
                        }
                        mp.prepareAsync()
                    } catch (e: Exception) {
                        releaseRoomMedia()
                        result.error("MEDIA_INIT_ERROR", e.message, null)
                    }
                }
                "mediaPlay" -> {
                    try {
                        roomMediaPlayer?.start()
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("MEDIA_PLAY_ERROR", e.message, null)
                    }
                }
                "mediaPause" -> {
                    try {
                        if (roomMediaPlayer?.isPlaying == true) {
                            roomMediaPlayer?.pause()
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("MEDIA_PAUSE_ERROR", e.message, null)
                    }
                }
                "mediaSeek" -> {
                    try {
                        val pos = call.argument<Int>("positionMs") ?: 0
                        roomMediaPlayer?.seekTo(pos.coerceAtLeast(0))
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("MEDIA_SEEK_ERROR", e.message, null)
                    }
                }
                "mediaGetStatus" -> {
                    val mp = roomMediaPlayer
                    if (mp == null) {
                        result.success(mapOf("isPlaying" to false, "positionMs" to 0, "durationMs" to 0))
                    } else {
                        val playing = try { mp.isPlaying } catch (_: Exception) { false }
                        val pos = try { mp.currentPosition.coerceAtLeast(0) } catch (_: Exception) { 0 }
                        val dur = try { mp.duration.coerceAtLeast(0) } catch (_: Exception) { 0 }
                        result.success(mapOf("isPlaying" to playing, "positionMs" to pos, "durationMs" to dur))
                    }
                }
                "mediaRelease" -> {
                    releaseRoomMedia()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun releaseRoomMedia() {
        try {
            roomMediaPlayer?.stop()
        } catch (_: Exception) {}
        try {
            roomMediaPlayer?.release()
        } catch (_: Exception) {}
        roomMediaPlayer = null
        try {
            roomVideoSurface?.release()
        } catch (_: Exception) {}
        roomVideoSurface = null
        try {
            roomSurfaceTextureEntry?.release()
        } catch (_: Exception) {}
        roomSurfaceTextureEntry = null
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val payload = extractSharedPayload(intent)
        if (payload.isNotEmpty()) {
            shareMethodChannel?.invokeMethod("onSharedDataReceived", payload)
        }
    }

    private fun extractSharedPayload(intent: Intent?): Map<String, Any> {
        val payload = HashMap<String, Any>()
        if (intent == null) return payload

        val action = intent.action
        if (Intent.ACTION_VIEW == action && intent.data != null) {
            val uri = intent.data
            if (uri?.scheme == "cloudpocket" && uri.host == "room") {
                val roomUrl = uri.getQueryParameter("url")
                if (!roomUrl.isNullOrBlank()) {
                    payload["roomUrl"] = roomUrl
                    val pin = uri.getQueryParameter("pin")
                    if (!pin.isNullOrBlank()) {
                        payload["roomPin"] = pin
                    }
                    val nick = uri.getQueryParameter("nick") ?: uri.getQueryParameter("nickname")
                    if (!nick.isNullOrBlank()) {
                        payload["roomNick"] = nick
                    }
                    return payload
                }
            }
        }

        if (Intent.ACTION_SEND != action && Intent.ACTION_SEND_MULTIPLE != action) {
            return payload
        }

        val filesList = ArrayList<String>()

        if (Intent.ACTION_SEND == action) {
            val uri: Uri? = if (Build.VERSION.SDK_INT >= 33) {
                intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
            } else {
                @Suppress("DEPRECATION")
                intent.getParcelableExtra(Intent.EXTRA_STREAM)
            }

            if (uri != null) {
                val path = resolveUriToPath(uri)
                if (path != null) {
                    filesList.add(path)
                }
            } else {
                val text = intent.getStringExtra(Intent.EXTRA_TEXT)
                if (!text.isNullOrBlank()) {
                    payload["text"] = text
                }
            }
        } else if (Intent.ACTION_SEND_MULTIPLE == action) {
            val uris: ArrayList<Uri>? = if (Build.VERSION.SDK_INT >= 33) {
                intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
            } else {
                @Suppress("DEPRECATION")
                intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM)
            }

            if (uris != null) {
                for (uri in uris) {
                    val path = resolveUriToPath(uri)
                    if (path != null) {
                        filesList.add(path)
                    }
                }
            }
        }

        if (filesList.isNotEmpty()) {
            payload["files"] = filesList
        }

        return payload
    }

    private fun resolveUriToPath(uri: Uri): String? {
        if ("file".equals(uri.scheme, ignoreCase = true)) {
            val file = File(uri.path ?: return null)
            return if (file.exists()) file.absolutePath else null
        }

        if ("content".equals(uri.scheme, ignoreCase = true)) {
            // 1. Try MediaStore DATA column query
            try {
                val projection = arrayOf(MediaStore.MediaColumns.DATA)
                contentResolver.query(uri, projection, null, null, null)?.use { cursor ->
                    if (cursor.moveToFirst()) {
                        val col = cursor.getColumnIndex(MediaStore.MediaColumns.DATA)
                        if (col != -1) {
                            val path = cursor.getString(col)
                            if (!path.isNullOrEmpty()) {
                                val f = File(path)
                                if (f.exists() && f.canRead()) {
                                    return f.absolutePath
                                }
                            }
                        }
                    }
                }
            } catch (_: Exception) {}

            // 2. Fallback: Copy content stream to cache directory
            try {
                var displayName: String? = null
                try {
                    contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
                        if (cursor.moveToFirst()) {
                            val nameCol = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                            if (nameCol != -1) {
                                displayName = cursor.getString(nameCol)
                            }
                        }
                    }
                } catch (_: Exception) {}

                if (displayName.isNullOrBlank()) {
                    val mime = contentResolver.getType(uri)
                    val ext = if (mime != null) {
                        MimeTypeMap.getSingleton().getExtensionFromMimeType(mime) ?: "bin"
                    } else "bin"
                    displayName = "shared_${System.currentTimeMillis()}.$ext"
                }

                val safeName = File(displayName).name
                val sharedDir = File(cacheDir, "shared_incoming")
                if (!sharedDir.exists()) sharedDir.mkdirs()

                var targetFile = File(sharedDir, safeName)
                if (targetFile.exists()) {
                    val base = safeName.substringBeforeLast('.', safeName)
                    val ext = if (safeName.contains('.')) ".${safeName.substringAfterLast('.')}" else ""
                    targetFile = File(sharedDir, "${base}_${System.currentTimeMillis()}$ext")
                }

                contentResolver.openInputStream(uri)?.use { input ->
                    FileOutputStream(targetFile).use { output ->
                        input.copyTo(output)
                    }
                }

                if (targetFile.exists() && targetFile.length() > 0) {
                    return targetFile.absolutePath
                }
            } catch (_: Exception) {}
        }
        return null
    }

    override fun onDestroy() {
        releaseRoomMedia()
        try {
            if (!com.pravera.flutter_foreground_task.service.ForegroundService.isRunningService) {
                if (wifiLock?.isHeld == true) {
                    wifiLock?.release()
                }
                if (wifiLowLatencyLock?.isHeld == true) {
                    wifiLowLatencyLock?.release()
                }
                if (multicastLock?.isHeld == true) {
                    multicastLock?.release()
                }
                if (wakeLock?.isHeld == true) {
                    wakeLock?.release()
                }
            }
        } catch (_: Exception) {}
        super.onDestroy()
    }
}
