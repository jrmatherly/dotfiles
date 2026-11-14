import RotmCore
import RotmTestSupport
import Testing

@testable import ReturnOfTheMac

@Test func theFixturesReachTheAppTests() throws {
  #expect(try Decode.rows(Fixtures.list).count == 9)
}
