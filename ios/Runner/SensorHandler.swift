import Foundation

/// Sensor reads feeding the ADR-003 fitness score.
///
/// Phase 0 stub: real battery / thermal (ProcessInfo.thermalState) / RSSI reads
/// land on-device.
final class SensorHandler: SensorApi {
  func getBatteryLevel(completion: @escaping (Result<Int64, Error>) -> Void) {
    completion(.failure(NotImplemented.error("SensorApi.getBatteryLevel")))
  }

  func getThermalState(completion: @escaping (Result<ThermalState, Error>) -> Void) {
    completion(.failure(NotImplemented.error("SensorApi.getThermalState")))
  }

  func getRssiToPeers(completion: @escaping (Result<[String: Int64], Error>) -> Void) {
    completion(.failure(NotImplemented.error("SensorApi.getRssiToPeers")))
  }
}
