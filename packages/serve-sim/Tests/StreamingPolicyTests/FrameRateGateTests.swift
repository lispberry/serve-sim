import Testing

@testable import StreamingPolicy

@Suite("FrameRateGate")
struct FrameRateGateTests {
    private static let frame60: UInt64 = 16_666_667
    private static let base: UInt64 = 1_000_000_000

    /// Arrival times for a 60 Hz source, each offset from its nominal slot.
    private func arrivals(count: Int, interval: UInt64 = frame60, offsets: (Int) -> Int64) -> [UInt64] {
        (0..<count).map { n in
            UInt64(Int64(Self.base &+ UInt64(n) &* interval) + offsets(n))
        }
    }

    private func accepted(_ times: [UInt64], fps: Int) -> [UInt64] {
        var gate = FrameRateGate(fps: fps)
        return times.filter { gate.shouldEncode(atNanoseconds: $0) }
    }

    @Test("keeps every frame of a 60 Hz source whose frames land late or early")
    func keepsJitteredSixtyHertz() {
        // Deterministic ±4 ms jitter, the spread measured on a simulator's frame callbacks.
        let pattern: [Int64] = [0, 4_000_000, -3_000_000, 2_500_000, -4_000_000, 3_500_000, -1_000_000]
        let times = arrivals(count: 600) { pattern[$0 % pattern.count] }
        #expect(accepted(times, fps: 60).count == 600)
    }

    @Test("a late frame does not cost the next on-time frame its slot")
    func lateFrameKeepsNextSlot() {
        let times = arrivals(count: 3) { $0 == 1 ? 3_000_000 : 0 }
        #expect(accepted(times, fps: 60) == times)
    }

    @Test("caps a faster source at the configured rate")
    func capsFasterSource() {
        let times = arrivals(count: 240, interval: Self.frame60 / 2) { _ in 0 }  // 2 s at 120 Hz
        let kept = accepted(times, fps: 60)
        #expect((119...121).contains(kept.count))
    }

    @Test("halves a 60 Hz source for a 30 fps stream")
    func halvesForThirty() {
        let times = arrivals(count: 120) { _ in 0 }  // 2 s at 60 Hz
        #expect((59...61).contains(accepted(times, fps: 30).count))
    }

    @Test("resumes after a stall without a burst of catch-up frames")
    func noBurstAfterStall() {
        var times = arrivals(count: 10) { _ in 0 }
        let resume = times.last! &+ 200_000_000
        times += (0..<10).map { resume &+ UInt64($0) &* Self.frame60 }
        times.insert(resume &+ 1_000_000, at: 11)  // a duplicate wake right after the stall
        let kept = accepted(times, fps: 60)
        let gaps = zip(kept.dropFirst(), kept).map { $0 &- $1 }
        #expect(kept.count == 20)
        #expect(gaps.allSatisfy { $0 >= Self.frame60 / 2 })
    }
}
