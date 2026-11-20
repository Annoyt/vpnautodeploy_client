package com.follow.clash.service.modules

import android.Manifest
import android.app.ActivityManager
import android.app.Notification
import android.app.Service
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.net.VpnService
import android.os.Build
import com.follow.clash.common.GlobalState
import com.follow.clash.common.startForeground
import java.io.File

// NekoVPN (neko.6, C3): the `location` type lets the cell be read after the user
// leaves the app; Android refuses it to a VPN started from the background.
internal class NekoForeground(private val service: Service) {
    @Volatile
    private var location: Boolean? = null

    fun start(notification: Notification) {
        val sdk = Build.VERSION.SDK_INT
        if (service !is VpnService || sdk < Build.VERSION_CODES.Q) {
            service.startForeground(notification)
            return
        }
        if (location ?: wanted(sdk).also { location = it }) {
            try {
                service.startForeground(
                    GlobalState.NOTIFICATION_ID,
                    notification,
                    NekoNetstatSwitch.type(location = true),
                )
                return
            } catch (error: RuntimeException) {
                location = false
                GlobalState.log("NekoVPN: the VPN runs without the location type: $error")
            }
        }
        service.startForeground(
            GlobalState.NOTIFICATION_ID,
            notification,
            NekoNetstatSwitch.type(location = false),
        )
    }

    private fun wanted(sdk: Int): Boolean = runCatching {
        val process = ActivityManager.RunningAppProcessInfo()
        ActivityManager.getMyMemoryState(process)
        NekoNetstatSwitch.wantsLocation(
            sdk = sdk,
            enabled = NekoNetstatSwitch.enabled(File(service.filesDir, NekoNetstatSwitch.FILE)),
            permitted = service.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) ==
                PackageManager.PERMISSION_GRANTED,
            importance = process.importance,
        )
    }.getOrDefault(false)
}

internal object NekoNetstatSwitch {
    const val FILE = "neko_netstat_cell.json"
    private val ENABLED = Regex("\"enabled\"\\s*:\\s*true")
    private val IN_FRONT = setOf(
        ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND,
        ActivityManager.RunningAppProcessInfo.IMPORTANCE_VISIBLE,
    )

    fun enabled(file: File): Boolean =
        runCatching { ENABLED.containsMatchIn(file.readText()) }.getOrDefault(false)

    fun wantsLocation(sdk: Int, enabled: Boolean, permitted: Boolean, importance: Int): Boolean =
        sdk >= Build.VERSION_CODES.Q && enabled && permitted && importance in IN_FRONT

    // Explicit everywhere: the two-argument call claims the manifest's location too.
    fun type(location: Boolean): Int {
        val special = ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
        return if (location) special or ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION else special
    }
}
