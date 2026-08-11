package com.fzrilsh.toice

/**
 * Keep-alive session control (ADR-005): foreground service with a persistent
 * notification.
 *
 * Phase 0 stub: real foreground service lands on-device.
 */
class BackgroundHandler : BackgroundApi {
  override fun startForegroundSession(callback: (Result<Unit>) -> Unit) =
    callback(notImplemented("BackgroundApi.startForegroundSession"))

  override fun stopForegroundSession(callback: (Result<Unit>) -> Unit) =
    callback(notImplemented("BackgroundApi.stopForegroundSession"))
}

/**
 * Shared failure for every Phase 0 stub. Fails loudly (never a dummy value)
 * so Dart-side logic cannot mistake an unimplemented bridge for a working one.
 */
internal fun <T> notImplemented(method: String): Result<T> =
  Result.failure(NotImplementedError("$method not implemented (Phase 0)"))
