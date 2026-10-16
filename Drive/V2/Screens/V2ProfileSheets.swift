//
//  V2ProfileSheets.swift
//  Drive — v2 "Road Furniture"
//
//  The edit sheets presented from Profile & Settings (§6.10), replacing the
//  v1 NameEditSheet / CarEditSheet / SchoolLinkSheet / SchoolConsentSheet
//  (still compiled in SettingsView.swift and SchoolViews.swift, unused).
//  Stock forms on V2 tokens; the writes and validation stay in the managers
//  exactly as the launch beta: ProfileManager trims names to ≤ 50, the car
//  to 50/50/4, and SchoolManager writes nothing before the consent's Agree.
//  Also the licence-change bookkeeping (graduation + 7-day undo).
//

import SwiftUI
import UIKit

// MARK: - Licence change (graduation + 7-day undo)

/// Permit → License bookkeeping shared by the Driver Card, the Profile
/// picker, the Logbook volumes and the All Time chart. Per user, this device:
/// `licenseChangedAt` (Date) and `licensePrevious` (DriverType rawValue).
enum V2LicenseChange {
    static let changedAtKeyName = "licenseChangedAt"
    static let previousKeyName = "licensePrevious"
    /// §4.14: graduation is reversible within 7 days.
    static let undoWindow: TimeInterval = 7 * 24 * 60 * 60

    static var changedAt: Date? {
        UserDefaults.standard.object(forKey: V2UserKey.scoped(changedAtKeyName)) as? Date
    }

    static var previous: DriverType? {
        UserDefaults.standard.string(forKey: V2UserKey.scoped(previousKeyName))
            .flatMap { DriverType(rawValue: $0) }
    }

    /// When the Permit logbook closed, if this user graduated from Permit.
    static var permitClosedAt: Date? {
        guard let date = changedAt, (previous ?? .learner) == .learner else { return nil }
        return date
    }

    /// "I got it" (or the Profile picker): the same ProfileManager write as
    /// the beta (Firestore driverType + licenseStage, scoring tuning), plus
    /// the change date for the Logbook volumes and the chart's LICENSE tab.
    static func graduate(now: Date = Date()) {
        let defaults = UserDefaults.standard
        defaults.set(now, forKey: V2UserKey.scoped(changedAtKeyName))
        defaults.set(DriverType.learner.rawValue, forKey: V2UserKey.scoped(previousKeyName))
        ProfileManager.shared.save(driverType: .full)
    }

    /// "Switch back to Permit": back to learner tuning, and the Permit
    /// logbook reopens (no volume split).
    static func revert() {
        clear()
        ProfileManager.shared.save(driverType: .learner)
    }

    static func clear() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: V2UserKey.scoped(changedAtKeyName))
        defaults.removeObject(forKey: V2UserKey.scoped(previousKeyName))
    }

    /// The Driver Card's undo row: a License holder who graduated < 7 days ago.
    static func canRevert(now: Date = Date()) -> Bool {
        guard ProfileManager.shared.driverType == .full, let date = permitClosedAt else { return false }
        let age = now.timeIntervalSince(date)
        return age >= 0 && age < undoWindow
    }
}

// MARK: - Name

/// Prefilled with the saved name. ProfileManager trims it and ignores an
/// empty or > 50-character name, so Save is disabled for those.
struct V2NameEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @FocusState private var focused: Bool

    init() {
        _name = State(initialValue: ProfileManager.shared.displayName)
    }

    private var trimmed: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        !trimmed.isEmpty && trimmed.count <= 50
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Your name", text: $name)
                        .font(V2Type.body)
                        .foregroundStyle(V2.label)
                        .textContentType(.name)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled(true)
                        .submitLabel(.done)
                        .focused($focused)
                        .onSubmit(save)
                } footer: {
                    Text(trimmed.count > 50
                         ? "Keep it to 50 characters."
                         : "Up to 50 characters. It's on your Driver Card.")
                }
                .listRowBackground(V2.card)
            }
            .scrollContentBackground(.hidden)
            .background(V2.bg)
            .navigationTitle("Your name")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!canSave)
                }
            }
        }
        .tint(V2.tint)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .onAppear { focused = true }
        .v2AppScheme()
    }

    private func save() {
        guard canSave else { return }
        ProfileManager.shared.save(displayName: name)
        dismiss()
    }
}

// MARK: - Car

/// Year menu `[""] + (1980...this year).reversed()`, then make and model,
/// prefilled on appear. ProfileManager trims and caps them (50 / 50 / 4).
struct V2CarEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var make = ""
    @State private var model = ""
    @State private var year = ""
    @State private var loaded = false

    init() {}

    private var yearOptions: [String] {
        let thisYear = Calendar.current.component(.year, from: Date())
        var options: [String] = [""] + (1980...max(1980, thisYear)).reversed().map { "\($0)" }
        // A saved year outside the menu (older data) still shows as selected.
        if !year.isEmpty && !options.contains(year) {
            options.insert(year, at: 1)
        }
        return options
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(selection: $year) {
                        ForEach(yearOptions, id: \.self) { option in
                            Text(verbatim: option.isEmpty ? "Not set" : option).tag(option)
                        }
                    } label: {
                        fieldLabel("Year")
                    }
                    .pickerStyle(.menu)

                    LabeledContent {
                        TextField("Make", text: $make, prompt: Text(verbatim: "Toyota"))
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled(true)
                            .submitLabel(.next)
                    } label: {
                        fieldLabel("Make")
                    }

                    LabeledContent {
                        TextField("Model", text: $model, prompt: Text(verbatim: "Corolla"))
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled(true)
                            .submitLabel(.done)
                            .onSubmit(save)
                    } label: {
                        fieldLabel("Model")
                    }
                } footer: {
                    Text("Shown on your Profile. Leave it blank to clear it.")
                }
                .listRowBackground(V2.card)
            }
            .font(V2Type.body)
            .scrollContentBackground(.hidden)
            .background(V2.bg)
            .navigationTitle("Your car")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                }
            }
        }
        .tint(V2.tint)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear(perform: prefill)
        .v2AppScheme()
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(verbatim: text)
            .font(V2Type.body)
            .foregroundStyle(V2.label)
    }

    private func prefill() {
        guard !loaded else { return }
        loaded = true
        let profile = ProfileManager.shared
        make = profile.carMake
        model = profile.carModel
        year = profile.carYear
    }

    private func save() {
        ProfileManager.shared.saveCarInfo(make: make, model: model, year: year)
        dismiss()
    }
}

// MARK: - School link

/// Code entry → `validateCode` (no writes). On a found school the caller
/// closes this sheet and opens the consent 0.3 s later (never two sheets at
/// once). Closes itself when `orgId` becomes non-nil.
struct V2SchoolLinkSheet: View {
    @Binding var codeInput: String
    @ObservedObject var manager: SchoolManager
    let onConsentNeeded: () -> Void
    let onDismiss: () -> Void
    @FocusState private var focused: Bool

    private var canFind: Bool {
        !codeInput.trimmingCharacters(in: .whitespaces).isEmpty && !manager.isLoading
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("School code", text: $codeInput, prompt: Text(verbatim: "DRIVE123"))
                        .font(V2Type.body.monospaced())
                        .foregroundStyle(V2.label)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled(true)
                        .keyboardType(.asciiCapable)
                        .submitLabel(.go)
                        .focused($focused)
                        .onSubmit(validateAction)
                        .accessibilityLabel("School code")
                } header: {
                    Text("School code")
                } footer: {
                    if let error = manager.errorMessage, !error.isEmpty {
                        Text(verbatim: error)
                            .foregroundStyle(V2.poor)
                    } else {
                        Text("Your instructor gives you the code.")
                    }
                }
                .listRowBackground(V2.card)

                Section {
                    Button(action: validateAction) {
                        HStack(spacing: 0) {
                            Spacer(minLength: 0)
                            if manager.isLoading {
                                ProgressView()
                            } else {
                                Text("Find School")
                                    .font(V2Type.headline)
                            }
                            Spacer(minLength: 0)
                        }
                        .frame(minHeight: V2.rowMin)
                        .contentShape(Rectangle())
                    }
                    .disabled(!canFind)
                    .accessibilityLabel(manager.isLoading ? "Finding school" : "Find School")
                }
                .listRowBackground(V2.card)
            }
            .scrollContentBackground(.hidden)
            .background(V2.bg)
            .navigationTitle("Link a school")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onDismiss)
                }
            }
        }
        .tint(V2.tint)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .onAppear { focused = true }
        .onChange(of: manager.orgId) { _, id in
            if id != nil { onDismiss() }
        }
        .v2AppScheme()
    }

    private func validateAction() {
        guard canFind else { return }
        Task {
            await manager.validateCode(codeInput)
            if manager.pendingSchool != nil {
                onConsentNeeded()
            }
        }
    }
}

// MARK: - School consent

/// Shown after the code validated, before anything is written. The copy is
/// the launch beta's, word for word. Agree → `confirmJoin`; Cancel →
/// `cancelPending`. Follows the app scheme; an explicit choice is required.
struct V2SchoolConsentSheet: View {
    let school: SchoolManager.PendingSchool
    let onAgree: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    consentRow("eye.fill",
                               "Your driving sessions — scores, metrics, and flagged events — will be visible to instructors at \(school.name).")
                    consentRow("flag.fill",
                               "Instructors may set in-app goals that appear on your home screen.")
                    consentRow("person.fill.checkmark",
                               "You can leave the school at any time in Settings.")
                } header: {
                    Text(verbatim: "Join \(school.name)?")
                        .font(V2Type.sectionHeader)
                        .foregroundStyle(V2.label)
                        .textCase(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 8)
                        .accessibilityAddTraits(.isHeader)
                }
                .listRowBackground(V2.card)

                Section {
                    Button(action: onAgree) {
                        Text("I Agree — Join School")
                            .font(V2Type.headline)
                            .foregroundStyle(V2.fixed(0xFFFFFF))
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(V2.tintFill, in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Shares your drives with \(school.name)")
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(V2.bg)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
        }
        .tint(V2.tint)
        .presentationDetents([.fraction(0.70), .large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled()
        .v2AppScheme()
    }

    private func consentRow(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: symbol)
                .font(V2Type.subheadSemibold)
                .foregroundStyle(V2.label2)
                .frame(width: 24)
                .accessibilityHidden(true)
            Text(verbatim: text)
                .font(V2Type.subhead)
                .foregroundStyle(V2.label)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }
}
