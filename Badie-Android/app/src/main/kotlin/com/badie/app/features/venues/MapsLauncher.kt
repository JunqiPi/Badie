package com.badie.app.features.venues

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.core.net.toUri
import com.badie.app.models.CoordinateDatum
import com.badie.app.models.NavigationApp
import com.badie.app.models.Venue
import java.util.Locale

/**
 * 导航到球馆：按球馆所在国家给出常用的导航 App。对应 iPhone 的 Services/MapsLauncher.swift。
 * - 安卓上没有 Apple 地图，列表里去掉它。
 * - Google 地图、Waze 用官方网址：装了 App 就打开 App，没装就打开网页。
 * - 高德、百度只在国内用；传 WGS-84 坐标，由对方做坐标偏移。
 */
object MapsLauncher {

    fun apps(venue: Venue): List<NavigationApp> = venue.country.navigationApps.filter { it != NavigationApp.AppleMaps }

    /** 打开这个 App 要用的地址；Apple 地图返回 null */
    fun uri(venue: Venue, app: NavigationApp, packageName: String = "com.badie.app"): Uri? {
        val ll = "${coordinate(venue.lat)},${coordinate(venue.lon)}"
        val wgs = venue.datum == CoordinateDatum.Wgs84
        return when (app) {
            NavigationApp.AppleMaps -> null
            NavigationApp.GoogleMaps -> "https://www.google.com/maps/dir/".toUri().buildUpon()
                .appendQueryParameter("api", "1").appendQueryParameter("destination", ll).build()
            NavigationApp.Waze -> "https://waze.com/ul".toUri().buildUpon()
                .appendQueryParameter("ll", ll).appendQueryParameter("navigate", "yes").build()
            // 高德安卓版：dev=1 表示传入的是 WGS-84，由高德偏移到 GCJ-02
            NavigationApp.Amap -> "amapuri://route/plan/".toUri().buildUpon()
                .appendQueryParameter("sourceApplication", "Badie")
                .appendQueryParameter("dlat", coordinate(venue.lat)).appendQueryParameter("dlon", coordinate(venue.lon))
                .appendQueryParameter("dname", venue.name).appendQueryParameter("dev", if (wgs) "1" else "0")
                .appendQueryParameter("t", "0").build()
            NavigationApp.Naver -> "nmap://route/public".toUri().buildUpon()
                .appendQueryParameter("dlat", coordinate(venue.lat)).appendQueryParameter("dlng", coordinate(venue.lon))
                .appendQueryParameter("dname", venue.name).appendQueryParameter("appname", packageName).build()
            NavigationApp.Kakao -> "kakaomap://route?ep=$ll&by=PUBLICTRANSIT".toUri()
            NavigationApp.Baidu -> "baidumap://map/direction".toUri().buildUpon()
                .appendQueryParameter("destination", "latlng:$ll|name:${venue.name}")
                .appendQueryParameter("coord_type", if (wgs) "wgs84" else "gcj02")
                .appendQueryParameter("mode", "transit").appendQueryParameter("src", "andr.badie.app").build()
        }
    }

    /** 打开导航；App 没装（高德、百度这类只认自己的地址的）返回 false */
    fun open(context: Context, venue: Venue, app: NavigationApp): Boolean {
        val uri = uri(venue, app, context.packageName) ?: return false
        return start(context, Intent(Intent.ACTION_VIEW, uri))
    }

    /** 拨打球馆电话（打开拨号盘，不直接打出去） */
    fun call(context: Context, phone: String): Boolean {
        val digits = phone.filter { it.isDigit() || it == '+' }
        return start(context, Intent(Intent.ACTION_DIAL, "tel:$digits".toUri()))
    }

    fun openWebsite(context: Context, website: String): Boolean = start(context, Intent(Intent.ACTION_VIEW, website.toUri()))

    private fun start(context: Context, intent: Intent): Boolean = try {
        if (context !is android.app.Activity) intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)
        true
    } catch (_: ActivityNotFoundException) {
        false
    }

    private fun coordinate(value: Double) = String.format(Locale.ROOT, "%.6f", value)
}
