package io.ente.ensu.chat

import org.junit.Assert.assertEquals
import org.junit.Test

class MicrophoneCaptureTest {
    @Test
    fun stopBetweenReadAndRouteCheckDeliversTheFinalBufferOnce() {
        var stopped = false
        val delivered = mutableListOf<Int>()
        captureMicrophoneAudio(
            isStopped = { stopped },
            read = { 3200 },
            isInterrupted = {
                // AudioRecord.stop() clears the route after a successful read.
                stopped = true
                true
            },
        ) { count ->
            delivered.add(count)
            true
        }
        assertEquals(listOf(3200), delivered)
    }
}
