package com.fzrilsh.toice

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.wifi.WifiManager
import android.net.wifi.WifiNetworkSpecifier
import android.os.Build
import android.provider.Settings
import androidx.core.content.ContextCompat

/**
 * Hotspot host/join control (ADR-001, ADR-002).
 *
 * Host: tries the reflection SoftAp path (fixed credentials, API 33+); any
 * failure returns [HostStartMode.MANUAL_REQUIRED] so the UI routes the user to
 * Settings. Client join lands in Task 5.
 */
class HotspotHandler(
  private val context: Context,
  private val events: HotspotEvents,
) : HotspotApi {
  private val wifiManager: WifiManager
    get() = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager

  private val connectivityManager: ConnectivityManager
    get() =
      context.applicationContext.getSystemService(Context.CONNECTIVITY_SERVICE)
        as ConnectivityManager

  private var reservation: WifiManager.LocalOnlyHotspotReservation? = null
  private var networkCallback: ConnectivityManager.NetworkCallback? = null

  override fun startHost(
    credentials: HotspotCredentials,
    callback: (Result<HostStartMode>) -> Unit,
  ) {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU || !hasNearbyWifiPermission()) {
      callback(Result.success(HostStartMode.MANUAL_REQUIRED))
      return
    }

    val hostCallback = object : WifiManager.LocalOnlyHotspotCallback() {
      override fun onStarted(res: WifiManager.LocalOnlyHotspotReservation) {
        reservation = res
        callback(Result.success(HostStartMode.PROGRAMMATIC))
      }

      override fun onStopped() {
        reservation = null
        events.onHostStopped("onStopped") {}
      }

      override fun onFailed(reason: Int) {
        reservation = null
        events.onHostStopped("onFailed($reason)") {}
      }
    }

    try {
      SoftApReflection.startLocalOnlyHotspot(
        wifiManager,
        credentials.ssid,
        credentials.password,
        ContextCompat.getMainExecutor(context),
        hostCallback,
      )
      // onStarted/onFailed complete the callback asynchronously.
    } catch (t: Throwable) {
      // Missing hidden API, OEM block, SecurityException, etc. Normal path,
      // not an error: fall back to manual hotspot configuration.
      callback(Result.success(HostStartMode.MANUAL_REQUIRED))
    }
  }

  override fun stopHost(callback: (Result<Unit>) -> Unit) {
    reservation?.close()
    reservation = null
    callback(Result.success(Unit))
  }

  override fun openTetherSettings(callback: (Result<Unit>) -> Unit) {
    val intent = Intent("com.android.settings.WIFI_TETHER_SETTINGS").apply {
      addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    }
    try {
      context.startActivity(intent)
    } catch (_: Throwable) {
      context.startActivity(
        Intent(Settings.ACTION_WIRELESS_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
      )
    }
    callback(Result.success(Unit))
  }

  override fun joinAsClient(
    credentials: HotspotCredentials,
    callback: (Result<Unit>) -> Unit,
  ) {
    // Tear down any prior request before starting a new one.
    unbind()

    val specifier = WifiNetworkSpecifier.Builder()
      .setSsid(credentials.ssid)
      .setWpa2Passphrase(credentials.password)
      .build()
    val request = NetworkRequest.Builder()
      .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
      .setNetworkSpecifier(specifier)
      .build()

    val cb = object : ConnectivityManager.NetworkCallback() {
      override fun onAvailable(network: Network) {
        // Route app sockets over the hotspot, not cellular.
        connectivityManager.bindProcessToNetwork(network)
        events.onClientStateChanged(true) {}
      }

      override fun onLost(network: Network) {
        connectivityManager.bindProcessToNetwork(null)
        events.onClientStateChanged(false) {}
      }

      override fun onUnavailable() {
        events.onClientStateChanged(false) {}
      }
    }

    networkCallback = cb
    connectivityManager.requestNetwork(request, cb)
    callback(Result.success(Unit))
  }

  override fun leave(callback: (Result<Unit>) -> Unit) {
    unbind()
    callback(Result.success(Unit))
  }

  private fun unbind() {
    networkCallback?.let { connectivityManager.unregisterNetworkCallback(it) }
    networkCallback = null
    connectivityManager.bindProcessToNetwork(null)
  }

  private fun hasNearbyWifiPermission(): Boolean {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return false
    return ContextCompat.checkSelfPermission(
      context,
      Manifest.permission.NEARBY_WIFI_DEVICES,
    ) == PackageManager.PERMISSION_GRANTED
  }
}
