import Foundation

/// Hotspot host/join control (ADR-001, ADR-002).
///
/// iOS cannot host a SoftAP, and joins the hotspot via the system Camera
/// WiFi-QR flow rather than this API (ADR-002 addendum: NEHotspotConfiguration
/// needs a paid-account entitlement). Every method fails loudly with an
/// explicit reason so the log states why, not just "not implemented".
final class HotspotHandler: HotspotApi {
  func startHost(credentials: HotspotCredentials, completion: @escaping (Result<HostStartMode, Error>) -> Void) {
    completion(.failure(NotImplemented.error("HotspotApi.startHost (iOS cannot host an AP)")))
  }

  func stopHost(completion: @escaping (Result<Void, Error>) -> Void) {
    completion(.failure(NotImplemented.error("HotspotApi.stopHost (iOS cannot host an AP)")))
  }

  func openTetherSettings(completion: @escaping (Result<Void, Error>) -> Void) {
    completion(.failure(NotImplemented.error("HotspotApi.openTetherSettings (Android-only fallback)")))
  }

  func joinAsClient(credentials: HotspotCredentials, completion: @escaping (Result<Void, Error>) -> Void) {
    completion(.failure(NotImplemented.error("HotspotApi.joinAsClient (iOS joins via system Camera QR, see ADR-002 addendum)")))
  }

  func leave(completion: @escaping (Result<Void, Error>) -> Void) {
    completion(.failure(NotImplemented.error("HotspotApi.leave (iOS joins via system Camera QR, see ADR-002 addendum)")))
  }
}
