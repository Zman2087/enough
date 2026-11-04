import FilterEngine
import SwiftUI

struct DoneOverlay: View {
    let count: Int
    let resetClockText: String
    var onMessages: () -> Void
    var onSearch: () -> Void
    var onProfile: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Text("You're done for today")
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
            Text(seenText)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text("The feed opens again at \(resetClockText).")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 12) {
                Button("Messages", action: onMessages)
                Button("Search", action: onSearch)
                Button("Profile", action: onProfile)
            }
            .buttonStyle(.bordered)
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .accessibilityElement(children: .contain)
    }

    private var seenText: String {
        if count == 1 {
            return "You've seen 1 post."
        }
        return "You've seen \(count) posts."
    }
}

struct SettingsView: View {
    @ObservedObject var model: FeedModel
    @Environment(\.dismiss) private var dismiss

    @State private var draft: EnoughSettings
    @State private var remoteDraft: String
    @State private var urlError: String?

    init(model: FeedModel) {
        self.model = model
        _draft = State(initialValue: model.settings)
        _remoteDraft = State(initialValue: model.settings.remoteConfigURL ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Today") {
                    LabeledContent("Posts seen", value: "\(model.snapshot.count) of \(model.snapshot.cap)")
                    LabeledContent("Resets", value: model.resetClockText)
                }
                Section("Daily cap") {
                    Toggle("Cap the feed", isOn: $draft.capEnabled)
                    Stepper(value: $draft.dailyCap, in: EnoughConstants.minimumCap...EnoughConstants.maximumCap) {
                        Text("Posts per day: \(draft.dailyCap)")
                    }
                    DatePicker("Reset time", selection: resetBinding, displayedComponents: .hourAndMinute)
                }
                Section("Hide") {
                    Toggle("Reels", isOn: $draft.hideReels)
                    Toggle("Explore", isOn: $draft.hideExplore)
                    Toggle("Suggested posts", isOn: $draft.hideSuggested)
                    Text("Ads stay visible and do not count.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("Selectors") {
                    TextField("Remote selector URL", text: $remoteDraft)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled(true)
                    Text(model.configStatus)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if let urlError {
                        Text(urlError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                    Text("Optional https link to a selector JSON file. Enough downloads that data only. It will not download or run script. Leave this empty to use the copy in the app.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: save)
                }
            }
        }
    }

    private var resetBinding: Binding<Date> {
        Binding(
            get: {
                var parts = Calendar.current.dateComponents([.year, .month, .day], from: Date())
                parts.hour = draft.resetHour
                parts.minute = draft.resetMinute
                return Calendar.current.date(from: parts) ?? Date()
            },
            set: { newValue in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                draft.resetHour = parts.hour ?? 0
                draft.resetMinute = parts.minute ?? 0
            }
        )
    }

    private func save() {
        let trimmed = remoteDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty && RemoteConfigURL.normalize(trimmed) == nil {
            urlError = "Enter an https URL, or leave this empty."
            return
        }
        urlError = nil
        draft.remoteConfigURL = trimmed.isEmpty ? nil : trimmed
        model.save(settings: draft)
        dismiss()
        Task { await model.refreshRemoteConfig() }
    }
}
