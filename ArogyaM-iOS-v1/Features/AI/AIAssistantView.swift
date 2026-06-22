import SwiftUI
import Combine

struct ChatMessage: Identifiable, Equatable {
    enum Role { case user, assistant }
    let id = UUID()
    let role: Role
    var text: String
    var isThinking: Bool = false
    var pendingWaterMl: Int? = nil
}

@MainActor
final class AIStore: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var isSending = false

    private let api = API.shared

    func send(_ raw: String) async {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        messages.append(ChatMessage(role: .user, text: text))
        messages.append(ChatMessage(role: .assistant, text: "", isThinking: true))
        let idx = messages.count - 1
        isSending = true
        defer { isSending = false }

        struct Payload: Encodable { let text: String }
        do {
            let body = try JSONEncoder().encode(Payload(text: text))
            let result: AIResult = try await api.postEnvelopedJSON("/api/ai/orchestrator", json: body)
            messages[idx].isThinking = false
            messages[idx].text = Self.summarize(result)
            messages[idx].pendingWaterMl = Self.detectWater(result)
        } catch {
            messages[idx].isThinking = false
            messages[idx].text = (error as? LocalizedError)?.errorDescription
                ?? "Sorry, something went wrong. Please try again."
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
            messages[i].text += "\n\n✅ Logged \(ml) ml of water."
        }
    }

    // MARK: - Result interpretation

    private static func summarize(_ r: AIResult) -> String {
        if let res = r.result {
            for key in ["message", "summary", "text", "reply", "response"] {
                if let s = res[key]?.stringValue, !s.isEmpty { return s }
            }
        }
        if let tool = r.tool, !tool.isEmpty {
            return "Got it — handled with **\(tool)**."
        }
        return "Done."
    }

    private static func detectWater(_ r: AIResult) -> Int? {
        guard let tool = r.tool, tool.lowercased().contains("water"),
              let res = r.result else { return nil }
        for key in ["amount", "waterIntake", "ml", "value"] {
            if let v = res[key]?.doubleValue, v > 0 { return Int(v) }
        }
        return nil
    }
}

struct AIAssistantView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var store = AIStore()
    @State private var draft = ""
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
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image("Kiki").resizable().scaledToFit()
                .frame(width: 42, height: 42)
            VStack(alignment: .leading, spacing: 1) {
                Text("ArogyaM AI").font(Theme.display(18, .bold)).foregroundStyle(Theme.text)
                Text("Log anything in plain words").font(Theme.body(12))
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
                        MessageBubble(message: msg) { ml in
                            Task { await store.confirmWater(ml, for: msg.id) }
                        }
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
            Image("Kiki").resizable().scaledToFit().frame(width: 104, height: 104)
                .shadow(color: Theme.violet.opacity(0.45), radius: 22, y: 10)
            Text("Ask me anything about your health")
                .font(Theme.display(20, .bold)).foregroundStyle(Theme.text)
                .multilineTextAlignment(.center)
            Text("Try “I drank 500ml of water”, “Log 30 min run”, or “I weigh 72 kg”.")
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

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Message ArogyaM…", text: $draft, axis: .vertical)
                .font(Theme.body(16))
                .foregroundStyle(Theme.text)
                .lineLimit(1...5)
                .focused($composerFocused)
                .padding(.horizontal, 16).padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Theme.surface.opacity(0.7))
                        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(Theme.hairline, lineWidth: 1))
                )

            Button { sendDraft() } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(canSend ? Theme.emerald : Theme.textMuted))
            }
            .disabled(!canSend)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !store.isSending
    }

    private func sendDraft() {
        let text = draft
        draft = ""
        Task { await store.send(text) }
    }
}

private struct MessageBubble: View {
    let message: ChatMessage
    var onConfirmWater: (Int) -> Void

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }
            VStack(alignment: .leading, spacing: 10) {
                if message.isThinking {
                    HStack(spacing: 6) {
                        ProgressView().tint(Theme.textSecondary).scaleEffect(0.8)
                        Text("Thinking…").font(Theme.body(14)).foregroundStyle(Theme.textMuted)
                    }
                } else {
                    Text(.init(message.text))
                        .font(Theme.body(15))
                        .foregroundStyle(message.role == .user ? .white : Theme.text)
                }
                if let ml = message.pendingWaterMl {
                    Button { onConfirmWater(ml) } label: {
                        Label("Confirm & log \(ml) ml", systemImage: "checkmark.circle.fill")
                            .font(Theme.body(14, .semibold)).foregroundStyle(.black)
                            .padding(.horizontal, 14).padding(.vertical, 9)
                            .background(Capsule().fill(Theme.cyan))
                    }
                    .buttonStyle(.plain)
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
