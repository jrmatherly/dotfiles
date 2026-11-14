import Foundation

public enum Fixtures {
  public static let list = load("list")
  public static let status = load("status")
  public static let updateCheck = load("update-check")
  /// `rotm update -y` as the app's console received it in row 2 of the P5 probe, escapes and all.
  public static let updateConsole = data("update-console", "raw")

  private static func load(_ name: String) -> String {
    String(decoding: data(name, "json"), as: UTF8.self)
  }

  private static func data(_ name: String, _ ext: String) -> Data {
    try! Data(contentsOf: Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Fixtures")!)
  }
}
