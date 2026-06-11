//
//  SettingsView.swift
//  Drive
//
import SwiftUI
import PhotosUI
import UserNotifications

// MARK: – SettingsView

struct SettingsView: View {
    @StateObject private var prefs = AppPreferences.shared

    @State private var appeared      = false
    @State private var showNameSheet = false
    @State private var nameInput     = ""
    @State private var showCarSheet  = false
    @State private var carMakeInput  = ""
    @State private var carModelInput = ""
    @State private var carYearInput  = ""
    @State private var showClearAlert = false
    @State private var showDeleteAccountAlert = false
    @State private var isDeletingAccount = false
    @State private var deleteAccountError: String? = nil

    // Avatar crop flow
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var imageForCrop: UIImage?   = nil
    @State private var showCropView             = false

    @ObservedObject private var userManager    = UserManager.shared
    @ObservedObject private var profileManager = ProfileManager.shared
    @ObservedObject private var driveStorage   = DriveStorage.shared
    @ObservedObject private var schoolManager  = SchoolManager.shared
    @State private var showSchoolSheet         = false
    @State private var showConsentSheet        = false
    @State private var schoolCodeInput         = ""
    @State private var showLeaveSchoolAlert    = false

    private var displayNameOrFallback: String {
        if !profileManager.displayName.isEmpty { return profileManager.displayName }
        return userManager.user?.email?.components(separatedBy: "@").first?.capitalized ?? "Driver"
    }
    private var userInitial: String { displayNameOrFallback.prefix(1).uppercased() }
    private var userEmail: String   { userManager.user?.email ?? "Guest" }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var avgScore: Double {
        let s = driveStorage.sessions
        guard !s.isEmpty else { return 0 }
        return s.map(\.score).reduce(0, +) / Double(s.count)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DS.Colors.bg.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: DS.Spacing.xl) {

                        // ── Profile card
                        profileCard
                            .padding(.top, DS.Spacing.s)
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 12)

                        // ── Driver Profile
                        settingSection("Driver Profile") {
                            HStack(spacing: DS.Spacing.m) {
                                Text("License Type")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(.primary)
                                Spacer()
                                HStack(spacing: 6) {
                                    ForEach(DriverType.allCases, id: \.rawValue) { type in
                                        let sel = profileManager.driverType == type
                                        Button {
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                                profileManager.save(driverType: type)
                                            }
                                        } label: {
                                            Text(type.label)
                                                .font(.system(size: 13, weight: .semibold))
                                                .foregroundColor(sel ? .white : DS.Colors.secondary)
                                                .padding(.horizontal, 14).padding(.vertical, 8)
                                                .background(
                                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                        .fill(sel ? DS.Colors.accent : Color.white.opacity(0.07))
                                                )
                                        }
                                        .buttonStyle(.plain)
                                        .sensoryFeedback(.impact(weight: .light), trigger: sel)
                                    }
                                }
                            }
                            .padding(.vertical, DS.Spacing.s)
                        }

                        // ── My Car
                        settingSection("My Car") {
                            Button { showCarSheet = true } label: {
                                HStack(spacing: DS.Spacing.m) {
                                    if profileManager.carDisplayName.isEmpty {
                                        Text("Add your car")
                                            .font(.system(size: 15, weight: .medium))
                                            .foregroundColor(DS.Colors.secondary)
                                    } else {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(profileManager.carDisplayName)
                                                .font(.system(size: 15, weight: .semibold))
                                                .foregroundColor(.primary)
                                            Text("Tap to edit")
                                                .font(.system(size: 11, weight: .medium))
                                                .foregroundColor(DS.Colors.secondary)
                                        }
                                    }
                                    Spacer()
                                    PhosphorIcon(name: "caret-right", size: 12, color: DS.Colors.secondary.opacity(0.55), weight: .bold)
                                }
                                .padding(.vertical, DS.Spacing.s)
                            }
                            .buttonStyle(.plain)
                            .sensoryFeedback(.impact(weight: .light), trigger: showCarSheet)
                        }

                        // ── My School
                        settingSection("My School") {
                            if let name = schoolManager.schoolName {
                                VStack(spacing: 0) {
                                    HStack(spacing: DS.Spacing.m) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(name)
                                                .font(.system(size: 15, weight: .semibold))
                                                .foregroundColor(.primary)
                                            Text(schoolManager.orgId ?? "")
                                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                                .foregroundColor(DS.Colors.secondary)
                                        }
                                        Spacer()
                                        if !schoolManager.subscriptionActive {
                                            Text("Inactive")
                                                .font(.system(size: 12, weight: .semibold))
                                                .foregroundColor(.orange)
                                        } else {
                                            Text("Active")
                                                .font(.system(size: 12, weight: .semibold))
                                                .foregroundColor(DS.Colors.scoreGreat)
                                        }
                                    }
                                    .padding(.vertical, DS.Spacing.s)

                                    if !schoolManager.subscriptionActive {
                                        Text("Your school's subscription has lapsed. Contact your instructor to reactivate access.")
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(.orange.opacity(0.85))
                                            .padding(.vertical, DS.Spacing.xs)
                                    }

                                    settingDivider

                                    Button {
                                        showLeaveSchoolAlert = true
                                    } label: {
                                        HStack {
                                            Text("Leave School")
                                                .font(.system(size: 14, weight: .semibold))
                                                .foregroundColor(.red.opacity(0.8))
                                            Spacer()
                                        }
                                        .padding(.vertical, DS.Spacing.s)
                                    }
                                    .buttonStyle(.plain)
                                }
                            } else {
                                Button { showSchoolSheet = true } label: {
                                    HStack(spacing: DS.Spacing.m) {
                                        Text("Link to a driving school")
                                            .font(.system(size: 15, weight: .medium))
                                            .foregroundColor(DS.Colors.secondary)
                                        Spacer()
                                        PhosphorIcon(name: "caret-right", size: 12,
                                                     color: DS.Colors.secondary.opacity(0.55), weight: .bold)
                                    }
                                    .padding(.vertical, DS.Spacing.s)
                                }
                                .buttonStyle(.plain)
                                .sensoryFeedback(.impact(weight: .light), trigger: showSchoolSheet)
                            }
                        }

                        // ── Drive Settings
                        settingSection("Drive Settings") {
                            SettingsToggle(label: "Dark Mode", isOn: Binding(
                                get: { !prefs.lightModeEnabled },
                                set: { _ in prefs.toggleModeWithGreyFade() }
                            ))
                            settingDivider
                            SettingsToggle(label: "Prompt to Tag Routes", isOn: $prefs.routeTagEnabled)
                            settingDivider
                            SettingsToggle(label: "Share Anonymous Data", isOn: $prefs.shareAnonymousData)
                        }

                        // ── About
                        settingSection("About") {
                            SettingsRow(label: "Version \(appVersion)", showChevron: false)
                            settingDivider
                            Link(destination: URL(string: "https://your-site.com/privacy")!) {
                                SettingsRow(label: "Privacy Policy", showChevron: true)
                            }
                            settingDivider
                            Link(destination: URL(string: "mailto:feedback@your-site.com")!) {
                                SettingsRow(label: "Send Feedback", showChevron: true)
                            }
                        }

                        // Sign out — neutral primary action
                        Button { userManager.signOut() } label: {
                            Text("Sign Out")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.primary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, DS.Spacing.m)
                        }
                        .sensoryFeedback(.impact(weight: .medium), trigger: userManager.user == nil)
                        .padding(.top, DS.Spacing.xs)

                        // Danger Zone — grouped destructive actions
                        settingSection("Danger Zone") {
                            Button { showClearAlert = true } label: {
                                HStack {
                                    Text("Clear All Drive Data")
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundColor(.red)
                                    Spacer()
                                }
                                .padding(.vertical, DS.Spacing.s)
                            }
                            .buttonStyle(.plain)
                            .sensoryFeedback(.impact(weight: .light), trigger: showClearAlert)
                            settingDivider
                            Button { showDeleteAccountAlert = true } label: {
                                HStack {
                                    if isDeletingAccount {
                                        ProgressView()
                                    } else {
                                        Text("Delete Account")
                                            .font(.system(size: 15, weight: .medium))
                                            .foregroundColor(.red)
                                    }
                                    Spacer()
                                }
                                .padding(.vertical, DS.Spacing.s)
                            }
                            .buttonStyle(.plain)
                            .disabled(isDeletingAccount)
                        }
                    }
                    .padding(DS.Spacing.l)
                }
            }
            .navigationBarHidden(true)
        }
        .preferredColorScheme(prefs.lightModeEnabled ? .light : .dark)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) { appeared = true }
        }
        // Name sheet
        .sheet(isPresented: $showNameSheet) {
            NameEditSheet(name: $nameInput, onSave: {
                profileManager.save(displayName: nameInput)
                showNameSheet = false
            }, onCancel: { showNameSheet = false })
            .instrumentBoot()
        }
        // Car sheet
        .sheet(isPresented: $showCarSheet) {
            CarEditSheet(
                make: $carMakeInput, model: $carModelInput, year: $carYearInput,
                onSave: {
                    profileManager.saveCarInfo(make: carMakeInput, model: carModelInput, year: carYearInput)
                    showCarSheet = false
                },
                onCancel: { showCarSheet = false }
            )
            .onAppear {
                carMakeInput  = profileManager.carMake
                carModelInput = profileManager.carModel
                carYearInput  = profileManager.carYear
            }
            .instrumentBoot()
        }
        // School link sheet
        .sheet(isPresented: $showSchoolSheet) {
            SchoolLinkSheet(
                codeInput: $schoolCodeInput,
                manager: schoolManager,
                onConsentNeeded: {
                    showSchoolSheet = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        showConsentSheet = true
                    }
                },
                onDismiss: { showSchoolSheet = false }
            )
            .instrumentBoot()
        }
        // Consent sheet (shown after code validated)
        .sheet(isPresented: $showConsentSheet) {
            if let pending = schoolManager.pendingSchool {
                SchoolConsentSheet(
                    school: pending,
                    onAgree: {
                        showConsentSheet = false
                        Task { await schoolManager.confirmJoin() }
                    },
                    onCancel: {
                        schoolManager.cancelPending()
                        showConsentSheet = false
                    }
                )
                .instrumentBoot()
            }
        }
        // Leave school confirmation
        .confirmationDialog(
            "Leave \(schoolManager.schoolName ?? "School")?",
            isPresented: $showLeaveSchoolAlert,
            titleVisibility: .visible
        ) {
            Button("Leave School", role: .destructive) {
                Task { await schoolManager.leaveSchool() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your sessions will no longer be visible to instructors. You can rejoin with the same code.")
        }
        // Crop view
        .fullScreenCover(isPresented: $showCropView) {
            if let img = imageForCrop {
                AvatarCropView(image: img, onSave: { data in
                    profileManager.saveAvatar(data)
                    showCropView = false
                }, onCancel: { showCropView = false })
            }
        }
        // Photo picker change — runs entirely on MainActor so UIKit calls are thread-safe
        .onChange(of: selectedPhotoItem) { _, item in
            Task { @MainActor in
                guard let data = try? await item?.loadTransferable(type: Data.self),
                      let raw = UIImage(data: data) else { return }
                // Downsample to max 1500px via preparingThumbnail which also
                // normalises EXIF orientation — always safe to draw afterward.
                let maxDim: CGFloat = 1500
                let longest = max(raw.size.width, raw.size.height)
                let targetSize: CGSize = longest > maxDim
                    ? CGSize(width: raw.size.width * maxDim / longest,
                             height: raw.size.height * maxDim / longest)
                    : raw.size
                guard let ready = raw.preparingThumbnail(of: targetSize),
                      ready.size.width > 0, ready.size.height > 0 else { return }
                imageForCrop = ready
                showCropView = true
            }
        }
        // Clear data confirmation
        .confirmationDialog(
            "Clear All Drive Data?",
            isPresented: $showClearAlert,
            titleVisibility: .visible
        ) {
            Button("Clear All Data", role: .destructive) {
                driveStorage.clearAll()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes all your recorded drives locally and from your account. This cannot be undone.")
        }
        // Delete account confirmation
        .confirmationDialog(
            "Delete Your Account?",
            isPresented: $showDeleteAccountAlert,
            titleVisibility: .visible
        ) {
            Button("Delete Account", role: .destructive) {
                isDeletingAccount = true
                driveStorage.clearAll()
                userManager.deleteAccount { error in
                    isDeletingAccount = false
                    if let error {
                        deleteAccountError = error.localizedDescription
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes your account, all drives, and all data. This cannot be undone.")
        }
        // Delete account error
        .alert("Could Not Delete Account", isPresented: Binding(
            get: { deleteAccountError != nil },
            set: { if !$0 { deleteAccountError = nil } }
        )) {
            Button("OK", role: .cancel) { deleteAccountError = nil }
        } message: {
            Text(deleteAccountError ?? "")
        }
    }

    // MARK: – Profile Card

    private var profileCard: some View {
        VStack(spacing: DS.Spacing.m) {

            // ── Avatar + name row
            HStack(spacing: DS.Spacing.m) {
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    ZStack {
                        Circle()
                            .fill(DS.Colors.accent.opacity(0.16))
                            .frame(width: 76, height: 76)
                        if let data = profileManager.avatarImageData,
                           let uiImg = UIImage(data: data) {
                            Image(uiImage: uiImg)
                                .resizable().scaledToFill()
                                .frame(width: 76, height: 76)
                                .clipShape(Circle())
                        } else {
                            Text(userInitial)
                                .font(.system(size: 30, weight: .bold, design: .rounded))
                                .foregroundColor(DS.Colors.accent)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Button {
                        nameInput = profileManager.displayName
                        showNameSheet = true
                    } label: {
                        HStack(spacing: 6) {
                            Text(displayNameOrFallback)
                                .font(.system(size: 19, weight: .black, design: .rounded))
                                .foregroundColor(.primary)
                            PhosphorIcon(name: "pencil", size: 11, color: DS.Colors.accent)
                        }
                    }
                    .buttonStyle(.plain)

                    Text(userEmail)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(DS.Colors.secondary)
                        .lineLimit(1)

                    // Driver type + join date row
                    HStack(spacing: 6) {
                        Text(profileManager.driverType.label)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(DS.Colors.accent)
                        Text("·")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(DS.Colors.secondary.opacity(0.4))
                        Text("Since \(profileManager.joinDate.formatted(.dateTime.month(.abbreviated).year()))")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(DS.Colors.secondary.opacity(0.7))
                    }
                }
                Spacer()
            }

            // ── Stats row
            HStack(spacing: 0) {
                statPill(value: "\(driveStorage.sessions.count)", label: "Drives")
                statPill(
                    value: driveStorage.sessions.isEmpty ? "–" : "\(Int(avgScore))",
                    label: "Avg score"
                )
                statPill(
                    value: driveStorage.sessions.map(\.score).max().map { "\(Int($0))" } ?? "–",
                    label: "Best"
                )
            }
            .padding(.top, DS.Spacing.s)

            // ── Badges
            let earnedBadges = AchievementEngine.badges(from: driveStorage.sessions).filter(\.isEarned)
            if !earnedBadges.isEmpty {
                settingDivider
                HStack {
                    Text("Badges")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(DS.Colors.secondary)
                    Spacer()
                    Text("\(earnedBadges.count) earned")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(DS.Colors.secondary)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    BadgeStripView(badges: earnedBadges)
                }
            }

            // ── Driver Card button
            settingDivider
            NavigationLink(destination: DriverLicenseView()) {
                HStack(spacing: DS.Spacing.m) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Driver Card")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.primary)
                        Text("Share your driving identity")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(DS.Colors.secondary)
                    }
                    Spacer()
                    PhosphorIcon(name: "caret-right", size: 12, color: DS.Colors.secondary.opacity(0.55), weight: .bold)
                }
                .padding(.vertical, DS.Spacing.s)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
    }

    // MARK: – Chip Setting Row (generic via erased Any)

    private func chipSettingRow<T: Hashable>(
        label: String,
        description: String? = nil,
        options: [(T, String)],
        selection: Binding<T>
    ) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.s) {
            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.primary)
                if let description {
                    Text(description)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(DS.Colors.secondary)
                }
            }
            Group {
                if #available(iOS 26, *) {
                    GlassEffectContainer(spacing: 6) {
                        HStack(spacing: 6) {
                            ForEach(options.indices, id: \.self) { i in
                                let (val, lbl) = options[i]
                                let isSelected = selection.wrappedValue == val
                                Button {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                        selection.wrappedValue = val
                                    }
                                } label: {
                                    Text(lbl)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(isSelected ? .white : DS.Colors.secondary)
                                        .padding(.horizontal, 12).padding(.vertical, 7)
                                        .glassEffect(
                                            isSelected ? .regular.tint(DS.Colors.accent.opacity(0.35)).interactive() : .regular.interactive(),
                                            in: .rect(cornerRadius: 8)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                } else {
                    HStack(spacing: 6) {
                        ForEach(options.indices, id: \.self) { i in
                            let (val, lbl) = options[i]
                            let isSelected = selection.wrappedValue == val
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    selection.wrappedValue = val
                                }
                            } label: {
                                Text(lbl)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(isSelected ? .white : DS.Colors.secondary)
                                    .padding(.horizontal, 12).padding(.vertical, 7)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(isSelected ? DS.Colors.accent : Color.white.opacity(0.07))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                    .stroke(isSelected ? Color.clear : Color.white.opacity(0.08), lineWidth: 1)
                                            )
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(.vertical, DS.Spacing.s)
    }

    // MARK: – Shared helpers

    private var settingDivider: some View {
        Rectangle()
            .fill(DS.Colors.cardStroke)
            .frame(height: 0.5)
    }

    @ViewBuilder
    private func settingSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.m) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(DS.Colors.secondary)
                .padding(.leading, 20)
            VStack(spacing: 0) { content() }
                .padding(.horizontal, 20)
        }
    }

    private func statPill(value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundColor(.primary)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(DS.Colors.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: – Name Edit Sheet

struct NameEditSheet: View {
    @Binding var name: String
    let onSave: () -> Void
    let onCancel: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            Color(red: 0.07, green: 0.07, blue: 0.11).ignoresSafeArea()
            VStack(spacing: 0) {
                Capsule().fill(Color.white.opacity(0.15))
                    .frame(width: 36, height: 4).padding(.top, DS.Spacing.m)
                VStack(spacing: DS.Spacing.xl) {
                    Text("Your name")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, DS.Spacing.l)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Name")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(focused ? DS.Colors.accent : DS.Colors.secondary)
                            .animation(.easeInOut(duration: 0.2), value: focused)
                        TextField("Your name", text: $name)
                            .focused($focused)
                            .font(.system(size: 16, weight: .medium)).foregroundColor(.primary)
                            .autocapitalization(.words).disableAutocorrection(true)
                            .submitLabel(.done).onSubmit(onSave)
                            .padding(.vertical, 14).padding(.horizontal, 16)
                            .background(Color.white.opacity(focused ? 0.09 : 0.06))
                            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous)
                                .stroke(focused ? DS.Colors.accent.opacity(0.7) : Color.white.opacity(0.10),
                                        lineWidth: focused ? 1.5 : 1))
                            .animation(.easeInOut(duration: 0.2), value: focused)
                    }
                    VStack(spacing: DS.Spacing.s) {
                        Button(action: onSave) {
                            Text("Save").font(.system(size: 16, weight: .bold)).foregroundColor(.primary)
                                .frame(maxWidth: .infinity).padding(.vertical, 16)
                                .background(RoundedRectangle(cornerRadius: DS.Radius.l, style: .continuous).fill(DS.Colors.accent))
                        }
                        Button(action: onCancel) {
                            Text("Cancel").font(.system(size: 15, weight: .semibold)).foregroundColor(DS.Colors.secondary)
                                .frame(maxWidth: .infinity).padding(.vertical, 12)
                        }
                    }
                }
                .padding(.horizontal, DS.Spacing.xl).padding(.bottom, DS.Spacing.xl)
            }
        }
        .presentationDetents([.fraction(0.42)])
        .presentationDragIndicator(.hidden)
        .preferredColorScheme(AppPreferences.shared.lightModeEnabled ? .light : .dark)
        .onAppear { focused = true }
    }
}

// MARK: – Car Edit Sheet (now includes year)

struct CarEditSheet: View {
    @Binding var make: String
    @Binding var model: String
    @Binding var year: String
    let onSave: () -> Void
    let onCancel: () -> Void
    @FocusState private var focusedField: CarField?

    enum CarField { case make, model }

    private let currentYear = Calendar.current.component(.year, from: Date())
    private var yearOptions: [String] {
        [""] + (1980...Calendar.current.component(.year, from: Date()))
            .reversed().map { "\($0)" }
    }

    var body: some View {
        ZStack {
            Color(red: 0.07, green: 0.07, blue: 0.11).ignoresSafeArea()
            VStack(spacing: 0) {
                Capsule().fill(Color.white.opacity(0.15))
                    .frame(width: 36, height: 4).padding(.top, DS.Spacing.m)
                VStack(spacing: DS.Spacing.xl) {
                    Text("Your car")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, DS.Spacing.l)

                    VStack(spacing: DS.Spacing.m) {
                        // Year picker
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Year")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(DS.Colors.secondary)
                            Menu {
                                ForEach(yearOptions, id: \.self) { y in
                                    Button(y.isEmpty ? "Select year" : y) { year = y }
                                }
                            } label: {
                                HStack {
                                    Text(year.isEmpty ? "Select year" : year)
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(year.isEmpty ? DS.Colors.secondary : .white)
                                    Spacer()
                                    PhosphorIcon(name: "arrows-down-up", size: 12, color: DS.Colors.secondary)
                                }
                                .padding(.vertical, 14).padding(.horizontal, 16)
                                .background(Color.white.opacity(0.06))
                                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous)
                                    .stroke(Color.white.opacity(0.10), lineWidth: 1))
                            }
                        }
                        carField(label: "Make",  placeholder: "e.g. Toyota", text: $make,  field: .make)
                        carField(label: "Model", placeholder: "e.g. Corolla", text: $model, field: .model)
                    }

                    VStack(spacing: DS.Spacing.s) {
                        Button(action: onSave) {
                            Text("Save").font(.system(size: 16, weight: .bold)).foregroundColor(.primary)
                                .frame(maxWidth: .infinity).padding(.vertical, 16)
                                .background(RoundedRectangle(cornerRadius: DS.Radius.l, style: .continuous).fill(DS.Colors.accent))
                        }
                        Button(action: onCancel) {
                            Text("Cancel").font(.system(size: 15, weight: .semibold)).foregroundColor(DS.Colors.secondary)
                                .frame(maxWidth: .infinity).padding(.vertical, 12)
                        }
                    }
                }
                .padding(.horizontal, DS.Spacing.xl).padding(.bottom, DS.Spacing.xl)
            }
        }
        .presentationDetents([.fraction(0.70)])
        .presentationDragIndicator(.hidden)
        .preferredColorScheme(AppPreferences.shared.lightModeEnabled ? .light : .dark)
    }

    @ViewBuilder
    private func carField(label: String, placeholder: String, text: Binding<String>, field: CarField) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(focusedField == field ? DS.Colors.accent : DS.Colors.secondary)
                .animation(.easeInOut(duration: 0.2), value: focusedField)
            TextField(placeholder, text: text)
                .focused($focusedField, equals: field)
                .font(.system(size: 16, weight: .medium)).foregroundColor(.primary)
                .autocapitalization(.words).disableAutocorrection(true)
                .padding(.vertical, 14).padding(.horizontal, 16)
                .background(Color.white.opacity(focusedField == field ? 0.09 : 0.06))
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous)
                    .stroke(focusedField == field ? DS.Colors.accent.opacity(0.7) : Color.white.opacity(0.10),
                            lineWidth: focusedField == field ? 1.5 : 1))
                .animation(.easeInOut(duration: 0.2), value: focusedField)
        }
    }
}

// MARK: – Settings Toggle Row

struct SettingsToggle: View {
    let label: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: DS.Spacing.m) {
            Text(label)
                .font(.system(size: 15, weight: .medium)).foregroundColor(.primary)
            Spacer()
            Toggle("", isOn: $isOn)
                .toggleStyle(SwitchToggleStyle(tint: DS.Colors.accent))
                .labelsHidden()
        }
        .padding(.vertical, DS.Spacing.s)
    }
}

// MARK: – Settings Plain Row

struct SettingsRow: View {
    let label: String
    let showChevron: Bool

    var body: some View {
        HStack(spacing: DS.Spacing.m) {
            Text(label)
                .font(.system(size: 15, weight: .medium)).foregroundColor(.primary)
            Spacer()
            if showChevron {
                PhosphorIcon(name: "caret-right", size: 12, color: DS.Colors.secondary.opacity(0.55), weight: .bold)
            }
        }
        .padding(.vertical, DS.Spacing.s)
    }
}


// MARK: – School Link Sheet

struct SchoolLinkSheet: View {
    @Binding var codeInput: String
    @ObservedObject var manager: SchoolManager
    let onConsentNeeded: () -> Void
    let onDismiss: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            Color(red: 0.07, green: 0.07, blue: 0.11).ignoresSafeArea()
            VStack(spacing: 0) {
                Capsule().fill(Color.white.opacity(0.15))
                    .frame(width: 36, height: 4).padding(.top, DS.Spacing.m)
                VStack(spacing: DS.Spacing.xl) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Link a school")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.primary)
                        Text("Enter the code from your instructor")
                            .font(.system(size: 13))
                            .foregroundColor(DS.Colors.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, DS.Spacing.l)

                    SchoolCodeField(
                        code: $codeInput,
                        focused: $focused,
                        errorMessage: manager.errorMessage
                    )

                    VStack(spacing: DS.Spacing.s) {
                        Button(action: validateAction) {
                            Group {
                                if manager.isLoading {
                                    ProgressView().tint(.white)
                                } else {
                                    Text("Find School")
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundColor(.white)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: DS.Radius.l, style: .continuous)
                                    .fill(DS.Colors.accent)
                            )
                        }
                        .disabled(codeInput.trimmingCharacters(in: .whitespaces).isEmpty || manager.isLoading)
                        Button(action: onDismiss) {
                            Text("Cancel")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(DS.Colors.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                    }
                }
                .padding(.horizontal, DS.Spacing.xl)
                .padding(.bottom, DS.Spacing.xl)
            }
        }
        .presentationDetents([.fraction(0.52)])
        .presentationDragIndicator(.hidden)
        .preferredColorScheme(AppPreferences.shared.lightModeEnabled ? .light : .dark)
        .onAppear { focused = true }
        .onChange(of: manager.orgId) { _, id in
            if id != nil { onDismiss() }
        }
    }

    private func validateAction() {
        Task {
            await manager.validateCode(codeInput)
            if manager.pendingSchool != nil {
                onConsentNeeded()
            }
        }
    }
}

#Preview {
    SettingsView()
}
