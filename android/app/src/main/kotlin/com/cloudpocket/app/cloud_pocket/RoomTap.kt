package com.cloudpocket.app.cloud_pocket

import android.app.Activity
import android.content.ComponentName
import android.content.pm.PackageManager
import android.nfc.NfcAdapter
import android.nfc.cardemulation.CardEmulation
import android.nfc.tech.IsoDep
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

class RoomTap(private val activity: Activity) {
    private val adapter get() = NfcAdapter.getDefaultAdapter(activity)
    private var pending: MethodChannel.Result? = null
    private var hosting = false

    fun handle(method: String, invite: String?, result: MethodChannel.Result) {
        val nfc = adapter
        if (method == "stop") { stop(); result.success(null); return }
        val host = method == "host" || method == "canHost"
        val supported = nfc != null && (!host || activity.packageManager.hasSystemFeature(PackageManager.FEATURE_NFC_HOST_CARD_EMULATION))
        if (method == "canHost" || method == "canRead") { result.success(supported); return }
        if (!supported || nfc == null || !nfc.isEnabled) { result.error("unavailable", "Turn on NFC or use the room QR code.", null); return }
        stop()
        pending = result
        hosting = host
        try {
            if (host) {
                val data = requireNotNull(invite).toByteArray(Charsets.UTF_8)
                require(data.size in 1..4096)
                check(CardEmulation.getInstance(nfc).setPreferredService(activity, ComponentName(activity, RoomTapService::class.java)))
                RoomTapService.delivered = { activity.runOnUiThread { if (pending === result) finish("") } }
                RoomTapService.invite = data
            } else {
                nfc.enableReaderMode(activity, { tag ->
                    try {
                        val value = IsoDep.get(tag)?.use { link ->
                            link.connect()
                            fun exchange(command: ByteArray): ByteArray {
                                val response = link.transceive(command)
                                require(response.size >= 2 && response.takeLast(2) == RoomTapService.ok.toList())
                                return response.copyOf(response.size - 2)
                            }
                            val size = exchange(RoomTapService.select)
                            require(size.size == 2)
                            val length = ((size[0].toInt() and 255) shl 8) or (size[1].toInt() and 255)
                            require(length in 1..4096)
                            val bytes = ByteArrayOutputStream()
                            while (bytes.size() < length) {
                                val offset = bytes.size()
                                val count = minOf(192, length - offset)
                                val chunk = exchange(byteArrayOf(0, -80, (offset shr 8).toByte(), offset.toByte(), count.toByte()))
                                require(chunk.size == count)
                                bytes.write(chunk)
                            }
                            exchange(byteArrayOf(-128, 1, 0, 0))
                            bytes.toString("UTF-8")
                        }
                        if (value != null) activity.runOnUiThread { if (pending === result) finish(value) }
                    } catch (_: Exception) { /* A broken tap can be retried while the sheet is open. */ }
                }, NfcAdapter.FLAG_READER_NFC_A or NfcAdapter.FLAG_READER_SKIP_NDEF_CHECK, null)
            }
        } catch (_: Exception) { pending = null; stop(); result.error("unavailable", "NFC is unavailable. Use the room QR code.", null) }
    }
    private fun finish(value: String?) {
        val result = pending
        pending = null
        RoomTapService.invite = null
        RoomTapService.delivered = null
        try {
            val nfc = adapter
            if (nfc != null && hosting) CardEmulation.getInstance(nfc).unsetPreferredService(activity)
            else if (nfc != null && result != null) nfc.disableReaderMode(activity)
        } catch (_: RuntimeException) {}
        hosting = false
        result?.success(value)
    }
    fun stop() = finish(null)
}
