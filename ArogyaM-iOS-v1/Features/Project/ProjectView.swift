import SwiftUI

/// About the open-source project — mirrors the web app's /project page.
struct ProjectView: View {
    private let repoURL = URL(string: "https://github.com/utsaaham/arogyamandiram")!

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                SectionTitle(title: "Project", subtitle: "ArogyaM is open source").padding(.top, 6)

                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Theme.purple.opacity(0.14)).frame(width: 54, height: 54)
                            Image(systemName: "chevron.left.forwardslash.chevron.right")
                                .font(.system(size: 22, weight: .semibold)).foregroundStyle(Theme.purple)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Arogyamandiram").font(Theme.display(18, .bold)).foregroundStyle(Theme.text)
                            Text("Open source health & wellness")
                                .font(Theme.body(12)).foregroundStyle(Theme.textSecondary)
                        }
                    }
                    Text("Everything in this app — the trackers, the scores, Kiki, this iOS app itself — is built in the open. Peek at the code, file an issue, or send a pull request.")
                        .font(Theme.body(13)).foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard()

                Link(destination: repoURL) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.up.right.square.fill")
                        Text("View on GitHub").font(Theme.body(16, .semibold))
                    }
                    .frame(maxWidth: .infinity).frame(height: 52)
                    .foregroundStyle(.white)
                    .background(Theme.purple, in: RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
                }
                .buttonStyle(SpringyButtonStyle(scale: 0.97))
            }
            .padding(.horizontal, 16)
            .padding(.bottom, AppShell.bottomBarInset)
        }
        .scrollIndicators(.hidden)
    }
}
