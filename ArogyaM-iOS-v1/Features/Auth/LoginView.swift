import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var auth: AuthStore

    @State private var email = ""
    @State private var password = ""
    @State private var serverURL = Config.baseURL
    @State private var showServerField = false

    @FocusState private var focus: Field?
    private enum Field: Hashable { case email, password, server }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 22) {
                    Spacer(minLength: 40)

                    VStack(spacing: 14) {
                        Image("Kiki")
                            .resizable().scaledToFit()
                            .frame(width: 118, height: 118)
                        Text("ArogyaM")
                            .font(Theme.display(38, .bold))
                            .foregroundStyle(Theme.text)
                        Text("Your health, beautifully tracked")
                            .font(Theme.body(14))
                            .foregroundStyle(Theme.textSecondary)
                    }

                    VStack(spacing: 14) {
                        field(
                            "Email", text: $email, field: .email,
                            icon: "envelope.fill",
                            keyboard: .emailAddress, content: .username, submit: .next
                        )
                        field(
                            "Password", text: $password, field: .password,
                            icon: "lock.fill", isSecure: true,
                            content: .password, submit: .go
                        )

                        if showServerField {
                            field(
                                "Server URL", text: $serverURL, field: .server,
                                icon: "server.rack",
                                keyboard: .URL, submit: .done
                            )
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }

                        if let error = auth.errorMessage {
                            Text(error)
                                .font(Theme.body(13, .medium))
                                .foregroundStyle(Theme.rose)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        PrimaryButton(
                            title: "Log In",
                            isLoading: auth.isLoading,
                            systemImage: "arrow.right"
                        ) { submit() }
                        .padding(.top, 4)

                        Button {
                            withAnimation { showServerField.toggle() }
                        } label: {
                            Label(showServerField ? "Hide server settings" : "Server settings",
                                  systemImage: "gearshape")
                                .font(Theme.body(13))
                                .foregroundStyle(Theme.textMuted)
                        }
                    }
                    .padding(20)
                    .glassCard(tint: Theme.emerald, padding: 20)
                    .id("form")

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 22)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: focus) { _, newValue in
                guard newValue != nil else { return }
                withAnimation { proxy.scrollTo("form", anchor: .center) }
            }
        }
    }

    @ViewBuilder
    private func field(
        _ placeholder: String,
        text: Binding<String>,
        field: Field,
        icon: String,
        isSecure: Bool = false,
        keyboard: UIKeyboardType = .default,
        content: UITextContentType? = nil,
        submit: SubmitLabel
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.textMuted)
                .frame(width: 22)
            Group {
                if isSecure {
                    SecureField(placeholder, text: text)
                } else {
                    TextField(placeholder, text: text)
                }
            }
            .font(Theme.body(16))
            .foregroundStyle(Theme.text)
            .focused($focus, equals: field)
            .keyboardType(keyboard)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .textContentType(content)
            .submitLabel(submit)
            .onSubmit { advance(from: field) }
        }
        .padding(.horizontal, 14)
        .frame(height: 52)
        .background(
            RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                .fill(Theme.surface.opacity(0.55))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                        .strokeBorder(focus == field ? Theme.emerald.opacity(0.6) : Theme.hairline,
                                      lineWidth: 1)
                )
        )
    }

    private func advance(from field: Field) {
        switch field {
        case .email: focus = .password
        case .password: submit()
        case .server: focus = nil
        }
    }

    private func submit() {
        focus = nil
        let trimmed = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { auth.setServerURL(trimmed) }
        guard !email.isEmpty, !password.isEmpty else {
            auth.errorMessage = "Enter your email and password."
            return
        }
        Task { await auth.login(email: email, password: password) }
    }
}
