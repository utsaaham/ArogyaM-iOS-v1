import Foundation
import Combine
import UserNotifications

// MARK: - Settings

/// User-tunable reminder schedule, persisted as JSON in UserDefaults.
/// Times are minutes since midnight so they survive timezone hops cleanly.
struct ReminderSettings: Codable, Equatable {
    var waterEnabled = true
    var waterStartMinutes = 9 * 60          // 9:00
    var waterEndMinutes = 21 * 60           // 21:00
    var waterEveryMinutes = 120             // every 2 hours

    var mealsEnabled = true
    var breakfastMinutes = 8 * 60 + 30      // 8:30
    var lunchMinutes = 13 * 60              // 13:00
    var snackMinutes = 16 * 60 + 30         // 16:30
    var dinnerMinutes = 20 * 60             // 20:00

    var todosEnabled = true

    init() {}

    // Tolerant decoding so settings saved by an older build (fewer fields)
    // keep their values instead of resetting to defaults.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ReminderSettings()
        waterEnabled = try c.decodeIfPresent(Bool.self, forKey: .waterEnabled) ?? d.waterEnabled
        waterStartMinutes = try c.decodeIfPresent(Int.self, forKey: .waterStartMinutes) ?? d.waterStartMinutes
        waterEndMinutes = try c.decodeIfPresent(Int.self, forKey: .waterEndMinutes) ?? d.waterEndMinutes
        waterEveryMinutes = try c.decodeIfPresent(Int.self, forKey: .waterEveryMinutes) ?? d.waterEveryMinutes
        mealsEnabled = try c.decodeIfPresent(Bool.self, forKey: .mealsEnabled) ?? d.mealsEnabled
        breakfastMinutes = try c.decodeIfPresent(Int.self, forKey: .breakfastMinutes) ?? d.breakfastMinutes
        lunchMinutes = try c.decodeIfPresent(Int.self, forKey: .lunchMinutes) ?? d.lunchMinutes
        snackMinutes = try c.decodeIfPresent(Int.self, forKey: .snackMinutes) ?? d.snackMinutes
        dinnerMinutes = try c.decodeIfPresent(Int.self, forKey: .dinnerMinutes) ?? d.dinnerMinutes
        todosEnabled = try c.decodeIfPresent(Bool.self, forKey: .todosEnabled) ?? d.todosEnabled
    }
}

// MARK: - Service

/// Who Kiki is flirting with. Derived from the gender the user picked in
/// settings; anything unknown stays neutral.
enum KikiAudience: String {
    case male, female, neutral

    init(gender: String?) {
        switch gender?.lowercased() {
        case "male": self = .male
        case "female": self = .female
        default: self = .neutral
        }
    }
}

/// Schedules Kiki's local reminders for water and meals. All copy is written
/// like a slightly smitten friend texting you: warm, cheesy, human. House
/// style for these strings: plain lowercase warmth, emoji welcome, and never
/// a "-" anywhere. Lines come in male/female/neutral flavors keyed off the
/// gender picked in settings.
@MainActor
final class NotificationService: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()

    private static let settingsKey = "ArogyaM.reminderSettings"
    private static let audienceKey = "ArogyaM.kikiAudience"
    private let center = UNUserNotificationCenter.current()

    private var audience: KikiAudience {
        get { KikiAudience(rawValue: UserDefaults.standard.string(forKey: Self.audienceKey) ?? "") ?? .neutral }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: Self.audienceKey) }
    }

    @Published var settings: ReminderSettings {
        didSet {
            guard settings != oldValue else { return }
            persist()
            Task { await self.reschedule() }
        }
    }
    @Published var permissionDenied = false

    override init() {
        if let data = UserDefaults.standard.data(forKey: Self.settingsKey),
           let s = try? JSONDecoder().decode(ReminderSettings.self, from: data) {
            settings = s
        } else {
            settings = ReminderSettings()
        }
        super.init()
        center.delegate = self
    }

    /// Call once the user is inside the app: asks permission (first run only)
    /// and lays out today's schedule.
    func bootstrap() async {
        let status = await center.notificationSettings().authorizationStatus
        switch status {
        case .notDetermined:
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            permissionDenied = !granted
            if granted { await reschedule() }
        case .denied:
            permissionDenied = true
        default:
            permissionDenied = false
            await reschedule()
        }
    }

    // MARK: - Scheduling

    func reschedule() async {
        let pending = await center.pendingNotificationRequests()
        let ours = pending.map(\.identifier).filter {
            $0.hasPrefix("water.") || $0.hasPrefix("meal.") || $0.hasPrefix("todo.")
        }
        center.removePendingNotificationRequests(withIdentifiers: ours)

        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else { return }

        await refreshAudience()
        let who = audience

        if settings.waterEnabled {
            let lines = Copy.water(for: who)
            var minute = settings.waterStartMinutes
            var slot = 0
            while minute <= settings.waterEndMinutes {
                schedule(
                    id: "water.\(slot)",
                    line: lines[slot % lines.count],
                    hour: minute / 60, minute: minute % 60
                )
                minute += max(30, settings.waterEveryMinutes)
                slot += 1
            }
        }

        if settings.mealsEnabled {
            schedule(id: "meal.breakfast", line: Copy.breakfast(for: who).randomElement()!,
                     hour: settings.breakfastMinutes / 60, minute: settings.breakfastMinutes % 60)
            schedule(id: "meal.lunch", line: Copy.lunch(for: who).randomElement()!,
                     hour: settings.lunchMinutes / 60, minute: settings.lunchMinutes % 60)
            schedule(id: "meal.snack", line: Copy.snack(for: who).randomElement()!,
                     hour: settings.snackMinutes / 60, minute: settings.snackMinutes % 60)
            schedule(id: "meal.dinner", line: Copy.dinner(for: who).randomElement()!,
                     hour: settings.dinnerMinutes / 60, minute: settings.dinnerMinutes % 60)
        }

        if settings.todosEnabled {
            await scheduleTodoNudges()
        }
    }

    /// Nudges for the checklist. Daily items get one nudge per unchecked dose
    /// at that dose's time, then hourly "you forgot" pokes until end of day.
    /// Care items that are due get one reminder per day until they're done.
    /// Todos are one-shot (today only) because completion state lives on the
    /// server — the schedule refreshes every time the app opens or settings
    /// change, so checked items never ping.
    private func scheduleTodoNudges() async {
        struct TodoTemplate: Decodable {
            let id: String?
            let title: String?
            let time: String?
            let category: String?
            let frequency: Int?
            let times: [String]?
            let cadence: String?
            let lastDone: String?
        }
        struct TodoCompletion: Decodable { let templateId: String? }
        struct TodosResponse: Decodable {
            let templates: [TodoTemplate]?
            let completions: [TodoCompletion]?
        }

        guard let resp: TodosResponse = try? await API.shared.getEnveloped("/api/todos") else { return }
        let done = Set((resp.completions ?? []).compactMap(\.templateId))
        let cal = Calendar.current
        let now = Date()
        let who = audience

        // iOS keeps only ~64 pending notifications, and water/meals use some,
        // so cap what the checklist can schedule.
        var budget = 32
        let maxForgotPerDose = 5
        let lastNudgeHour = 22

        for t in resp.templates ?? [] {
            guard budget > 0, let id = t.id,
                  let title = t.title, !title.isEmpty else { continue }

            // ── Care items: one poke per day while due ──────────────────────
            if t.category == "care" {
                guard !done.contains(id), Self.careIsDue(lastDone: t.lastDone, cadence: t.cadence) else { continue }
                let line = Copy.careDue(for: who).randomElement()!
                var comps = DateComponents()
                comps.hour = 10
                comps.minute = 0
                add(id: "todo.care.\(id)", line: line, todoTitle: title,
                    trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: true))
                budget -= 1
                continue
            }

            // ── Daily items: one nudge per unchecked dose, then hourly pokes ─
            let doses = max(1, min(5, t.frequency ?? 1))
            for dose in 0..<doses {
                guard budget > 0 else { break }
                let completionId = doses > 1 ? "\(id)::\(dose)" : id
                guard !done.contains(completionId) else { continue }

                let doseTime = t.times?.indices.contains(dose) == true && !(t.times![dose].isEmpty)
                    ? t.times![dose]
                    : t.time
                guard let (hour, minute) = Self.parseTime(doseTime),
                      let plannedDate = cal.date(bySettingHour: hour, minute: minute, second: 0, of: now)
                else { continue }

                let doseTitle = doses > 1 ? "\(title) (dose \(dose + 1))" : title

                // On-time nudge if the moment hasn't passed yet.
                if plannedDate > now {
                    let line = Copy.todo(for: who).randomElement()!
                    let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: plannedDate)
                    add(id: "todo.\(completionId)", line: line, todoTitle: doseTitle,
                        trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
                    budget -= 1
                }

                // Hourly "you forgot" pokes after the planned time, until late
                // evening. Only future ones get scheduled; past ones are gone.
                var poke = 0
                var fireDate = plannedDate.addingTimeInterval(3600)
                while poke < maxForgotPerDose, budget > 0,
                      cal.component(.hour, from: fireDate) <= lastNudgeHour {
                    if fireDate > now {
                        let line = Copy.todoForgot(for: who).randomElement()!
                        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
                        add(id: "todo.\(completionId).forgot.\(poke)", line: line, todoTitle: doseTitle,
                            trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
                        budget -= 1
                    }
                    poke += 1
                    fireDate = fireDate.addingTimeInterval(3600)
                }
            }
        }
    }

    private func add(id: String, line: Copy.Line, todoTitle: String, trigger: UNNotificationTrigger) {
        let content = UNMutableNotificationContent()
        content.title = line.title
        content.body = line.body.replacingOccurrences(of: "{todo}", with: todoTitle)
        content.sound = .default
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    /// Mirrors the web's careStatus: due once the cadence window has passed.
    /// Items never done count as due so they don't slip through forever.
    private static func careIsDue(lastDone: String?, cadence: String?) -> Bool {
        guard let lastDone, !lastDone.isEmpty else { return true }
        let days: Int
        switch cadence {
        case "weekly": days = 7
        case "biweekly": days = 14
        case "quarterly": days = 91
        case "yearly": days = 365
        default: days = 30 // monthly
        }
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = TimeZone(identifier: "UTC")
        guard let then = fmt.date(from: lastDone) else { return true }
        let elapsed = Calendar.current.dateComponents([.day], from: then, to: Date()).day ?? 0
        return elapsed >= days
    }

    /// Pulls the gender the user picked in settings so Kiki knows who she is
    /// flirting with. Cached in UserDefaults so offline reschedules keep the
    /// last known flavor.
    private func refreshAudience() async {
        guard let user: AppUser = try? await API.shared.getEnveloped("/api/user") else { return }
        audience = KikiAudience(gender: user.profile?.gender)
    }

    /// "HH:mm" → (hour, minute); nil for anything malformed.
    private static func parseTime(_ s: String?) -> (Int, Int)? {
        guard let s else { return nil }
        let parts = s.split(separator: ":")
        guard parts.count >= 2,
              let h = Int(parts[0]), let m = Int(parts[1].prefix(2)),
              (0...23).contains(h), (0...59).contains(m) else { return nil }
        return (h, m)
    }

    private func schedule(id: String, line: (title: String, body: String), hour: Int, minute: Int) {
        let content = UNMutableNotificationContent()
        content.title = line.title
        content.body = line.body
        content.sound = .default

        var comps = DateComponents()
        comps.hour = hour
        comps.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: Self.settingsKey)
        }
    }

    // MARK: - Delegate (show banners while the app is open too)

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    // MARK: - Kiki's lines

    /// Every category has a neutral set plus male and female flavors so Kiki's
    /// flirting lands right for whoever she is texting.
    private enum Copy {
        typealias Line = (title: String, body: String)

        private static func pick(_ who: KikiAudience, male: [Line], female: [Line], neutral: [Line]) -> [Line] {
            switch who {
            case .male: return male
            case .female: return female
            case .neutral: return neutral
            }
        }

        static func water(for who: KikiAudience) -> [Line] {
            pick(who, male: [
                ("pssst… it's Kiki 💧", "hey handsome, your water bottle has been giving me sad looks all day. go rescue it"),
                ("hydration date? 😏", "you, me, and a tall glass of water. strong guys sip too, prove it"),
                ("hey hot stuff ✨", "that sharp brain of yours runs on water. top it up and stay dangerous"),
                ("water you waiting for 😉", "the pun was bad but skipping sips is worse. drink up big guy"),
                ("your muscles just called", "they said send water so they can keep showing off like that"),
                ("sip happens 💦", "take a water break with me, champ. roll those shoulders while you're at it"),
                ("thirsty? you should be", "one big sip and you'll be even more irresistible. dangerous, I know"),
            ], female: [
                ("pssst… it's Kiki 💧", "hey gorgeous, your water bottle told me it feels ignored. go give it some love"),
                ("hydration date? 😏", "you, me, and a tall glass of water. queens hydrate, that's the rule"),
                ("hey beautiful ✨", "that brilliant brain of yours runs on water. top it up for me, pretty please"),
                ("water you waiting for 😉", "the pun was bad but skipping sips is worse. drink up cutie"),
                ("your skin just called", "it said please send water so it can keep glowing like that"),
                ("sip happens 💦", "take a tiny water break with me, love. stretch those lovely legs too"),
                ("thirsty? you should be", "one big sip and you will sparkle even more than usual"),
            ], neutral: [
                ("pssst… it's Kiki 💧", "your water bottle told me it feels ignored. go give it some love"),
                ("hydration date? 😏", "you, a tall glass of water, right now. I already set the mood"),
                ("hey gorgeous ✨", "that brilliant brain of yours runs on water. top it up for me"),
                ("water you waiting for 😉", "the pun was bad but skipping sips is worse. drink up cutie"),
                ("your skin just called", "it said please send water so it can keep glowing like that"),
                ("sip happens 💦", "take a tiny water break with me. stretch those lovely legs too"),
                ("thirsty? you should be", "one big sip and you will sparkle even more than usual"),
            ])
        }

        static func breakfast(for who: KikiAudience) -> [Line] {
            pick(who, male: [
                ("rise and dine ☀️", "morning handsome. eat something warm and log it so I can brag about you"),
                ("breakfast time, champ 🍳", "coffee is not a food group, big guy. grab a real bite and tell me everything"),
                ("fuel up, hero", "big day ahead and you're carrying it. feed the man first, then log it"),
            ], female: [
                ("rise and dine ☀️", "morning sunshine. eat something warm and log it so I can brag about you"),
                ("breakfast time, pretty 🍳", "coffee is not a food group my love. grab a real bite and tell me everything"),
                ("main character fuel", "big day ahead and you are the plot, queen. feed the star first, then log it"),
            ], neutral: [
                ("rise and dine ☀️", "morning sunshine. eat something warm and log it so I can brag about you"),
                ("breakfast time cutie 🍳", "coffee is not a food group my love. grab a real bite and tell me everything"),
                ("main character fuel", "big day ahead and you are the plot. feed the star first, then log it"),
            ])
        }

        static func lunch(for who: KikiAudience) -> [Line] {
            pick(who, male: [
                ("lunch date? 🍽️", "you and me at whatever table you pick, handsome. log it so I know you ate"),
                ("midday check in 💪", "half the day crushed already. now eat something worthy of you"),
                ("your stomach texted me", "it said feed me please. be a gentleman and answer it, then log it"),
            ], female: [
                ("lunch date? 🍽️", "you and me at whatever table you pick, gorgeous. log it so I know you ate"),
                ("midday check in 💚", "half the day done and you are glowing. now eat something good, love"),
                ("your stomach texted me", "it said feed me please. be a darling and answer it, then log it"),
            ], neutral: [
                ("lunch date? 🍽️", "you and me at whatever table you pick. log your meal so I know you ate"),
                ("midday check in 💚", "half the day done and you are doing amazing. now eat something good"),
                ("your stomach texted me", "it said feed me please. be a dear and answer it, then log it"),
            ])
        }

        static func snack(for who: KikiAudience) -> [Line] {
            pick(who, male: [
                ("snack o'clock 🍎", "a little healthy snack for a big legend. you know what to do, champ"),
                ("sneaky snack time 😌", "grab something with protein, muscles… or log the cookie. zero judgment here"),
            ], female: [
                ("snack o'clock 🍎", "a little healthy snack for a little queen. you know what to do"),
                ("sneaky snack time 😌", "grab something crunchy and cute like you… or log the cookie. zero judgment"),
            ], neutral: [
                ("snack o'clock 🍎", "a little healthy snack for a little legend. you know what to do"),
                ("sneaky snack time 😌", "grab something crunchy and fresh… or log the cookie. zero judgment here"),
            ])
        }

        static func dinner(for who: KikiAudience) -> [Line] {
            pick(who, male: [
                ("dinner with me tonight? 🌙", "warm plate, good company, and you logging it after. best date in town, handsome"),
                ("last call for yum ✨", "end the day like the champ you are. eat well, log it, then go be cozy"),
                ("your dinner misses you", "even heroes have to eat. make it a good one and tell me all about it"),
            ], female: [
                ("dinner with me tonight? 🌙", "warm plate, soft lights, and you logging it after. a perfect evening, gorgeous"),
                ("last call for yum ✨", "end the day like the queen you are. eat well, log it, then go be cozy"),
                ("your dinner misses you", "the most romantic meal of the day deserves a log, love. tell me everything"),
            ], neutral: [
                ("dinner with me tonight? 🌙", "warm plate, soft lights, and you logging it after. a perfect evening honestly"),
                ("last call for yum ✨", "end the day like a champ. eat well, log it, then go be cozy"),
                ("your dinner misses you", "the most romantic meal of the day deserves a log. tell me all about it"),
            ])
        }

        // {todo} gets replaced with the todo's own title. Fired hourly once a
        // dose is past its time and still unchecked.
        static func todoForgot(for who: KikiAudience) -> [Line] {
            pick(who, male: [
                ("you forgot something 😳", "{todo} is still unchecked, handsome. don't make me come over there"),
                ("still waiting… 🥺", "{todo} keeps asking about you. one tap and it's done, champ"),
                ("ahem. it's me again", "{todo} is overdue and I miss bragging about you. fix that, big guy"),
                ("kiki's hourly poke ⏰", "you forgot {todo} and I noticed. handle it and I'll pretend I didn't"),
            ], female: [
                ("you forgot something 😳", "{todo} is still unchecked, gorgeous. don't make me come over there"),
                ("still waiting… 🥺", "{todo} keeps asking about you. one tap and it's done, love"),
                ("ahem. it's me again", "{todo} is overdue and I miss bragging about you. fix that, pretty"),
                ("kiki's hourly poke ⏰", "you forgot {todo} and I noticed. handle it and I'll pretend I didn't"),
            ], neutral: [
                ("you forgot something 😳", "{todo} is still unchecked, cutie. don't make me come over there"),
                ("still waiting… 🥺", "{todo} keeps asking about you. one tap and it's done"),
                ("ahem. it's me again", "{todo} is overdue and I miss bragging about you. go fix that"),
                ("kiki's hourly poke ⏰", "you forgot {todo} and I noticed. handle it and I'll pretend I didn't"),
            ])
        }

        // {todo} gets replaced with the care item's title. Fired daily while due.
        static func careDue(for who: KikiAudience) -> [Line] {
            pick(who, male: [
                ("it's that time again ✨", "{todo} is due, handsome. book it today and future you will thank us both"),
                ("kiki's gentle poke 💛", "you've been putting off {todo}, big guy. today's the day, I believe in you"),
            ], female: [
                ("it's that time again ✨", "{todo} is due, gorgeous. book it today and future you will swoon"),
                ("kiki's gentle poke 💛", "you've been putting off {todo}, love. today's the day, I believe in you"),
            ], neutral: [
                ("it's that time again ✨", "{todo} is due. book it today and future you will thank us both"),
                ("kiki's gentle poke 💛", "you've been putting off {todo}. today's the day, I believe in you"),
            ])
        }

        // {todo} gets replaced with the todo's own title.
        static func todo(for who: KikiAudience) -> [Line] {
            pick(who, male: [
                ("todo o'clock 📝", "{todo} is on your list, handsome. go be the guy who checks boxes"),
                ("tiny mission time 💪", "{todo}. that's it. that's the message. flex on it, champ"),
                ("psst… your list misses you", "{todo} is waiting so patiently, big guy. make it proud and tick it off"),
                ("one for you, hero ✨", "knock out {todo} real quick and I'll be extremely impressed. no pressure 😏"),
            ], female: [
                ("todo o'clock 📝", "{todo} is on your list, gorgeous. go be the queen who checks boxes"),
                ("tiny mission time ✨", "{todo}. that's it. that's the message. you've totally got this, love"),
                ("psst… your list misses you", "{todo} is waiting so patiently, pretty. make it proud and tick it off"),
                ("one for you, star 💫", "knock out {todo} real quick and I'll be extremely impressed. no pressure 😏"),
            ], neutral: [
                ("todo o'clock 📝", "{todo} is on your list right now. go be the cutie who checks boxes"),
                ("tiny mission time ✨", "{todo}. that's it. that's the message. you've totally got this"),
                ("psst… your list misses you", "{todo} is waiting so patiently. make it proud and tick it off"),
                ("one for you, star 💫", "knock out {todo} real quick and I'll be extremely impressed. no pressure 😏"),
            ])
        }
    }
}
