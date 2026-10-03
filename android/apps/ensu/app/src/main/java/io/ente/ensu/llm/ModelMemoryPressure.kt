package io.ente.ensu.llm

import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

internal class ModelMemoryPressure(private val elapsedRealtime: () -> Long) {
    private var requestedGeneration = 0L
    private var releasedGeneration = 0L
    private var retryAfter = 0L

    @Synchronized
    fun requestEviction() {
        requestedGeneration++
        retryAfter = elapsedRealtime() + COOLDOWN_MILLIS
    }

    @Synchronized
    fun suppressesOptionalWork(): Boolean =
        requestedGeneration != releasedGeneration || elapsedRealtime() < retryAfter

    @Synchronized
    fun pendingEviction(): Long? = requestedGeneration.takeIf { it != releasedGeneration }

    @Synchronized
    fun didRelease(generation: Long) {
        releasedGeneration = maxOf(releasedGeneration, generation)
    }

    private companion object {
        const val COOLDOWN_MILLIS = 30_000L
    }
}

internal suspend fun <T> withModelResources(
    mutex: Mutex,
    releaseIfNeeded: () -> Unit,
    block: suspend () -> T,
): T = mutex.withLock {
    releaseIfNeeded()
    try {
        block()
    } finally {
        releaseIfNeeded()
    }
}
