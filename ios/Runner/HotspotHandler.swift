import Foundation

/// Hotspot host/join control (ADR-001, ADR-002).
///
/// Phase 0 stub: iOS join uses NEHotspotConfiguration; iOS cannot host a
/// SoftAP, so `startHost`/`stopHost` stay unimplemented here by design.
/// Every method fails loudly so nothing above mistakes a stub for working code.
final class HotspotHandler: HotspotApi {
  func startHost(credentials: HotspotCredentials, completion: @escaping (Result<Void, Error>) -> Void) {
    completion(.failure(NotImplemented.error("HotspotApi.startHost")))
  }

  func stopHost(completion: @escaping (Result<Void, Error>) -> Void) {
    completion(.failure(NotImplemented.error("HotspotApi.stopHost")))
  }

  func joinAsClient(credentials: HotspotCredentials, completion: @escaping (Result<Void, Error>) -> Void) {
    completion(.failure(NotImplemented.error("HotspotApi.joinAsClient")))
  }

  func leave(completion: @escaping (Result<Void, Error>) -> Void) {
    completion(.failure(NotImplemented.error("HotspotApi.leave")))
  }
}
