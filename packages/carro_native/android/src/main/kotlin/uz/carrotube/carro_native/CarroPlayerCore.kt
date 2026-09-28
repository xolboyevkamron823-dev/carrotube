package uz.carrotube.carro_native

import androidx.annotation.OptIn
import android.content.Context
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.net.Uri
import android.os.Handler
import android.os.Looper
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.ForwardingPlayer
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.PlaybackException
import androidx.media3.common.PlaybackParameters
import androidx.media3.common.Player
import androidx.media3.common.VideoSize
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.datasource.HttpDataSource
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.audio.AudioSink
import androidx.media3.exoplayer.audio.DefaultAudioSink
import androidx.media3.exoplayer.source.MediaSource
import androidx.media3.exoplayer.source.MergingMediaSource
import androidx.media3.exoplayer.source.ProgressiveMediaSource
import io.flutter.view.TextureRegistry
import java.io.File

/**
 * Process-wide player. Lives outside the Activity so playback (and the Dart isolate kept alive
 * by the cached FlutterEngine) survives the app being minimised or swiped away while
 * [CarroPlaybackService] holds the foreground.
 */
@OptIn(UnstableApi::class)
object CarroPlayerCore {
    private val main = Handler(Looper.getMainLooper())
    private var appContext: Context? = null
    private var exo: ExoPlayer? = null
    private var sessionPlayer: QueueAwarePlayer? = null

    /** Events for Dart (set by the plugin, called on the main thread). */
    var emit: ((Map<String, Any?>) -> Unit)? = null

    var hasNext = false
    var resumeOnBluetooth = true
    private var pausedByNoisy = false
    private var ended = false
    private var loading = false
    private var isLocal = false
    private var withVideo = false
    private var surfaceProducer: TextureRegistry.SurfaceProducer? = null
    private var videoEnabled = true
    private var lastState: String = "idle"
    private var browsable: List<MediaItem> = emptyList()

    private val ticker = object : Runnable {
        override fun run() {
            sendState()
            if (exo?.isPlaying == true || loading) main.postDelayed(this, 250) else main.postDelayed(this, 1000)
        }
    }

    fun player(context: Context): ExoPlayer {
        exo?.let { return it }
        val ctx = context.applicationContext
        appContext = ctx
        val renderers = object : DefaultRenderersFactory(ctx) {
            override fun buildAudioSink(
                context: Context,
                enableFloatOutput: Boolean,
                enableAudioOutputPlaybackParams: Boolean,
            ): AudioSink =
                DefaultAudioSink.Builder(context)
                    .setAudioProcessors(arrayOf<AudioProcessor>(CarroAudioProcessor()))
                    .build()
        }
        val load = DefaultLoadControl.Builder()
            .setBufferDurationsMs(15_000, 60_000, 1_500, 3_000)
            .build()
        val p = ExoPlayer.Builder(ctx, renderers)
            .setLoadControl(load)
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(C.USAGE_MEDIA)
                    .setContentType(C.AUDIO_CONTENT_TYPE_MUSIC)
                    .build(),
                /* handleAudioFocus = */ true,
            )
            .setHandleAudioBecomingNoisy(true) // headphones unplugged / BT lost -> pause
            .setWakeMode(C.WAKE_MODE_NETWORK)
            .setSeekBackIncrementMs(10_000)
            .setSeekForwardIncrementMs(10_000)
            .build()
        p.addListener(listener)
        exo = p
        sessionPlayer = QueueAwarePlayer(p)
        registerDeviceCallback(ctx)
        main.post(ticker)
        return p
    }

    fun sessionPlayer(context: Context): Player {
        player(context)
        return sessionPlayer!!
    }

    // ------------------------------------------------------------------------------------
    // Loading
    // ------------------------------------------------------------------------------------
    private fun dataSourceFactory(ctx: Context, headers: Map<String, String>): DefaultDataSource.Factory {
        val http = DefaultHttpDataSource.Factory()
            .setAllowCrossProtocolRedirects(true)
            .setConnectTimeoutMs(15_000)
            .setReadTimeoutMs(20_000)
        headers["User-Agent"]?.let { http.setUserAgent(it) }
        val rest = headers.filterKeys { it != "User-Agent" }
        if (rest.isNotEmpty()) http.setDefaultRequestProperties(rest)
        return DefaultDataSource.Factory(ctx, http)
    }

    private fun uriOf(s: String): Uri =
        if (isLocal || s.startsWith("/")) Uri.fromFile(File(s)) else Uri.parse(s)

    /** Returns the Flutter texture id when video is rendered. */
    fun load(context: Context, textures: TextureRegistry?, args: Map<*, *>): Long? {
        val p = player(context)
        val audioUrl = args["audioUrl"] as? String ?: ""
        val videoUrl = args["videoUrl"] as? String
        val muxedUrl = args["muxedUrl"] as? String
        @Suppress("UNCHECKED_CAST")
        val headers = (args["headers"] as? Map<String, String>) ?: emptyMap()
        isLocal = args["isLocalFile"] as? Boolean ?: false
        val wantVideo = (args["video"] as? Boolean ?: false) && (videoUrl != null || muxedUrl != null)
        val startMs = (args["startMs"] as? Number)?.toLong() ?: 0L
        val playWhenReady = args["playWhenReady"] as? Boolean ?: true

        val metadata = MediaMetadata.Builder()
            .setTitle(args["title"] as? String)
            .setArtist(args["artist"] as? String)
            .setDisplayTitle(args["title"] as? String)
            .setArtworkUri((args["artworkUrl"] as? String)?.let { Uri.parse(it) })
            .setIsPlayable(true)
            .setIsBrowsable(false)
            .setMediaType(if (wantVideo) MediaMetadata.MEDIA_TYPE_VIDEO else MediaMetadata.MEDIA_TYPE_MUSIC)
            .build()
        val id = args["id"] as? String ?: audioUrl
        val factory = ProgressiveMediaSource.Factory(dataSourceFactory(context, headers))

        fun item(url: String) = MediaItem.Builder().setMediaId(id).setUri(uriOf(url)).setMediaMetadata(metadata).build()

        val source: MediaSource = when {
            wantVideo && videoUrl != null -> MergingMediaSource(
                /* adjustPeriodTimeOffsets = */ true,
                /* clipDurations = */ true,
                factory.createMediaSource(item(videoUrl)),
                factory.createMediaSource(item(audioUrl)),
            )
            wantVideo && muxedUrl != null -> factory.createMediaSource(item(muxedUrl))
            else -> factory.createMediaSource(item(audioUrl))
        }

        releaseSurface(p)
        withVideo = wantVideo
        var textureId: Long? = null
        if (wantVideo && textures != null) {
            val producer = textures.createSurfaceProducer()
            producer.setCallback(object : TextureRegistry.SurfaceProducer.Callback {
                override fun onSurfaceAvailable() {
                    exo?.setVideoSurface(producer.surface)
                }

                override fun onSurfaceCleanup() {
                    exo?.clearVideoSurface()
                }
            })
            surfaceProducer = producer
            p.setVideoSurface(producer.surface)
            textureId = producer.id()
        }
        applyVideoEnabled(p)

        ended = false
        loading = true
        p.setMediaSource(source, startMs)
        p.prepare()
        p.playWhenReady = playWhenReady
        main.removeCallbacks(ticker)
        main.post(ticker)
        sendState()
        return textureId
    }

    private fun releaseSurface(p: ExoPlayer) {
        p.clearVideoSurface()
        surfaceProducer?.release()
        surfaceProducer = null
    }

    fun play(context: Context) {
        val p = player(context)
        if (p.playbackState == Player.STATE_ENDED) p.seekTo(0)
        p.play()
    }

    fun pause() {
        exo?.pause()
    }

    fun seek(ms: Long) {
        ended = false
        exo?.seekTo(ms.coerceAtLeast(0))
    }

    fun setRate(rate: Float) {
        exo?.playbackParameters = PlaybackParameters(rate.coerceIn(0.25f, 2f))
    }

    fun stop() {
        exo?.let {
            it.stop()
            it.clearMediaItems()
            releaseSurface(it)
        }
        withVideo = false
        loading = false
        ended = false
        sendState()
    }

    /** Background without PiP: stop decoding video, keep the audio running. */
    fun setVideoEnabled(enabled: Boolean) {
        videoEnabled = enabled
        exo?.let { applyVideoEnabled(it) }
    }

    private fun applyVideoEnabled(p: ExoPlayer) {
        p.trackSelectionParameters = p.trackSelectionParameters.buildUpon()
            .setTrackTypeDisabled(C.TRACK_TYPE_VIDEO, !(withVideo && videoEnabled))
            .build()
    }

    fun setBrowsable(items: List<Map<*, *>>) {
        browsable = items.mapNotNull { m ->
            val id = m["id"] as? String ?: return@mapNotNull null
            MediaItem.Builder()
                .setMediaId(id)
                .setMediaMetadata(
                    MediaMetadata.Builder()
                        .setTitle(m["title"] as? String)
                        .setArtist(m["artist"] as? String)
                        .setArtworkUri((m["artworkUrl"] as? String)?.let { Uri.parse(it) })
                        .setIsPlayable(true)
                        .setIsBrowsable(false)
                        .setMediaType(MediaMetadata.MEDIA_TYPE_MUSIC)
                        .build(),
                )
                .build()
        }
    }

    fun browsableItems(): List<MediaItem> = browsable

    // ------------------------------------------------------------------------------------
    // Events
    // ------------------------------------------------------------------------------------
    private val listener = object : Player.Listener {
        override fun onPlaybackStateChanged(playbackState: Int) {
            if (playbackState == Player.STATE_READY || playbackState == Player.STATE_ENDED) loading = false
            if (playbackState == Player.STATE_ENDED) ended = true
            sendState()
        }

        override fun onIsPlayingChanged(isPlaying: Boolean) {
            if (isPlaying) pausedByNoisy = false
            sendState()
            main.removeCallbacks(ticker)
            main.post(ticker)
        }

        override fun onPlayWhenReadyChanged(playWhenReady: Boolean, reason: Int) {
            if (!playWhenReady && reason == Player.PLAY_WHEN_READY_CHANGE_REASON_AUDIO_BECOMING_NOISY) {
                pausedByNoisy = true
                emit?.invoke(mapOf("type" to "route", "reason" to "unplugged"))
            }
            if (reason == Player.PLAY_WHEN_READY_CHANGE_REASON_AUDIO_FOCUS_LOSS) {
                emit?.invoke(mapOf("type" to "interruption", "began" to !playWhenReady, "shouldResume" to playWhenReady))
            }
            sendState()
        }

        override fun onPlayerError(error: PlaybackException) {
            loading = false
            var status = 0
            var cause: Throwable? = error.cause
            while (cause != null) {
                if (cause is HttpDataSource.InvalidResponseCodeException) {
                    status = cause.responseCode
                    break
                }
                cause = cause.cause
            }
            emit?.invoke(
                mapOf(
                    "type" to "error",
                    "code" to if (isLocal) "file" else if (status != 0) "http" else "source",
                    "message" to (error.message ?: error.errorCodeName),
                    "httpStatus" to status,
                ),
            )
            sendState()
        }

        override fun onVideoSizeChanged(videoSize: VideoSize) {
            if (videoSize.width <= 0 || videoSize.height <= 0) return
            val w = (videoSize.width * videoSize.pixelWidthHeightRatio).toInt()
            surfaceProducer?.setSize(videoSize.width, videoSize.height)
            emit?.invoke(
                mapOf(
                    "type" to "video",
                    "width" to w,
                    "height" to videoSize.height,
                    "textureId" to surfaceProducer?.id(),
                ),
            )
        }
    }

    fun sendState() {
        val p = exo ?: run {
            emit?.invoke(mapOf("type" to "state", "state" to "idle", "playing" to false))
            return
        }
        val state = when {
            ended || p.playbackState == Player.STATE_ENDED -> "ended"
            p.playerError != null -> "error"
            p.playbackState == Player.STATE_BUFFERING -> if (loading) "loading" else "buffering"
            p.playbackState == Player.STATE_READY -> "ready"
            loading -> "loading"
            else -> "idle"
        }
        lastState = state
        val duration = if (p.duration == C.TIME_UNSET) 0L else p.duration
        emit?.invoke(
            mapOf(
                "type" to "state",
                "state" to state,
                "playing" to (p.playWhenReady && p.playbackState != Player.STATE_ENDED && p.playbackState != Player.STATE_IDLE),
                "positionMs" to p.currentPosition,
                "durationMs" to duration,
                "bufferedMs" to p.bufferedPosition,
                "rate" to p.playbackParameters.speed.toDouble(),
            ),
        )
    }

    fun emitRemote(command: String, extra: Map<String, Any?> = emptyMap()) {
        main.post { emit?.invoke(mapOf("type" to "remote", "command" to command) + extra) }
    }

    // ------------------------------------------------------------------------------------
    // Bluetooth / car reconnect -> resume
    // ------------------------------------------------------------------------------------
    private fun registerDeviceCallback(ctx: Context) {
        val am = ctx.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        am.registerAudioDeviceCallback(object : AudioDeviceCallback() {
            override fun onAudioDevicesAdded(addedDevices: Array<out AudioDeviceInfo>) {
                val carOrBt = addedDevices.any {
                    it.isSink && (it.type == AudioDeviceInfo.TYPE_BLUETOOTH_A2DP ||
                        it.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO ||
                        it.type == AudioDeviceInfo.TYPE_USB_DEVICE ||
                        it.type == AudioDeviceInfo.TYPE_AUX_LINE)
                }
                if (carOrBt) {
                    emit?.invoke(mapOf("type" to "route", "reason" to "connected"))
                    if (resumeOnBluetooth && pausedByNoisy && exo?.mediaItemCount ?: 0 > 0) {
                        pausedByNoisy = false
                        // Give the Bluetooth link a moment to settle before audio starts.
                        main.postDelayed({ exo?.play() }, 1500)
                    }
                }
            }
        }, main)
    }
}

/**
 * The player exposed to the MediaSession (notification, lock screen, Bluetooth/steering
 * wheel buttons, Android Auto). Next/previous are forwarded to the Dart queue; "play this
 * item" requests from Android Auto become remote commands too.
 */
@OptIn(UnstableApi::class)
class QueueAwarePlayer(player: ExoPlayer) : ForwardingPlayer(player) {
    override fun getAvailableCommands(): Player.Commands =
        super.getAvailableCommands().buildUpon()
            .addAll(
                Player.COMMAND_SEEK_TO_NEXT,
                Player.COMMAND_SEEK_TO_NEXT_MEDIA_ITEM,
                Player.COMMAND_SEEK_TO_PREVIOUS,
                Player.COMMAND_SEEK_TO_PREVIOUS_MEDIA_ITEM,
            )
            .build()

    override fun isCommandAvailable(command: Int): Boolean = when (command) {
        Player.COMMAND_SEEK_TO_NEXT, Player.COMMAND_SEEK_TO_NEXT_MEDIA_ITEM,
        Player.COMMAND_SEEK_TO_PREVIOUS, Player.COMMAND_SEEK_TO_PREVIOUS_MEDIA_ITEM -> true
        else -> super.isCommandAvailable(command)
    }

    override fun hasNextMediaItem(): Boolean = true
    override fun hasPreviousMediaItem(): Boolean = true
    override fun seekToNext() = CarroPlayerCore.emitRemote("next")
    override fun seekToNextMediaItem() = CarroPlayerCore.emitRemote("next")
    override fun seekToPrevious() {
        if (currentPosition > 3_000) seekTo(0) else CarroPlayerCore.emitRemote("previous")
    }

    override fun seekToPreviousMediaItem() = CarroPlayerCore.emitRemote("previous")


    // Android Auto / assistant "play X": hand the id to Dart, which resolves the stream.
    override fun setMediaItems(mediaItems: MutableList<MediaItem>, startIndex: Int, startPositionMs: Long) {
        mediaItems.getOrNull(startIndex.coerceAtLeast(0))?.let {
            CarroPlayerCore.emitRemote("playId", mapOf("id" to it.mediaId))
        }
    }

    override fun setMediaItems(mediaItems: MutableList<MediaItem>, resetPosition: Boolean) {
        mediaItems.firstOrNull()?.let { CarroPlayerCore.emitRemote("playId", mapOf("id" to it.mediaId)) }
    }

    override fun setMediaItem(mediaItem: MediaItem) {
        CarroPlayerCore.emitRemote("playId", mapOf("id" to mediaItem.mediaId))
    }

    override fun stop() {
        super.stop()
        CarroPlayerCore.emitRemote("stop")
    }

}
