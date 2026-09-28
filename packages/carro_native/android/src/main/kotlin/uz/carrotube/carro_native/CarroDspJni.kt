package uz.carrotube.carro_native

import java.nio.ByteBuffer

/** JNI entry points of libcarro_dsp.so (the same library dart:ffi opens). */
object CarroDspJni {
    init {
        System.loadLibrary("carro_dsp")
    }

    external fun version(): String

    /** Allocates / resets the engine for a sample rate (never on the audio render thread). */
    external fun prepare(sampleRate: Double, maxFrames: Int)

    /**
     * Runs [frames] of 1- or 2-channel PCM from [input] (direct buffer, byte offset [inOffset])
     * through the DSP and writes interleaved stereo 16-bit PCM to [output] at [outOffset].
     */
    external fun process(
        input: ByteBuffer,
        inOffset: Int,
        inputIsFloat: Boolean,
        inChannels: Int,
        frames: Int,
        output: ByteBuffer,
        outOffset: Int,
    )

    external fun sweep(frames: Int, sampleRate: Double, f1: Double, f2: Double, amplitude: Float): FloatArray

    external fun writeWav(path: String, interleaved: FloatArray, channels: Int, sampleRate: Int): Boolean
}
