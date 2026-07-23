// Off-device (JUnit) verification of the Nearby transport wire framing —
// the chunk/reassemble contract that only otherwise runs on a physical
// two-phone link. Locks AUDIT FINDING #5: a multibyte UTF-8 character split
// across a 24 KB chunk boundary must reassemble byte-for-byte, or the
// payload fails its CRDT Ed25519 signature and is silently dropped.

package com.aura.omnimesh

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class PayloadFramingTest {

    /** Frame [payload], feed the frames (in [order]) to a fresh reassembler,
     *  and return whatever it reassembled. */
    private fun roundTrip(
        payload: String,
        order: (List<ByteArray>) -> List<ByteArray> = { it },
    ): String? {
        val frames = PayloadFraming.frame(payload, "testmsg1")
        val r = PayloadReassembler()
        var out: String? = null
        for (f in order(frames)) out = r.accept(f) ?: out
        return out
    }

    @Test
    fun asciiAcrossManyChunks() {
        val p = "a".repeat(PayloadFraming.CHUNK_BYTES * 3 + 17)
        assertEquals(p, roundTrip(p))
    }

    @Test
    fun singleSmallPayload() {
        val p = "offer: guitar lessons — нужна помощь с переездом 日本語"
        val frames = PayloadFraming.frame(p)
        assertEquals(1, frames.size)
        assertEquals(p, roundTrip(p))
    }

    @Test
    fun emptyPayloadRoundTripsToEmpty() {
        val frames = PayloadFraming.frame("")
        assertEquals(1, frames.size)
        assertEquals("", roundTrip(""))
    }

    @Test
    fun multibyteCharSplitAcrossBoundarySurvives() {
        // Place a 2-byte Cyrillic 'Я' (0xD0 0xAF) exactly on the 24000-byte
        // boundary: lead byte ends chunk 0, continuation byte starts chunk 1.
        // The old per-chunk String() decode turned this into two U+FFFD.
        val p = "a".repeat(PayloadFraming.CHUNK_BYTES - 1) + "Я" + "b".repeat(10)
        val result = roundTrip(p)
        assertEquals(p, result)
        assertTrue(result!!.contains("Я"))
        assertTrue(!result.contains("�"))
    }

    @Test
    fun mixedMultilingualAcrossChunks() {
        val unit = "Дart→Флаттер offer 日本語 need 한국어 · "
        val p = unit.repeat(4000) // hundreds of KB, many chunk boundaries
        assertEquals(p, roundTrip(p))
    }

    @Test
    fun outOfOrderChunksReassemble() {
        val p = "Ю".repeat(40_000) // 2-byte chars, > 3 chunks
        assertEquals(p, roundTrip(p) { it.reversed() })
    }

    @Test
    fun malformedFramesAreIgnored() {
        val r = PayloadReassembler()
        assertNull(r.accept("not a frame".toByteArray()))
        assertNull(r.accept("AOM1|m|0|".toByteArray()))        // too few pipes
        assertNull(r.accept("XXXX|m|0|1|hi".toByteArray()))    // wrong magic
        assertNull(r.accept("AOM1|m|x|1|hi".toByteArray()))    // bad index
    }

    @Test
    fun interleavedMessagesDoNotCrossContaminate() {
        val a = "α".repeat(30_000)
        val b = "β".repeat(30_000)
        val fa = PayloadFraming.frame(a, "aaaa")
        val fb = PayloadFraming.frame(b, "bbbb")
        val r = PayloadReassembler()
        var ra: String? = null
        var rb: String? = null
        // Interleave the two messages' frames.
        val max = maxOf(fa.size, fb.size)
        for (i in 0 until max) {
            if (i < fa.size) ra = r.accept(fa[i]) ?: ra
            if (i < fb.size) rb = r.accept(fb[i]) ?: rb
        }
        assertEquals(a, ra)
        assertEquals(b, rb)
    }
}
