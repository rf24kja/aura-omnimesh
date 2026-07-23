// android/app/src/main/kotlin/com/aura/omnimesh/PayloadFraming.kt
//
// Pure, unit-testable framing for the Nearby BYTES transport, extracted
// from NearbyTransportChannel so the wire contract can be tested off-device
// (JUnit) instead of relying on a physical two-phone run.
//
// Nearby caps a BYTES payload at ~32 KB (ConnectionsClient.MAX_BYTES_DATA_
// SIZE), so a UTF-8 payload is split into <= CHUNK_BYTES raw-byte frames:
//
//   frame = "AOM1|<msgId>|<index>|<total>|" (ASCII header) + <raw byte slice>
//
// Reassembly is BYTE-level: a multibyte UTF-8 character split across a chunk
// boundary MUST survive intact, or the reassembled payload differs from the
// signed original and fails Ed25519 verification (silently dropping large
// multilingual CRDT batches). '|' (0x7C) never occurs inside a multibyte
// UTF-8 sequence, so scanning for the 4 header pipes is byte-safe even when
// the slice itself contains '|'.

package com.aura.omnimesh

import java.util.UUID
import kotlin.text.Charsets.UTF_8

object PayloadFraming {
    const val CHUNK_BYTES = 24_000
    const val FRAME_MAGIC = "AOM1"

    /** Fresh 8-char message id for a new outbound payload. */
    fun newMsgId(): String = UUID.randomUUID().toString().substring(0, 8)

    /** Split [payload] into wire frames tagged with [msgId]. Always yields at
     *  least one frame — an empty payload becomes a single empty-slice frame
     *  that reassembles back to "". */
    fun frame(payload: String, msgId: String = newMsgId()): List<ByteArray> {
        val bytes = payload.toByteArray(UTF_8)
        val total = maxOf(1, (bytes.size + CHUNK_BYTES - 1) / CHUNK_BYTES)
        val frames = ArrayList<ByteArray>(total)
        for (index in 0 until total) {
            val from = index * CHUNK_BYTES
            val to = minOf(from + CHUNK_BYTES, bytes.size)
            val header = "$FRAME_MAGIC|$msgId|$index|$total|".toByteArray(UTF_8)
            frames.add(header + bytes.copyOfRange(from, to))
        }
        return frames
    }
}

/**
 * Stateful byte-level reassembler. [accept] returns the full payload string
 * on the frame that completes a message, else null. Malformed / hostile
 * frames are ignored; memory is bounded to [maxPending] in-flight messages
 * (oldest incomplete message evicted under flood).
 */
class PayloadReassembler(private val maxPending: Int = 64) {
    private val pending = LinkedHashMap<String, Array<ByteArray?>>()

    fun clear() = pending.clear()

    fun accept(frame: ByteArray): String? {
        val pipe = '|'.code.toByte()
        var pipes = 0
        var sliceStart = -1
        for (i in frame.indices) {
            if (frame[i] == pipe && ++pipes == 4) {
                sliceStart = i + 1
                break
            }
        }
        if (sliceStart < 0) return null
        val header = String(frame, 0, sliceStart, UTF_8).split('|')
        if (header.size < 4 || header[0] != PayloadFraming.FRAME_MAGIC) return null
        val msgId = header[1]
        val index = header[2].toIntOrNull() ?: return null
        val total = header[3].toIntOrNull() ?: return null
        if (total <= 0 || index !in 0 until total) return null

        val slots = pending.getOrPut(msgId) {
            if (pending.size >= maxPending) pending.remove(pending.keys.first())
            arrayOfNulls(total)
        }
        if (slots.size != total) {
            pending.remove(msgId)
            return null
        }
        slots[index] = frame.copyOfRange(sliceStart, frame.size)
        if (slots.any { it == null }) return null

        pending.remove(msgId)
        val full = ByteArray(slots.sumOf { it!!.size })
        var off = 0
        for (slice in slots) {
            slice!!.copyInto(full, off)
            off += slice.size
        }
        return String(full, UTF_8)
    }
}
