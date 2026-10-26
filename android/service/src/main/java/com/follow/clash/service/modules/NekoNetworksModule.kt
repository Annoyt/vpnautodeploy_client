package com.follow.clash.service.modules

import android.app.Service
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.VpnService
import android.os.Build
import androidx.core.content.getSystemService
import com.follow.clash.common.GlobalState
import com.follow.clash.core.Core
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.io.File
import java.util.concurrent.ConcurrentHashMap

/**
 * NekoVPN (client plan E37): Wi-Fi and mobile data at once, e.g. a second
 * phone's hotspot plus this phone's own SIM (docs/MULTIPATH.md, 3.1).
 *
 * While the VPN runs with a mode other than off, it keeps mobile data up
 * next to Wi-Fi and reports every network to the core, which binds each new
 * socket to one of them (core/neko_multipath.go). The mode is the app's
 * choice in Tools, kept in [NekoMultipath.FILE] in the app's files and read
 * again every few seconds, so a change applies without a reconnect.
 */
internal class NekoNetworksModule(
    private val service: Service,
    private val scope: CoroutineScope,
) : ServiceModule {
    private val connectivity by lazy { service.getSystemService<ConnectivityManager>() }
    private val networks = ConcurrentHashMap<Network, NetworkCapabilities>()
    private var poll: Job? = null
    private var cellularHeld = false

    @Volatile
    private var mode = NekoMultipath.OFF

    private val observer = object : ConnectivityManager.NetworkCallback() {
        override fun onCapabilitiesChanged(network: Network, capabilities: NetworkCapabilities) {
            networks[network] = capabilities
            report()
        }

        override fun onLost(network: Network) {
            networks.remove(network)
            report()
        }
    }

    // Holding this request is what keeps mobile data up while Wi-Fi is on.
    private val cellular = object : ConnectivityManager.NetworkCallback() {}

    override fun start() {
        if (service !is VpnService) return
        val manager = connectivity ?: return
        runCatching { manager.registerNetworkCallback(NekoMultipath.observed(), observer) }
            .onFailure { error -> GlobalState.log("NekoVPN networks: $error") }
        poll = scope.launch {
            while (isActive) {
                val next = NekoMultipath.readMode(File(service.filesDir, NekoMultipath.FILE))
                if (next != mode) {
                    mode = next
                    holdCellular(next != NekoMultipath.OFF)
                    report()
                }
                delay(NekoMultipath.POLL_MILLIS)
            }
        }
    }

    override fun stop() {
        val vpn = service as? VpnService ?: return
        poll?.cancel()
        poll = null
        runCatching { connectivity?.unregisterNetworkCallback(observer) }
        holdCellular(false)
        networks.clear()
        mode = NekoMultipath.OFF
        runCatching { Core.nekoUpdateNetworks(NekoMultipath.report(NekoMultipath.OFF, emptyList())) }
        runCatching { vpn.setUnderlyingNetworks(null) }
    }

    @Synchronized
    private fun holdCellular(hold: Boolean) {
        val manager = connectivity ?: return
        if (hold == cellularHeld) return
        runCatching {
            if (hold) {
                manager.requestNetwork(NekoMultipath.cellular(), cellular)
            } else {
                manager.unregisterNetworkCallback(cellular)
            }
        }.onSuccess { cellularHeld = hold }
            .onFailure { error -> GlobalState.log("NekoVPN mobile data: $error") }
    }

    private fun report() {
        val current = mode
        val entries = networks.entries.map { (network, capabilities) ->
            NekoMultipath.Entry(
                handle = network.networkHandle,
                transport = NekoMultipath.transport(capabilities),
                validated = capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED),
            )
        }
        runCatching { Core.nekoUpdateNetworks(NekoMultipath.report(current, entries)) }
            .onFailure { error -> GlobalState.log("NekoVPN networks to the core: $error") }
        // The VPN tells the system which networks carry it: metering and
        // traffic accounting follow; null is "the default network".
        val vpn = service as? VpnService ?: return
        val underlying = if (current == NekoMultipath.OFF) null else networks.keys.toTypedArray()
        runCatching { vpn.setUnderlyingNetworks(underlying) }
    }
}

/** The module's pure part: the mode file and the report the core reads. */
internal object NekoMultipath {
    const val FILE = "neko_multipath.json"
    const val OFF = "off"
    const val POLL_MILLIS = 5_000L
    private val MODES = setOf(OFF, "failover", "distribute")
    private val MODE = Regex("\"mode\"\\s*:\\s*\"(\\w+)\"")

    data class Entry(val handle: Long, val transport: String, val validated: Boolean)

    /** The mode the app wrote; off for a missing or unreadable file. */
    fun readMode(file: File): String {
        val text = runCatching { file.readText() }.getOrNull() ?: return OFF
        val mode = MODE.find(text)?.groupValues?.get(1)
        return if (mode != null && mode in MODES) mode else OFF
    }

    /**
     * The JSON core/neko_multipath.go reads. Built by hand: a reflective
     * serializer would follow the field names R8 renames in a release build.
     */
    fun report(mode: String, entries: List<Entry>): String = buildString {
        append("{\"mode\":\"").append(if (mode in MODES) mode else OFF).append("\",\"networks\":[")
        entries.forEachIndexed { index, entry ->
            if (index > 0) append(',')
            append("{\"handle\":").append(entry.handle)
            append(",\"transport\":\"").append(entry.transport).append('"')
            append(",\"validated\":").append(entry.validated).append('}')
        }
        append("]}")
    }

    fun transport(capabilities: NetworkCapabilities): String = when {
        capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "wifi"
        capabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "ethernet"
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_USB) -> "usb"
        capabilities.hasTransport(NetworkCapabilities.TRANSPORT_BLUETOOTH) -> "bluetooth"
        capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "cellular"
        else -> "other"
    }

    fun observed(): NetworkRequest = NetworkRequest.Builder()
        .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
        .addCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)
        .build()

    fun cellular(): NetworkRequest = NetworkRequest.Builder()
        .addTransportType(NetworkCapabilities.TRANSPORT_CELLULAR)
        .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
        .build()
}
