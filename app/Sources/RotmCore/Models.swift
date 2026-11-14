import Foundation

public struct SettingRow: Codable, Identifiable, Equatable, Sendable {
  public var id: String { settingId }
  public let settingId: String, label: String, section: String, help: String, kind: String, scope: String
  public let type: String, access: String, widget: String, source: String
  public let value: String?, seed: String?
  public let drift: Bool, seatList: Bool
  public let choices: [String], seatModels: [String], seatEfforts: [String]
}

public struct Status: Codable, Equatable, Sendable {
  public struct Profile: Codable, Equatable, Sendable {
    public let active: String
    public let names: [String]
    public let missing: String?
    public let miseEnv: Bool
  }
  public struct Sync: Codable, Equatable, Sendable {
    public let connected: Bool
    public let origin: String?
    public let waiting: [String]
    public let conflicts: String?
  }
  public let mode: String, branch: String?, commit: String?
  public let profile: Profile, sync: Sync
}

public struct UpdateCheck: Codable, Equatable, Sendable {
  public let mode: String
  public let branch: String?
  public let behind: Int?
}

public enum Decode {
  public static func rows(_ json: String) throws -> [SettingRow] { try decode(json) }
  public static func status(_ json: String) throws -> Status { try decode(json) }
  public static func updateCheck(_ json: String) throws -> UpdateCheck { try decode(json) }

  private static func decode<T: Decodable>(_ json: String) throws -> T {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    do {
      return try decoder.decode(T.self, from: Data(json.utf8))
    } catch {
      throw CommandError.badJSON(String(json.prefix(200)))
    }
  }
}
