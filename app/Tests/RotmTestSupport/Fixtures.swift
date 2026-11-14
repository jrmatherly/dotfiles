import Foundation

public enum Fixtures {
  public static let list = load("list")
  public static let status = load("status")
  public static let updateCheck = load("update-check")

  private static func load(_ name: String) -> String {
    let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")!
    return try! String(contentsOf: url, encoding: .utf8)
  }
}
