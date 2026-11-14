import Foundation
import RotmCore
import Testing

private func tempDir() throws -> URL {
  let dir = FileManager.default.temporaryDirectory.appendingPathComponent("rotm-cli-tests-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
  return dir
}

private func stubScript() throws -> URL {
  let url = try tempDir().appendingPathComponent("rotm")
  let body = """
    #!/bin/bash
    case "$1" in
      ok) echo out; echo err >&2;;
      ro) echo "t.count is read-only" >&2; exit 3;;
      invalid) echo "usage: rotm" >&2; exit 2;;
      fail) echo boom >&2; exit 1;;
      color) printf '\\033[31mred\\033[0m\\n' >&2; exit 1;;
      args) printf '%s\\n' "$#" "$2";;
      env) printf '%s\\n%s\\n' "$PATH" "$TERM"
        if [ "$(stat -f %Z /dev/fd/0)" = "$(stat -f %Z /dev/null)" ]; then echo null; else echo other; fi;;
      slow) sleep 30 & echo $! > "$2"; wait;;
      *) exit 1;;
    esac

    """
  try body.write(to: url, atomically: true, encoding: .utf8)
  try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
  return url
}

private let home = URL(fileURLWithPath: "/Users/someone")

@Test func exitZeroReturnsStdoutAndStderr() async throws {
  let out = try await CLI(tool: stubScript(), home: home).run(["ok"])
  #expect(out == CommandOutput(stdout: "out", stderr: "err"))
}

@Test func exitThreeIsReadOnly() async throws {
  let cli = CLI(tool: try stubScript(), home: home)
  await #expect(throws: CommandError.readOnly("t.count is read-only")) { try await cli.run(["ro"]) }
}

@Test func exitTwoIsInvalid() async throws {
  let cli = CLI(tool: try stubScript(), home: home)
  await #expect(throws: CommandError.invalid("usage: rotm")) { try await cli.run(["invalid"]) }
}

@Test func otherExitIsFailedWithPlainStderr() async throws {
  let cli = CLI(tool: try stubScript(), home: home)
  await #expect(throws: CommandError.failed(1, "boom")) { try await cli.run(["fail"]) }
  await #expect(throws: CommandError.failed(1, "red")) { try await cli.run(["color"]) }
}

@Test func aMissingToolIsToolMissing() async {
  let cli = CLI(tool: URL(fileURLWithPath: "/nope/rotm"), home: home)
  await #expect(throws: CommandError.toolMissing("/nope/rotm")) { try await cli.run(["ok"]) }
}

@Test func aSlowCommandTimesOutAndIsKilled() async throws {
  let stub = try stubScript()
  let pidFile = stub.deletingLastPathComponent().appendingPathComponent("pid")
  let cli = CLI(tool: stub, home: home, timeout: 1)
  await #expect(throws: CommandError.timedOut) { try await cli.run(["slow", pidFile.path]) }
  let sleeper = try #require(Int32(String(contentsOf: pidFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)))
  var alive = true
  for _ in 0..<40 {
    alive = kill(sleeper, 0) == 0 || pgrep(stub.path)
    if !alive { break }
    try await Task.sleep(nanoseconds: 50_000_000)
  }
  #expect(!alive, "the script and its child are gone")
}

private func pgrep(_ pattern: String) -> Bool {
  let p = Process()
  p.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
  p.arguments = ["-f", pattern]
  p.standardOutput = FileHandle.nullDevice
  try? p.run()
  p.waitUntilExit()
  return p.terminationStatus == 0
}

@Test func anArgumentArrivesByteForByte() async throws {
  let out = try await CLI(tool: stubScript(), home: home).run(["args", #"-a "b" #c"#])
  #expect(out.stdout == "2\n-a \"b\" #c")
}

@Test func theChildGetsTheSearchPathDumbTermAndNullStdin() async throws {
  let out = try await CLI(tool: stubScript(), home: home).run(["env"])
  #expect(out.stdout.split(separator: "\n").map(String.init) == [CLI.searchPath(home: home), "dumb", "null"])
}

@Test func searchPathIsTheGlobalConstraintsList() {
  #expect(
    CLI.searchPath(home: home)
      == "/Users/someone/.local/bin:/Users/someone/.local/share/mise/shims:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin")
}

@Test func locateFindsTheLinkOrTheOverride() throws {
  let empty = try tempDir()
  #expect(CLI.locate(override: nil, home: empty) == nil)
  let stub = try stubScript()
  #expect(CLI.locate(override: stub.path, home: empty) == stub)
  #expect(CLI.locate(override: "", home: empty) == nil)

  let bin = empty.appendingPathComponent("dotfiles/bin")
  try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
  let linked = bin.appendingPathComponent("rotm")
  try "#!/bin/bash\n".write(to: linked, atomically: true, encoding: .utf8)
  #expect(CLI.locate(override: nil, home: empty) == nil, "not executable yet")
  try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: linked.path)
  #expect(CLI.locate(override: nil, home: empty)?.path == linked.path)
  #expect(CLI.locate(override: stub.path, home: empty) == stub)
  #expect(CLI.locate(override: "/nope/rotm", home: empty)?.path == linked.path)
}
