import SwiftUI

struct FloatingTabBar: View {
    @Binding var selected: AppTab
    var onAI: () -> Void

    @Namespace private var ns

    private struct Spec { let tab: AppTab; let icon: String; let tint: Color }
    private let specs: [Spec] = [
        .init(tab: .home,   icon: "house.fill",             tint: Theme.emerald),
        .init(tab: .water,  icon: "drop.fill",              tint: Theme.cyan),
        .init(tab: .food,   icon: "fork.knife",             tint: Theme.amber),
        .init(tab: .health, icon: "heart.text.square.fill", tint: Theme.rose),
    ]

    // Pill height so Kiki can be anchored to the same baseline
    private let pillHeight: CGFloat = 72

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            // ── Liquid-glass pill ──
            HStack(spacing: 0) {
                ForEach(specs, id: \.tab) { item($0) }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(height: pillHeight)
            .background(liquidGlass)
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(specularBorder, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.22), radius: 28, y: 10)

            // ── Kiki — bottom-aligned with pill, floats above ──
            Button(action: onAI) {
                Image("Kiki")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 88, height: 88)
            }
            .buttonStyle(SpringyButtonStyle())
            .offset(y: -(88 - pillHeight) / 2 - 4)   // float above pill floor
        }
    }

    // MARK: - Liquid glass background

    private var liquidGlass: some View {
        ZStack {
            // Blur layer
            Capsule().fill(.ultraThinMaterial)
            // Top specular sheen
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(0.30), .white.opacity(0.04)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
        }
    }

    private var specularBorder: LinearGradient {
        LinearGradient(
            colors: [.white.opacity(0.55), .white.opacity(0.08)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
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
                        .fill(spec.tint.opacity(0.22))
                        .overlay {
                            Capsule().fill(
                                LinearGradient(
                                    colors: [.white.opacity(0.18), .clear],
                                    startPoint: .top, endPoint: .bottom
                                )
                            )
                        }
                        .overlay {
                            Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 0.5)
                        }
                        .matchedGeometryEffect(id: "highlight", in: ns)
                }
                Image(systemName: spec.icon)
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(isSelected ? spec.tint : .white.opacity(0.55))
                    .scaleEffect(isSelected ? 1.10 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
            }
            .frame(width: 58, height: 52)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
