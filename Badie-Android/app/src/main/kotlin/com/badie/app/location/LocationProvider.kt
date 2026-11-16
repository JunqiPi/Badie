package com.badie.app.location

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationManager
import androidx.core.content.ContextCompat
import androidx.core.location.LocationManagerCompat
import androidx.core.os.CancellationSignal
import com.badie.app.models.Coordinate
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withTimeoutOrNull
import kotlin.coroutines.resume

/**
 * 取一次当前位置（找附近的球馆用）。用系统自带的定位，不靠 Google Play 服务。
 * 没给权限、关了定位、或 15 秒内拿不到，都返回 null
 */
class LocationProvider(private val context: Context) {
    private val manager get() = context.getSystemService(Context.LOCATION_SERVICE) as LocationManager

    /** 给了定位权限（精确或大概都算） */
    val isAuthorized: Boolean
        get() = listOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION).any {
            ContextCompat.checkSelfPermission(context, it) == PackageManager.PERMISSION_GRANTED
        }

    @SuppressLint("MissingPermission")
    suspend fun current(): Coordinate? {
        if (!isAuthorized) return null
        val manager = manager
        // 合并定位（fused）Android 12 起才有
        val fused = if (android.os.Build.VERSION.SDK_INT >= 31) listOf(LocationManager.FUSED_PROVIDER) else emptyList()
        val provider = (fused + listOf(LocationManager.NETWORK_PROVIDER, LocationManager.GPS_PROVIDER))
            .firstOrNull { runCatching { manager.isProviderEnabled(it) }.getOrDefault(false) } ?: return lastKnown(manager)
        val fresh = withTimeoutOrNull(15_000) {
            suspendCancellableCoroutine<Location?> { continuation ->
                val signal = CancellationSignal()
                continuation.invokeOnCancellation { signal.cancel() }
                LocationManagerCompat.getCurrentLocation(manager, provider, signal, ContextCompat.getMainExecutor(context)) { location ->
                    if (continuation.isActive) continuation.resume(location)
                }
            }
        }
        return fresh?.let { Coordinate(it.latitude, it.longitude) } ?: lastKnown(manager)
    }

    /** 拿不到新的位置时，用系统记得的上一次（10 分钟以内的才算） */
    @SuppressLint("MissingPermission")
    private fun lastKnown(manager: LocationManager): Coordinate? {
        val recent = manager.getProviders(true).mapNotNull { runCatching { manager.getLastKnownLocation(it) }.getOrNull() }
            .filter { System.currentTimeMillis() - it.time < 10 * 60_000 }
            .maxByOrNull { it.time } ?: return null
        return Coordinate(recent.latitude, recent.longitude)
    }

    companion object {
        val PERMISSIONS = arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION)
    }
}
