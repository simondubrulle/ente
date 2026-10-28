package io.ente.ensu.device

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class ChatDeviceCapabilityTest {
    @Test
    fun liveVoiceRequiresMoreThanFourGiB() {
        val limit = 4L * 1024 * 1024 * 1024
        for (bytes in listOf(null, -1L, 0L, 4_000_000_000L, limit)) {
            assertFalse(supportsLiveVoice(bytes))
        }
        for (bytes in listOf(limit + 1, 8_000_000_000L)) assertTrue(supportsLiveVoice(bytes))
    }

    @Test
    fun minimumRamBlocksOnlyKnownReadingsBelowTheFloor() {
        val belowMinimum = chatDeviceCapability(1_599_999_999L)
        assertFalse(belowMinimum.isChatSupported())
        assertThrows(UnsupportedDeviceMemoryException::class.java) {
            belowMinimum.requireChatSupported()
        }
        val atMinimum = chatDeviceCapability(1_600_000_000L)
        assertTrue(atMinimum.isChatSupported())
        atMinimum.requireChatSupported()
        for (bytes in listOf(0L, -1L)) {
            val capability = chatDeviceCapability(bytes)
            assertEquals(ChatDeviceCapability.Unknown, capability)
            assertTrue(capability.isChatSupported())
            capability.requireChatSupported()
        }
    }
}
