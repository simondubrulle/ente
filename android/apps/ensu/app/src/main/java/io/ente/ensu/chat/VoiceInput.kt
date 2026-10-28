package io.ente.ensu.chat

import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.ApplicationInfo
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.MediaRecorder
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import io.ente.ensu.assets.AssetStore
import io.ente.ensu.bindings.DictationException
import io.ente.ensu.bindings.DictationFeedResult
import io.ente.ensu.bindings.DictationInsertion
import io.ente.ensu.bindings.DictationPhase
import io.ente.ensu.bindings.DictationSession
import io.ente.ensu.bindings.DictationSnapshot
import io.ente.ensu.bindings.DictationStopReason
import io.ente.ensu.bindings.DictationStream
import io.ente.ensu.bindings.DictationStreamCallback
import io.ente.ensu.bindings.transcriptionModelAsset
import io.ente.ensu.bindings.voiceActivityModelAsset
import io.ente.ensu.device.AndroidDeviceCapabilityProvider
import io.ente.ensu.device.supportsLiveVoice
import io.ente.ensu.llm.LlmProvider
import io.ente.ensu.logging.FileLogRepository
import io.ente.ensu.logging.LogLevel
import java.io.IOException
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.log10
import kotlin.math.sqrt
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.cancel
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

internal sealed interface VoiceInputState {
    data object Idle : VoiceInputState

    data object Preparing : VoiceInputState

    data object Recording : VoiceInputState

    data class Downloading(val percent: Int?) : VoiceInputState

    data object Transcribing : VoiceInputState

    data class Error(val message: String) : VoiceInputState
}

internal val VoiceInputState.isRecording: Boolean
    get() = this is VoiceInputState.Recording

internal class VoiceTranscriptionController(
    context: Context,
    private val assetStore: AssetStore,
    private val llmProvider: LlmProvider,
    private val logRepository: FileLogRepository,
    private val onVoiceInputJob: (Job) -> Unit,
    private val onInsert: (DictationInsertion, String) -> Boolean,
) {
    private val diagnosticsEnabled =
        context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0

    private fun diagnostic(event: String) {
        if (diagnosticsEnabled) {
            logRepository.log(LogLevel.Info, event, tag = "EnsuVoice")
        }
    }

    private val audioManager = context.getSystemService(AudioManager::class.java)
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val usesLiveDictation =
        supportsLiveVoice(
            AndroidDeviceCapabilityProvider(context).chatCapability().totalMemoryBytes
        )
    private val modelAssets =
        listOf(
            transcriptionModelAsset(),
            voiceActivityModelAsset(),
        )
    private var session: DictationSession? = null
    private var stream: DictationStream? = null
    private var capture: LiveMicrophone? = null
    private var work: Job? = null
    private var finishingNoticeJob: Job? = null
    private var attemptFinished = false
    private var insertion: DictationInsertion? = null
    private var foreground = true
    private var generation = 0L
    val sessionVersion: Long
        get() = generation

    private var initialRecordPending = false
    private var awaitingPermission = false
    private var startOnForeground = false

    var active by mutableStateOf(false)
        private set

    var state: VoiceInputState by mutableStateOf(VoiceInputState.Idle)
        private set

    var isFinishingSlow by mutableStateOf(false)
        private set

    var snapshot: DictationSnapshot? by mutableStateOf(null)
        private set

    private var notice: String? = null

    var audioLevels: List<Float> by mutableStateOf(List(24) { 0f })
        private set

    var composerCaret: Int? by mutableStateOf(null)

    var hasActiveWork by mutableStateOf(false)
        private set

    val canOpen: Boolean
        get() = !active && !hasActiveWork

    fun open(insertion: DictationInsertion) {
        if (!canOpen) return
        generation++
        initialRecordPending = true
        attemptFinished = false
        isFinishingSlow = false
        this.insertion = insertion
        session = DictationSession(live = usesLiveDictation)
        snapshot = session?.snapshot()
        notice = null
        audioLevels = List(24) { 0f }
        active = true
        state = VoiceInputState.Idle
    }

    fun composerPreview(original: String): io.ente.ensu.bindings.DictationInsertionResult? {
        val value = snapshot ?: return null
        if (!active) return null
        return runCatching { insertion?.preview(original, value.text + value.hypothesis) }
            .getOrNull()
    }

    fun takeInitialRecord(): Boolean = initialRecordPending.also { initialRecordPending = false }

    fun permissionRequested() {
        awaitingPermission = true
    }

    fun permissionResult(granted: Boolean) {
        awaitingPermission = false
        if (granted) {
            if (foreground) record() else startOnForeground = true
        } else {
            discard()
            state =
                VoiceInputState.Error("Microphone permission is required. Enable it in Settings.")
        }
    }

    fun setForeground(active: Boolean) {
        foreground = active
        if (active) {
            if (startOnForeground) {
                startOnForeground = false
                record()
            } else session?.let { refresh(it, generation) }
        } else if (!awaitingPermission && !startOnForeground) interrupt()
    }

    fun record() {
        val owner = session ?: return
        if (!active || !foreground || hasActiveWork || attemptFinished) return
        notice = null
        state = VoiceInputState.Preparing
        val token = generation
        hasActiveWork = true
        work =
            scope
                .launch {
                    var ownedCapture: LiveMicrophone? = null
                    var ownedStream: DictationStream? = null
                    try {
                        if (
                            !withContext(Dispatchers.IO) {
                                modelAssets.all { assetStore.isDownloaded(it) }
                            }
                        ) {
                            state = VoiceInputState.Downloading(null)
                            assetStore.download(modelAssets) { progress ->
                                scope.launch {
                                    if (token == generation && state is VoiceInputState.Downloading)
                                        state =
                                            VoiceInputState.Downloading(progress.percentage.toInt())
                                }
                            }
                        }
                        if (token != generation || !foreground) return@launch
                        state = VoiceInputState.Preparing
                        val activeStream = DictationStream(owner, 16000u, 1u)
                        stream = activeStream
                        ownedStream = activeStream
                        val microphone =
                            LiveMicrophone(
                                activeStream,
                                audioManager,
                                onLevel = { level ->
                                    scope.launch {
                                        if (token == generation && state.isRecording)
                                            audioLevels = audioLevels.drop(1) + level
                                    }
                                },
                            ) {
                                scope.launch {
                                    if (token == generation)
                                        interrupt(
                                            "Microphone interrupted. Review the text before continuing."
                                        )
                                }
                            }
                        capture = microphone
                        ownedCapture = microphone
                        coroutineScope {
                            val hardwareReady = async(Dispatchers.IO) { microphone.prepare() }
                            val callback =
                                object : DictationStreamCallback {
                                    override fun onReady() {
                                        scope.launch {
                                            try {
                                                hardwareReady.await()
                                                val value = owner.snapshot()
                                                if (
                                                    token != generation ||
                                                        !foreground ||
                                                        !active ||
                                                        stream !== activeStream ||
                                                        !value.workerActive ||
                                                        value.phase != DictationPhase.LISTENING
                                                )
                                                    return@launch
                                                microphone.start(scope)
                                                state = VoiceInputState.Recording
                                                audioLevels = List(24) { 0f }
                                                notice = null
                                                refresh(owner, token)
                                            } catch (_: Exception) {
                                                if (token == generation)
                                                    interrupt(
                                                        "Could not start the microphone. Tap the microphone to start again."
                                                    )
                                            }
                                        }
                                    }

                                    override fun onChange() {
                                        scope.launch { refresh(owner, token) }
                                    }

                                    override fun onCaptureClosed() {
                                        microphone.stop()
                                        scope.launch {
                                            watchFinalization(owner, activeStream, token)
                                        }
                                    }
                                }
                            llmProvider.runLiveVoice(activeStream, callback)
                        }
                    } catch (error: CancellationException) {
                        throw error
                    } catch (error: Exception) {
                        ownedStream?.let { runCatching { it.abandon(DictationStopReason.FAILURE) } }
                        diagnostic(
                            if (error is DictationException.InvalidOperation)
                                "failure ${error.detail}"
                            else "failure ${error.javaClass.simpleName}"
                        )
                        if (token == generation && notice == null) {
                            notice = "Voice input stopped. Review the available text or try again."
                        }
                    } finally {
                        withContext(NonCancellable) { ownedCapture?.stopAndDrain() }
                        hasActiveWork = false
                        if (token == generation) {
                            finishingNoticeJob?.cancel()
                            finishingNoticeJob = null
                            capture = null
                            stream = null
                            attemptFinished = true
                            refresh(owner, token)
                        }
                    }
                }
                .also(onVoiceInputJob)
    }

    private fun refresh(owner: DictationSession, token: Long) {
        if (token != generation || !active) return
        val value = owner.snapshot()
        snapshot = value
        if (!attemptFinished) {
            if (value.phase == DictationPhase.FINISHING) state = VoiceInputState.Transcribing
            return
        }
        if (!foreground) return
        val text = value.text + value.hypothesis
        val added = text.isNotBlank() && insertion?.let { onInsert(it, text) } == true
        val completedState =
            when {
                added && !value.incomplete -> VoiceInputState.Idle
                text.isBlank() -> VoiceInputState.Error(notice ?: "No speech detected.")
                else -> VoiceInputState.Error("Voice input stopped.")
            }
        active = false
        isFinishingSlow = false
        snapshot = null
        session = null
        insertion = null
        audioLevels = List(24) { 0f }
        state = completedState
    }

    private fun watchFinalization(
        owner: DictationSession,
        finishingStream: DictationStream,
        token: Long,
    ) {
        if (
            token != generation ||
                !active ||
                stream !== finishingStream ||
                !owner.snapshot().workerActive ||
                finishingNoticeJob != null
        )
            return
        finishingNoticeJob = scope.launch {
            delay(10_000)
            if (
                token != generation ||
                    !active ||
                    stream !== finishingStream ||
                    !owner.snapshot().workerActive
            )
                return@launch
            isFinishingSlow = true
        }
    }

    fun stop() {
        val reason = DictationStopReason.DONE
        runCatching { session?.stop(reason) }
        snapshot = session?.snapshot()
        if (snapshot?.workerActive != true) return
        state = VoiceInputState.Transcribing
        audioLevels = List(24) { 0f }
        val active = stream
        val microphone = capture
        if (active != null) session?.let { watchFinalization(it, active, generation) }
        scope.launch {
            microphone?.stopAndDrain()
            runCatching { active?.stop(reason) }
        }
    }

    fun interrupt(message: String = "Voice input stopped.") {
        if (!active || attemptFinished) return
        if (!hasActiveWork && stream == null) {
            discard()
            return
        }
        capture?.stop()
        runCatching { stream?.abandon(DictationStopReason.INTERRUPTION) }
        work?.cancel()
        finishingNoticeJob?.cancel()
        isFinishingSlow = false
        notice = message
        state = VoiceInputState.Transcribing
    }

    fun discard() {
        awaitingPermission = false
        startOnForeground = false
        generation++
        finishingNoticeJob?.cancel()
        finishingNoticeJob = null
        capture?.stop()
        runCatching { stream?.abandon(DictationStopReason.DISCARD) }
        work?.cancel()
        active = false
        isFinishingSlow = false
        state = VoiceInputState.Idle
        snapshot = null
        session = null
        insertion = null
        stream = null
        capture = null
    }

    fun dispose() {
        discard()
        scope.cancel()
    }
}

private class LiveMicrophone(
    private val stream: DictationStream,
    private val audioManager: AudioManager,
    private val onLevel: (Float) -> Unit,
    private val onInterrupted: () -> Unit,
) {
    private val stopped = AtomicBoolean(false)
    @Volatile private var recorder: AudioRecord? = null
    private var readJob: Job? = null

    @SuppressLint("MissingPermission")
    fun prepare() {
        if (stopped.get() || recorder != null) return
        val minimum =
            AudioRecord.getMinBufferSize(
                16000,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
            )
        if (minimum <= 0) throw IOException("Microphone format unavailable")
        val active =
            AudioRecord.Builder()
                .setAudioSource(MediaRecorder.AudioSource.VOICE_RECOGNITION)
                .setAudioFormat(
                    AudioFormat.Builder()
                        .setSampleRate(16000)
                        .setChannelMask(AudioFormat.CHANNEL_IN_MONO)
                        .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                        .build()
                )
                .setBufferSizeInBytes(maxOf(minimum * 2, 6400))
                .build()
        if (active.state != AudioRecord.STATE_INITIALIZED) {
            active.release()
            throw IOException("Microphone unavailable")
        }
        recorder = active
    }

    @SuppressLint("MissingPermission")
    fun start(scope: CoroutineScope) {
        if (stopped.get()) return
        val active = recorder ?: return
        try {
            active.startRecording()
            if (active.recordingState != AudioRecord.RECORDSTATE_RECORDING)
                throw IOException("Microphone did not start")
        } catch (error: Exception) {
            active.release()
            recorder = null
            throw error
        }
        var routedDevice = active.routedDevice?.id
        readJob =
            scope.launch(Dispatchers.IO) {
                val buffer = ByteBuffer.allocateDirect(3200).order(ByteOrder.LITTLE_ENDIAN)
                try {
                    captureMicrophoneAudio(
                        isStopped = stopped::get,
                        read = {
                            buffer.clear()
                            active.read(buffer, buffer.capacity(), AudioRecord.READ_BLOCKING)
                        },
                        isInterrupted = {
                            audioManager.isMicrophoneMute ||
                                (android.os.Build.VERSION.SDK_INT >= 29 &&
                                    active.activeRecordingConfiguration?.isClientSilenced ==
                                        true) ||
                                (routedDevice != null && active.routedDevice?.id != routedDevice)
                        },
                    ) { read ->
                        routedDevice = active.routedDevice?.id
                        buffer.position(0)
                        buffer.limit(read)
                        var energy = 0.0
                        for (index in 0 until read / 2) {
                            val sample = buffer.getShort(index * 2).toDouble() / 32768.0
                            energy += sample * sample
                        }
                        val rms = sqrt(energy / (read / 2).coerceAtLeast(1))
                        onLevel(
                            ((20 * log10(rms.coerceAtLeast(0.00001)) + 55) / 45)
                                .toFloat()
                                .coerceIn(0f, 1f)
                        )
                        stream.feed(buffer) == DictationFeedResult.ACCEPTED
                    }
                } catch (_: Exception) {
                    if (!stopped.get()) {
                        runCatching { stream.abandon(DictationStopReason.FAILURE) }
                        onInterrupted()
                    }
                } finally {
                    stop()
                    active.release()
                    recorder = null
                }
            }
    }

    suspend fun stopAndDrain() {
        stop()
        readJob?.join()
        // A reader canceled before dispatch never enters its cleanup block.
        recorder?.release()
        recorder = null
    }

    fun stop() {
        if (stopped.compareAndSet(false, true)) runCatching { recorder?.stop() }
    }
}
