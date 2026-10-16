//
//  V2OnboardingPages.swift
//  Drive — v2 "Road Furniture"
//
//  The six onboarding pages (§6.10) and the static Driver Card they end on.
//  Illustrations use the canonical sample drive (§6.0: Friday's School run,
//  73 buckets); the card uses the signed-in account's real profile and drives.
//

import SwiftUI
import UIKit
import FirebaseAuth

// MARK: - Shared page scaffold

private enum V2OnboardingFont {
    /// Page titles: a sentence, 28 Bold, follows Dynamic Type.
    static var title: Font { V2Type.scaled(28, .title1, weight: .bold) }
    /// HUD preview readouts (drawn object, fixed).
    static let readout = V2Type.fixedSize(15, weight: .semibold).width(.condensed).monospacedDigit()
    /// Driver Card values and number (drawn object, fixed).
    static let cardValue = V2Type.fixedSize(20, weight: .semibold).monospacedDigit()
    static let cardNumber = V2Type.fixedSize(15, weight: .semibold).width(.condensed).monospacedDigit()
    static let cardBrand = V2Type.fixedSize(17, weight: .bold)
}

/// One page: the sentence title, one line under it, then the illustration.
/// Scrolls when Dynamic Type makes it taller than the screen.
struct V2OnboardingPageScaffold<Content: View>: View {
    private let title: String
    private let line: String?
    private let content: Content

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(title: String, line: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.line = line
        self.content = content()
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: title)
                    .font(V2OnboardingFont.title)
                    .foregroundStyle(V2.label)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                if let line {
                    // Explanations are coaching copy, so `label` (colour rule 9).
                    Text(verbatim: line)
                        .font(V2Type.body)
                        .foregroundStyle(V2.label)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8)
                }
                content
                    .padding(.top, 32)
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollDismissesKeyboard(.interactively)
    }
}

// MARK: - Canonical sample (§6.0)

/// Friday's School run: 73 buckets of 20 s, calm except these dips.
private enum V2OnboardingSample {
    static let bucketCount = 73
    static let dips: [Int: Double] = [12: 52, 13: 78, 21: 81, 34: 74, 53: 77, 60: 82, 61: 80]

    /// The completed drive: three numbered moments and the 6 min clean run.
    static var strip: V2Strip {
        let buckets: [Double?] = (0..<bucketCount).map { dips[$0] ?? 100 }
        let markers = [
            V2StripMarker(number: 1, bucket: 12, band: .poor, isFocus: false, timeOffset: 252),
            V2StripMarker(number: 2, bucket: 34, band: .okay, isFocus: false, timeOffset: 690),
            V2StripMarker(number: 3, bucket: 53, band: .okay, isFocus: false, timeOffset: 1068)
        ]
        return V2Strip(buckets: buckets, markers: markers, isComplete: true,
                       cleanRun: V2Strip.longestCalmRun(buckets))
    }

    /// The HUD recording sample: 39 of 73 buckets filled (12:48 elapsed).
    static var liveStrip: V2Strip {
        let buckets: [Double?] = (0..<39).map { dips[$0] ?? 100 }
        return V2Strip(buckets: buckets, isComplete: false)
    }

    /// 3:28 PM today → 3:52 PM (the sample's departure and park).
    static var start: Date {
        Calendar.current.date(bySettingHour: 15, minute: 28, second: 0, of: Date()) ?? Date()
    }
    static var end: Date { start.addingTimeInterval(24 * 60) }
}

// MARK: - P1 "You already know this language."

/// The vocabulary, taught once (§4.1 placement rule 7): five 64 pt plates.
struct V2OnboardingLanguagePage: View {
    private struct Family: Identifiable {
        let id: Int
        let plate: V2Plate
        let title: String
        let detail: String
    }

    private var families: [Family] {
        [
            Family(id: 0, plate: V2Plate.category(.braking, size: 64),
                   title: "Braking", detail: "Stops and hard brakes."),
            Family(id: 1, plate: V2Plate.category(.acceleration, size: 64),
                   title: "Going", detail: "Pulling away and speeding up."),
            Family(id: 2, plate: V2Plate.category(.cornering, size: 64),
                   title: "How you handle the road", detail: "Turns, curves, smoothness and pace."),
            Family(id: 3, plate: V2Plate(.yield, legend: .twoCars, size: 64),
                   title: "Other road users", detail: "Following distance, your lane and your attention."),
            Family(id: 4, plate: V2Plate.category(.positive, size: 64),
                   title: "Things you earned", detail: "Badges, bests and jobs cleared.")
        ]
    }

    var body: some View {
        V2OnboardingPageScaffold(title: "You already know this language.",
                                 line: "Drive talks in road signs. Each shape has one job.") {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(families) { family in
                    row(family)
                }
            }
        }
    }

    private func row(_ family: Family) -> some View {
        HStack(spacing: 16) {
            family.plate
                .frame(width: 90, height: 64)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: family.title)
                    .font(V2Type.headline)
                    .foregroundStyle(V2.label)
                Text(verbatim: family.detail)
                    .font(V2Type.subhead)
                    .foregroundStyle(V2.label2)
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - P2 "A clean drive is an empty road."

struct V2OnboardingRoadPage: View {
    var body: some View {
        V2OnboardingPageScaffold(title: "A clean drive is an empty road.",
                                 line: "Calm driving stays on the lane line. Only incidents rise.") {
            V2LaneStrip(strip: V2OnboardingSample.strip,
                        zoneHeight: 120,
                        showBracket: true,
                        startClock: V2Format.clock(V2OnboardingSample.start),
                        endClock: V2Format.clock(V2OnboardingSample.end),
                        car: V2StripCar(position: .parked, size: .l, color: V2.label))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("A sample drive: a calm lane line with three incidents rising from it, and 6 minutes clean.")
        }
    }
}

// MARK: - P3 "One job per drive."

/// The yellow Focus Sign beside the green cleared plate. Static here; the
/// morph itself only ever plays at Parked.
struct V2OnboardingJobPage: View {
    var body: some View {
        V2OnboardingPageScaffold(title: "One job per drive.",
                                 line: "Each drive leaves you one thing to work on. Clear it two drives in a row and it's retired.") {
            HStack(alignment: .top, spacing: 12) {
                sign(cleared: false, caption: "Your one job next drive",
                     spoken: "Your one job next drive: a yellow warning sign.")
                Image(systemName: "arrow.right")
                    .font(V2Type.headline)
                    .foregroundStyle(V2.label3)
                    .frame(height: 120)
                    .accessibilityHidden(true)
                sign(cleared: true, caption: "Job retired",
                     spoken: "Job retired: the sign becomes a green plate with a check.")
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func sign(cleared: Bool, caption: String, spoken: String) -> some View {
        VStack(spacing: 12) {
            V2FocusSign(category: .braking, size: 120, cleared: cleared)
            Text(verbatim: caption)
                .font(V2Type.subheadSemibold)
                .foregroundStyle(V2.label)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }
}

// MARK: - P4 "Try a demo drive."

/// Tap-triggered only; the Continue button skips it.
struct V2OnboardingDemoPage: View {
    private let onPlay: () -> Void

    init(onPlay: @escaping () -> Void) {
        self.onPlay = onPlay
    }

    var body: some View {
        V2OnboardingPageScaffold(title: "Try a demo drive.",
                                 line: "Twenty seconds of a sample drive, then the reveal when you park.") {
            VStack(spacing: 16) {
                // The preview is a second, larger target for the same action.
                Button(action: onPlay) {
                    V2OnboardingHUDPreview()
                }
                .buttonStyle(V2PressableCardStyle())
                .accessibilityHidden(true)

                Button(action: onPlay) {
                    Label("Play demo drive", systemImage: "play.fill")
                        .font(V2Type.headline)
                        .foregroundStyle(V2.tint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(V2.fill, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(V2PressableCardStyle())

                Text(verbatim: "Demo drive. Sample data, nothing is recorded.")
                    .font(V2Type.footnote)
                    .foregroundStyle(V2.label2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

/// A still of the recording HUD (§6.0 sample: 12:48, 89 A−, 4.2 mi, 39
/// buckets). Dark only, like the HUD itself.
private struct V2OnboardingHUDPreview: View {
    private let score: Double = 89

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: "12:48")
                    .font(V2OnboardingFont.readout)
                    .foregroundStyle(V2.label2)
                Spacer(minLength: 8)
                Text(verbatim: "4.2 mi")
                    .font(V2OnboardingFont.readout)
                    .foregroundStyle(V2.label2)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(verbatim: V2Voice.scoreText(score))
                    .font(V2Type.hero(56))
                    .tracking(V2Type.heroTracking(56))
                    .foregroundStyle(V2.label)
                Text(verbatim: grade(for: score))
                    .font(V2Type.gradeLetter(22))
                    .foregroundStyle(V2Band(score: score).color)
            }
            V2LaneStrip(strip: V2OnboardingSample.liveStrip,
                        zoneHeight: 20,
                        neutral: true,
                        showMarkers: false,
                        liveCapacity: V2OnboardingSample.bucketCount,
                        ticks: [12, 34],
                        car: V2StripCar(position: .head, size: .m, color: V2.label2))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(V2.bg, in: RoundedRectangle(cornerRadius: V2.radiusCard, style: .continuous))
        .overlay(
            // A flat bezel so the black screen reads on a black page.
            RoundedRectangle(cornerRadius: V2.radiusCard, style: .continuous)
                .strokeBorder(V2.card2, lineWidth: 4)
        )
        .contentShape(RoundedRectangle(cornerRadius: V2.radiusCard, style: .continuous))
        .environment(\.colorScheme, .dark)
    }
}

// MARK: - Permissions (v1's priming, kept so the first drive behaves the same)

struct V2OnboardingPermissionsPage: View {
    @ObservedObject private var perms: OnboardingPermissions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(perms: OnboardingPermissions) {
        _perms = ObservedObject(wrappedValue: perms)
    }

    var body: some View {
        V2OnboardingPageScaffold(title: "Before your first drive.",
                                 line: "Drive uses these only while you're driving. Nothing runs in the background.") {
            VStack(alignment: .leading, spacing: 12) {
                VStack(spacing: 0) {
                    row(symbol: "camera.fill", title: "Camera",
                        detail: "Sees the road so each drive can be scored. Video only, no sound.",
                        state: perms.camera, action: { perms.requestCamera() })
                    separator
                    row(symbol: "location.fill", title: "Location",
                        detail: "Maps your route and measures speed while you use the app.",
                        state: perms.location, action: { perms.requestLocation() })
                    separator
                    row(symbol: "bell.fill", title: "Notifications",
                        detail: "Parked summaries, streak reminders and new badges.",
                        state: perms.notifications, action: { perms.requestNotifications() })
                }
                .background(V2.card, in: RoundedRectangle(cornerRadius: V2.radiusCard, style: .continuous))

                Text(verbatim: "You can change these any time in Settings.")
                    .font(V2Type.footnote)
                    .foregroundStyle(V2.label2)
                    .padding(.horizontal, 4)
            }
        }
    }

    private var separator: some View {
        Rectangle()
            .fill(V2.sep)
            .frame(height: 0.5)
            .padding(.leading, 58)
            .accessibilityHidden(true)
    }

    private func row(symbol: String, title: String, detail: String, state: PermState,
                     action: @escaping @MainActor () -> Void) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(V2Type.voiceHeadline)
                .foregroundStyle(V2.label)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title)
                    .font(V2Type.headline)
                    .foregroundStyle(V2.label)
                Text(verbatim: detail)
                    .font(V2Type.footnote)
                    .foregroundStyle(V2.label2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 8)
            status(state, title: title, action: action)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 64)
        .animation(V2Motion.reduced(V2Motion.settle, reduceMotion: reduceMotion), value: state)
    }

    /// Live status: a check when allowed; otherwise "Allow" (asks) or
    /// "Settings" (denied → opens Settings), exactly like v1's cards.
    @ViewBuilder
    private func status(_ state: PermState, title: String,
                        action: @escaping @MainActor () -> Void) -> some View {
        switch state {
        case .granted:
            Image(systemName: "checkmark.circle.fill")
                .font(V2Type.voiceHeadline)
                .foregroundStyle(V2.great)
                .frame(minWidth: 44, minHeight: 44)
                .transition(.opacity)
                .accessibilityLabel("\(title) allowed")
        case .undetermined, .denied:
            Button {
                action()
            } label: {
                Text(verbatim: state == .denied ? "Settings" : "Allow")
                    .font(V2Type.subheadSemibold)
                    .foregroundStyle(V2.tint)
                    .lineLimit(1)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 32)
                    .background(V2.fill, in: Capsule())
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .transition(.opacity)
            .accessibilityLabel(actionLabel(state, title: title))
        }
    }

    private func actionLabel(_ state: PermState, title: String) -> String {
        state == .denied ? "Open Settings for \(title)" : "Allow \(title)"
    }
}

// MARK: - P5 "Learning or licensed?"

struct V2OnboardingCardPage: View {
    @Binding private var name: String
    @Binding private var driverType: DriverType
    private let nameFocused: FocusState<Bool>.Binding

    @ObservedObject private var library = V2Library.shared
    @ObservedObject private var profile = ProfileManager.shared
    @ObservedObject private var users = UserManager.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(name: Binding<String>, driverType: Binding<DriverType>, nameFocused: FocusState<Bool>.Binding) {
        _name = name
        _driverType = driverType
        self.nameFocused = nameFocused
    }

    var body: some View {
        V2OnboardingPageScaffold(title: "Learning or licensed?",
                                 line: "This sets your card and how drives are scored. You can change it later in Profile.") {
            VStack(alignment: .leading, spacing: 24) {
                choices
                cardSlot
                nameField
            }
        }
    }

    // MARK: Choice

    private var choices: some View {
        VStack(spacing: 0) {
            choice(.learner, detail: "Learning to drive. Gentler thresholds.")
            Rectangle()
                .fill(V2.sep)
                .frame(height: 0.5)
                .padding(.leading, 16)
                .accessibilityHidden(true)
            choice(.full, detail: "Licensed driver. Standard scoring.")
        }
        .background(V2.card, in: RoundedRectangle(cornerRadius: V2.radiusCard, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: V2.radiusCard, style: .continuous))
    }

    private func choice(_ type: DriverType, detail: String) -> some View {
        let selected = driverType == type
        return Button {
            guard driverType != type else { return }
            V2Haptics.play(.select)
            withAnimation(V2Motion.reduced(V2Motion.settle, reduceMotion: reduceMotion)) {
                driverType = type
            }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: type.label)
                        .font(V2Type.headline)
                        .foregroundStyle(V2.label)
                    Text(verbatim: detail)
                        .font(V2Type.footnote)
                        .foregroundStyle(V2.label2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: "checkmark")
                    .font(V2Type.headline)
                    .foregroundStyle(V2.tint)
                    .opacity(selected ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(minHeight: 60)
        }
        .buttonStyle(V2RowButtonStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Card

    private var cardTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96))
    }

    /// Portrait for Permit, landscape for License; scales down on narrow
    /// phones so the landscape card never clips.
    private var cardSlot: some View {
        let portrait = driverType == .learner
        let size = portrait ? V2OnboardingCard.portraitSize : V2OnboardingCard.landscapeSize
        let model = cardModel()
        return GeometryReader { proxy in
            let scale = min(1, proxy.size.width / size.width)
            // Two branches (not .id) so the choice crossfades one card into the other.
            ZStack {
                if portrait {
                    V2OnboardingCard(model: model, portrait: true)
                        .transition(cardTransition)
                } else {
                    V2OnboardingCard(model: model, portrait: false)
                        .transition(cardTransition)
                }
            }
            .scaleEffect(scale)
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .frame(height: size.height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(model, portrait: portrait))
    }

    private func cardModel() -> V2OnboardingCardModel {
        let snapshot = library.snapshot
        let stats = snapshot.stats
        let tier = snapshot.badges.filter { !$0.isOneTime }.compactMap(\.currentTier).max()
        // AVG is the 30-day average; a lapsed driver falls back to every counted drive.
        let counted = snapshot.facts.filter(\.isCounted).map(\.score)
        let average = stats.thirtyDay ?? (counted.isEmpty ? nil : counted.reduce(0, +) / Double(counted.count))
        return V2OnboardingCardModel(
            name: holderName,
            number: V2OnboardingCardCopy.cardNumber(joinDate: profile.joinDate, drives: stats.totalDrives),
            average: average,
            drives: stats.totalDrives,
            best: stats.bestScore,
            since: V2Format.monthYear(profile.joinDate).uppercased(),
            sinceSpoken: V2Format.monthYear(profile.joinDate),
            tier: tier,
            photo: profile.avatarImageData.flatMap { UIImage(data: $0) })
    }

    /// The name being typed, else the saved name, else the email prefix
    /// capitalised, else "Driver" (the Driver Card's rule).
    private var holderName: String {
        let typed = name.trimmingCharacters(in: .whitespaces)
        if !typed.isEmpty { return typed }
        let saved = profile.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !saved.isEmpty { return saved }
        if let email = users.user?.email,
           let prefix = email.split(separator: "@").first, !prefix.isEmpty {
            return String(prefix).capitalized
        }
        return "Driver"
    }

    private func spoken(_ m: V2OnboardingCardModel, portrait: Bool) -> String {
        var parts = ["Driver Card preview", portrait ? "Learner" : "Driver", "Name \(m.name)"]
        parts.append(m.drives == 1 ? "1 drive" : "\(m.drives) drives")
        if let avg = m.average {
            parts.append("Average \(V2Voice.scoreText(avg)), grade \(grade(for: avg))")
        }
        parts.append("Since \(m.sinceSpoken)")
        return parts.joined(separator: ". ")
    }

    // MARK: Name

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: "Name on your card")
                .font(V2Type.footnoteSemibold)
                .foregroundStyle(V2.label2)
                .padding(.leading, 4)
            TextField("First name (optional)", text: $name)
                .font(V2Type.body)
                .foregroundStyle(V2.label)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .textContentType(.givenName)
                .submitLabel(.done)
                .focused(nameFocused)
                .onSubmit { nameFocused.wrappedValue = false }
                .padding(.horizontal, 16)
                .frame(minHeight: 50)
                .background(V2.card, in: RoundedRectangle(cornerRadius: V2.radiusToken, style: .continuous))
        }
    }
}

// MARK: - Driver Card (static, simplified)

struct V2OnboardingCardModel {
    let name: String
    let number: String
    let average: Double?
    let drives: Int
    let best: Double?
    let since: String
    let sinceSpoken: String
    let tier: BadgeTier?
    let photo: UIImage?
}

private enum V2OnboardingCardCopy {
    private static let numberDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyMMdd"
        return f
    }()

    /// "DRV-260604-028": join date + 3-digit total drive count (the card's rule).
    static func cardNumber(joinDate: Date, drives: Int) -> String {
        "DRV-\(numberDate.string(from: joinDate))-\(String(format: "%03d", max(0, drives)))"
    }
}

/// Card coordinates (board v2-DriverCard, px = pt), same as the Driver Card.
private struct V2OnboardingCardLayout {
    let size: CGSize
    let photo: CGPoint
    let name: CGPoint
    let nameWidth: CGFloat
    let number: CGPoint
    let numberWidth: CGFloat
    let avg: CGPoint
    let drives: CGPoint
    let best: CGPoint
    let since: CGPoint
    let leftWidth: CGFloat
    let rightWidth: CGFloat
    let carY: CGFloat
    let dotsY: CGFloat

    static let portrait = V2OnboardingCardLayout(
        size: CGSize(width: 240, height: 380),
        photo: CGPoint(x: 20, y: 68),
        name: CGPoint(x: 108, y: 66), nameWidth: 112,
        number: CGPoint(x: 108, y: 126), numberWidth: 112,
        avg: CGPoint(x: 20, y: 176), drives: CGPoint(x: 108, y: 176),
        best: CGPoint(x: 20, y: 226), since: CGPoint(x: 108, y: 226),
        leftWidth: 88, rightWidth: 112,
        carY: 327, dotsY: 352)

    static let landscape = V2OnboardingCardLayout(
        size: CGSize(width: 358, height: 226),
        photo: CGPoint(x: 20, y: 64),
        name: CGPoint(x: 108, y: 61), nameWidth: 116,
        number: CGPoint(x: 224, y: 61), numberWidth: 114,
        avg: CGPoint(x: 108, y: 103), drives: CGPoint(x: 224, y: 103),
        best: CGPoint(x: 108, y: 145), since: CGPoint(x: 224, y: 145),
        leftWidth: 116, rightWidth: 114,
        carY: 173, dotsY: 198)
}

/// The flat card (§4.14): `card` face, INK header band, photo, fields, car,
/// tier Botts' dots and a 2 pt tier-colour rim inset 6. No hold-to-reveal ink
/// or stamp here; it's a preview of the card the account will carry.
struct V2OnboardingCard: View {
    static let portraitSize = CGSize(width: 240, height: 380)
    static let landscapeSize = CGSize(width: 358, height: 226)

    private let model: V2OnboardingCardModel
    private let portrait: Bool

    init(model: V2OnboardingCardModel, portrait: Bool) {
        self.model = model
        self.portrait = portrait
    }

    private var layout: V2OnboardingCardLayout { portrait ? .portrait : .landscape }
    private var rim: Color { model.tier.map { V2.tierColor($0) } ?? V2.paint }
    private var dotCount: Int { model.tier?.rawValue ?? 0 }
    private var dotsWidth: CGFloat { dotCount > 0 ? CGFloat(dotCount) * 6 + CGFloat(dotCount - 1) * 4 : 0 }

    var body: some View {
        let l = layout
        let w = l.size.width
        let h = l.size.height
        ZStack(alignment: .topLeading) {
            header(width: w - 12)
                .offset(x: 6, y: 6)

            photo
                .offset(x: l.photo.x, y: l.photo.y)

            fields(l)

            V2Car(.xl, color: V2.label, knockout: V2.card)
                .offset(x: 20, y: l.carY)

            dots
                .offset(x: w - 20 - dotsWidth, y: l.dotsY)

            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(rim, lineWidth: 2)
                .frame(width: w - 12, height: h - 12)
                .offset(x: 6, y: 6)
                .allowsHitTesting(false)
        }
        .frame(width: w, height: h, alignment: .topLeading)
        .background(V2.card)
        .clipShape(RoundedRectangle(cornerRadius: V2.radiusDriverCard, style: .continuous))
        .accessibilityHidden(true)
    }

    /// NAME / CARD and the 2×2 grid (separate so the face's ZStack stays small).
    @ViewBuilder
    private func fields(_ l: V2OnboardingCardLayout) -> some View {
        V2OnboardingCardField("NAME", width: l.nameWidth) {
            Text(verbatim: model.name)
                .font(V2OnboardingFont.cardValue)
                .foregroundStyle(V2.label)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .offset(x: l.name.x, y: l.name.y)

        V2OnboardingCardField("CARD", width: l.numberWidth) {
            Text(verbatim: model.number)
                .font(V2OnboardingFont.cardNumber)
                .foregroundStyle(V2.label)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .offset(x: l.number.x, y: l.number.y)

        V2OnboardingCardField("AVG", width: l.leftWidth) { avgValue }
            .offset(x: l.avg.x, y: l.avg.y)

        V2OnboardingCardField("DRIVES", width: l.rightWidth) {
            value("\(model.drives)")
        }
        .offset(x: l.drives.x, y: l.drives.y)

        V2OnboardingCardField("BEST", width: l.leftWidth) {
            if let best = model.best {
                value(V2Voice.scoreText(best))
            } else {
                value("\u{2014}", color: V2.label2)
            }
        }
        .offset(x: l.best.x, y: l.best.y)

        V2OnboardingCardField("SINCE", width: l.rightWidth) {
            value(model.since)
        }
        .offset(x: l.since.x, y: l.since.y)
    }

    @ViewBuilder
    private var avgValue: some View {
        if let avg = model.average {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(verbatim: V2Voice.scoreText(avg))
                    .font(V2OnboardingFont.cardValue)
                    .foregroundStyle(V2.label)
                Text(verbatim: grade(for: avg))
                    .font(V2Type.gradeLetter(15))
                    .foregroundStyle(V2Band(score: avg).color)
            }
            .lineLimit(1)
        } else {
            value("\u{2014}", color: V2.label2)
        }
    }

    private func value(_ text: String, color: Color = V2.label) -> some View {
        Text(verbatim: text)
            .font(V2OnboardingFont.cardValue)
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    private func header(width: CGFloat) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                V2BrandMark(size: 20, color: V2.bg)
                    .offset(y: 1)
                Text(verbatim: "Drive")
                    .font(V2OnboardingFont.cardBrand)
            }
            Spacer(minLength: 8)
            Text(verbatim: portrait ? "LEARNER" : "DRIVER")
                .font(V2Type.plate(15, weight: .bold))
        }
        .foregroundStyle(V2.bg)
        .lineLimit(1)
        .padding(.horizontal, 14)
        .padding(.top, 2)
        .frame(width: width, height: 46)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 12, bottomLeadingRadius: 0,
                                   bottomTrailingRadius: 0, topTrailingRadius: 12,
                                   style: .continuous)
                .fill(V2.label)
        )
    }

    @ViewBuilder
    private var photo: some View {
        let shape = RoundedRectangle(cornerRadius: V2.radiusPhoto, style: .continuous)
        if let image = model.photo {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 72, height: 90)
                .clipShape(shape)
        } else {
            shape
                .fill(V2.label)
                .frame(width: 72, height: 90)
                .overlay {
                    V2Car(.l, color: V2.bg, knockout: V2.label)
                }
        }
    }

    private var dots: some View {
        HStack(spacing: 4) {
            ForEach(0..<dotCount, id: \.self) { _ in
                Circle()
                    .fill(rim)
                    .frame(width: 6, height: 6)
            }
        }
    }
}

/// Field label (Compressed Semibold 10, label2, uppercase) over its value.
private struct V2OnboardingCardField<Value: View>: View {
    private let label: String
    private let width: CGFloat
    private let value: Value

    init(_ label: String, width: CGFloat, @ViewBuilder value: () -> Value) {
        self.label = label
        self.width = width
        self.value = value()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: label)
                .font(V2Type.plate(10, weight: .semibold))
                .foregroundStyle(V2.label2)
                .frame(height: 12, alignment: .leading)
            value
                .frame(height: 24, alignment: .leading)
        }
        .frame(width: width, alignment: .leading)
    }
}
