import SwiftUI

// MARK: - Circular progress ring

struct ProgressRing<Center: View>: View {
    var progress: Double            // 0...1 (clamped)
    var tint: Color
    var size: CGFloat = 120
    var lineWidth: CGFloat = 12
    var track: Color = Color.black.opacity(0.07)
    @ViewBuilder var center: () -> Center

    @State private var animated: Double = 0

    var body: some View {
        ZStack {
            Circle().stroke(track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(animated, 1)))
                .stroke(
                    AngularGradient(
                        colors: [tint.opacity(0.7), tint],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: tint.opacity(0.5), radius: 6)
            center()
        }
        .frame(width: size, height: size)
        .onAppear { withAnimation(.easeOut(duration: 0.7)) { animated = progress } }
        .onChange(of: progress) { _, new in
            withAnimation(.easeOut(duration: 0.6)) { animated = new }
        }
    }
}

extension ProgressRing where Center == EmptyView {
    init(progress: Double, tint: Color, size: CGFloat = 120, lineWidth: CGFloat = 12) {
        self.init(progress: progress, tint: tint, size: size, lineWidth: lineWidth) { EmptyView() }
    }
}

// MARK: - Horizontal macro / goal bar

struct MacroBar: View {
    var label: String
    var value: Double
    var goal: Double
    var tint: Color
    var unit: String = "g"

    private var fraction: Double { goal > 0 ? min(value / goal, 1) : 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label).font(Theme.body(13, .medium)).foregroundStyle(Theme.textSecondary)
                Spacer()
                Text("\(Int(value)) / \(Int(goal))\(unit)")
                    .font(Theme.body(12, .semibold)).foregroundStyle(Theme.text)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.track)
                    Capsule().fill(tint)
                        .frame(width: max(6, geo.size.width * fraction))
                }
            }
            .frame(height: 8)
        }
    }
}

// MARK: - Stat tile

struct StatTile: View {
    var icon: String
    var tint: Color
    var label: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(tint.opacity(0.16))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(tint)
            }
            Spacer(minLength: 0)
            Text(value).font(Theme.display(20, .bold)).foregroundStyle(Theme.text)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(Theme.body(12)).foregroundStyle(Theme.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 116)
        .glassCard(tint: tint, padding: 14)
    }
}

// MARK: - Primary button

struct PrimaryButton: View {
    var title: String
    var tint: Color = Theme.emerald
    var isLoading: Bool = false
    var systemImage: String?
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView().tint(.white)
                } else {
                    if let systemImage { Image(systemName: systemImage) }
                    Text(title).font(Theme.body(16, .semibold))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .foregroundStyle(.white)
            .background(
                LinearGradient(colors: [tint, tint.opacity(0.82)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
            )
            .shadow(color: tint.opacity(0.4), radius: 12, y: 6)
        }
        .disabled(isLoading)
    }
}

// MARK: - Section header

struct SectionTitle: View {
    var title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(Theme.display(22, .bold)).foregroundStyle(Theme.text)
            if let subtitle {
                Text(subtitle).font(Theme.body(13)).foregroundStyle(Theme.textMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Tactile button style (subtle press spring)

struct SpringyButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.9
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
