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
            Text("You've reached your limit for today.")
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
}

struct SettingsView: View {
    @ObservedObject var model: FeedModel
    @Environment(\.dismiss) private var dismiss

    @State private var draft: EnoughSettings
    @State private var remoteDraft: String
    @State private var urlError: String?
    @State private var capText: String
    @FocusState private var capFieldFocused: Bool
    @ObservedObject private var lock: PINLock
    @State private var pinPrompt: PINPurpose?
    @State private var showPINSetup = false

    init(model: FeedModel) {
        self.model = model
        self.lock = model.lock
        _draft = State(initialValue: model.settings)
        _remoteDraft = State(initialValue: model.settings.remoteConfigURL ?? "")
        _capText = State(initialValue: String(model.settings.dailyCap))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Today") {
                    LabeledContent("Posts seen") {
                        if model.capReached {
                            Text("Limit reached").foregroundStyle(.red)
                        } else {
                            Text("\(model.displayedCount) of \(model.snapshot.cap)")
                        }
                    }
                    LabeledContent("Resets", value: model.resetClockText)
                }
                Section("Daily cap") {
                    Toggle("Cap the feed", isOn: $draft.capEnabled)
                    HStack(spacing: 12) {
                        Text("Posts per day")
                        Spacer(minLength: 8)
                        // Type a number or use - and +.
                        TextField("30", text: $capText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .font(.body.monospacedDigit())
                            .frame(width: 56)
                            .focused($capFieldFocused)
                            .accessibilityLabel("Posts per day")
                        Stepper("Posts per day", value: $draft.dailyCap, in: EnoughConstants.minimumCap...EnoughConstants.maximumCap)
                            .labelsHidden()
                    }
                    .onChange(of: capText) { text in
                        let digits = String(text.filter(\.isNumber).prefix(3))
                        if digits != text { capText = digits; return }
                        guard let value = Int(digits) else { return }
                        let clamped = min(max(value, EnoughConstants.minimumCap), EnoughConstants.maximumCap)
                        if clamped != draft.dailyCap { draft.dailyCap = clamped }
                        if clamped != value { capText = String(clamped) }
                    }
                    .onChange(of: draft.dailyCap) { value in
                        if Int(capText) != value { capText = String(value) }
                    }
                    .onChange(of: capFieldFocused) { focused in
                        if !focused { capText = String(draft.dailyCap) }
                    }
                    DatePicker("Reset time", selection: resetBinding, displayedComponents: .hourAndMinute)
                }
                Section("Hide") {
                    Toggle("Reels", isOn: $draft.hideReels)
                    Toggle("Explore", isOn: $draft.hideExplore)
                    Toggle("Suggested posts", isOn: $draft.hideSuggested)
                    Text(PlatformCatalog.active.hidesAds ? "Ads are hidden and do not count." : "Ads stay visible and do not count.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section {
                    if lock.isEnabled {
                        Label("Locked with a PIN", systemImage: "lock.fill")
                        Button("Remove PIN lock", role: .destructive) { pinPrompt = .remove }
                    } else {
                        Button {
                            showPINSetup = true
                        } label: {
                            Label("Set up a PIN lock", systemImage: "lock.open")
                        }
                    }
                } header: {
                    Text("Restrictions")
                } footer: {
                    Text(lock.isEnabled
                         ? "Raising the limit, turning the cap or hiding off, or changing the reset time needs the PIN. Lowering the limit or turning hiding on never does."
                         : "Ask a friend to type a PIN you don't know. After that, loosening your limits needs their PIN. Deleting the app clears the lock along with your settings.")
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
            .sheet(item: $pinPrompt) { purpose in
                PINEntryView(lock: lock, purpose: purpose) {
                    pinPrompt = nil
                    switch purpose {
                    case .save: commit()
                    case .remove: lock.remove()
                    }
                } onCancel: {
                    pinPrompt = nil
                }
            }
            .sheet(isPresented: $showPINSetup) {
                PINSetupView(lock: lock) { showPINSetup = false }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: save)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { capFieldFocused = false }
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
        if let typed = Int(capText) {
            draft.dailyCap = min(max(typed, EnoughConstants.minimumCap), EnoughConstants.maximumCap)
        }
        draft.remoteConfigURL = trimmed.isEmpty ? nil : trimmed
        if lock.isEnabled && SettingsLock.loosens(from: model.settings, to: draft) {
            pinPrompt = .save
            return
        }
        commit()
    }

    private func commit() {
        model.save(settings: draft)
        dismiss()
        Task { await model.refreshRemoteConfig() }
    }
}

enum PINPurpose: String, Identifiable {
    case save
    case remove
    var id: String { rawValue }
}

/// Asks for the lock PIN before a change that loosens a limit, or before removing the lock.
struct PINEntryView: View {
    @ObservedObject var lock: PINLock
    let purpose: PINPurpose
    var onAccepted: () -> Void
    var onCancel: () -> Void

    @State private var pin = ""
    @State private var message: String?
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("PIN", text: $pin)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .focused($focused)
                        .onSubmit(submit)
                } footer: {
                    Text(message ?? (purpose == .remove
                        ? "Enter the PIN to remove the lock."
                        : "This change loosens your limits. Enter the PIN to save it."))
                        .foregroundStyle(message == nil ? Color.secondary : Color.red)
                }
            }
            .navigationTitle("Enter PIN")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(purpose == .remove ? "Remove" : "Unlock", action: submit)
                        .disabled(pin.isEmpty)
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium])
    }

    private func submit() {
        switch lock.check(pin) {
        case .accepted:
            onAccepted()
        case .wrong(let remaining):
            pin = ""
            message = remaining == 1 ? "Wrong PIN. 1 try left before a pause." : "Wrong PIN. \(remaining) tries left before a pause."
        case .paused(let until):
            pin = ""
            let seconds = max(1, Int(until.timeIntervalSinceNow.rounded(.up)))
            message = "Too many tries. Try again in \(seconds) seconds."
        }
    }
}

/// Sets a new PIN. Meant to be typed by a friend.
struct PINSetupView: View {
    @ObservedObject var lock: PINLock
    var onDone: () -> Void

    @State private var pin = ""
    @State private var confirm = ""
    @FocusState private var focused: Bool

    private var valid: Bool { SettingsLock.isValidPIN(pin) && pin == confirm }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("New PIN (\(SettingsLock.minimumDigits)-\(SettingsLock.maximumDigits) digits)", text: $pin)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .focused($focused)
                    SecureField("Type it again", text: $confirm)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                } footer: {
                    Text(footer)
                }
            }
            .navigationTitle("PIN lock")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onDone)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lock") {
                        if lock.set(pin: pin) { onDone() }
                    }
                    .disabled(!valid)
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium, .large])
    }

    private var footer: String {
        if !confirm.isEmpty && pin != confirm { return "The PINs don't match." }
        return "Hand the phone to a friend and let them choose the PIN. Don't watch, and don't write it down."
    }
}
