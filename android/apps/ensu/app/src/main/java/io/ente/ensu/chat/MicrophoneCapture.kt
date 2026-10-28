package io.ente.ensu.chat

import java.io.IOException

internal fun captureMicrophoneAudio(
    isStopped: () -> Boolean,
    read: () -> Int,
    isInterrupted: () -> Boolean,
    deliver: (Int) -> Boolean,
) {
    while (!isStopped()) {
        val count = read()
        if (count <= 0) {
            if (isStopped()) return
            throw IOException("Microphone read failed")
        }
        // Stop changes the route too. Preserve a successful final read while draining.
        if (isInterrupted() && !isStopped()) throw IOException("Microphone interrupted")
        if (!deliver(count)) return
    }
}
