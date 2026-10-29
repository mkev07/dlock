import AppKit

@main struct AboutFlagTooltipChecks {
    @MainActor static func main() {
        let formatter = ISO8601DateFormatter()
        let morning = formatter.date(from: "2026-10-27T23:36:00Z")!
        precondition(AboutFlagTooltip.text(at: morning) == "🇲🇺 Mauritius GMT+4 • 3:36 AM")
        let afternoon = formatter.date(from: "2026-10-28T11:36:00Z")!
        precondition(AboutFlagTooltip.text(at: afternoon) == "🇲🇺 Mauritius GMT+4 • 3:36 PM")
        let midnight = formatter.date(from: "2026-10-28T20:00:00Z")!
        precondition(AboutFlagTooltip.text(at: midnight) == "🇲🇺 Mauritius GMT+4 • 12:00 AM")
        print("PASS: Mauritius time, bullet separator, AM/PM and midnight formatting")
    }
}
