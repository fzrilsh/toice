import Foundation

/// Keep-alive session control (ADR-005): iOS background audio session.
///
/// Phase 0 stub: real background audio session setup lands on-device.
final class BackgroundHandler: BackgroundApi {
  func startForegroundSession(completion: @escaping (Result<Void, Error>) -> Void) {
    completion(.failure(NotImplemented.error("BackgroundApi.startForegroundSession")))
  }

  func stopForegroundSession(completion: @escaping (Result<Void, Error>) -> Void) {
    completion(.failure(NotImplemented.error("BackgroundApi.stopForegroundSession")))
  }
}

/// Shared failure for every Phase 0 stub. Fails loudly (never a dummy value)
/// so Dart-side logic cannot mistake an unimplemented bridge for a working one.
enum NotImplemented {
  static func error(_ method: String) -> NSError {
    NSError(
      domain: "com.fzrilsh.toice.NotImplemented",
      code: 501,
      userInfo: [NSLocalizedDescriptionKey: "\(method) not implemented (Phase 0)"]
    )
  }
}
