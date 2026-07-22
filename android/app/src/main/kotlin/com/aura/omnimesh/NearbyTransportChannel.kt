// android/app/src/main/kotlin/com/aura/omnimesh/NearbyTransportChannel.kt
//
// Native side of:
//   MethodChannel("aura.omnimesh/transport")
//     startDiscovery{publicKey, alias} / stopDiscovery /
//     broadcastPayload{payload} / sendPayloadToPeer{peerPublicKey, payload}
//   EventChannel("aura.omnimesh/transport_events")
//     {type:"nodeState", node:{publicKey, alias}, state, rssi}
//     {type:"payloadReceived", payload}
//
// Radio: Google Nearby Connections, Strategy.P2P_CLUSTER (BLE + Wi-Fi
// hotspot/Direct under the hood, fully offline).
// build.gradle: implementation("com.google.android.gms:play-services-nearby:19.1.0")
//
// MTU strategy: Nearby BYTES payloads cap at ConnectionsClient
// MAX_BYTES_DATA_SIZE (~32 KB). CRDT batches with 384-dim vectors exceed
// that, so payloads are framed into <=24000-byte UTF-8 chunks:
//   "AOM1|<msgId>|<index>|<total>|<slice>"
// and reassembled per msgId. This satisfies the Dart-side contract that
// MTU chunking is the native layer's job.
//
// Double-connect prevention: both sides discover each other; only the
// lexicographically SMALLER public key requests the connection — one
// deterministic initiator, zero simultaneous-connect races.

package com.aura.omnimesh

import android.content.Context
import android.os.Handler
import android.os.Looper
import com.google.android.gms.nearby.Nearby
import com.google.android.gms.nearby.connection.AdvertisingOptions
import com.google.android.gms.nearby.connection.ConnectionInfo
import com.google.android.gms.nearby.connection.ConnectionLifecycleCallback
import com.google.android.gms.nearby.connection.ConnectionResolution
import com.google.android.gms.nearby.connection.ConnectionsClient
import com.google.android.gms.nearby.connection.DiscoveredEndpointInfo
import com.google.android.gms.nearby.connection.DiscoveryOptions
import com.google.android.gms.nearby.connection.EndpointDiscoveryCallback
import com.google.android.gms.nearby.connection.Payload
import com.google.android.gms.nearby.connection.PayloadCallback
import com.google.android.gms.nearby.connection.PayloadTransferUpdate
import com.google.android.gms.nearby.connection.Strategy
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.UUID
import kotlin.text.Charsets.UTF_8

class NearbyTransportChannel(context: Context) :
    MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    companion object {
        const val METHOD_NAME = "aura.omnimesh/transport"
        const val EVENT_NAME = "aura.omnimesh/transport_events"
        private const val SERVICE_ID = "aura-omnimesh"
        private const val CHUNK_BYTES = 24_000
        private const val FRAME_MAGIC = "AOM1"
        private const val MAX_PENDING_REASSEMBLIES = 64
    }

    private val client: ConnectionsClient = Nearby.getConnectionsClient(context)
    private val mainHandler = Handler(Looper.getMainLooper())

    private var eventSink: EventChannel.EventSink? = null
    private var selfKey: String = ""
    private var selfAlias: String = ""
    private var active = false

    /** endpointId <-> peer identity, both directions. */
    private val identityByEndpoint = HashMap<String, Pair<String, String>>()
    private val endpointByKey = HashMap<String, String>()
    private val connectedEndpoints = HashSet<String>()

    /** msgId -> raw byte slices per index. Reassembly is byte-level: a
     *  multibyte UTF-8 character split across a 24 KB chunk boundary must
     *  survive intact, or the reassembled payload differs from the signed
     *  original and fails Ed25519 verification. */
    private val reassembly = LinkedHashMap<String, Array<ByteArray?>>()

    // -----------------------------------------------------------------
    // Method channel
    // -----------------------------------------------------------------

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "startDiscovery" -> {
                    selfKey = call.argument<String>("publicKey") ?: ""
                    selfAlias = call.argument<String>("alias") ?: ""
                    if (selfKey.isEmpty()) {
                        result.error("BAD_ARGS", "publicKey required", null)
                        return
                    }
                    startRadios()
                    result.success(null)
                }

                "stopDiscovery" -> {
                    stopRadios()
                    result.success(null)
                }

                "broadcastPayload" -> {
                    val payload = call.argument<String>("payload")
                    if (payload == null) {
                        result.error("BAD_ARGS", "payload required", null)
                        return
                    }
                    if (connectedEndpoints.isEmpty()) {
                        result.error("NO_PEERS", "zero connected peers", null)
                        return
                    }
                    sendFramed(connectedEndpoints.toList(), payload)
                    result.success(null)
                }

                "sendPayloadToPeer" -> {
                    val key = call.argument<String>("peerPublicKey")
                    val payload = call.argument<String>("payload")
                    val endpoint = key?.let { endpointByKey[it] }
                    if (payload == null || endpoint == null ||
                        endpoint !in connectedEndpoints
                    ) {
                        result.error("PEER_UNREACHABLE", "peer not connected", null)
                        return
                    }
                    sendFramed(listOf(endpoint), payload)
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            // Radio-stack faults surface to Dart as PlatformException,
            // which the Dart layer maps to MeshUnreachableException.
            result.error("RADIO_FAULT", e.message, null)
        }
    }

    // -----------------------------------------------------------------
    // Event channel
    // -----------------------------------------------------------------

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    private fun emit(event: Map<String, Any?>) {
        // EventSink is main-thread-only; Nearby callbacks arrive elsewhere.
        mainHandler.post { eventSink?.success(event) }
    }

    private fun emitNodeState(endpointId: String, state: String) {
        val identity = identityByEndpoint[endpointId] ?: return
        emit(
            mapOf(
                "type" to "nodeState",
                "node" to mapOf(
                    "publicKey" to identity.first,
                    "alias" to identity.second,
                ),
                "state" to state,
                "rssi" to 0, // Nearby exposes no RSSI; 0 = link-quality n/a.
            )
        )
    }

    // -----------------------------------------------------------------
    // Radios
    // -----------------------------------------------------------------

    private fun startRadios() {
        if (active) return
        active = true
        val endpointName = "$selfKey|$selfAlias"
        client.startAdvertising(
            endpointName,
            SERVICE_ID,
            connectionLifecycle,
            AdvertisingOptions.Builder().setStrategy(Strategy.P2P_CLUSTER).build(),
        )
        client.startDiscovery(
            SERVICE_ID,
            endpointDiscovery,
            DiscoveryOptions.Builder().setStrategy(Strategy.P2P_CLUSTER).build(),
        )
    }

    private fun stopRadios() {
        if (!active) return
        active = false
        client.stopAdvertising()
        client.stopDiscovery()
        client.stopAllEndpoints()
        identityByEndpoint.clear()
        endpointByKey.clear()
        connectedEndpoints.clear()
        reassembly.clear()
    }

    private fun registerIdentity(endpointId: String, endpointName: String): Boolean {
        val separator = endpointName.indexOf('|')
        if (separator <= 0) return false
        val key = endpointName.substring(0, separator)
        val alias = endpointName.substring(separator + 1)
        identityByEndpoint[endpointId] = key to alias
        endpointByKey[key] = endpointId
        return true
    }

    private val endpointDiscovery = object : EndpointDiscoveryCallback() {
        override fun onEndpointFound(
            endpointId: String,
            info: DiscoveredEndpointInfo,
        ) {
            if (!registerIdentity(endpointId, info.endpointName)) return
            emitNodeState(endpointId, "discovered")
            val peerKey = identityByEndpoint[endpointId]!!.first
            // Deterministic initiator: smaller key dials.
            if (selfKey < peerKey) {
                emitNodeState(endpointId, "connecting")
                client.requestConnection(
                    "$selfKey|$selfAlias", endpointId, connectionLifecycle,
                )
            }
        }

        override fun onEndpointLost(endpointId: String) {
            emitNodeState(endpointId, "lost")
            forgetEndpoint(endpointId)
        }
    }

    private val connectionLifecycle = object : ConnectionLifecycleCallback() {
        override fun onConnectionInitiated(
            endpointId: String,
            info: ConnectionInfo,
        ) {
            registerIdentity(endpointId, info.endpointName)
            emitNodeState(endpointId, "connecting")
            // Transport-level accept. Trust is NOT granted here: peer
            // authenticity is established per-operation by Ed25519
            // signatures in the CRDT layer. The radio only moves bytes.
            client.acceptConnection(endpointId, payloadCallback)
        }

        override fun onConnectionResult(
            endpointId: String,
            resolution: ConnectionResolution,
        ) {
            if (resolution.status.isSuccess) {
                connectedEndpoints.add(endpointId)
                emitNodeState(endpointId, "connected")
            } else {
                emitNodeState(endpointId, "lost")
                forgetEndpoint(endpointId)
            }
        }

        override fun onDisconnected(endpointId: String) {
            emitNodeState(endpointId, "lost")
            forgetEndpoint(endpointId)
        }
    }

    private fun forgetEndpoint(endpointId: String) {
        connectedEndpoints.remove(endpointId)
        val identity = identityByEndpoint.remove(endpointId)
        if (identity != null) endpointByKey.remove(identity.first)
    }

    // -----------------------------------------------------------------
    // Framing (chunk + reassemble)
    // -----------------------------------------------------------------

    private fun sendFramed(endpoints: List<String>, payload: String) {
        val bytes = payload.toByteArray(UTF_8)
        val total = (bytes.size + CHUNK_BYTES - 1) / CHUNK_BYTES
        val msgId = UUID.randomUUID().toString().substring(0, 8)
        for (index in 0 until total) {
            val from = index * CHUNK_BYTES
            val to = minOf(from + CHUNK_BYTES, bytes.size)
            val header = "$FRAME_MAGIC|$msgId|$index|$total|".toByteArray(UTF_8)
            val frame = header + bytes.copyOfRange(from, to)
            for (endpoint in endpoints) {
                client.sendPayload(endpoint, Payload.fromBytes(frame))
            }
        }
    }

    private val payloadCallback = object : PayloadCallback() {
        override fun onPayloadReceived(endpointId: String, payload: Payload) {
            val bytes = payload.asBytes() ?: return
            // Locate the ASCII header "AOM1|msgId|index|total|" at the BYTE
            // level, then keep the slice as RAW BYTES. Decoding each chunk
            // as its own UTF-8 String (as the old code did) corrupts any
            // multibyte character split across a 24 KB boundary into U+FFFD —
            // and a single changed byte fails the CRDT Ed25519 signature,
            // silently dropping large multilingual batches. '|' (0x7C) never
            // occurs inside a multibyte UTF-8 sequence, so scanning for the
            // 4 header pipes is byte-safe even when the slice contains '|'.
            val pipe = '|'.code.toByte()
            var pipes = 0
            var sliceStart = -1
            for (i in bytes.indices) {
                if (bytes[i] == pipe && ++pipes == 4) {
                    sliceStart = i + 1
                    break
                }
            }
            if (sliceStart < 0) return
            val header = String(bytes, 0, sliceStart, UTF_8).split('|')
            if (header.size < 4 || header[0] != FRAME_MAGIC) return
            val msgId = header[1]
            val index = header[2].toIntOrNull() ?: return
            val total = header[3].toIntOrNull() ?: return
            if (total <= 0 || index !in 0 until total) return

            val slots = reassembly.getOrPut(msgId) {
                // Bounded reassembly memory: evict oldest incomplete
                // message when a hostile peer floods partial frames.
                if (reassembly.size >= MAX_PENDING_REASSEMBLIES) {
                    reassembly.remove(reassembly.keys.first())
                }
                arrayOfNulls(total)
            }
            if (slots.size != total) {
                reassembly.remove(msgId)
                return
            }
            slots[index] = bytes.copyOfRange(sliceStart, bytes.size)
            if (slots.all { it != null }) {
                reassembly.remove(msgId)
                val full = ByteArray(slots.sumOf { it!!.size })
                var off = 0
                for (slice in slots) {
                    slice!!.copyInto(full, off)
                    off += slice.size
                }
                emit(
                    mapOf(
                        "type" to "payloadReceived",
                        "payload" to String(full, UTF_8),
                    )
                )
            }
        }

        override fun onPayloadTransferUpdate(
            endpointId: String,
            update: PayloadTransferUpdate,
        ) {
            // BYTES payloads arrive atomically; per-chunk progress is noise.
        }
    }
}
