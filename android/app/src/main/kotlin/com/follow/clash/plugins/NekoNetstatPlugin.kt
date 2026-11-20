package com.follow.clash.plugins

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationManager
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.telephony.CellIdentityNr
import android.telephony.CellInfo
import android.telephony.CellInfoGsm
import android.telephony.CellInfoLte
import android.telephony.CellInfoNr
import android.telephony.CellInfoTdscdma
import android.telephony.CellInfoWcdma
import android.telephony.CellSignalStrength
import android.telephony.CellSignalStrengthGsm
import android.telephony.CellSignalStrengthLte
import android.telephony.CellSignalStrengthNr
import android.telephony.CellSignalStrengthTdscdma
import android.telephony.CellSignalStrengthWcdma
import android.telephony.SignalStrength
import android.telephony.SubscriptionManager
import android.telephony.TelephonyManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.follow.clash.common.Components
import com.follow.clash.common.GlobalState
import com.follow.clash.common.PendingCallback
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

// NekoVPN (neko.6, C3), for lib/neko/netstat*.dart: every call answers, with
// nulls where Android says no, and nothing thrown off the main thread escapes.
class NekoNetstatPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware {
    private lateinit var context: Context
    private lateinit var channel: MethodChannel
    private var executor: ExecutorService? = null
    private var activityBinding: ActivityPluginBinding? = null
    private val main = Handler(Looper.getMainLooper())
    private val permission = PendingCallback<Boolean>()

    private val permissionListener =
        PluginRegistry.RequestPermissionsResultListener { requestCode, _, _ ->
            if (requestCode != REQUEST_CODE) return@RequestPermissionsResultListener false
            permission.resolve(hasFineLocation())
            true
        }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        executor = Executors.newCachedThreadPool()
        channel = MethodChannel(binding.binaryMessenger, "${Components.PACKAGE_NAME}/neko_netstat")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        executor?.shutdownNow()
        executor = null
        permission.resolve(false)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        detachFromActivity()
        activityBinding = binding
        binding.addRequestPermissionsResultListener(permissionListener)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        detachFromActivity()
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        onAttachedToActivity(binding)
    }

    override fun onDetachedFromActivity() {
        detachFromActivity()
        permission.resolve(false)
    }

    private fun detachFromActivity() {
        activityBinding?.removeRequestPermissionsResultListener(permissionListener)
        activityBinding = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "snapshot" -> inBackground(result) { snapshot(call.argument<Boolean>("cell") == true) }
            "probeRu" -> inBackground(result) { probeRu() }
            "hasLocation" -> result.success(hasFineLocation())
            "requestLocation" -> requestLocation { granted -> result.success(granted) }
            else -> result.notImplemented()
        }
    }

    private fun answer(result: MethodChannel.Result, value: Any?) {
        main.post { result.success(value) }
    }

    private fun inBackground(result: MethodChannel.Result, work: () -> Any?) {
        val pool = executor
        if (pool == null) {
            answer(result, null)
            return
        }
        try {
            pool.execute {
                val value = try {
                    work()
                } catch (error: Throwable) {
                    GlobalState.log("NekoVPN netstat: $error")
                    null
                }
                answer(result, value)
            }
        } catch (_: RuntimeException) {
            answer(result, null)
        }
    }

    private fun hasFineLocation(): Boolean = ContextCompat.checkSelfPermission(
        context,
        Manifest.permission.ACCESS_FINE_LOCATION,
    ) == PackageManager.PERMISSION_GRANTED

    // The dialog offers "while using the app" at most: background location
    // is never asked for.
    private fun requestLocation(done: (Boolean) -> Unit) {
        val activity = activityBinding?.activity
        if (activity == null || hasFineLocation()) {
            done(hasFineLocation())
            return
        }
        permission.replace(done, supersededValue = false)
        runCatching {
            ActivityCompat.requestPermissions(activity, LOCATION_PERMISSIONS, REQUEST_CODE)
        }.onFailure { permission.resolve(false) }
    }

    private fun snapshot(withCell: Boolean): Map<String, Any?>? {
        val connectivity = context.getSystemService(ConnectivityManager::class.java) ?: return null
        val (_, capabilities) = underlying(connectivity) ?: return null
        val net = netOf(capabilities)
        val telephony = dataTelephony()
        val (mcc, mnc) = NekoNetstat.operator(runCatching { telephony?.networkOperator }.getOrNull())
        val strength = signalStrength(telephony)
        val located = withCell && hasFineLocation()
        val serving = if (located) servingCell(telephony, mcc, mnc) else null
        val location = if (located) lastLocation() else null
        val level = when (net) {
            NekoNetstat.WIFI -> wifiLevel(capabilities)
            NekoNetstat.CELL -> NekoNetstat.signalLevel(
                runCatching { strength?.level }.getOrNull() ?: serving?.level,
            )
            else -> null
        }
        return NekoNetstat.snapshot(
            net = net,
            level = level,
            mcc = mcc,
            mnc = mnc,
            rat = serving?.rat ?: strengthRat(strength),
            cell = serving,
            lat = location?.latitude,
            lon = location?.longitude,
        )
    }

    // A HEAD outside the tunnel: a socket bound to the network under the VPN
    // skips it, as the core's own sockets do.
    private fun probeRu(): Boolean? {
        val connectivity = context.getSystemService(ConnectivityManager::class.java) ?: return null
        val (network, _) = underlying(connectivity) ?: return null
        return try {
            val connection = network.openConnection(URL(NekoNetstat.RU_URL)) as HttpURLConnection
            try {
                connection.requestMethod = "HEAD"
                connection.connectTimeout = NekoNetstat.PROBE_TIMEOUT_MILLIS
                connection.readTimeout = NekoNetstat.PROBE_TIMEOUT_MILLIS
                connection.instanceFollowRedirects = false
                connection.useCaches = false
                connection.responseCode > 0
            } finally {
                connection.disconnect()
            }
        } catch (_: IOException) {
            false
        }
    }

    // The app is inside its own VPN, so its active network is the VPN; the
    // VPN's capabilities name the transports it rides on.
    private fun underlying(connectivity: ConnectivityManager): Pair<Network, NetworkCapabilities>? {
        val vpn = connectivity.activeNetwork
            ?.let { runCatching { connectivity.getNetworkCapabilities(it) }.getOrNull() }
            ?.takeIf { it.hasTransport(NetworkCapabilities.TRANSPORT_VPN) }
        val carried = buildSet {
            if (vpn?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true) add(NekoNetstat.WIFI)
            if (vpn?.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) == true) add(NekoNetstat.CELL)
        }
        @Suppress("DEPRECATION")
        val networks = connectivity.allNetworks.mapNotNull { network ->
            runCatching { connectivity.getNetworkCapabilities(network) }.getOrNull()
                ?.takeIf {
                    it.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
                        it.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)
                }
                ?.let { network to it }
        }
        val candidates = networks.mapIndexed { index, (_, capabilities) ->
            NekoNetstat.Candidate(
                index = index,
                net = netOf(capabilities),
                validated = capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED),
            )
        }
        val picked = NekoNetstat.pick(candidates, carried) ?: return null
        return networks[picked.index]
    }

    private fun netOf(capabilities: NetworkCapabilities): String = NekoNetstat.net(
        wifi = capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI),
        cellular = capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR),
    )

    private fun wifiLevel(capabilities: NetworkCapabilities): Int? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            NekoNetstat.wifiLevel(capabilities.signalStrength)
        } else {
            null
        }

    private fun dataTelephony(): TelephonyManager? = runCatching {
        val telephony = context.getSystemService(TelephonyManager::class.java)
        val subscription = SubscriptionManager.getDefaultDataSubscriptionId()
        if (telephony == null || subscription == SubscriptionManager.INVALID_SUBSCRIPTION_ID) {
            telephony
        } else {
            telephony.createForSubscriptionId(subscription)
        }
    }.getOrNull()

    private fun signalStrength(telephony: TelephonyManager?): SignalStrength? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            runCatching { telephony?.signalStrength }.getOrNull()
        } else {
            null
        }

    private fun strengthRat(strength: SignalStrength?): String {
        if (strength == null || Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            return NekoNetstat.UNKNOWN
        }
        val rats = runCatching { strength.cellSignalStrengths.mapNotNull { ratOf(it) } }
            .getOrDefault(emptyList())
        return NekoNetstat.ratOf(rats)
    }

    private fun ratOf(strength: CellSignalStrength): String? = when (strength) {
        is CellSignalStrengthNr -> NekoNetstat.NR
        is CellSignalStrengthLte -> NekoNetstat.LTE
        is CellSignalStrengthWcdma, is CellSignalStrengthTdscdma -> NekoNetstat.UMTS
        is CellSignalStrengthGsm -> NekoNetstat.GSM
        else -> null
    }

    @SuppressLint("MissingPermission")
    private fun servingCell(
        telephony: TelephonyManager?,
        mcc: String?,
        mnc: String?,
    ): NekoNetstat.Cell? {
        val infos = runCatching { telephony?.allCellInfo }.getOrNull() ?: return null
        val cells = infos.mapNotNull { info -> runCatching { cellOf(info) }.getOrNull() }
        return NekoNetstat.serving(cells, mcc, mnc)
    }

    // CellInfo has getCellSignalStrength() itself only from Android 11: each
    // radio's own class answers it on older ones.
    private fun cellOf(info: CellInfo): NekoNetstat.Cell? {
        val sdk = Build.VERSION.SDK_INT
        val registered = info.isRegistered
        return when {
            info is CellInfoLte -> info.cellIdentity.let { id ->
                NekoNetstat.cell(
                    rat = NekoNetstat.LTE,
                    registered = registered,
                    tac = id.tac.toLong(),
                    cid = id.ci.toLong(),
                    pci = id.pci.toLong(),
                    channel = id.earfcn.toLong(),
                    mcc = if (sdk >= Build.VERSION_CODES.P) id.mccString else null,
                    mnc = if (sdk >= Build.VERSION_CODES.P) id.mncString else null,
                    level = info.cellSignalStrength.level,
                )
            }
            sdk >= Build.VERSION_CODES.Q && info is CellInfoNr ->
                (info.cellIdentity as? CellIdentityNr)?.let { id ->
                    NekoNetstat.cell(
                        rat = NekoNetstat.NR,
                        registered = registered,
                        tac = id.tac.toLong(),
                        cid = id.nci,
                        pci = id.pci.toLong(),
                        channel = id.nrarfcn.toLong(),
                        mcc = id.mccString,
                        mnc = id.mncString,
                        level = info.cellSignalStrength.level,
                    )
                }
            info is CellInfoWcdma -> info.cellIdentity.let { id ->
                NekoNetstat.cell(
                    rat = NekoNetstat.UMTS,
                    registered = registered,
                    tac = id.lac.toLong(),
                    cid = id.cid.toLong(),
                    pci = id.psc.toLong(),
                    channel = id.uarfcn.toLong(),
                    mcc = if (sdk >= Build.VERSION_CODES.P) id.mccString else null,
                    mnc = if (sdk >= Build.VERSION_CODES.P) id.mncString else null,
                    level = info.cellSignalStrength.level,
                )
            }
            sdk >= Build.VERSION_CODES.Q && info is CellInfoTdscdma -> info.cellIdentity.let { id ->
                NekoNetstat.cell(
                    rat = NekoNetstat.UMTS,
                    registered = registered,
                    tac = id.lac.toLong(),
                    cid = id.cid.toLong(),
                    pci = id.cpid.toLong(),
                    channel = id.uarfcn.toLong(),
                    mcc = id.mccString,
                    mnc = id.mncString,
                    level = info.cellSignalStrength.level,
                )
            }
            info is CellInfoGsm -> info.cellIdentity.let { id ->
                NekoNetstat.cell(
                    rat = NekoNetstat.GSM,
                    registered = registered,
                    tac = id.lac.toLong(),
                    cid = id.cid.toLong(),
                    pci = id.bsic.toLong(),
                    channel = id.arfcn.toLong(),
                    mcc = if (sdk >= Build.VERSION_CODES.P) id.mccString else null,
                    mnc = if (sdk >= Build.VERSION_CODES.P) id.mncString else null,
                    level = info.cellSignalStrength.level,
                )
            }
            else -> null
        }
    }

    @SuppressLint("MissingPermission")
    private fun lastLocation(): Location? {
        val manager = context.getSystemService(LocationManager::class.java) ?: return null
        val now = SystemClock.elapsedRealtimeNanos()
        return listOf(LocationManager.NETWORK_PROVIDER, LocationManager.GPS_PROVIDER)
            .mapNotNull { provider ->
                runCatching { manager.getLastKnownLocation(provider) }.getOrNull()
            }
            .filter { NekoNetstat.fresh((now - it.elapsedRealtimeNanos) / 1_000_000) }
            .maxByOrNull { it.elapsedRealtimeNanos }
    }

    private companion object {
        // Every plugin on the activity sees every result: clear of the others' codes.
        const val REQUEST_CODE = 2601
        val LOCATION_PERMISSIONS = arrayOf(
            Manifest.permission.ACCESS_FINE_LOCATION,
            Manifest.permission.ACCESS_COARSE_LOCATION,
        )
    }
}
