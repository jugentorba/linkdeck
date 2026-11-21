import Foundation

/// Stable hashing used for cache keys, letter-tile colors, and rule-list versions.
/// Swift's `Hasher` is randomly seeded per process, so it cannot be used here.
enum StableHash {
    static func fnv1a(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return hash
    }

    static func fnv1a(_ data: Data) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in data {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return hash
    }

    static func hex(_ value: UInt64) -> String {
        String(value, radix: 16)
    }
}
