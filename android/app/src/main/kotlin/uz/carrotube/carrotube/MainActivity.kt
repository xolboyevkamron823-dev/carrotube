package uz.carrotube.carrotube

import android.content.Context
import android.content.res.Configuration
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import uz.carrotube.carro_native.CarroNativePlugin

/**
 * The Flutter engine is cached at process level and NOT destroyed with the Activity. When the
 * user swipes the app away from recents while music plays, the foreground media service keeps
 * the process alive and the Dart isolate (queue, autoplay, stream re-resolution) keeps
 * running; reopening the app re-attaches to the same engine and state.
 */
class MainActivity : FlutterActivity() {
    override fun provideFlutterEngine(context: Context): FlutterEngine {
        FlutterEngineCache.getInstance().get(ENGINE_ID)?.let { return it }
        val engine = FlutterEngine(context.applicationContext)
        engine.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault())
        FlutterEngineCache.getInstance().put(ENGINE_ID, engine)
        return engine
    }

    override fun shouldDestroyEngineWithHost(): Boolean = false

    override fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean, newConfig: Configuration) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        CarroNativePlugin.notifyPipChanged(isInPictureInPictureMode)
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        CarroNativePlugin.onUserLeaveHint(this)
    }

    private companion object {
        const val ENGINE_ID = "carrotube_main_engine"
    }
}
