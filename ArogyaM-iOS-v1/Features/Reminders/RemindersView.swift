import SwiftUI

/// Settings page for Kiki's water, meal and todo reminders.
struct RemindersView: View {
    @ObservedObject private var service = NotificationService.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                header

                if service.permissionDenied { deniedBanner }

                waterCard
                mealsCard
                todosCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, AppShell.bottomBarInset)
        }
        .scrollIndicators(.hidden)
        .background(Theme.backgroundGradient)
        .task { await service.bootstrap() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image("Kiki").resizable().scaledToFit().frame(width: 46, height: 46)
            VStack(alignment: .leading, spacing: 1) {
                Text("Reminders").font(Theme.display(22, .bold)).foregroundStyle(Theme.text)
                Text("Little love notes from Kiki").font(Theme.body(12)).foregroundStyle(Theme.textMuted)
            }
            Spacer()
        }
    }

    private var deniedBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "bell.slash.fill").foregroundStyle(Theme.rose)
            Text("Notifications are off for ArogyaM. Enable them in Settings and Kiki will start writing again.")
                .font(Theme.body(13)).foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(tint: Theme.rose, padding: 14)
    }

    // MARK: - Water

    private var waterCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle(isOn: $service.settings.waterEnabled) {
                Label {
                    Text("Water nudges").font(Theme.body(15, .semibold)).foregroundStyle(Theme.text)
                } icon: {
                    Image(systemName: "drop.fill").foregroundStyle(Theme.cyan)
                }
            }
            .tint(Theme.cyan)

            if service.settings.waterEnabled {
                VStack(spacing: 12) {
                    timeRow("First sip", minutes: $service.settings.waterStartMinutes)
                    timeRow("Last sip", minutes: $service.settings.waterEndMinutes)
                    HStack {
                        Text("Every").font(Theme.body(14)).foregroundStyle(Theme.textSecondary)
                        Spacer()
                        Picker("Every", selection: $service.settings.waterEveryMinutes) {
                            Text("30 minutes").tag(30)
                            Text("1 hour").tag(60)
                            Text("1.5 hours").tag(90)
                            Text("2 hours").tag(120)
                            Text("3 hours").tag(180)
                        }
                        .pickerStyle(.menu)
                        .tint(Theme.cyan)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(padding: 16)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: service.settings.waterEnabled)
    }

    // MARK: - Meals

    private var mealsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle(isOn: $service.settings.mealsEnabled) {
                Label {
                    Text("Meal nudges").font(Theme.body(15, .semibold)).foregroundStyle(Theme.text)
                } icon: {
                    Image(systemName: "fork.knife").foregroundStyle(Theme.orange)
                }
            }
            .tint(Theme.orange)

            if service.settings.mealsEnabled {
                VStack(spacing: 12) {
                    timeRow("Breakfast", minutes: $service.settings.breakfastMinutes)
                    timeRow("Lunch", minutes: $service.settings.lunchMinutes)
                    timeRow("Snack", minutes: $service.settings.snackMinutes)
                    timeRow("Dinner", minutes: $service.settings.dinnerMinutes)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(padding: 16)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: service.settings.mealsEnabled)
    }

    // MARK: - Todos

    private var todosCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $service.settings.todosEnabled) {
                Label {
                    Text("Checklist nudges").font(Theme.body(15, .semibold)).foregroundStyle(Theme.text)
                } icon: {
                    Image(systemName: "checklist").foregroundStyle(Theme.indigo)
                }
            }
            .tint(Theme.indigo)

            Text("Kiki pings each dose at its own time, then keeps poking every hour if you forget to check it off. Care items that come due get one poke a day until they're done. Times come straight from your checklist.")
                .font(Theme.body(12))
                .foregroundStyle(Theme.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(padding: 16)
    }

    // MARK: - Rows

    private func timeRow(_ label: String, minutes: Binding<Int>) -> some View {
        HStack {
            Text(label).font(Theme.body(14)).foregroundStyle(Theme.textSecondary)
            Spacer()
            DatePicker(
                label,
                selection: Binding(
                    get: {
                        Calendar.current.date(
                            bySettingHour: minutes.wrappedValue / 60,
                            minute: minutes.wrappedValue % 60,
                            second: 0, of: Date()
                        ) ?? Date()
                    },
                    set: { date in
                        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                        minutes.wrappedValue = (c.hour ?? 0) * 60 + (c.minute ?? 0)
                    }
                ),
                displayedComponents: .hourAndMinute
            )
            .labelsHidden()
        }
    }
}
