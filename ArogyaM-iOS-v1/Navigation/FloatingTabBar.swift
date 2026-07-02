import SwiftUI

struct FloatingTabBar: View {
    @Binding var selected: AppTab
    var onAI: () -> Void

    @Namespace private var ns
    @State private var showKikiHint = false

    private struct Spec { let tab: AppTab; let icon: String; let tint: Color }
    private let specs: [Spec] = [
        .init(tab: .home,   icon: "house.fill",        tint: Theme.emerald),
        .init(tab: .vitals, icon: "waveform.path.ecg", tint: Theme.red),
        .init(tab: .checklist, icon: "checklist",      tint: Theme.purple),
        .init(tab: .more,   icon: "ellipsis",          tint: Theme.indigo),
    ]

    // Pill height so Kiki can be anchored to the same baseline
    private let pillHeight: CGFloat = 72

    var body: some View {
        GlassEffectContainer(spacing: 14) {
            HStack(alignment: .bottom, spacing: 10) {
                // ── Liquid Glass pill ──
                HStack(spacing: 0) {
                    ForEach(specs, id: \.tab) { item($0) }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
                .frame(height: pillHeight)
                .frame(maxWidth: .infinity)
                .glassEffect(.regular.tint(Color.white.opacity(0.45)), in: .capsule)
                .shadow(color: .black.opacity(0.12), radius: 20, y: 8)

                // ── Kiki — bottom-aligned with pill, floats above ──
                Button(action: onAI) {
                    Image("Kiki")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 84, height: 84)
                }
                .buttonStyle(SpringyButtonStyle())
                .overlay(alignment: .top) {
                    if showKikiHint { kikiHint }
                }
                // No offset: the HStack bottom-aligns Kiki with the pill, so
                // her bottom edge sits exactly on the bar's bottom line.
            }
        }
        .task {
            // A quick hello so people know Kiki is the AI — shows for a
            // couple of seconds after launch, then gets out of the way.
            try? await Task.sleep(nanoseconds: 700_000_000)
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) { showKikiHint = true }
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            withAnimation(.easeOut(duration: 0.35)) { showKikiHint = false }
        }
    }

    // MARK: - Kiki hint bubble

    private var kikiHint: some View {
        VStack(spacing: -1) {
            Text("hi! I'm Kiki, your AI ✨ tap me")
                .font(Theme.body(12, .semibold))
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Theme.card)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Theme.hairline, lineWidth: 0.5)
                )
            Triangle()
                .fill(Theme.card)
                .frame(width: 14, height: 7)
        }
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        .fixedSize()
        .offset(x: -46, y: -34)
        .transition(.opacity.combined(with: .scale(scale: 0.7, anchor: .bottomTrailing)))
        .allowsHitTesting(false)
    }

    private struct Triangle: Shape {
        func path(in rect: CGRect) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            p.closeSubpath()
            return p
        }
    }

    // MARK: - Tab item

    private func item(_ spec: Spec) -> some View {
        let isSelected = selected == spec.tab
        return Button {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.74)) {
                selected = spec.tab
            }
        } label: {
            ZStack {
                if isSelected {
                    Capsule()
                        .fill(spec.tint.opacity(0.16))
                        .overlay {
                            Capsule().strokeBorder(spec.tint.opacity(0.30), lineWidth: 0.5)
                        }
                        .matchedGeometryEffect(id: "highlight", in: ns)
                }
                Image(systemName: spec.icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(isSelected ? spec.tint : Theme.textMuted)
                    .scaleEffect(isSelected ? 1.10 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
