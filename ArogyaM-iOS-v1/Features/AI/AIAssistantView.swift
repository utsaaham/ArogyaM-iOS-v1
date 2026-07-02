import SwiftUI
import Combine
import PhotosUI

struct PendingFoodItem: Equatable {
    let name: String
    let quantity: Double
    let unit: String
    let calories: Double
    let protein: Double
    let carbs: Double
    let fat: Double
    let fiber: Double?
    let sugar: Double?
    let sodium: Double?
}

struct PendingFoodLog: Equatable {
    let items: [PendingFoodItem]
    let totalCalories: Double?
    let totalProtein: Double?
    let totalCarbs: Double?
    let totalFat: Double?
}

struct ChatMessage: Identifiable, Equatable {
    enum Role { case user, assistant }
    let id = UUID()
    let role: Role
    var text: String
    var image: UIImage? = nil
    var isThinking: Bool = false
    var pendingWaterMl: Int? = nil
    var pendingFood: PendingFoodLog? = nil
}

@MainActor
final class AIStore: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var isSending = false

    private let api = API.shared

    func send(_ raw: String, image: UIImage? = nil) async {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || image != nil else { return }

        messages.append(ChatMessage(role: .user, text: text, image: image))
        messages.append(ChatMessage(role: .assistant, text: "", isThinking: true))
        let idx = messages.count - 1
        isSending = true
        defer { isSending = false }

        struct Payload: Encodable {
            let text: String
            let imageBase64: String?
            let imageMimeType: String?
        }
        do {
            let base64 = image.flatMap(Self.jpegBase64)
            let body = try JSONEncoder().encode(Payload(
                text: text,
                imageBase64: base64,
                imageMimeType: base64 != nil ? "image/jpeg" : nil
            ))
            let result: AIResult = try await api.postEnvelopedJSON("/api/ai/orchestrator", json: body)
            messages[idx].isThinking = false
            var reply = Self.summarize(result)
            if let feedback = result.result?["feedback"]?.stringValue, !feedback.isEmpty {
                reply += "\n\n" + feedback
            }
            messages[idx].text = reply
            messages[idx].pendingWaterMl = Self.detectWater(result)
            messages[idx].pendingFood = Self.detectFood(result)
        } catch {
            messages[idx].isThinking = false
            messages[idx].text = (error as? LocalizedError)?.errorDescription
                ?? "Oops, I tripped over my own paws 🙈 mind trying that again?"
        }
    }

    func confirmWater(_ ml: Int, for id: UUID) async {
        struct Payload: Encodable { let date: String; let amount: Int }
        let body = try? JSONEncoder().encode(Payload(date: DateUtil.todayKey, amount: ml))
        if let body {
            let _: WaterLogResult? = try? await api.postEnvelopedJSON("/api/water", json: body)
        }
        if let i = messages.firstIndex(where: { $0.id == id }) {
            messages[i].pendingWaterMl = nil
            messages[i].text += "\n\nDone! \(ml) ml down the hatch 💧 so proud of you."
        }
    }

    func confirmFood(_ food: PendingFoodLog, mealType: String, time: String, for id: UUID) async {
        struct MealBody: Encodable {
            let name: String
            let calories: Double
            let protein: Double
            let carbs: Double
            let fat: Double
            let fiber: Double?
            let sugar: Double?
            let sodium: Double?
            let quantity: Double
            let unit: String
            let mealType: String
            let time: String
        }
        struct Payload: Encodable { let date: String; let meal: MealBody }

        var logged = 0
        for item in food.items {
            let payload = Payload(date: DateUtil.todayKey, meal: MealBody(
                name: item.name,
                calories: item.calories,
                protein: item.protein,
                carbs: item.carbs,
                fat: item.fat,
                fiber: item.fiber,
                sugar: item.sugar,
                sodium: item.sodium,
                quantity: item.quantity,
                unit: item.unit,
                mealType: mealType,
                time: time
            ))
            if let body = try? JSONEncoder().encode(payload) {
                do {
                    try await api.postExpectingSuccess("/api/daily-log/meal", json: body)
                    logged += 1
                } catch { /* keep going; report count below */ }
            }
        }

        if let i = messages.firstIndex(where: { $0.id == id }) {
            messages[i].pendingFood = nil
            if logged == food.items.count {
                messages[i].text += "\n\nYum! Tucked \(logged) treat\(logged == 1 ? "" : "s") into your \(mealType) 😋 your macros thank you."
            } else if logged > 0 {
                messages[i].text += "\n\nI logged \(logged) of \(food.items.count) but a couple slipped past me 🙈 give it another go?"
            } else {
                messages[i].text += "\n\nUgh, that meal wouldn't stick 🙈 try logging it again for me?"
            }
        }
    }

    // MARK: - Result interpretation

    private static func summarize(_ r: AIResult) -> String {
        if let res = r.result {
            for key in ["message", "summary", "text", "reply", "response"] {
                if let s = res[key]?.stringValue, !s.isEmpty { return s }
            }
        }
        if r.tool?.isEmpty == false {
            return "All done, took care of that for you 💛"
        }
        return "Done and dusted 💛"
    }

    private static func detectWater(_ r: AIResult) -> Int? {
        guard let tool = r.tool, tool.lowercased().contains("water"),
              let res = r.result else { return nil }
        for key in ["amount", "waterIntake", "ml", "value"] {
            if let v = res[key]?.doubleValue, v > 0 { return Int(v) }
        }
        return nil
    }

    private static func detectFood(_ r: AIResult) -> PendingFoodLog? {
        guard let items = r.result?["foodItems"]?.arrayValue, !items.isEmpty else { return nil }
        let parsed: [PendingFoodItem] = items.compactMap { item in
            guard let name = item["name"]?.stringValue, !name.isEmpty else { return nil }
            return PendingFoodItem(
                name: name,
                quantity: item["quantity"]?.doubleValue ?? 1,
                unit: item["unit"]?.stringValue ?? "serving",
                calories: item["calories"]?.doubleValue ?? 0,
                protein: item["protein"]?.doubleValue ?? 0,
                carbs: item["carbs"]?.doubleValue ?? 0,
                fat: item["fat"]?.doubleValue ?? 0,
                fiber: item["fiber"]?.doubleValue,
                sugar: item["sugar"]?.doubleValue,
                sodium: item["sodium"]?.doubleValue
            )
        }
        guard !parsed.isEmpty else { return nil }
        let total = r.result?["foodTotal"]
        return PendingFoodLog(
            items: parsed,
            totalCalories: total?["calories"]?.doubleValue,
            totalProtein: total?["protein"]?.doubleValue,
            totalCarbs: total?["carbs"]?.doubleValue,
            totalFat: total?["fat"]?.doubleValue
        )
    }

    // MARK: - Image encoding

    /// Downscale + JPEG-encode so meal photos stay well under request limits.
    private static func jpegBase64(_ image: UIImage) -> String? {
        let maxDim: CGFloat = 1280
        let size = image.size
        let scale = min(1, maxDim / max(size.width, size.height))
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: target)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: 0.7)?.base64EncodedString()
    }
}

struct AIAssistantView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var store = AIStore()
    @StateObject private var speech = SpeechRecognizer()
    @State private var draft = ""
    @State private var attachedImage: UIImage? = nil
    @State private var pickerItem: PhotosPickerItem? = nil
    @State private var showAttachOptions = false
    @State private var showPhotosPicker = false
    @State private var showCamera = false
    @FocusState private var composerFocused: Bool

    var body: some View {
        ZStack {
            Theme.backgroundGradient
            VStack(spacing: 0) {
                header
                messageList
            }
        }
        .safeAreaInset(edge: .bottom) { composer }
        .confirmationDialog("Add a photo", isPresented: $showAttachOptions, titleVisibility: .visible) {
            Button("Take Photo") { showCamera = true }
            Button("Choose from Library") { showPhotosPicker = true }
        }
        .photosPicker(isPresented: $showPhotosPicker, selection: $pickerItem, matching: .images, photoLibrary: .shared())
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { image in
                attachedImage = image
            }
            .ignoresSafeArea()
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    attachedImage = image
                }
                pickerItem = nil
            }
        }
        .onChange(of: speech.transcript) { _, transcript in
            if speech.isRecording { draft = transcript }
        }
        .alert("Microphone access needed", isPresented: $speech.permissionDenied) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Enable the microphone and speech recognition for ArogyaM in Settings to use voice input.")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image("Kiki").resizable().scaledToFit()
                .frame(width: 42, height: 42)
            VStack(alignment: .leading, spacing: 1) {
                Text("Kiki").font(Theme.display(18, .bold)).foregroundStyle(Theme.text)
                Text("tell me everything, I'm all ears 💛").font(Theme.body(12))
                    .foregroundStyle(Theme.textMuted)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Theme.surface.opacity(0.6)))
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 14) {
                    if store.messages.isEmpty { emptyState }
                    ForEach(store.messages) { msg in
                        MessageBubble(
                            message: msg,
                            onConfirmWater: { ml in
                                Task { await store.confirmWater(ml, for: msg.id) }
                            },
                            onConfirmFood: { food, mealType, time in
                                Task { await store.confirmFood(food, mealType: mealType, time: time, for: msg.id) }
                            }
                        )
                        .id(msg.id)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: store.messages) { _, _ in
                withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onChange(of: composerFocused) { _, focused in
                if focused { withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Text("Type it, say it, or sneak me a pic of your plate and I'll do the math for you 😘")
                .font(Theme.body(13)).foregroundStyle(Theme.textMuted)
                .multilineTextAlignment(.center)
            VStack(spacing: 8) {
                ForEach(["I drank 500ml of water", "Log a 30 minute run", "Ate 2 eggs and toast"], id: \.self) { hint in
                    Button { draft = hint } label: {
                        Text(hint).font(Theme.body(14, .medium)).foregroundStyle(Theme.cyan)
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Theme.cyan.opacity(0.10)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 6)
        }
        .padding(.top, 50)
        .padding(.horizontal, 8)
    }

    // MARK: - Composer

    private var composer: some View {
        VStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 10) {
                if let image = attachedImage {
                    attachmentPreview(image)
                }

                TextField("Log your steps?", text: $draft, axis: .vertical)
                    .font(Theme.body(16))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1...5)
                    .focused($composerFocused)

                HStack(spacing: 12) {
                    Button { showAttachOptions = true } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                            .frame(width: 32, height: 32)
                            .contentShape(Circle())
                    }
                    .disabled(store.isSending)

                    Spacer()

                    if canSend {
                        Button { sendDraft() } label: {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 32, height: 32)
                                .background(Circle().fill(Theme.text))
                        }
                        .transition(.scale.combined(with: .opacity))
                    } else {
                        Button { speech.toggle() } label: {
                            Image(systemName: speech.isRecording ? "waveform" : "mic")
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(speech.isRecording ? Theme.rose : Theme.textSecondary)
                                .frame(width: 32, height: 32)
                                .contentShape(Circle())
                        }
                        .disabled(store.isSending)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Theme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.06), radius: 14, x: 0, y: 4)
            .animation(.easeInOut(duration: 0.15), value: canSend)

            Text("Kiki tries her best, double check the important stuff 💛")
                .font(Theme.body(11))
                .foregroundStyle(Theme.textMuted)
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    private func attachmentPreview(_ image: UIImage) -> some View {
        ZStack(alignment: .topTrailing) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            Button { attachedImage = nil } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(.white, .black.opacity(0.55))
            }
            .offset(x: 6, y: -6)
        }
        .padding(.top, 4)
    }

    private var canSend: Bool {
        (!draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || attachedImage != nil)
            && !store.isSending
    }

    private func sendDraft() {
        if speech.isRecording { speech.stop() }
        let text = draft
        let image = attachedImage
        draft = ""
        attachedImage = nil
        Task { await store.send(text, image: image) }
    }
}

private struct MessageBubble: View {
    let message: ChatMessage
    var onConfirmWater: (Int) -> Void
    var onConfirmFood: (PendingFoodLog, String, String) -> Void

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }
            VStack(alignment: .leading, spacing: 10) {
                if let image = message.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: 200, maxHeight: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                if message.isThinking {
                    HStack(spacing: 6) {
                        ProgressView().tint(Theme.textSecondary).scaleEffect(0.8)
                        Text("Hmm, let me think…").font(Theme.body(14)).foregroundStyle(Theme.textMuted)
                    }
                } else if !message.text.isEmpty {
                    Text(.init(message.text))
                        .font(Theme.body(15))
                        .foregroundStyle(message.role == .user ? .white : Theme.text)
                }
                if let ml = message.pendingWaterMl {
                    Button { onConfirmWater(ml) } label: {
                        Label("Yes, log my \(ml) ml 💧", systemImage: "checkmark.circle.fill")
                            .font(Theme.body(14, .semibold)).foregroundStyle(.black)
                            .padding(.horizontal, 14).padding(.vertical, 9)
                            .background(Capsule().fill(Theme.cyan))
                    }
                    .buttonStyle(.plain)
                }
                if let food = message.pendingFood {
                    FoodConfirmCard(food: food) { mealType, time in
                        onConfirmFood(food, mealType, time)
                    }
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            .background(bubbleBackground)
            if message.role == .assistant { Spacer(minLength: 40) }
        }
    }

    @ViewBuilder private var bubbleBackground: some View {
        if message.role == .user {
            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.emerald)
        } else {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.surface.opacity(0.7))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 1))
        }
    }
}

// MARK: - Food confirmation card

private struct FoodConfirmCard: View {
    let food: PendingFoodLog
    var onConfirm: (String, String) -> Void

    private static let mealTypes = ["breakfast", "lunch", "dinner", "snack"]

    @State private var mealType: String = Self.guessMealType()
    @State private var eatenAt = Date()
    @State private var isLogging = false

    private static func guessMealType() -> String {
        let h = Calendar.current.component(.hour, from: Date())
        if h < 10 { return "breakfast" }
        if h < 14 { return "lunch" }
        if h < 18 { return "snack" }
        return "dinner"
    }

    private var timeString: String {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: eatenAt)
        return String(format: "%02d:%02d", parts.hour ?? 12, parts.minute ?? 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(food.items.enumerated()), id: \.offset) { _, item in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("\(item.quantity.formatted()) \(item.unit) \(item.name)")
                            .font(Theme.body(13, .medium))
                            .foregroundStyle(Theme.text)
                            .lineLimit(2)
                        Spacer()
                        Text("\(Int(item.calories)) cal")
                            .font(Theme.number(13, .semibold))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Text("P \(Int(item.protein))g · C \(Int(item.carbs))g · F \(Int(item.fat))g")
                        .font(Theme.body(11))
                        .foregroundStyle(Theme.textMuted)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Theme.bgRaised))
            }

            if let calories = food.totalCalories, food.items.count > 1 {
                HStack {
                    Text("Total").font(Theme.body(12, .semibold)).foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Text("\(Int(calories)) cal")
                        .font(Theme.number(13, .bold)).foregroundStyle(Theme.emerald)
                }
                .padding(.horizontal, 4)
            }

            HStack(spacing: 6) {
                ForEach(Self.mealTypes, id: \.self) { type in
                    Button { mealType = type } label: {
                        Text(type.capitalized)
                            .font(Theme.body(11, .medium))
                            .foregroundStyle(mealType == type ? .white : Theme.textSecondary)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Capsule().fill(mealType == type ? Theme.emerald : Theme.surface))
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack {
                Text("When did you have it?")
                    .font(Theme.body(12, .medium))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                DatePicker("", selection: $eatenAt, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .datePickerStyle(.compact)
            }
            .padding(.horizontal, 4)

            Button {
                isLogging = true
                onConfirm(mealType, timeString)
            } label: {
                Label(isLogging ? "On it…" : "Yep, that's my plate 😋", systemImage: "checkmark.circle.fill")
                    .font(Theme.body(14, .semibold)).foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(Theme.cyan))
            }
            .buttonStyle(.plain)
            .disabled(isLogging)
        }
        .frame(maxWidth: 280)
    }
}
