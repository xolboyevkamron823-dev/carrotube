package uz.carrotube.carro_native

import android.annotation.SuppressLint
import android.content.Context
import android.media.AudioAttributes
import android.media.AudioDeviceInfo
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.AudioTrack
import android.media.MediaRecorder
import android.os.Handler
import android.os.Looper
import java.io.File
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.abs
import kotlin.math.log10
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow

/**
 * Recording side of the IR capture wizard: plays the C++-generated exponential sweep on the
 * left/right/both channels and records the input (USB audio interface on the head unit's
 * RCA outputs is preferred, else the phone microphone, unprocessed when available).
 */
class CarroIrCapture(private val context: Context) {
    private val main = Handler(Looper.getMainLooper())
    private val cancel = AtomicBoolean(false)
    @Volatile private var running = false

    fun route(): Map<String, Any?> {
        val am = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val inputs = am.getDevices(AudioManager.GET_DEVICES_INPUTS)
        val outputs = am.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
        val usbIn = inputs.firstOrNull { isUsb(it) }
        val input = usbIn ?: inputs.firstOrNull { it.type == AudioDeviceInfo.TYPE_BUILTIN_MIC }
        val output = outputs.firstOrNull { isUsb(it) || it.type == AudioDeviceInfo.TYPE_BLUETOOTH_A2DP ||
            it.type == AudioDeviceInfo.TYPE_WIRED_HEADPHONES || it.type == AudioDeviceInfo.TYPE_WIRED_HEADSET }
            ?: outputs.firstOrNull { it.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER }
        return mapOf(
            "input" to (input?.productName?.toString() ?: "none"),
            "inputType" to (input?.let { typeName(it.type) } ?: "none"),
            "inputChannels" to (input?.channelCounts?.maxOrNull() ?: 1),
            "output" to (output?.productName?.toString() ?: "none"),
            "outputType" to (output?.let { typeName(it.type) } ?: "none"),
            "sampleRate" to outputRate(am).toDouble(),
            "availableInputs" to inputs.map { it.productName.toString() },
        )
    }

    private fun isUsb(d: AudioDeviceInfo) =
        d.type == AudioDeviceInfo.TYPE_USB_DEVICE || d.type == AudioDeviceInfo.TYPE_USB_HEADSET ||
            d.type == AudioDeviceInfo.TYPE_USB_ACCESSORY

    private fun typeName(t: Int) = when (t) {
        AudioDeviceInfo.TYPE_USB_DEVICE, AudioDeviceInfo.TYPE_USB_HEADSET, AudioDeviceInfo.TYPE_USB_ACCESSORY -> "usb"
        AudioDeviceInfo.TYPE_BUILTIN_MIC -> "builtInMic"
        AudioDeviceInfo.TYPE_BLUETOOTH_A2DP -> "bluetoothA2DP"
        AudioDeviceInfo.TYPE_BLUETOOTH_SCO -> "bluetoothHFP"
        AudioDeviceInfo.TYPE_WIRED_HEADSET -> "headsetMic"
        AudioDeviceInfo.TYPE_WIRED_HEADPHONES -> "headphones"
        AudioDeviceInfo.TYPE_BUILTIN_SPEAKER -> "speaker"
        else -> "other"
    }

    private fun outputRate(am: AudioManager): Int =
        am.getProperty(AudioManager.PROPERTY_OUTPUT_SAMPLE_RATE)?.toIntOrNull() ?: 48000

    fun cancel() {
        cancel.set(true)
    }

    @SuppressLint("MissingPermission")
    fun capture(args: Map<*, *>, done: (Result<Map<String, Any?>>) -> Unit) {
        if (running) {
            done(Result.failure(IllegalStateException("A capture is already running")))
            return
        }
        running = true
        cancel.set(false)
        val channel = (args["channel"] as? Number)?.toInt() ?: 2
        val sweepSeconds = (args["sweepSeconds"] as? Number)?.toDouble() ?: 10.0
        val f1 = (args["f1"] as? Number)?.toDouble() ?: 20.0
        val f2 = (args["f2"] as? Number)?.toDouble() ?: 20000.0
        val amplitudeDb = (args["amplitudeDb"] as? Number)?.toDouble() ?: -6.0
        val tailSeconds = (args["tailSeconds"] as? Number)?.toDouble() ?: 4.0

        Thread({
            val result = runCatching {
                val am = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
                val rate = outputRate(am)
                val lead = (0.5 * rate).toInt()
                val sweepFrames = (sweepSeconds * rate).toInt()
                val total = lead + sweepFrames + (tailSeconds * rate).toInt()
                val amp = 10.0.pow(amplitudeDb / 20.0).toFloat()
                val sweep = CarroDspJni.sweep(sweepFrames, rate.toDouble(), f1, f2, amp)
                val stimulus = FloatArray(total * 2)
                for (i in sweep.indices) {
                    if (channel == 0 || channel == 2) stimulus[(lead + i) * 2] = sweep[i]
                    if (channel == 1 || channel == 2) stimulus[(lead + i) * 2 + 1] = sweep[i]
                }

                // --- recorder (prefer the USB interface, stereo if it has 2+ channels) ---
                val inputs = am.getDevices(AudioManager.GET_DEVICES_INPUTS)
                val usb = inputs.firstOrNull { isUsb(it) }
                val stereoIn = (usb?.channelCounts?.maxOrNull() ?: 1) >= 2
                val inChannels = if (stereoIn) 2 else 1
                val inMask = if (stereoIn) AudioFormat.CHANNEL_IN_STEREO else AudioFormat.CHANNEL_IN_MONO
                val unprocessed = am.getProperty(AudioManager.PROPERTY_SUPPORT_AUDIO_SOURCE_UNPROCESSED) == "true"
                val source = if (unprocessed) MediaRecorder.AudioSource.UNPROCESSED
                else MediaRecorder.AudioSource.VOICE_RECOGNITION
                val minRec = AudioRecord.getMinBufferSize(rate, inMask, AudioFormat.ENCODING_PCM_FLOAT)
                val record = AudioRecord.Builder()
                    .setAudioSource(source)
                    .setAudioFormat(
                        AudioFormat.Builder()
                            .setEncoding(AudioFormat.ENCODING_PCM_FLOAT)
                            .setSampleRate(rate)
                            .setChannelMask(inMask)
                            .build(),
                    )
                    .setBufferSizeInBytes(max(minRec * 4, rate * inChannels * 4 / 2))
                    .build()
                if (usb != null) record.setPreferredDevice(usb)
                check(record.state == AudioRecord.STATE_INITIALIZED) { "Audio input could not be opened" }

                // --- player ---
                val track = AudioTrack.Builder()
                    .setAudioAttributes(
                        AudioAttributes.Builder()
                            .setUsage(AudioAttributes.USAGE_MEDIA)
                            .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                            .build(),
                    )
                    .setAudioFormat(
                        AudioFormat.Builder()
                            .setEncoding(AudioFormat.ENCODING_PCM_FLOAT)
                            .setSampleRate(rate)
                            .setChannelMask(AudioFormat.CHANNEL_OUT_STEREO)
                            .build(),
                    )
                    .setTransferMode(AudioTrack.MODE_STREAM)
                    .setBufferSizeInBytes(
                        max(AudioTrack.getMinBufferSize(rate, AudioFormat.CHANNEL_OUT_STEREO, AudioFormat.ENCODING_PCM_FLOAT) * 2, 16384),
                    )
                    .build()
                usb?.let { dev ->
                    am.getDevices(AudioManager.GET_DEVICES_OUTPUTS).firstOrNull { isUsb(it) && it.productName == dev.productName }
                        ?.let { track.setPreferredDevice(it) }
                }

                val recFrames = total + rate // one extra second for output latency
                val recorded = FloatArray(recFrames * inChannels)
                var recPos = 0
                record.startRecording()
                track.play()
                // Writer thread feeds the stimulus while this thread records.
                val writer = Thread {
                    var off = 0
                    val chunk = 2048 * 2
                    while (off < stimulus.size && !cancel.get()) {
                        val n = min(chunk, stimulus.size - off)
                        val w = track.write(stimulus, off, n, AudioTrack.WRITE_BLOCKING)
                        if (w <= 0) break
                        off += w
                    }
                }
                writer.start()
                val buf = FloatArray(4096 * inChannels)
                while (recPos < recorded.size && !cancel.get()) {
                    val n = record.read(buf, 0, min(buf.size, recorded.size - recPos), AudioRecord.READ_BLOCKING)
                    if (n <= 0) break
                    System.arraycopy(buf, 0, recorded, recPos, n)
                    recPos += n
                }
                writer.join(2000)
                track.stop()
                track.release()
                record.stop()
                record.release()
                check(!cancel.get()) { "Capture canceled" }

                var peak = 0f
                for (i in 0 until recPos) peak = max(peak, abs(recorded[i]))
                val file = File(context.cacheDir, "carro_capture_${System.currentTimeMillis()}.wav")
                val data = if (recPos == recorded.size) recorded else recorded.copyOf(recPos)
                check(CarroDspJni.writeWav(file.absolutePath, data, inChannels, rate)) { "Could not write the recording" }
                mapOf(
                    "path" to file.absolutePath,
                    "sampleRate" to rate.toDouble(),
                    "inputSampleRate" to rate.toDouble(),
                    "channels" to inChannels,
                    "peakDb" to if (peak > 0) 20.0 * log10(peak.toDouble()) else -120.0,
                )
            }
            running = false
            main.post { done(result) }
        }, "carro-ir-capture").start()
    }
}
