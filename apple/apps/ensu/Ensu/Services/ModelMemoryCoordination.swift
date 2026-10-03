import Foundation

struct ModelMemoryPressureState {
    static let cooldown: TimeInterval = 30
    private var generation: UInt64 = 0
    private var evictedGeneration: UInt64 = 0
    private var retryAfter: TimeInterval = 0

    mutating func recordPressure(now: TimeInterval) {
        generation &+= 1
        retryAfter = now + Self.cooldown
    }

    func suppressesOptionalWork(now: TimeInterval) -> Bool {
        generation != evictedGeneration || now < retryAfter
    }

    func requiresCleanup(appForeground: Bool, now: TimeInterval) -> Bool {
        !appForeground || suppressesOptionalWork(now: now)
    }

    mutating func didCleanUp() {
        evictedGeneration = generation
    }
}

actor AsyncSerialGate {
    private var isLocked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func withLock<T>(
        isolation: isolated (any Actor)? = #isolation,
        onEnter: () async -> Void = {},
        onExit: () async -> Void = {},
        _ operation: () async throws -> T
    ) async throws -> T {
        await acquire()
        do {
            try Task.checkCancellation()
            await onEnter()
            try Task.checkCancellation()
            let result = try await operation()
            await onExit()
            await release()
            return result
        } catch {
            await onExit()
            await release()
            throw error
        }
    }

    private func acquire() async {
        if !isLocked {
            isLocked = true
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    private func release() {
        guard !waiters.isEmpty else {
            isLocked = false
            return
        }

        let continuation = waiters.removeFirst()
        continuation.resume()
    }
}
