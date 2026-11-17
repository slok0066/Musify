package com.musify.musify

import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMuxer
import android.os.Build
import android.os.Handler
import android.os.Looper
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.nio.ByteBuffer
import java.util.concurrent.Executors

/**
 * CRITICAL: extends [AudioServiceActivity], never a plain FlutterActivity.
 *
 * Using FlutterActivity with audio_service causes a fatal crash / blank screen
 * on Android launch because the media notification and foreground service
 * lifecycle cannot bind to the engine.
 */
class MainActivity : AudioServiceActivity() {
    private val remuxExecutor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.musify.musify/canvas_remux",
        ).setMethodCallHandler { call, result ->
            if (call.method != "remuxToMp4") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val inputPath = call.argument<String>("inputPath")
            val outputPath = call.argument<String>("outputPath")
            val maxDurationMs = call.argument<Int>("maxDurationMs") ?: 16000
            if (inputPath.isNullOrEmpty() || outputPath.isNullOrEmpty()) {
                result.success(false)
                return@setMethodCallHandler
            }
            remuxExecutor.execute {
                val ok = remuxVideoToMp4(inputPath, outputPath, maxDurationMs.toLong() * 1000L)
                mainHandler.post { result.success(ok) }
            }
        }
    }

    override fun onDestroy() {
        remuxExecutor.shutdownNow()
        super.onDestroy()
    }

    /**
     * Losslessly remuxes a raw YouTube DASH fMP4 clip into a standard
     * non-fragmented MP4 (with clean moov/stbl sample table and t=0 timestamps)
     * so ExoPlayer loops it with zero stuttering or buffering stalls.
     */
    private fun remuxVideoToMp4(
        inputPath: String,
        outputPath: String,
        maxDurationUs: Long,
    ): Boolean {
        val outFile = File(outputPath)
        val tmpFile = File("$outputPath.tmp")
        var probe: MediaExtractor? = null
        var extractor: MediaExtractor? = null
        var muxer: MediaMuxer? = null
        var muxerStarted = false
        var writtenFrames = 0

        try {
            // Pass 1: find video track and minimum PTS (prevents negative PTS on B-frames).
            probe = MediaExtractor()
            probe.setDataSource(inputPath)
            var videoTrack = -1
            var format: MediaFormat? = null
            for (i in 0 until probe.trackCount) {
                val f = probe.getTrackFormat(i)
                val mime = f.getString(MediaFormat.KEY_MIME) ?: continue
                if (mime.startsWith("video/")) {
                    videoTrack = i
                    format = f
                    break
                }
            }
            if (videoTrack < 0 || format == null) return false

            probe.selectTrack(videoTrack)
            var seenSync = false
            var minPtsUs = Long.MAX_VALUE
            while (true) {
                val t = probe.sampleTime
                if (t < 0) break
                val isSync = (probe.sampleFlags and MediaExtractor.SAMPLE_FLAG_SYNC) != 0
                if (!seenSync) {
                    if (!isSync) {
                        if (!probe.advance()) break
                        continue
                    }
                    seenSync = true
                }
                if (t < minPtsUs) minPtsUs = t
                if (!probe.advance()) break
            }
            probe.release()
            probe = null
            if (!seenSync || minPtsUs == Long.MAX_VALUE) return false

            // Pass 2: copy compressed H.264 frames into a clean standard MP4 container.
            extractor = MediaExtractor()
            extractor.setDataSource(inputPath)
            extractor.selectTrack(videoTrack)

            outFile.parentFile?.mkdirs()
            if (tmpFile.exists()) tmpFile.delete()

            muxer = MediaMuxer(tmpFile.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            if (format.containsKey(MediaFormat.KEY_ROTATION)) {
                muxer.setOrientationHint(format.getInteger(MediaFormat.KEY_ROTATION))
            }
            val dstTrack = muxer.addTrack(format)
            muxer.start()
            muxerStarted = true

            val initialCap = if (format.containsKey(MediaFormat.KEY_MAX_INPUT_SIZE)) {
                maxOf(format.getInteger(MediaFormat.KEY_MAX_INPUT_SIZE), 2 * 1024 * 1024)
            } else {
                2 * 1024 * 1024
            }
            var buffer = ByteBuffer.allocate(initialCap)
            val info = MediaCodec.BufferInfo()
            var started = false

            while (true) {
                val rawPts = extractor.sampleTime
                if (rawPts < 0) break
                val isSync = (extractor.sampleFlags and MediaExtractor.SAMPLE_FLAG_SYNC) != 0
                if (!started) {
                    if (!isSync) {
                        if (!extractor.advance()) break
                        continue
                    }
                    started = true
                }

                val pts = maxOf(0L, rawPts - minPtsUs)
                // Stop cleanly on a keyframe boundary once past maxDurationUs.
                if (maxDurationUs > 0 && writtenFrames > 0 && isSync && pts >= maxDurationUs) {
                    break
                }

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                    val needed = extractor.sampleSize
                    if (needed > buffer.capacity() && needed <= 8 * 1024 * 1024) {
                        buffer = ByteBuffer.allocate(needed.toInt())
                    }
                }

                var sampleSize: Int
                try {
                    sampleSize = extractor.readSampleData(buffer, 0)
                } catch (_: IllegalArgumentException) {
                    if (buffer.capacity() >= 8 * 1024 * 1024) break
                    buffer = ByteBuffer.allocate(minOf(buffer.capacity() * 2, 8 * 1024 * 1024))
                    sampleSize = extractor.readSampleData(buffer, 0)
                }
                if (sampleSize < 0) break

                info.offset = 0
                info.size = sampleSize
                info.presentationTimeUs = pts
                info.flags = if (isSync) MediaCodec.BUFFER_FLAG_KEY_FRAME else 0
                muxer.writeSampleData(dstTrack, buffer, info)
                writtenFrames++

                if (!extractor.advance()) break
            }

            if (writtenFrames < 10) return false
            muxer.stop()
            muxerStarted = false
            muxer.release()
            muxer = null

            if (outFile.exists()) outFile.delete()
            return tmpFile.renameTo(outFile)
        } catch (_: Throwable) {
            return false
        } finally {
            try { probe?.release() } catch (_: Throwable) {}
            try { extractor?.release() } catch (_: Throwable) {}
            if (muxer != null) {
                if (muxerStarted && writtenFrames > 0) {
                    try { muxer.stop() } catch (_: Throwable) {}
                }
                try { muxer.release() } catch (_: Throwable) {}
            }
            if (tmpFile.exists()) {
                try { tmpFile.delete() } catch (_: Throwable) {}
            }
        }
    }
}
