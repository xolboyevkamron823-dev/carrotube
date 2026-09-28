package uz.carrotube.carro_native

import androidx.annotation.OptIn
import androidx.media3.common.C
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.audio.BaseAudioProcessor
import androidx.media3.common.util.UnstableApi
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * ExoPlayer [AudioProcessor] that runs every decoded sample (audio-only and video playback,
 * foreground and background) through the Carrozzeria DSP chain.
 *
 * Input: mono/stereo 16-bit or float PCM. Output: stereo 16-bit PCM (the engine's true-peak
 * limiter keeps the signal below -1 dBTP, so 16-bit output never clips and stays compatible
 * with ExoPlayer's speed/pitch processor that follows in the chain).
 */
@OptIn(UnstableApi::class)
class CarroAudioProcessor : BaseAudioProcessor() {
    private var inputIsFloat = false
    private var inChannels = 2
    private var staging: ByteBuffer = ByteBuffer.allocateDirect(0).order(ByteOrder.nativeOrder())

    override fun onConfigure(inputAudioFormat: AudioProcessor.AudioFormat): AudioProcessor.AudioFormat {
        val enc = inputAudioFormat.encoding
        if ((enc != C.ENCODING_PCM_16BIT && enc != C.ENCODING_PCM_FLOAT) ||
            inputAudioFormat.channelCount !in 1..2
        ) {
            // Multichannel / exotic formats pass through untouched.
            return AudioProcessor.AudioFormat.NOT_SET
        }
        inputIsFloat = enc == C.ENCODING_PCM_FLOAT
        inChannels = inputAudioFormat.channelCount
        CarroDspJni.prepare(inputAudioFormat.sampleRate.toDouble(), 8192)
        return AudioProcessor.AudioFormat(inputAudioFormat.sampleRate, 2, C.ENCODING_PCM_16BIT)
    }

    override fun queueInput(inputBuffer: ByteBuffer) {
        val bytesPerFrame = inChannels * if (inputIsFloat) 4 else 2
        val frames = inputBuffer.remaining() / bytesPerFrame
        if (frames == 0) {
            inputBuffer.position(inputBuffer.limit())
            return
        }
        val out = replaceOutputBuffer(frames * 2 * 2)
        val src: ByteBuffer
        val srcOffset: Int
        if (inputBuffer.isDirect) {
            src = inputBuffer
            srcOffset = inputBuffer.position()
        } else {
            // Heap buffers (software decoders) are copied to a reusable direct buffer.
            val needed = frames * bytesPerFrame
            if (staging.capacity() < needed) {
                staging = ByteBuffer.allocateDirect(needed * 2).order(ByteOrder.nativeOrder())
            }
            staging.clear()
            val dup = inputBuffer.duplicate()
            dup.limit(dup.position() + needed)
            staging.put(dup)
            src = staging
            srcOffset = 0
        }
        CarroDspJni.process(src, srcOffset, inputIsFloat, inChannels, frames, out, out.position())
        inputBuffer.position(inputBuffer.position() + frames * bytesPerFrame)
        out.position(out.position() + frames * 4)
        out.flip()
    }
}
