package io.ente.photos.media_extension

import android.content.ContentResolver
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.util.Base64
import android.util.Log
import java.io.IOException
import java.io.InputStream
import org.mockito.ArgumentMatchers.any
import org.mockito.ArgumentMatchers.anyInt
import org.mockito.ArgumentMatchers.eq
import org.mockito.Mockito.CALLS_REAL_METHODS
import org.mockito.Mockito.mock
import org.mockito.Mockito.mockStatic
import org.mockito.Mockito.`when`
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class MediaExtensionViewIntentTest {
    @Test
    fun encodesSmallImagesAndClosesTheStream() {
        val input = ImageStream(23)
        val result = resolveImage(input)

        assertEquals(
            java.util.Base64.getEncoder().encodeToString(ByteArray(23) { 42 }),
            result["data"]
        )
        assertEquals("VIEW", result["action"])
        assertEquals("image", result["type"])
        assertTrue(input.closed)
    }

    @Test
    fun acceptsImagesAtTheInlineLimit() {
        val input = ImageStream(inlineLimit)
        val result = resolveImage(input)

        val decoded = java.util.Base64.getDecoder().decode(result["data"] as String)
        assertEquals(inlineLimit, decoded.size.toLong())
        assertTrue(decoded.all { it == 42.toByte() })
        assertTrue(input.closed)
    }

    @Test
    fun rejectsImagesOneByteOverTheLimitWithoutEncoding() {
        val input = ImageStream(inlineLimit + 1)
        val result = resolveImage(input, expectEncoding = false)

        assertNull(result["data"])
        assertEquals("VIEW", result["action"])
        assertEquals("image", result["type"])
        assertTrue(input.closed)
    }

    @Test
    fun stopsAnEndlessStreamWithShortReadsAndClosesIt() {
        val input = ImageStream(Long.MAX_VALUE, chunkSize = 1023)
        val result = resolveImage(input, expectEncoding = false)

        assertNull(result["data"])
        assertTrue(input.bytesRead > inlineLimit)
        assertTrue(input.bytesRead <= inlineLimit + 1023)
        assertTrue(input.closed)
    }

    @Test
    fun ignoresProviderAvailableSizeWhenBoundingTheRead() {
        val input = ImageStream(inlineLimit + 1, availableBytes = Int.MAX_VALUE)
        val result = resolveImage(input, expectEncoding = false)

        assertNull(result["data"])
        assertTrue(input.closed)
    }

    @Test
    fun closesTheStreamAfterAReadFailure() {
        val input = ImageStream(23, failOnRead = true)
        val result = resolveImage(input, expectEncoding = false)

        assertNull(result["data"])
        assertEquals("VIEW", result["action"])
        assertTrue(input.closed)
    }

    @Test
    fun preservesEmptyImages() {
        val input = ImageStream(0)

        assertEquals("", resolveImage(input)["data"])
        assertTrue(input.closed)
    }

    @Test
    fun keepsMediaStoreImagesAsUrisWithoutReadingThem() {
        val input = ImageStream(Long.MAX_VALUE)
        val result = resolveImage(input, expectEncoding = false, authority = "media")

        assertEquals("content://media/image.jpg", result["data"])
        assertEquals(0, input.bytesRead)
    }

    @Test
    fun keepsVideosAsUrisWithoutReadingThem() {
        val input = ImageStream(Long.MAX_VALUE)
        val result = resolveImage(input, expectEncoding = false, contentType = "video/mp4")

        assertEquals("content://external.provider/image.jpg", result["data"])
        assertEquals(0, input.bytesRead)
    }

    private fun resolveImage(
        input: InputStream,
        expectEncoding: Boolean = true,
        authority: String = "external.provider",
        contentType: String = "image/jpeg"
    ): Map<*, *> {
        val uri = mock(Uri::class.java)
        `when`(uri.scheme).thenReturn("content")
        `when`(uri.host).thenReturn(authority)
        `when`(uri.lastPathSegment).thenReturn("image.jpg")
        `when`(uri.toString()).thenReturn("content://$authority/image.jpg")
        val resolver = mock(ContentResolver::class.java)
        `when`(resolver.openInputStream(uri)).thenReturn(input)
        val context = mock(Context::class.java)
        `when`(context.contentResolver).thenReturn(resolver)
        val intent = mock(Intent::class.java)
        `when`(intent.action).thenReturn(Intent.ACTION_VIEW)
        `when`(intent.data).thenReturn(uri)
        `when`(intent.type).thenReturn(contentType)
        val plugin = mock(MediaExtensionPlugin::class.java, CALLS_REAL_METHODS)
        MediaExtensionPlugin::class.java.getDeclaredField("context").apply {
            isAccessible = true
            set(plugin, context)
        }
        val method = MediaExtensionPlugin::class.java.getDeclaredMethod(
            "getIntentAction", Intent::class.java
        ).apply { isAccessible = true }
        mockStatic(Log::class.java).use {
            mockStatic(Base64::class.java).use { encoder ->
                encoder.`when`<String> {
                    Base64.encodeToString(any(), anyInt())
                }.thenAnswer {
                    java.util.Base64.getEncoder().encodeToString(it.getArgument(0))
                }
                val result = method.invoke(plugin, intent) as Map<*, *>
                if (expectEncoding) {
                    encoder.verify {
                        Base64.encodeToString(
                            any(), eq(Base64.DEFAULT)
                        )
                    }
                } else {
                    encoder.verifyNoInteractions()
                }
                return result
            }
        }
    }

    private class ImageStream(
        private val size: Long,
        private val chunkSize: Int = 8192,
        private val availableBytes: Int = 0,
        private val failOnRead: Boolean = false
    ) : InputStream() {
        var bytesRead = 0L
        var closed = false

        override fun available() = availableBytes

        override fun read(): Int = error("Expected buffered reads")

        override fun read(buffer: ByteArray, offset: Int, length: Int): Int {
            if (failOnRead) throw IOException("Provider read failed")
            check(bytesRead <= inlineLimit + 8192) { "Read exceeded test safety bound" }
            if (bytesRead == size) return -1
            val count = minOf(length.toLong(), chunkSize.toLong(), size - bytesRead).toInt()
            buffer.fill(42, offset, offset + count)
            bytesRead += count
            return count
        }

        override fun close() {
            closed = true
        }
    }

    private companion object {
        const val inlineLimit = 10L * 1024L * 1024L
    }
}
