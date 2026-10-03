package io.ente.ensu.device

import org.junit.Assert.assertEquals
import org.junit.Test

class ModelMemoryHeadroomTest {
    @Test
    fun profileReserveRespectsPlatformAndProcessLimits() {
        assertEquals(
            1500uL,
            modelMemoryHeadroomBytes(12000, 2000, 200, 200, optionalReserveCapBytes = 500),
        )
        assertEquals(
            0uL,
            modelMemoryHeadroomBytes(12000, 400, 200, 200, optionalReserveCapBytes = 500),
        )
        assertEquals(
            1200uL,
            modelMemoryHeadroomBytes(12000, 2000, 800, 200, optionalReserveCapBytes = 500),
        )
        assertEquals(
            100uL,
            modelMemoryHeadroomBytes(12000, 2000, 200, 5900, optionalReserveCapBytes = 500),
        )
    }

    @Test
    fun systemPressureLimitsAnOtherwiseSmallProcess() {
        assertEquals(100uL, modelMemoryHeadroomBytes(4000, 500, 100, 100))
        assertEquals(0uL, modelMemoryHeadroomBytes(4000, 300, 100, 100))
        assertEquals(100uL, modelMemoryHeadroomBytes(4000, 800, 700, 100))
    }

    @Test
    fun nativeProcessFootprintLimitsAnOtherwiseIdleSystem() {
        assertEquals(200uL, modelMemoryHeadroomBytes(4000, 3500, 100, 1800))
        assertEquals(0uL, modelMemoryHeadroomBytes(4000, 3500, 100, 2100))
    }

    @Test
    fun requiredWorkPreservesPlatformAndProcessLimitsWithoutTheSpeculativeReserve() {
        assertEquals(400uL, modelMemoryHeadroomBytes(4000, 500, 100, 100, optionalWork = false))
        assertEquals(0uL, modelMemoryHeadroomBytes(4000, 90, 100, 100, optionalWork = false))
        assertEquals(200uL, modelMemoryHeadroomBytes(4000, 3500, 100, 1800, optionalWork = false))
    }
}
