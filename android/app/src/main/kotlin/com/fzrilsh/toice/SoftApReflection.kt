package com.fzrilsh.toice

import android.net.wifi.WifiManager
import android.os.Build
import androidx.annotation.RequiresApi
import java.util.concurrent.Executor

/**
 * Reflection bridge to the hidden `@SystemApi` that lets an app set its own
 * SoftAp credentials (ADR-002). The public `startLocalOnlyHotspot(callback,
 * handler)` overload always generates random SSID/password, which breaks the
 * fixed-credential handoff design; the overload taking a `SoftApConfiguration`
 * is hidden and only reachable via reflection, only on API 33+ with
 * NEARBY_WIFI_DEVICES granted.
 *
 * ponytail: reflection is the ceiling here. If it proves unreliable across too
 * many OEMs, drop to the manual-Settings path only and revise ADR-002.
 */
object SoftApReflection {
  // android.net.wifi.SoftApConfiguration constants (hidden).
  private const val SECURITY_TYPE_WPA2_PSK = 1
  private const val BAND_2GHZ = 1

  /**
   * Build a hidden SoftApConfiguration and start a local-only hotspot with the
   * given fixed credentials. Throws on any failure (missing hidden API, OEM
   * block, SecurityException); the caller treats that as the manual fallback.
   */
  @RequiresApi(Build.VERSION_CODES.TIRAMISU)
  fun startLocalOnlyHotspot(
    wifiManager: WifiManager,
    ssid: String,
    passphrase: String,
    executor: Executor,
    callback: WifiManager.LocalOnlyHotspotCallback,
  ) {
    val builderClass = Class.forName("android.net.wifi.SoftApConfiguration\$Builder")
    val configClass = Class.forName("android.net.wifi.SoftApConfiguration")

    val builder = builderClass.getConstructor().newInstance()
    builderClass.getMethod("setSsid", String::class.java).invoke(builder, ssid)
    builderClass
      .getMethod("setPassphrase", String::class.java, Int::class.javaPrimitiveType)
      .invoke(builder, passphrase, SECURITY_TYPE_WPA2_PSK)
    builderClass
      .getMethod("setBand", Int::class.javaPrimitiveType)
      .invoke(builder, BAND_2GHZ)
    builderClass
      .getMethod("setAutoShutdownEnabled", Boolean::class.javaPrimitiveType)
      .invoke(builder, false)
    val config = builderClass.getMethod("build").invoke(builder)

    WifiManager::class.java
      .getMethod(
        "startLocalOnlyHotspot",
        configClass,
        Executor::class.java,
        WifiManager.LocalOnlyHotspotCallback::class.java,
      )
      .invoke(wifiManager, config, executor, callback)
  }
}
