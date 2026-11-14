import Foundation

public enum AppUpdate {
  public static let package = "brew-cask:jrmatherly/tap/returnofthemac-app"
  public static let caskURL = URL(string: "https://raw.githubusercontent.com/jrmatherly/homebrew-tap/HEAD/Casks/returnofthemac-app.rb")!
  public static let releasesURL = "https://github.com/jrmatherly/returnofthemac/releases"
  public static let upgradeArguments = ["bootstrap", "packages", "upgrade", "--yes", package]

  /// The first `version "X.Y.Z"` line; nil for anything that is not three numbers.
  public static func version(inCask text: String) -> String? {
    guard let match = text.firstMatch(of: #/(?m)^\s*version\s+"([^"]*)"/#) else { return nil }
    let version = String(match.1)
    return components(version) == nil ? nil : version
  }

  public static func isNewer(_ candidate: String, than current: String) -> Bool {
    guard let a = components(candidate), let b = components(current) else { return false }
    return b.lexicographicallyPrecedes(a)
  }

  /// Read from the file, never `Bundle.main`, which caches its Info.plist.
  public static func diskVersion(_ app: URL) -> String? {
    NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist"))?["CFBundleShortVersionString"] as? String
  }

  /// nil for a development build (`swift run`, or a bundle with no version), which never checks.
  public static func runningVersion(_ bundle: URL) -> String? {
    bundle.pathExtension == "app" ? diskVersion(bundle) : nil
  }

  private static func components(_ version: String) -> [Int]? {
    guard version.wholeMatch(of: #/[0-9]+\.[0-9]+\.[0-9]+/#) != nil else { return nil }
    let numbers = version.split(separator: ".").compactMap { Int($0) }
    return numbers.count == 3 ? numbers : nil
  }
}

/// The text is what the user is shown.
public enum UpdateOutcome: Equatable { case relaunch, unchanged(String), failed(String) }
