import Foundation

/// Minimal test harness: XCTest is unavailable with Command Line Tools only.
enum T {
    static var failures = 0
    static var checks = 0

    static func run(_ name: String, _ body: () throws -> Void) {
        print("• \(name)")
        do { try body() } catch {
            failures += 1
            print("  ❌ THREW: \(error)")
        }
    }

    static func expect(_ ok: Bool, _ message: String,
                       file: StaticString = #filePath, line: UInt = #line) {
        checks += 1
        if !ok {
            failures += 1
            print("  ❌ FAIL: \(message) (\(file):\(line))")
        }
    }

    static func equal<V: Equatable>(_ actual: V, _ expected: V, _ message: String = "",
                                    file: StaticString = #filePath, line: UInt = #line) {
        expect(actual == expected,
               "\(message) — expected \(expected), got \(actual)",
               file: file, line: line)
    }

    static func finish() -> Never {
        if failures == 0 {
            print("\n✅ All \(checks) checks passed")
            exit(0)
        } else {
            print("\n❌ \(failures) failure(s) out of \(checks) checks")
            exit(1)
        }
    }
}
