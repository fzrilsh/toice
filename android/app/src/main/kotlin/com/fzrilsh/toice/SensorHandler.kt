package com.fzrilsh.toice

/**
 * Sensor reads feeding the ADR-003 fitness score.
 *
 * Phase 0 stub: real battery / thermal / RSSI reads land on-device.
 */
class SensorHandler : SensorApi {
  override fun getBatteryLevel(callback: (Result<Long>) -> Unit) =
    callback(notImplemented("SensorApi.getBatteryLevel"))

  override fun getThermalState(callback: (Result<ThermalState>) -> Unit) =
    callback(notImplemented("SensorApi.getThermalState"))

  override fun getRssiToPeers(callback: (Result<Map<String, Long>>) -> Unit) =
    callback(notImplemented("SensorApi.getRssiToPeers"))
}
