import Foundation

/// Heap-owned lock and state, available before OSAllocatedUnfairLock (macOS 13).
final class LockedState<State>: @unchecked Sendable {
    private let mutex = NSLock()
    private var state: State
    init(initialState: State) { state = initialState }
    func withLock<R>(_ body: (inout State) throws -> R) rethrows -> R {
        mutex.lock()
        defer { mutex.unlock() }
        return try body(&state)
    }
    func withLockUnchecked<R>(_ body: (inout State) throws -> R) rethrows -> R { try withLock(body) }
}
extension LockedState where State == Void {
    convenience init() { self.init(initialState: ()) }
    func withLockUnchecked<R>(_ body: () throws -> R) rethrows -> R { try withLock { _ in try body() } }
}
