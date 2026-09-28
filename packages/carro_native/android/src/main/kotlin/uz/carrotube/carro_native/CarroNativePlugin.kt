package uz.carrotube.carro_native

import androidx.annotation.OptIn
import android.Manifest
import android.app.Activity
import android.app.Application
import android.app.PictureInPictureParams
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Rect
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Rational
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.media3.common.util.UnstableApi
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import io.flutter.view.TextureRegistry

/**
 * Flutter entry point (Android). Channels mirror the iOS implementation:
 *   carro/player, carro/player/events, carro/system, carro/ircapture.
 * The DSP parameters are set from Dart through dart:ffi on the same libcarro_dsp.so.
 */
@OptIn(UnstableApi::class)
class CarroNativePlugin : FlutterPlugin, MethodChannel.MethodCallHandler, EventChannel.StreamHandler,
    ActivityAware, PluginRegistry.RequestPermissionsResultListener {

    private lateinit var context: Context
    private var textures: TextureRegistry? = null
    private var playerChannel: MethodChannel? = null
    private var eventChannel: EventChannel? = null
    private var systemChannel: MethodChannel? = null
    private var irChannel: MethodChannel? = null
    private var sink: EventChannel.EventSink? = null
    private var activity: Activity? = null
    private var activityBinding: ActivityPluginBinding? = null
    private var irCapture: CarroIrCapture? = null
    private var pendingMic: MethodChannel.Result? = null
    private val main = Handler(Looper.getMainLooper())

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        textures = binding.textureRegistry
        CarroDspJni.version() // loads libcarro_dsp.so early (also used by dart:ffi)
        irCapture = CarroIrCapture(context)

        playerChannel = MethodChannel(binding.binaryMessenger, "carro/player").also { it.setMethodCallHandler(this) }
        eventChannel = EventChannel(binding.binaryMessenger, "carro/player/events").also { it.setStreamHandler(this) }
        systemChannel = MethodChannel(binding.binaryMessenger, "carro/system").also {
            it.setMethodCallHandler { call, result -> handleSystem(call, result) }
        }
        irChannel = MethodChannel(binding.binaryMessenger, "carro/ircapture").also {
            it.setMethodCallHandler { call, result -> handleIr(call, result) }
        }
        CarroPlayerCore.emit = { event -> main.post { sink?.success(event) } }
        instance = this
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        playerChannel?.setMethodCallHandler(null)
        eventChannel?.setStreamHandler(null)
        systemChannel?.setMethodCallHandler(null)
        irChannel?.setMethodCallHandler(null)
        if (instance === this) {
            CarroPlayerCore.emit = null
            instance = null
        }
    }

    // ---- events -----------------------------------------------------------------------------
    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
        CarroPlayerCore.sendState()
    }

    override fun onCancel(arguments: Any?) {
        sink = null
    }

    private fun ensureService() {
        try {
            context.startService(Intent(context, CarroPlaybackService::class.java))
        } catch (_: Exception) {
            // Background start not allowed right now; Media3 starts it when playback begins.
        }
    }

    // ---- carro/player -------------------------------------------------------------------------
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val args = call.arguments as? Map<*, *> ?: emptyMap<String, Any?>()
        when (call.method) {
            "init" -> {
                CarroPlayerCore.player(context)
                ensureService()
                result.success(null)
            }
            "load" -> {
                ensureService()
                result.success(CarroPlayerCore.load(context, textures, args))
                updatePipParams()
            }
            "play" -> {
                ensureService()
                CarroPlayerCore.play(context)
                result.success(null)
            }
            "pause" -> {
                CarroPlayerCore.pause()
                result.success(null)
            }
            "stop", "dispose" -> {
                CarroPlayerCore.stop()
                result.success(null)
            }
            "seek" -> {
                CarroPlayerCore.seek((args["ms"] as? Number)?.toLong() ?: 0L)
                result.success(null)
            }
            "setRate" -> {
                CarroPlayerCore.setRate((args["rate"] as? Number)?.toFloat() ?: 1f)
                result.success(null)
            }
            "setQueueControls" -> {
                CarroPlayerCore.hasNext = args["hasNext"] as? Boolean ?: false
                result.success(null)
            }
            "setResumeOnBluetooth" -> {
                CarroPlayerCore.resumeOnBluetooth = args["enabled"] as? Boolean ?: true
                result.success(null)
            }
            "setVideoEnabled" -> {
                CarroPlayerCore.setVideoEnabled(args["enabled"] as? Boolean ?: true)
                result.success(null)
            }
            "setBrowsable" -> {
                @Suppress("UNCHECKED_CAST")
                CarroPlayerCore.setBrowsable((args["items"] as? List<Map<*, *>>) ?: emptyList())
                result.success(null)
            }
            "setAutoPip" -> {
                autoPip = args["enabled"] as? Boolean ?: false
                updatePipParams()
                result.success(null)
            }
            "isPipSupported" -> result.success(pipSupported())
            "startPip" -> result.success(enterPip(args))
            "stopPip" -> result.success(null)
            else -> result.notImplemented()
        }
    }

    private fun pipSupported(): Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            context.packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)

    private fun pipParams(args: Map<*, *>? = null): PictureInPictureParams? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return null
        val b = PictureInPictureParams.Builder().setAspectRatio(aspect)
        if (args != null) {
            val d = context.resources.displayMetrics.density
            val x = ((args["x"] as? Number)?.toDouble() ?: 0.0) * d
            val y = ((args["y"] as? Number)?.toDouble() ?: 0.0) * d
            val w = ((args["w"] as? Number)?.toDouble() ?: 0.0) * d
            val h = ((args["h"] as? Number)?.toDouble() ?: 0.0) * d
            if (w > 0 && h > 0) b.setSourceRectHint(Rect(x.toInt(), y.toInt(), (x + w).toInt(), (y + h).toInt()))
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            b.setAutoEnterEnabled(autoPip)
            b.setSeamlessResizeEnabled(true)
        }
        return b.build()
    }

    private fun updatePipParams() {
        val a = activity ?: return
        if (!pipSupported()) return
        try {
            pipParams()?.let { a.setPictureInPictureParams(it) }
        } catch (_: Exception) {
        }
    }

    private fun enterPip(args: Map<*, *>): Boolean {
        val a = activity ?: return false
        if (!pipSupported()) return false
        return try {
            val params = pipParams(args) ?: return false
            a.enterPictureInPictureMode(params)
        } catch (_: Exception) {
            false
        }
    }

    // ---- carro/system -------------------------------------------------------------------------
    private fun handleSystem(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "deviceInfo" -> result.success(CarroSystem.deviceInfo())
            "isIgnoringBatteryOptimizations" -> result.success(CarroSystem.isIgnoringBatteryOptimizations(context))
            "requestIgnoreBatteryOptimizations" -> {
                CarroSystem.requestIgnoreBatteryOptimizations(activity ?: context)
                result.success(null)
            }
            "openVendorBackgroundSettings" -> {
                val vendor = (call.argument<String>("vendor")) ?: android.os.Build.MANUFACTURER
                result.success(CarroSystem.openVendorBackgroundSettings(activity ?: context, vendor))
            }
            else -> result.notImplemented()
        }
    }

    // ---- carro/ircapture ----------------------------------------------------------------------
    private fun hasMic() =
        ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED

    private fun handleIr(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "requestMicrophone" -> {
                if (hasMic()) {
                    result.success(true)
                    return
                }
                val a = activity
                if (a == null) {
                    result.success(false)
                    return
                }
                pendingMic?.success(false)
                pendingMic = result
                ActivityCompat.requestPermissions(a, arrayOf(Manifest.permission.RECORD_AUDIO), REQ_MIC)
            }
            "route" -> result.success(irCapture?.route())
            "capture" -> {
                if (!hasMic()) {
                    result.error("permission", "Microphone / audio input permission denied", null)
                    return
                }
                CarroPlayerCore.pause()
                val args = call.arguments as? Map<*, *> ?: emptyMap<String, Any?>()
                irCapture?.capture(args) { r ->
                    r.fold(
                        onSuccess = { result.success(it) },
                        onFailure = { result.error("capture", it.message ?: "Capture failed", null) },
                    )
                }
            }
            "cancel" -> {
                irCapture?.cancel()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray): Boolean {
        if (requestCode != REQ_MIC) return false
        val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
        pendingMic?.success(granted)
        pendingMic = null
        return true
    }

    // ---- activity -----------------------------------------------------------------------------
    private val lifecycle = object : Application.ActivityLifecycleCallbacks {
        override fun onActivityStarted(a: Activity) {
            if (a !== activity) return
            CarroPlayerCore.setVideoEnabled(true)
            sink?.success(mapOf("type" to "background", "background" to false))
        }

        override fun onActivityStopped(a: Activity) {
            if (a !== activity) return
            val inPip = Build.VERSION.SDK_INT >= Build.VERSION_CODES.N && a.isInPictureInPictureMode
            if (!inPip) CarroPlayerCore.setVideoEnabled(false) // keep audio, stop decoding video
            sink?.success(mapOf("type" to "background", "background" to true))
        }

        override fun onActivityCreated(a: Activity, b: Bundle?) {}
        override fun onActivityResumed(a: Activity) {}
        override fun onActivityPaused(a: Activity) {}
        override fun onActivitySaveInstanceState(a: Activity, b: Bundle) {}
        override fun onActivityDestroyed(a: Activity) {}
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        activityBinding = binding
        binding.addRequestPermissionsResultListener(this)
        binding.activity.application.registerActivityLifecycleCallbacks(lifecycle)
        updatePipParams()
    }

    override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) = onAttachedToActivity(binding)

    override fun onDetachedFromActivity() {
        activityBinding?.removeRequestPermissionsResultListener(this)
        activity?.application?.unregisterActivityLifecycleCallbacks(lifecycle)
        activityBinding = null
        activity = null
    }

    companion object {
        private const val REQ_MIC = 7431
        @JvmStatic var autoPip = false
        @JvmStatic var aspect = Rational(16, 9)
        private var instance: CarroNativePlugin? = null

        /** Called by MainActivity.onPictureInPictureModeChanged. */
        @JvmStatic
        fun notifyPipChanged(active: Boolean) {
            if (active) CarroPlayerCore.setVideoEnabled(true)
            CarroPlayerCore.emit?.invoke(mapOf("type" to "pip", "active" to active))
        }

        /** Called by MainActivity.onUserLeaveHint (Android < 12 auto PiP). */
        @JvmStatic
        fun onUserLeaveHint(activity: Activity) {
            if (!autoPip || Build.VERSION.SDK_INT < Build.VERSION_CODES.O || Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) return
            try {
                activity.enterPictureInPictureMode(PictureInPictureParams.Builder().setAspectRatio(aspect).build())
            } catch (_: Exception) {
            }
        }
    }
}
