import Foundation
import XCTest
@testable import DiskatCore

final class CompatibilityTests: XCTestCase {
    func testLockedStateSerializesConcurrentUpdates() {
        let count = LockedState(initialState: 0)
        DispatchQueue.concurrentPerform(iterations: 5_000) { _ in
            count.withLock { $0 += 1 }
        }
        XCTAssertEqual(count.withLock { $0 }, 5_000)
    }

    func testLockedStateUnlocksAfterThrowing() {
        enum Failure: Error { case expected }
        let count = LockedState(initialState: 0)
        XCTAssertThrowsError(try count.withLock { value in
            value = 1
            throw Failure.expected
        })
        XCTAssertEqual(count.withLock { $0 }, 1)
    }

    func testUnknownCloneReferenceCountDoesNotPromiseReclaimableSpace() {
        // Older kernels expose shared-block flags but may not expose clone reference counts.
        let shared = DupFile(path: "/shared", modified: 0, linkCount: 1, otherNames: [],
                             isClone: true, device: 1, cloneID: 1, cloneRefs: .max)
        let otherShared = DupFile(path: "/other", modified: 0, linkCount: 1, otherNames: [],
                                  isClone: true, device: 1, cloneID: 2, cloneRefs: .max)
        XCTAssertEqual(DupGroup(size: 100, files: [shared, otherShared]).wasted, 0)
    }
}
