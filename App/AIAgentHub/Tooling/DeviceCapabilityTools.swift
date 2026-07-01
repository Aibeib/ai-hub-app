import Foundation
import AIAgentHubCore
#if canImport(EventKit)
import EventKit
#endif
#if canImport(UserNotifications)
import UserNotifications
#endif
#if canImport(UIKit)
import UIKit
#endif

/// Tools that grant the assistant safe, scoped access to on-device capabilities — local
/// reminders, calendar events, the app sandbox file area, and "launch an installed app /
/// dial a number / draft an SMS or email" via URL schemes. Each tool is marked
/// `riskLevel: .high` so the existing `ToolAuthorization` pipeline asks the user to
/// approve before the side-effect happens. Info.plist usage descriptions and the
/// `LSApplicationQueriesSchemes` allowlist live in `project.pbxproj` (search for
/// `INFOPLIST_KEY_LSApplicationQueriesSchemes`).
///
/// We never read the user's existing events, reminders, or installed-app catalogue —
/// these tools are *write-only* helpers ("schedule X", "remind me at Y", "open WeChat",
/// "call mom"). Read-back would be a separate set of tools with a separate authorization
/// story.
enum DeviceCapabilityTools {
    static func makeAll() -> [any Tool] {
        var tools: [any Tool] = [
            CreateAlarmTool(),
            SaveFileTool()
        ]
        #if canImport(EventKit)
        tools.append(CreateCalendarEventTool())
        #endif
        #if canImport(UIKit)
        tools.append(contentsOf: [
            OpenAppTool(),
            MakePhoneCallTool(),
            SendSMSTool(),
            ComposeEmailTool()
        ] as [any Tool])
        #endif
        return tools
    }
}

// MARK: - Alarms (local notifications)

/// Schedules a one-shot local notification at the supplied date. Implemented via
/// UserNotifications rather than the Clock app because the Clock app exposes no public
/// API for adding alarms — Apple-sanctioned third-party "alarms" are local notifications
/// with a Critical-Alert-style sound. We default to the standard alert sound to stay out
/// of the Critical Alert entitlement path.
struct CreateAlarmTool: Tool {
    let definition = ToolDefinition(
        name: "create_alarm",
        description: "Schedules a one-shot alarm/reminder via the iOS notification system. Use when the user asks 'remind me at X' or 'wake me up at Y'. The `fire_at` parameter must be an ISO-8601 timestamp in the user's local time. Returns the notification id so it can be cancelled later.",
        parameters: [
            ToolParameter(name: "title", type: .string, isRequired: true),
            ToolParameter(name: "body", type: .string, isRequired: false),
            ToolParameter(name: "fire_at", type: .string, isRequired: true)
        ]
    )
    let riskLevel: ToolRiskLevel = .high

    func execute(arguments: [String: ToolArgument]) async throws -> ToolResult {
        guard case let .string(title) = arguments["title"], !title.isEmpty else {
            return ToolResult(displayText: "create_alarm needs a non-empty `title`.")
        }
        guard case let .string(fireAtRaw) = arguments["fire_at"], !fireAtRaw.isEmpty else {
            return ToolResult(displayText: "create_alarm needs a `fire_at` ISO-8601 timestamp.")
        }
        let body: String
        if case let .string(b) = arguments["body"] {
            body = b
        } else {
            body = ""
        }

        guard var fireDate = Self.parseISODate(fireAtRaw) else {
            return ToolResult(displayText: "create_alarm couldn't parse `fire_at`=\"\(fireAtRaw)\". Use ISO-8601, e.g. 2026-06-25T07:30:00+08:00.")
        }
        // The model sometimes names a clock time that has already passed today (e.g. the
        // user says "8am" mid-afternoon). Rather than failing — which surfaces to the user
        // as a confusing error — roll forward exactly 24 hours so the alarm fires at the
        // same clock time tomorrow. We only auto-correct when the requested moment is less
        // than a full day in the past; anything further back is almost certainly a model
        // mistake and we surface it as an error instead.
        let now = Date()
        if fireDate < now {
            let secondsBehind = now.timeIntervalSince(fireDate)
            if secondsBehind < 86_400 {
                fireDate = fireDate.addingTimeInterval(86_400)
            } else {
                return ToolResult(displayText: "create_alarm refused: \(fireAtRaw) is more than a day in the past. Pick a future time.")
            }
        }

        #if canImport(UserNotifications)
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            guard granted else {
                return ToolResult(displayText: "create_alarm needs notification permission. Open Settings → Notifications → AI Agent Hub and re-try.")
            }
        } catch {
            return ToolResult(displayText: "create_alarm couldn't request notification permission: \(error.localizedDescription)")
        }

        let content = UNMutableNotificationContent()
        content.title = title
        if !body.isEmpty {
            content.body = body
        }
        content.sound = .default

        let triggerComponents = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: fireDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComponents, repeats: false)
        let id = UUID().uuidString
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)

        do {
            try await center.add(request)
        } catch {
            return ToolResult(displayText: "create_alarm failed to schedule: \(error.localizedDescription)")
        }
        let display = ISO8601DateFormatter().string(from: fireDate)

        // iOS exposes no public API to write a real alarm into the Clock app — only local
        // notifications. So after scheduling the notification we also drop the user into
        // the Clock app's alarm tab via the `clock-alarm://` scheme (iOS 17+) so they can
        // add a persistent system alarm for the same time in one tap. The notification is
        // the reliable fallback; the Clock-app jump is a convenience. Opening is best-
        // effort — if the scheme isn't available we still report success on the notification.
        #if canImport(UIKit)
        let openedClock = await Self.openClockAppAlarms()
        let clockLine = openedClock
            ? " Also opened the Clock app's alarm tab so you can add a persistent system alarm at the same time."
            : " You can also add a permanent alarm in the Clock app manually."
        #else
        let clockLine = ""
        #endif

        return ToolResult(
            displayText: "Scheduled alarm \"\(title)\" for \(display). Notification id: \(id).\(clockLine)",
            metadata: ["notification_id": id]
        )
        #else
        return ToolResult(displayText: "create_alarm is not available on this platform.")
        #endif
    }

    /// Parse an ISO-8601 string. We accept both the strict variant and the lenient
    /// "no timezone offset → treat as local time" form because most LLMs hand back
    /// `2026-06-25T07:30:00` without a zone.
    private static func parseISODate(_ raw: String) -> Date? {
        let withZone = ISO8601DateFormatter()
        withZone.formatOptions = [.withInternetDateTime]
        if let date = withZone.date(from: raw) {
            return date
        }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: raw) {
            return date
        }
        // Fall back to "yyyy-MM-ddTHH:mm:ss" in the current locale's timezone.
        let local = DateFormatter()
        local.locale = Locale(identifier: "en_US_POSIX")
        local.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        local.timeZone = TimeZone.current
        return local.date(from: raw)
    }

    #if canImport(UIKit)
    /// Best-effort jump to the Clock app's alarm tab. `clock-alarm://` opens the Clock
    /// app directly on the Alarms screen on iOS 17+; on older OS versions or where the
    /// scheme isn't registered it quietly no-ops. Must run on the main actor because
    /// `UIApplication.open` is main-actor-isolated.
    @MainActor
    private static func openClockAppAlarms() async -> Bool {
        guard let url = URL(string: "clock-alarm://") else { return false }
        let app = UIApplication.shared
        guard app.canOpenURL(url) else { return false }
        return await app.open(url, options: [:])
    }
    #endif
}

// MARK: - Calendar events

#if canImport(EventKit)
/// Adds an event to the user's default calendar via EventKit. Read access is *not*
/// requested — we never enumerate the user's existing events. The Info.plist
/// `NSCalendarsWriteOnlyAccessUsageDescription` is what iOS shows in the permission
/// prompt.
struct CreateCalendarEventTool: Tool {
    let definition = ToolDefinition(
        name: "create_calendar_event",
        description: "Adds an event to the user's default calendar. Use when the user asks 'schedule a meeting / put it on my calendar'. `starts_at` and `ends_at` are ISO-8601 timestamps; if the model omits `ends_at` we default to 1 hour after start.",
        parameters: [
            ToolParameter(name: "title", type: .string, isRequired: true),
            ToolParameter(name: "starts_at", type: .string, isRequired: true),
            ToolParameter(name: "ends_at", type: .string, isRequired: false),
            ToolParameter(name: "location", type: .string, isRequired: false),
            ToolParameter(name: "notes", type: .string, isRequired: false)
        ]
    )
    let riskLevel: ToolRiskLevel = .high

    init() {}

    func execute(arguments: [String: ToolArgument]) async throws -> ToolResult {
        // Build a fresh EKEventStore per call. `EKEventStore` is not `Sendable`, so
        // storing one on the tool would either require unsafe annotations or a global
        // actor. Allocation is cheap relative to the user-visible permission prompt that
        // follows, so this is fine.
        let store = EKEventStore()
        guard case let .string(title) = arguments["title"], !title.isEmpty else {
            return ToolResult(displayText: "create_calendar_event needs a non-empty `title`.")
        }
        guard case let .string(startsRaw) = arguments["starts_at"], !startsRaw.isEmpty else {
            return ToolResult(displayText: "create_calendar_event needs a `starts_at` ISO-8601 timestamp.")
        }
        guard let startDate = CreateAlarmTool.parseISO(startsRaw) else {
            return ToolResult(displayText: "create_calendar_event couldn't parse `starts_at`=\"\(startsRaw)\". Use ISO-8601 (e.g. 2026-06-25T15:00:00+08:00).")
        }
        let endDate: Date
        if case let .string(endRaw) = arguments["ends_at"], !endRaw.isEmpty {
            guard let parsed = CreateAlarmTool.parseISO(endRaw) else {
                return ToolResult(displayText: "create_calendar_event couldn't parse `ends_at`=\"\(endRaw)\".")
            }
            endDate = parsed
        } else {
            endDate = startDate.addingTimeInterval(3600)
        }
        guard endDate > startDate else {
            return ToolResult(displayText: "create_calendar_event refused: ends_at must be after starts_at.")
        }

        // Request write-only access. iOS 17+ surfaces this as a separate prompt from full
        // calendar access; the API call is the same.
        do {
            if #available(iOS 17.0, *) {
                let granted = try await store.requestWriteOnlyAccessToEvents()
                guard granted else {
                    return ToolResult(displayText: "create_calendar_event needs calendar write access. Enable it in Settings → Privacy → Calendars → AI Agent Hub.")
                }
            } else {
                let granted = try await store.requestAccess(to: .event)
                guard granted else {
                    return ToolResult(displayText: "create_calendar_event needs calendar access.")
                }
            }
        } catch {
            return ToolResult(displayText: "create_calendar_event couldn't request calendar access: \(error.localizedDescription)")
        }

        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = startDate
        event.endDate = endDate
        if case let .string(location) = arguments["location"], !location.isEmpty {
            event.location = location
        }
        if case let .string(notes) = arguments["notes"], !notes.isEmpty {
            event.notes = notes
        }
        event.calendar = store.defaultCalendarForNewEvents

        do {
            try store.save(event, span: .thisEvent)
        } catch {
            return ToolResult(displayText: "create_calendar_event failed to save: \(error.localizedDescription)")
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return ToolResult(
            displayText: "Added \"\(title)\" to your calendar (\(formatter.string(from: startDate)) → \(formatter.string(from: endDate))).",
            metadata: ["event_id": event.eventIdentifier ?? ""]
        )
    }
}

private extension CreateAlarmTool {
    /// Static parser exposed for sibling tools so they don't each maintain their own copy.
    static func parseISO(_ raw: String) -> Date? {
        parseISODate(raw)
    }
}
#endif

// MARK: - Files (app sandbox only)

/// Writes a UTF-8 text file into the app's Documents directory. Constrained to the app
/// sandbox so we can't accidentally clobber anything outside; `filename` may contain a
/// relative path (subfolders are created on demand) but `..` segments are rejected.
struct SaveFileTool: Tool {
    let definition = ToolDefinition(
        name: "save_file",
        description: "Writes a UTF-8 text file into the app's Documents folder. Use when the user says 'save this as a file' or 'download it locally'. `filename` is a relative path under Documents (subfolders are created automatically); `..` is not allowed. Overwrites if the file already exists.",
        parameters: [
            ToolParameter(name: "filename", type: .string, isRequired: true),
            ToolParameter(name: "content", type: .string, isRequired: true)
        ]
    )
    let riskLevel: ToolRiskLevel = .high

    func execute(arguments: [String: ToolArgument]) async throws -> ToolResult {
        guard case let .string(filename) = arguments["filename"], !filename.isEmpty else {
            return ToolResult(displayText: "save_file needs a `filename`.")
        }
        guard case let .string(content) = arguments["content"] else {
            return ToolResult(displayText: "save_file needs `content` (a UTF-8 string).")
        }
        let trimmedFilename = filename.trimmingCharacters(in: .whitespaces)
        // Defense in depth: reject any path component equal to ".." so the model can't
        // escape the sandbox via "../../../etc/passwd". The sandbox would block that
        // anyway, but failing loudly is better than the OS silently denying the write.
        let parts = trimmedFilename.split(separator: "/").map(String.init)
        if parts.contains("..") || parts.contains(".") || trimmedFilename.hasPrefix("/") {
            return ToolResult(displayText: "save_file refused: relative path components like \"..\" or absolute paths are not allowed.")
        }

        let documents: URL
        do {
            documents = try FileManager.default.url(
                for: .documentDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
        } catch {
            return ToolResult(displayText: "save_file couldn't locate the Documents folder: \(error.localizedDescription)")
        }

        let destination = documents.appendingPathComponent(trimmedFilename)
        let parent = destination.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            try content.data(using: .utf8)?.write(to: destination, options: .atomic)
        } catch {
            return ToolResult(displayText: "save_file failed: \(error.localizedDescription)")
        }
        let bytes = content.utf8.count
        return ToolResult(
            displayText: "Saved \(bytes) bytes to Documents/\(trimmedFilename).",
            metadata: ["path": destination.path, "bytes": String(bytes)]
        )
    }
}

// MARK: - App launch / phone / SMS / email (URL schemes)

#if canImport(UIKit)

/// Curated map of "common app name" → URL scheme. iOS won't let us scan installed apps
/// without entitlements, so we ship a hand-picked allowlist of well-known consumer apps
/// the user is likely to ask about (WeChat / Alipay / Maps / Spotify / etc.). Each entry
/// here MUST also appear in `LSApplicationQueriesSchemes` in the project's Info.plist
/// (see project.pbxproj) or `UIApplication.canOpenURL` returns false even when the app
/// is installed.
///
/// Keys are normalised to lowercase ASCII so "WeChat", "wechat", and "微信" all resolve.
private enum AppLauncherCatalog {
    /// Single deep-link URL for an app — `scheme://` is sufficient to launch it at its
    /// home screen; deeper paths (search, share-sheet) are app-specific and out of scope
    /// here.
    static let map: [String: String] = [
        // Chat & social
        "wechat": "weixin://",
        "微信": "weixin://",
        "qq": "mqq://",
        "weibo": "sinaweibo://",
        "微博": "sinaweibo://",
        "line": "line://",
        "whatsapp": "whatsapp://",
        "telegram": "tg://",
        "messenger": "fb-messenger://",
        "zoom": "zoomus://",

        // Payments
        "alipay": "alipay://",
        "支付宝": "alipay://",

        // Maps
        "apple maps": "maps://",
        "maps": "maps://",
        "苹果地图": "maps://",
        "google maps": "comgooglemaps://",
        "百度地图": "baidumap://",
        "高德": "iosamap://",
        "高德地图": "iosamap://",

        // Media — global
        "apple music": "music://",
        "spotify": "spotify://",
        "netflix": "nflx://",
        "youtube": "youtube://",
        "bilibili": "bilibili://",
        "b站": "bilibili://",
        "哔哩哔哩": "bilibili://",

        // Media — China
        // Each one verified against the publicly-documented scheme. Some apps publish
        // multiple schemes; we pick the most stable. All schemes here must also appear
        // in the Info.plist LSApplicationQueriesSchemes list (see project.pbxproj).
        "网易云": "orpheus://",
        "网易云音乐": "orpheus://",
        "netease music": "orpheus://",
        "neteasemusic": "orpheus://",
        "qq音乐": "qqmusic://",
        "qq music": "qqmusic://",
        "酷狗": "kugou://",
        "酷狗音乐": "kugou://",
        "酷我": "kwapp://",
        "酷我音乐": "kwapp://",
        "tiktok": "snssdk1233://",
        "抖音": "snssdk1128://",
        "douyin": "snssdk1128://",
        "快手": "kwai://",
        "kuaishou": "kwai://",
        "小红书": "xhsdiscover://",
        "xiaohongshu": "xhsdiscover://",
        "rednote": "xhsdiscover://",
        "西瓜视频": "snssdk32://",
        "今日头条": "snssdk141://",
        "toutiao": "snssdk141://",

        // Shopping & local
        "taobao": "taobao://",
        "淘宝": "taobao://",
        "天猫": "tmall://",
        "tmall": "tmall://",
        "jd": "openapp.jdmobile://",
        "京东": "openapp.jdmobile://",
        "拼多多": "pinduoduo://",
        "pdd": "pinduoduo://",
        "pinduoduo": "pinduoduo://",
        "大众点评": "dianping://",
        "dianping": "dianping://",
        "美团": "imeituan://",
        "meituan": "imeituan://",
        "饿了么": "eleme://",
        "eleme": "eleme://",
        "ele.me": "eleme://",
        "ctrip": "ctripcomh5://",
        "携程": "ctripcomh5://",
        "去哪儿": "qunariphone://",
        "qunar": "qunariphone://",
        "12306": "cn.12306://",
        "铁路12306": "cn.12306://",
        "sf express": "sf-express://",
        "顺丰": "sf-express://",
        "顺丰速运": "sf-express://",
        "菜鸟": "cainiao://",
        "菜鸟裹裹": "cainiao://",

        // Ride & travel
        "滴滴": "diditaxi://",
        "didi": "diditaxi://",
        "uber": "uber://",

        // Productivity
        "feishu": "feishu://",
        "飞书": "feishu://",
        "lark": "feishu://",
        "dingtalk": "dingtalk://",
        "钉钉": "dingtalk://",
        "wework": "wxwork://",
        "企业微信": "wxwork://",
        "notion": "notion://",
        "slack": "slack://",
        "linkedin": "linkedin://",

        // Browsers (occasionally users ask "在 Chrome 里打开 …")
        "chrome": "googlechrome://",
        "edge": "microsoft-edge://",
        "firefox": "firefox://",

        // System
        "settings": "App-Prefs:",
        "设置": "App-Prefs:",
        "system settings": "App-Prefs:"
    ]

    static func resolve(_ name: String) -> URL? {
        let key = name.trimmingCharacters(in: .whitespaces).lowercased()
        guard let raw = map[key] else { return nil }
        return URL(string: raw)
    }

    static var knownNames: [String] {
        Array(Set(map.keys)).sorted()
    }
}

/// Launches a known app via its URL scheme. Tool naming kept neutral (`open_app`) rather
/// than vendor-specific (`open_wechat`) so the assistant just picks the right argument
/// — the catalogue lookup is the only thing that's vendor-specific.
struct OpenAppTool: Tool {
    let definition = ToolDefinition(
        name: "open_app",
        description: "Launches a known consumer app installed on the user's iPhone via its URL scheme. Use when the user says 'open X' or 'launch X' where X is an app like WeChat, Alipay, Maps, Spotify, etc. `app_name` accepts common English or Chinese names — \"wechat\", \"微信\", \"alipay\", \"支付宝\", \"apple maps\", \"spotify\", and so on. Returns an error if the app isn't on the curated allowlist or isn't installed.",
        parameters: [
            ToolParameter(name: "app_name", type: .string, isRequired: true)
        ]
    )
    let riskLevel: ToolRiskLevel = .high

    func execute(arguments: [String: ToolArgument]) async throws -> ToolResult {
        guard case let .string(name) = arguments["app_name"], !name.isEmpty else {
            return ToolResult(displayText: "open_app needs an `app_name` (e.g. \"wechat\", \"alipay\", \"spotify\").")
        }
        guard let url = AppLauncherCatalog.resolve(name) else {
            let known = AppLauncherCatalog.knownNames.prefix(20).joined(separator: ", ")
            return ToolResult(
                displayText: "open_app: \"\(name)\" isn't in the known-app list. Known names include: \(known) …"
            )
        }
        return try await openOnMainActor(url: url, label: name)
    }

    @MainActor
    private func openOnMainActor(url: URL, label: String) async -> ToolResult {
        let app = UIApplication.shared
        guard app.canOpenURL(url) else {
            return ToolResult(
                displayText: "open_app: \"\(label)\" doesn't appear to be installed on this device. (URL scheme \(url.scheme ?? "?") returned false from canOpenURL.)"
            )
        }
        let opened = await app.open(url, options: [:])
        if opened {
            return ToolResult(
                displayText: "Opened \(label).",
                metadata: ["url": url.absoluteString]
            )
        } else {
            return ToolResult(displayText: "open_app: iOS refused to open \(label). Try again from the home screen.")
        }
    }
}

/// Initiates a phone call by dialling `tel:<number>`. iOS shows the system call sheet —
/// we don't bypass that, so the user still confirms the call from the Phone UI. The tool
/// is still high-risk because the user shouldn't have to recover from the assistant
/// dialling random numbers without their say.
struct MakePhoneCallTool: Tool {
    let definition = ToolDefinition(
        name: "make_phone_call",
        description: "Starts a phone call to the supplied number. iOS shows its standard call-confirmation sheet before the call connects. Use when the user says 'call X' or 'dial Y'. `number` should include the country code (e.g. +14155551212) or be a local number iOS can resolve.",
        parameters: [
            ToolParameter(name: "number", type: .string, isRequired: true)
        ]
    )
    let riskLevel: ToolRiskLevel = .high

    func execute(arguments: [String: ToolArgument]) async throws -> ToolResult {
        guard case let .string(raw) = arguments["number"], !raw.isEmpty else {
            return ToolResult(displayText: "make_phone_call needs a `number`.")
        }
        // Strip whitespace + visual separators iOS does NOT accept inside tel: URLs.
        let allowed = CharacterSet(charactersIn: "0123456789+#*,")
        let sanitised = raw.unicodeScalars.filter { allowed.contains($0) }.map(String.init).joined()
        guard !sanitised.isEmpty,
              let url = URL(string: "tel:\(sanitised)") else {
            return ToolResult(displayText: "make_phone_call: \"\(raw)\" doesn't look like a dialable number.")
        }
        return await launch(url: url, summary: "Calling \(raw)…")
    }

    @MainActor
    private func launch(url: URL, summary: String) async -> ToolResult {
        let app = UIApplication.shared
        guard app.canOpenURL(url) else {
            return ToolResult(displayText: "make_phone_call: this device can't place phone calls (likely an iPad without cellular).")
        }
        let opened = await app.open(url, options: [:])
        return opened
            ? ToolResult(displayText: summary, metadata: ["url": url.absoluteString])
            : ToolResult(displayText: "make_phone_call: iOS refused to launch the call sheet.")
    }
}

/// Opens the Messages app pre-filled with a draft SMS. iOS does NOT allow third-party
/// apps to *send* SMS silently — the user has to tap "Send" inside the Messages
/// composer. That's exactly what we want for safety.
struct SendSMSTool: Tool {
    let definition = ToolDefinition(
        name: "send_sms",
        description: "Opens the Messages app pre-filled with an SMS draft. The user still has to tap Send inside Messages (iOS sandbox doesn't allow silent SMS from third-party apps). Use when the user says 'text X' or 'send a message to Y'. `number` is the recipient; `body` is optional draft text.",
        parameters: [
            ToolParameter(name: "number", type: .string, isRequired: true),
            ToolParameter(name: "body", type: .string, isRequired: false)
        ]
    )
    let riskLevel: ToolRiskLevel = .high

    func execute(arguments: [String: ToolArgument]) async throws -> ToolResult {
        guard case let .string(number) = arguments["number"], !number.isEmpty else {
            return ToolResult(displayText: "send_sms needs a `number`.")
        }
        let body: String
        if case let .string(b) = arguments["body"], !b.isEmpty {
            body = b
        } else {
            body = ""
        }
        // `sms:NUMBER&body=TEXT` — Apple's documented form. URL-encode the body.
        var components = URLComponents()
        components.scheme = "sms"
        components.path = number
        if !body.isEmpty {
            components.queryItems = [URLQueryItem(name: "body", value: body)]
        }
        guard let url = components.url else {
            return ToolResult(displayText: "send_sms: couldn't build a valid sms: URL.")
        }
        return await launch(url: url, summary: "Opened Messages with a draft to \(number).")
    }

    @MainActor
    private func launch(url: URL, summary: String) async -> ToolResult {
        let app = UIApplication.shared
        guard app.canOpenURL(url) else {
            return ToolResult(displayText: "send_sms: this device can't send SMS.")
        }
        let opened = await app.open(url, options: [:])
        return opened
            ? ToolResult(displayText: summary, metadata: ["url": url.absoluteString])
            : ToolResult(displayText: "send_sms: iOS refused to launch the Messages composer.")
    }
}

/// Opens the Mail composer (or the user's default mail app) with a pre-filled draft via
/// `mailto:`. Same safety guarantee as SMS: the user still has to tap Send.
struct ComposeEmailTool: Tool {
    let definition = ToolDefinition(
        name: "compose_email",
        description: "Opens the user's mail app pre-filled with a draft email. The user still has to tap Send inside Mail. Use when the user says 'email X' or 'send a note to Y'. `to` is the recipient address; `subject` and `body` are optional draft fields.",
        parameters: [
            ToolParameter(name: "to", type: .string, isRequired: true),
            ToolParameter(name: "subject", type: .string, isRequired: false),
            ToolParameter(name: "body", type: .string, isRequired: false)
        ]
    )
    let riskLevel: ToolRiskLevel = .high

    func execute(arguments: [String: ToolArgument]) async throws -> ToolResult {
        guard case let .string(to) = arguments["to"], !to.isEmpty else {
            return ToolResult(displayText: "compose_email needs a `to` address.")
        }
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = to
        var queryItems: [URLQueryItem] = []
        if case let .string(subject) = arguments["subject"], !subject.isEmpty {
            queryItems.append(URLQueryItem(name: "subject", value: subject))
        }
        if case let .string(body) = arguments["body"], !body.isEmpty {
            queryItems.append(URLQueryItem(name: "body", value: body))
        }
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        guard let url = components.url else {
            return ToolResult(displayText: "compose_email: couldn't build a valid mailto: URL.")
        }
        return await launch(url: url, summary: "Opened Mail with a draft to \(to).")
    }

    @MainActor
    private func launch(url: URL, summary: String) async -> ToolResult {
        let app = UIApplication.shared
        guard app.canOpenURL(url) else {
            return ToolResult(displayText: "compose_email: no mail app is configured on this device.")
        }
        let opened = await app.open(url, options: [:])
        return opened
            ? ToolResult(displayText: summary, metadata: ["url": url.absoluteString])
            : ToolResult(displayText: "compose_email: iOS refused to launch the mail composer.")
    }
}

#endif
