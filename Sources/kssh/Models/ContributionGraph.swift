import Foundation

/// A single day in a contribution calendar: its date, the contribution count, and a
/// 0–4 intensity level used to pick the heatmap cell color.
struct ContributionDay: Equatable {
    let date: Date
    let count: Int
    /// 0 = none, 1–4 = increasing intensity (mirrors GitHub's 5-bucket scale).
    let level: Int
}

/// A contribution calendar as a grid of weeks, each week an array of (up to) 7 days
/// ordered Sunday→Saturday — the same shape GitHub's GraphQL `contributionCalendar`
/// returns. The heatmap renders one column per week.
struct ContributionGraph: Equatable {
    let weeks: [[ContributionDay]]

    var totalContributions: Int {
        weeks.flatMap { $0 }.reduce(0) { $0 + $1.count }
    }

    /// The trailing `count` weeks, so a full-year calendar can be trimmed to fit the
    /// narrow popover (default 13 ≈ last 3 months). Pure and testable.
    func recent(weeks count: Int) -> ContributionGraph {
        guard weeks.count > count else { return self }
        return ContributionGraph(weeks: Array(weeks.suffix(count)))
    }

    /// Buckets a contribution count into a 0–4 intensity level. Used when mapping the
    /// GraphQL response (which also returns a `color`, but a numeric bucket keeps the
    /// rendering independent of GitHub's palette).
    static func level(forCount count: Int) -> Int {
        switch count {
        case 0: return 0
        case 1...2: return 1
        case 3...5: return 2
        case 6...9: return 3
        default: return 4
        }
    }
}
