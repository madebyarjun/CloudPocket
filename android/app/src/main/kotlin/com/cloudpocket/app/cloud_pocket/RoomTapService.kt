package com.cloudpocket.app.cloud_pocket

import android.nfc.cardemulation.HostApduService
import android.os.Bundle

class RoomTapService : HostApduService() {
    companion object {
        val select = byteArrayOf(0, -92, 4, 0, 7, -16, 67, 80, 82, 79, 79, 77, 0)
        val ok = byteArrayOf(-112, 0)
        @Volatile var invite: ByteArray? = null
        @Volatile var delivered: (() -> Unit)? = null
    }
    override fun processCommandApdu(command: ByteArray, extras: Bundle?): ByteArray {
        val data = invite ?: return byteArrayOf(0x69, -123)
        if (command.contentEquals(select)) return byteArrayOf((data.size shr 8).toByte(), data.size.toByte()) + ok
        if (command.contentEquals(byteArrayOf(-128, 1, 0, 0))) {
            delivered?.invoke()
            return ok
        }
        if (command.size != 5 || command[0] != 0.toByte() || command[1] != (-80).toByte()) return byteArrayOf(0x6d, 0)
        val offset = ((command[2].toInt() and 255) shl 8) or (command[3].toInt() and 255)
        val count = command[4].toInt() and 255
        if (count == 0 || offset + count > data.size) return byteArrayOf(0x6b, 0)
        return data.copyOfRange(offset, offset + count) + ok
    }
    override fun onDeactivated(reason: Int) {}
}
