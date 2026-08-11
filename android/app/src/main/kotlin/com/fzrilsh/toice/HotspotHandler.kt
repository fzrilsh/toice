package com.fzrilsh.toice

/**
 * Hotspot host/join control (ADR-001, ADR-002).
 *
 * Phase 0 stub: signatures are locked by Pigeon; the real
 * SoftApConfiguration (host) and join logic land in Phase 0 on-device.
 * Every method fails loudly so nothing above mistakes a stub for a working
 * implementation.
 */
class HotspotHandler : HotspotApi {
  override fun startHost(
    credentials: HotspotCredentials,
    callback: (Result<Unit>) -> Unit,
  ) = callback(notImplemented("HotspotApi.startHost"))

  override fun stopHost(callback: (Result<Unit>) -> Unit) =
    callback(notImplemented("HotspotApi.stopHost"))

  override fun joinAsClient(
    credentials: HotspotCredentials,
    callback: (Result<Unit>) -> Unit,
  ) = callback(notImplemented("HotspotApi.joinAsClient"))

  override fun leave(callback: (Result<Unit>) -> Unit) =
    callback(notImplemented("HotspotApi.leave"))
}
