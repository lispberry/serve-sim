/// Caps an encoder at its configured frame rate without dropping frames from a source that
/// already runs at that rate.
///
/// Display callbacks are not phase-locked to the encoder queue, so nominal 60 Hz frames land a
/// few milliseconds early or late. Accepted frames therefore advance a deadline grid rather than
/// restarting the interval from their own arrival: a late frame used to push the next on-time
/// frame past its deadline, which dropped one frame in every handful and held a 60 Hz simulator
/// near 45 fps. Half an interval of slack absorbs that jitter while every accepted frame still
/// moves the grid a full interval, so the long-run rate never exceeds the cap.
public struct FrameRateGate: Sendable {
    private var intervalNanoseconds: UInt64
    private var nextDeadlineNanoseconds: UInt64?
    private var lastAcceptedNanoseconds: UInt64 = 0

    public init(fps: Int) {
        intervalNanoseconds = Self.interval(fps: fps)
    }

    public mutating func update(fps: Int) {
        intervalNanoseconds = Self.interval(fps: fps)
        nextDeadlineNanoseconds = nil
    }

    public mutating func shouldEncode(atNanoseconds now: UInt64) -> Bool {
        let slack = intervalNanoseconds / 2
        guard let deadline = nextDeadlineNanoseconds else {
            nextDeadlineNanoseconds = now &+ intervalNanoseconds
            lastAcceptedNanoseconds = now
            return true
        }
        // Accepted frames stay at least half an interval apart, so the slack can never let
        // two frames through back to back.
        if now &+ slack < deadline || now &- lastAcceptedNanoseconds < slack {
            return false
        }
        // A frame later than half an interval re-anchors the grid on itself, so a stall
        // cannot release a burst of catch-up frames afterwards.
        nextDeadlineNanoseconds = max(deadline &+ intervalNanoseconds, now &+ slack)
        lastAcceptedNanoseconds = now
        return true
    }

    private static func interval(fps: Int) -> UInt64 {
        1_000_000_000 / UInt64(max(1, fps))
    }
}
