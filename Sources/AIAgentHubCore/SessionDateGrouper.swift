import Foundation

/// Date-bucket grouping for the session list sidebar.
///
/// Buckets are mutually exclusive and ordered by recency. We compute the bucket once per
/// session using a single Calendar instance so the grouping is consistent under clock skew.
public enum SessionDateBucket: String, CaseIterable, Identifiable, Sendable {
    case pinned        // Pinned sessions float to the top regardless of date
    case today
    case yesterday
    case thisWeek      // 2-7 days ago
    case thisMonth     // 8-30 days ago
    case earlier

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .pinned: "Pinned"
        case .today: "Today"
        case .yesterday: "Yesterday"
        case .thisWeek: "This week"
        case .thisMonth: "This month"
        case .earlier: "Earlier"
        }
    }
}

public struct SessionDateGrouper: Sendable {
    private let clock: any Clock
    private let calendar: Calendar

    public init(clock: any Clock = SystemClock(), calendar: Calendar = .current) {
        self.clock = clock
        self.calendar = calendar
    }

    /// Group sessions into buckets, preserving the input order within each bucket.
    /// Pinned sessions form their own group at the top regardless of date.
    public func group(_ sessions: [ChatSessionRecord]) -> [(bucket: SessionDateBucket, sessions: [ChatSessionRecord])] {
        let now = clock.now
        var buckets: [SessionDateBucket: [ChatSessionRecord]] = [:]

        for session in sessions {
            let bucket: SessionDateBucket
            if session.isPinned {
                bucket = .pinned
            } else {
                bucket = self.bucket(for: session.updatedAt, relativeTo: now)
            }
            buckets[bucket, default: []].append(session)
        }

        return SessionDateBucket.allCases.compactMap { bucket -> (SessionDateBucket, [ChatSessionRecord])? in
            guard let entries = buckets[bucket], !entries.isEmpty else { return nil }
            return (bucket, entries)
        }
    }

    /// Compute the bucket for a date, taking the *day boundaries* of the user's calendar so
    /// "yesterday" at 23:59 counts as yesterday even if it was 24 minutes ago.
    public func bucket(for date: Date, relativeTo now: Date) -> SessionDateBucket {
        if calendar.isDate(date, inSameDayAs: now) {
            return .today
        }
        if calendar.isDate(date, inSameDayAs: now.addingTimeInterval(-86_400)) {
            return .yesterday
        }
        // Same-week / same-month checks are calendar-aware, not raw seconds.
        if let weekAgo = calendar.date(byAdding: .day, value: -7, to: now), date >= weekAgo {
            return .thisWeek
        }
        if let monthAgo = calendar.date(byAdding: .day, value: -30, to: now), date >= monthAgo {
            return .thisMonth
        }
        return .earlier
    }
}
