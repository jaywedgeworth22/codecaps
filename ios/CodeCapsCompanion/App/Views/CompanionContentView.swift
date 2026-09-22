import SwiftUI

/// The main content view of the CodeCaps iOS companion app.
public struct CompanionContentView: View {
    @ObservedObject public var model: CompanionQuotaModel
    @State private var showingSettings = false

    public init(model: CompanionQuotaModel) {
        self.model = model
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    headerCard
                    ForEach(model.items) { item in
                        quotaCard(item)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .navigationTitle("CodeCaps")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
                #else
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
                #endif
            }
            .refreshable {
                await model.refresh()
            }
            .sheet(isPresented: $showingSettings) {
                companionSettingsView
            }
        }
    }

    // MARK: - Colors

    private var cardBackground: Color {
        #if os(iOS)
        return Color(uiColor: .secondarySystemBackground)
        #else
        return Color(nsColor: .windowBackgroundColor)
        #endif
    }

    private var trackColor: Color {
        #if os(iOS)
        return Color(uiColor: .tertiarySystemFill)
        #else
        return Color.secondary.opacity(0.15)
        #endif
    }

    // MARK: - Header Card

    private var headerCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("FLEET STATUS")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                Text("\(model.items.count) Quotas Active")
                    .font(.headline)
            }
            Spacer()
            if let updated = model.lastUpdated {
                Text("Updated \(updated.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Quota Card

    private func quotaCard(_ item: CompanionQuotaItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 15, weight: .semibold))
                    if let sub = item.subtitle {
                        Text(sub)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                HStack(spacing: 10) {
                    Button {
                        model.toggleAlarm(for: item.id)
                    } label: {
                        Image(systemName: item.isAlarmArmed ? "bell.fill" : "bell")
                            .font(.system(size: 14))
                            .foregroundStyle(item.isAlarmArmed ? Color.accentColor : .secondary)
                    }
                    .buttonStyle(.plain)

                    Text(item.displayPercent)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(item.statusColor)
                }
            }

            // Progress Bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(trackColor)
                    if let pct = item.remainingPercent {
                        Capsule()
                            .fill(item.statusColor)
                            .frame(width: geo.size.width * CGFloat(min(max(pct, 0), 100)) / 100)
                    }
                }
            }
            .frame(height: 6)
        }
        .padding(14)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Settings View

    private var companionSettingsView: some View {
        NavigationStack {
            Form {
                Section("Mac Sync Endpoint") {
                    #if os(iOS)
                    TextField("Endpoint URL (https://...)", text: $model.syncEndpoint)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                    #else
                    TextField("Endpoint URL (https://...)", text: $model.syncEndpoint)
                        .autocorrectionDisabled(true)
                    #endif
                    SecureField("Sync Bearer Token", text: $model.syncToken)
                }

                Section("Alerts & Notifications") {
                    Toggle("Notify on Quota Reset", isOn: $model.notifyOnReset)
                    Picker("Reset Alert Sound", selection: $model.alarmSound) {
                        ForEach(ResetAlarmSound.defaultPickerOrder, id: \.self) { sound in
                            Text(sound.displayName).tag(sound)
                        }
                    }
                    Text(model.alarmSound.pickerDetail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button("Refresh Quotas Now") {
                        Task { await model.refresh() }
                    }
                }
            }
            .navigationTitle("Companion Settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showingSettings = false }
                }
                #else
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { showingSettings = false }
                }
                #endif
            }
        }
    }
}
