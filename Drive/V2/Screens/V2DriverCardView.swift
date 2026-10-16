//
//  V2DriverCardView.swift
//  Drive — v2 "Road Furniture"
//
//  The Driver Card (§4.14, §6.8): a flat paper card, portrait for a Permit
//  holder and landscape for a License holder. No tilt, holo or motion
//  sensors (the old holographic DriverLicenseView stays compiled but unused).
//  Hold the card to see the route ink; "Got your license?" is the real
//  driverType write (Firestore driverType + licenseStage, scoring tuning)
//  followed by the LICENSED stamp and the switch to the landscape card.
//

import SwiftUI
import UIKit
import FirebaseAuth

struct V2DriverCardView: View {
    @ObservedObject private var library = V2Library.shared
    @ObservedObject private var profile = ProfileManager.shared
    @ObservedObject private var users = UserManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @GestureState private var hold: V2CardHold = .idle
    /// VoiceOver can't hold: an action toggles the ink layer instead.
    @State private var a11yInk = false
    @State private var showHint: Bool
    @State private var openCounted = false
    @State private var shareImage: UIImage? = nil
    @State private var askingLicense = false
    @State private var phase: V2Graduation = .resting
    @State private var stampLanded = false
    @State private var graduationLine: String? = nil

    init() {
        // The hint shows on the first 3 opens (per user).
        let opens = UserDefaults.standard.integer(forKey: V2UserKey.scoped("driverCardOpens"))
        _showHint = State(initialValue: opens < 3)
    }

    var body: some View {
        let portrait = showsPortrait
        let model = cardModel()
        ScrollView {
            scrollContent(model, portrait: portrait)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(V2.bg.ignoresSafeArea())
        .navigationTitle("Driver Card")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let image = shareImage {
                    ShareLink(item: RenderedDriveCard(image: image),
                              preview: SharePreview("Driver Card", image: Image(uiImage: image))) {
                        Image(systemName: "square.and.arrow.up")
                            .fontWeight(.semibold)
                    }
                    .accessibilityLabel("Share Driver Card")
                }
            }
        }
        .alert("Got your license?", isPresented: $askingLicense) {
            Button("Not yet", role: .cancel) {}
            Button("I got it") { graduate() }
        } message: {
            Text("We'll close your Permit logbook and switch scoring to licensed-driver tuning.")
        }
        .onChange(of: hold == .holding) { _, holding in
            if holding { V2Haptics.play(.soft) }
        }
        .task(id: shareKey(model, portrait: portrait)) {
            renderShare(model, portrait: portrait)
        }
        .task { countOpen() }
    }

    /// Card, hint line, rows and footer (split out to keep `body` cheap to type-check).
    private func scrollContent(_ model: V2CardModel, portrait: Bool) -> some View {
        VStack(spacing: 0) {
            card(model, portrait: portrait)
                .padding(.top, 14)
            lineSlot
            rows(portrait: portrait)
                .padding(.top, lineVisible ? 18 : 24)
            Text("Drive app card. Not a government ID.")
                .font(V2Type.footnote)
                .foregroundStyle(V2.label2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.top, 32)
                .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Card

    /// Learner → portrait. The stamp holds the portrait card up while it lands.
    private var showsPortrait: Bool {
        phase == .stamping || profile.driverType == .learner
    }

    private var inkVisible: Bool { hold == .holding || a11yInk }

    private func card(_ model: V2CardModel, portrait: Bool) -> some View {
        let holdGesture = LongPressGesture(minimumDuration: 0.5)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .updating($hold) { value, state, _ in
                switch value {
                case .first(true):     state = .pressing
                case .second(true, _): state = .holding
                default:               state = .idle
                }
            }
        return ZStack {
            if portrait {
                V2DriverCardFace(model: model, portrait: true, inkVisible: inkVisible,
                                 stampLanded: phase == .stamping ? stampLanded : nil)
                    .transition(.opacity)
            } else {
                V2DriverCardFace(model: model, portrait: false, inkVisible: inkVisible,
                                 stampLanded: nil)
                    .transition(.opacity)
            }
        }
        .frame(width: portrait ? V2CardLayout.portrait.size.width : V2CardLayout.landscape.size.width,
               height: portrait ? V2CardLayout.portrait.size.height : V2CardLayout.landscape.size.height)
        .contentShape(RoundedRectangle(cornerRadius: V2.radiusDriverCard, style: .continuous))
        .gesture(holdGesture)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenCard(model, portrait: portrait))
        .accessibilityAction(named: a11yInk ? "Hide route ink" : "Show route ink") {
            a11yInk.toggle()
        }
    }

    // MARK: Hint / graduation line

    private var lineVisible: Bool { currentLine != nil }

    private var currentLine: (text: String, emphasised: Bool)? {
        if phase == .licensed, profile.driverType == .full, let graduationLine {
            return (graduationLine, true)
        }
        if showHint { return ("Hold the card to see your route ink.", false) }
        return nil
    }

    @ViewBuilder
    private var lineSlot: some View {
        if let line = currentLine {
            Text(verbatim: line.text)
                .font(line.emphasised ? V2Type.subheadSemibold : V2Type.footnote)
                .foregroundStyle(line.emphasised ? V2.label : V2.label2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.top, 24)
                .transition(.opacity)
        }
    }

    // MARK: Rows

    private func rows(portrait: Bool) -> some View {
        VStack(spacing: 0) {
            NavigationLink(value: V2Destination.logbook) {
                HStack(spacing: 8) {
                    Text("Logbook")
                        .font(V2Type.body)
                        .foregroundStyle(V2.label)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(V2Type.footnoteSemibold)
                        .foregroundStyle(V2.label3)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 16)
                .frame(minHeight: V2.rowMin)
            }
            .buttonStyle(V2RowButtonStyle())

            V2CardRowSeparator()

            if let image = shareImage {
                ShareLink(item: RenderedDriveCard(image: image),
                          preview: SharePreview("Driver Card", image: Image(uiImage: image))) {
                    rowLabel("Share card", color: V2.tint)
                }
                .buttonStyle(V2RowButtonStyle())
                .accessibilityLabel("Share your Driver Card")
            } else {
                rowLabel("Share card", color: V2.label3)
                    .accessibilityLabel("Share card, preparing")
            }

            if portrait && phase == .resting {
                V2CardRowSeparator()
                Button {
                    askingLicense = true
                } label: {
                    rowLabel("Got your license?", color: V2.tint)
                }
                .buttonStyle(V2RowButtonStyle())
            }
        }
        .background(V2.card, in: RoundedRectangle(cornerRadius: V2.radiusCard, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: V2.radiusCard, style: .continuous))
        .padding(.horizontal, 16)
    }

    private func rowLabel(_ title: String, color: Color) -> some View {
        Text(verbatim: title)
            .font(V2Type.body)
            .foregroundStyle(color)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: V2.rowMin, alignment: .leading)
    }

    // MARK: Model

    private func cardModel() -> V2CardModel {
        let snapshot = library.snapshot
        let stats = snapshot.stats
        let tier = snapshot.badges.filter { !$0.isOneTime }.compactMap(\.currentTier).max()
        // AVG is the 30-day average; a lapsed driver falls back to every counted drive.
        let counted = snapshot.facts.filter(\.isCounted).map(\.score)
        let average = stats.thirtyDay ?? (counted.isEmpty ? nil : counted.reduce(0, +) / Double(counted.count))
        let photo = profile.avatarImageData.flatMap { UIImage(data: $0) }
        return V2CardModel(name: holderName,
                           number: V2CardCopy.cardNumber(joinDate: profile.joinDate, drives: stats.totalDrives),
                           average: average,
                           drives: stats.totalDrives,
                           best: stats.bestScore,
                           since: V2Format.monthYear(profile.joinDate).uppercased(),
                           sinceSpoken: V2CardCopy.monthYearLong(profile.joinDate),
                           tier: tier,
                           photo: photo,
                           photoBytes: profile.avatarImageData?.count ?? 0,
                           route: inkRoute(snapshot))
    }

    /// displayName, else the email prefix capitalised, else "Driver".
    private var holderName: String {
        let trimmed = profile.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        if let email = users.user?.email,
           let prefix = email.split(separator: "@").first, !prefix.isEmpty {
            return String(prefix).capitalized
        }
        return "Driver"
    }

    /// The most-driven route's latest polyline; else the newest drive with GPS.
    private func inkRoute(_ snapshot: V2Snapshot) -> [CGPoint] {
        let withGPS = snapshot.facts.filter { $0.session.route.count >= 2 }
        if let most = snapshot.stats.mostDriven,
           let latest = withGPS.first(where: { $0.routeName == most.name }) {
            return V2CardCopy.project(latest.session.route)
        }
        if let newest = withGPS.first {
            return V2CardCopy.project(newest.session.route)
        }
        return []
    }

    private func spokenCard(_ m: V2CardModel, portrait: Bool) -> String {
        var parts = ["Driver Card, \(portrait ? "learner" : "driver")",
                     "\(m.name), card \(m.number)"]
        if let avg = m.average {
            let letter = grade(for: avg)
                .replacingOccurrences(of: "\u{2212}", with: " minus")
                .replacingOccurrences(of: "+", with: " plus")
            parts.append("Average \(V2Voice.scoreText(avg)), \(letter)")
        }
        parts.append("\(m.drives) \(m.drives == 1 ? "drive" : "drives")")
        if let best = m.best { parts.append("Best \(V2Voice.scoreText(best))") }
        parts.append("Member since \(m.sinceSpoken)")
        if let tier = m.tier { parts.append("\(V2Voice.tierWord(tier)) tier") }
        return parts.joined(separator: ". ") + "."
    }

    // MARK: Share

    private func shareKey(_ m: V2CardModel, portrait: Bool) -> String {
        [m.name, m.number,
         m.average.map { V2Voice.scoreText($0) } ?? "-",
         "\(m.drives)",
         m.best.map { V2Voice.scoreText($0) } ?? "-",
         m.since,
         m.tier.map { "\($0.rawValue)" } ?? "0",
         portrait ? "p" : "l",
         colorScheme == .dark ? "dark" : "light",
         "\(m.photoBytes)"].joined(separator: "|")
    }

    /// The card at rest (no ink) on the screen background, 3×, in the
    /// screen's colour scheme set explicitly (ImageRenderer doesn't inherit it).
    private func renderShare(_ m: V2CardModel, portrait: Bool) {
        let content = V2DriverCardFace(model: m, portrait: portrait, inkVisible: false, stampLanded: nil)
            .padding(24)
            .background(V2.bg)
            .environment(\.colorScheme, colorScheme)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 3
        renderer.isOpaque = true
        shareImage = renderer.uiImage
    }

    // MARK: First opens

    private func countOpen() {
        guard !openCounted else { return }
        openCounted = true
        let key = V2UserKey.scoped("driverCardOpens")
        let opens = UserDefaults.standard.integer(forKey: key)
        UserDefaults.standard.set(opens + 1, forKey: key)
    }

    // MARK: Graduation

    /// "I got it": the real backend write, then STAMP + crossfade to the
    /// landscape card. Reduce Motion: the crossfade only.
    private func graduate() {
        let stats = library.snapshot.stats
        let line = V2CardCopy.graduationLine(drives: stats.totalDrives, minutes: stats.totalMinutes)
        a11yInk = false
        if reduceMotion {
            withAnimation(.easeInOut(duration: 0.3)) {
                ProfileManager.shared.save(driverType: .full)
                graduationLine = line
                phase = .licensed
            }
            return
        }
        // Hold the portrait card up (phase) before the type flips underneath it.
        stampLanded = false
        phase = .stamping
        ProfileManager.shared.save(driverType: .full)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            withAnimation(V2Motion.stamp) { stampLanded = true }
            V2Haptics.play(.stamp)
            try? await Task.sleep(for: .milliseconds(700))
            withAnimation(.easeInOut(duration: 0.3)) {
                graduationLine = line
                phase = .licensed
            }
        }
    }
}

// MARK: - State types

fileprivate enum V2CardHold: Equatable {
    case idle, pressing, holding
}

fileprivate enum V2Graduation: Equatable {
    case resting, stamping, licensed
}

/// Everything the card face draws, read fresh from the managers each render.
fileprivate struct V2CardModel {
    let name: String
    let number: String
    let average: Double?
    let drives: Int
    let best: Double?
    let since: String
    let sinceSpoken: String
    let tier: BadgeTier?
    let photo: UIImage?
    let photoBytes: Int
    /// Projected route (x east, y south), any scale; the face aspect-fits it.
    let route: [CGPoint]
}

// MARK: - Geometry (board v2-DriverCard, px = pt)

fileprivate struct V2CardLayout {
    let size: CGSize
    let photo: CGPoint
    let name: CGPoint, nameWidth: CGFloat
    let number: CGPoint, numberWidth: CGFloat
    let avg: CGPoint, drives: CGPoint, best: CGPoint, since: CGPoint
    let leftWidth: CGFloat, rightWidth: CGFloat
    let carY: CGFloat
    let dotsY: CGFloat
    /// Route ink box in card coordinates.
    let routeBox: CGRect

    static let portrait = V2CardLayout(
        size: CGSize(width: 240, height: 380),
        photo: CGPoint(x: 20, y: 68),
        name: CGPoint(x: 108, y: 66), nameWidth: 112,
        number: CGPoint(x: 108, y: 126), numberWidth: 112,
        avg: CGPoint(x: 20, y: 176), drives: CGPoint(x: 108, y: 176),
        best: CGPoint(x: 20, y: 226), since: CGPoint(x: 108, y: 226),
        leftWidth: 88, rightWidth: 112,
        carY: 327, dotsY: 352,
        routeBox: CGRect(x: 20, y: 64, width: 200, height: 292))

    static let landscape = V2CardLayout(
        size: CGSize(width: 358, height: 226),
        photo: CGPoint(x: 20, y: 64),
        name: CGPoint(x: 108, y: 61), nameWidth: 116,
        number: CGPoint(x: 224, y: 61), numberWidth: 114,
        avg: CGPoint(x: 108, y: 103), drives: CGPoint(x: 224, y: 103),
        best: CGPoint(x: 108, y: 145), since: CGPoint(x: 224, y: 145),
        leftWidth: 116, rightWidth: 114,
        carY: 173, dotsY: 198,
        routeBox: CGRect(x: 112, y: 58, width: 226, height: 156))
}

// MARK: - Card face

/// The flat card: `card` face, INK header band, photo, fields, car XL,
/// tier Botts' dots and a 2 pt tier-colour rim inset 6. Fixed size: it is a
/// drawn object, so its type doesn't reflow with Dynamic Type.
fileprivate struct V2DriverCardFace: View {
    let model: V2CardModel
    let portrait: Bool
    let inkVisible: Bool
    /// nil: no stamp. false → true plays the LICENSED STAMP.
    let stampLanded: Bool?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(model: V2CardModel, portrait: Bool, inkVisible: Bool, stampLanded: Bool?) {
        self.model = model
        self.portrait = portrait
        self.inkVisible = inkVisible
        self.stampLanded = stampLanded
    }

    private var layout: V2CardLayout { portrait ? .portrait : .landscape }
    private var rim: Color { model.tier.map { V2.tierColor($0) } ?? V2.paint }

    var body: some View {
        let l = layout
        let w = l.size.width
        let h = l.size.height
        ZStack(alignment: .topLeading) {
            header(width: w - 12)
                .offset(x: 6, y: 6)

            photo
                .offset(x: l.photo.x, y: l.photo.y)

            inkLayer(width: w - 16, height: h - 60, routeBox: l.routeBox)
                .offset(x: 8, y: 52)

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
        .overlay {
            if let landed = stampLanded {
                V2LicensedStamp()
                    .rotationEffect(.degrees(-6))
                    .scaleEffect(landed ? 1 : 1.5)
                    .opacity(landed ? 1 : 0)
                    .offset(y: 24)
            }
        }
    }

    /// NAME / CARD and the 2×2 stat grid at their card coordinates (a
    /// separate builder so the face's ZStack stays small for the type checker).
    @ViewBuilder
    private func fields(_ l: V2CardLayout) -> some View {
        V2CardField("NAME", width: l.nameWidth) {
            Text(verbatim: model.name)
                .font(V2CardFont.value)
                .foregroundStyle(V2.label)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .offset(x: l.name.x, y: l.name.y)

        V2CardField("CARD", width: l.numberWidth) {
            Text(verbatim: model.number)
                .font(V2CardFont.number)
                .foregroundStyle(V2.label)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .offset(x: l.number.x, y: l.number.y)

        V2CardField("AVG", width: l.leftWidth) { avgValue }
            .offset(x: l.avg.x, y: l.avg.y)

        V2CardField("DRIVES", width: l.rightWidth) {
            V2CardValue("\(model.drives)")
        }
        .offset(x: l.drives.x, y: l.drives.y)

        V2CardField("BEST", width: l.leftWidth) { bestValue }
            .offset(x: l.best.x, y: l.best.y)

        V2CardField("SINCE", width: l.rightWidth) {
            V2CardValue(model.since)
        }
        .offset(x: l.since.x, y: l.since.y)
    }

    @ViewBuilder
    private var avgValue: some View {
        if let avg = model.average {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(verbatim: V2Voice.scoreText(avg))
                    .font(V2CardFont.value)
                    .foregroundStyle(V2.label)
                Text(verbatim: grade(for: avg))
                    .font(V2Type.gradeLetter(15))
                    .foregroundStyle(V2Band(score: avg).color)
            }
            .lineLimit(1)
        } else {
            V2CardValue("\u{2014}", color: V2.label2)
        }
    }

    @ViewBuilder
    private var bestValue: some View {
        if let best = model.best {
            V2CardValue(V2Voice.scoreText(best))
        } else {
            V2CardValue("\u{2014}", color: V2.label2)
        }
    }

    private func header(width: CGFloat) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                V2BrandMark(size: 20, color: V2.bg)
                    .offset(y: 1)
                Text("Drive")
                    .font(V2CardFont.brand)
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

    /// Hold-to-reveal ink: repeating 6 pt microtext of the card number at 30%
    /// and the route polyline in the tier colour at 40%. Fades over 200 ms.
    private func inkLayer(width: CGFloat, height: CGFloat, routeBox: CGRect) -> some View {
        // routeBox is in card coordinates; the layer starts at (8, 52).
        let box = routeBox.offsetBy(dx: -8, dy: -52)
        return ZStack(alignment: .topLeading) {
            Text(verbatim: String(repeating: model.number + " ", count: 200))
                .font(V2CardFont.micro)
                .foregroundStyle(V2.paint)
                .lineSpacing(1)
                .frame(width: width - 4, alignment: .topLeading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 2)
                .padding(.top, 3)
                .opacity(0.3)
            V2CardRouteInk(points: model.route, box: box, color: rim)
                .frame(width: width, height: height)
        }
        .frame(width: width, height: height, alignment: .topLeading)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 10,
                                          bottomTrailingRadius: 10, topTrailingRadius: 0,
                                          style: .continuous))
        .opacity(inkVisible ? 1 : 0)
        .animation(V2Motion.reduced(.easeInOut(duration: 0.2), reduceMotion: reduceMotion), value: inkVisible)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var dotCount: Int { model.tier?.rawValue ?? 0 }
    private var dotsWidth: CGFloat { dotCount > 0 ? CGFloat(dotCount) * 6 + CGFloat(dotCount - 1) * 4 : 0 }

    private var dots: some View {
        HStack(spacing: 4) {
            ForEach(0..<dotCount, id: \.self) { _ in
                Circle()
                    .fill(rim)
                    .frame(width: 6, height: 6)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Fixed card fonts (all from V2Type).
fileprivate enum V2CardFont {
    static let value = V2Type.fixedSize(20, weight: .semibold).monospacedDigit()
    static let number = V2Type.fixedSize(15, weight: .semibold).width(.condensed).monospacedDigit()
    static let brand = V2Type.fixedSize(17, weight: .bold)
    static let micro = V2Type.fixedSize(6, weight: .semibold).monospacedDigit()
}

/// Field label (Compressed Semibold 10, label2, uppercase) over its value.
fileprivate struct V2CardField<Value: View>: View {
    let label: String
    let width: CGFloat
    let value: Value

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

/// A plain field value: 20 Semibold tabular.
fileprivate struct V2CardValue: View {
    let text: String
    let color: Color

    init(_ text: String, color: Color = V2.label) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(verbatim: text)
            .font(V2CardFont.value)
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }
}

/// The route polyline, aspect-fit into `box`, 2 pt round, colour at 40%.
fileprivate struct V2CardRouteInk: View {
    let points: [CGPoint]
    let box: CGRect
    let color: Color

    var body: some View {
        Canvas { ctx, _ in
            guard points.count >= 2 else { return }
            let xs = points.map(\.x)
            let ys = points.map(\.y)
            guard let minX = xs.min(), let maxX = xs.max(),
                  let minY = ys.min(), let maxY = ys.max() else { return }
            let w = maxX - minX
            let h = maxY - minY
            guard w > 0 || h > 0 else { return }
            let s = min(w > 0 ? box.width / w : .greatestFiniteMagnitude,
                        h > 0 ? box.height / h : .greatestFiniteMagnitude)
            let ox = box.minX + (box.width - w * s) / 2
            let oy = box.minY + (box.height - h * s) / 2
            var path = Path()
            for (i, p) in points.enumerated() {
                let q = CGPoint(x: ox + (p.x - minX) * s, y: oy + (p.y - minY) * s)
                if i == 0 { path.move(to: q) } else { path.addLine(to: q) }
            }
            ctx.stroke(path, with: .color(color.opacity(0.4)),
                       style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
    }
}

/// GUIDE "LICENSED" plate: 120×44, white Compressed Heavy 22 on guide green
/// with the white inner rim of a guide sign.
fileprivate struct V2LicensedStamp: View {
    var body: some View {
        let white = V2.fixed(0xFFFFFF)
        return Text(verbatim: "LICENSED")
            .font(V2Type.plate(22, weight: .heavy))
            .foregroundStyle(white)
            .lineLimit(1)
            .frame(width: 120, height: 44)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(V2.guideGreen)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(white, lineWidth: 1.5)
                    .padding(3)
            }
            .accessibilityHidden(true)
    }
}

/// Inset-group separator (0.5 pt `sep`, inset 16).
fileprivate struct V2CardRowSeparator: View {
    var body: some View {
        Rectangle()
            .fill(V2.sep)
            .frame(height: 0.5)
            .padding(.leading, 16)
            .accessibilityHidden(true)
    }
}

// MARK: - Copy and math

fileprivate enum V2CardCopy {
    private static let numberDate: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyMMdd"
        return f
    }()

    private static let longMonthYear: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("MMMMyyyy")
        return f
    }()

    /// "DRV-260604-028": join date + 3-digit total drive count.
    static func cardNumber(joinDate: Date, drives: Int) -> String {
        "DRV-\(numberDate.string(from: joinDate))-\(String(format: "%03d", max(0, drives)))"
    }

    /// "June 2026" (VoiceOver).
    static func monthYearLong(_ date: Date) -> String {
        longMonthYear.string(from: date)
    }

    /// "From Permit to License. 28 drives and 12 hours got you here."
    static func graduationLine(drives: Int, minutes: Int) -> String {
        guard drives > 0 else { return "From Permit to License." }
        let d = drives == 1 ? "1 drive" : "\(drives) drives"
        let hours = minutes / 60
        let time: String
        if hours >= 1 {
            time = hours == 1 ? "1 hour" : "\(hours) hours"
        } else {
            time = minutes == 1 ? "1 minute" : "\(max(0, minutes)) minutes"
        }
        return "From Permit to License. \(d) and \(time) got you here."
    }

    /// Equirectangular projection (x east, y south), ≤ ~240 points, skipping
    /// 0,0 fixes. Scale is irrelevant: the face aspect-fits it.
    static func project(_ route: [RoutePoint]) -> [CGPoint] {
        let pts = route.filter { abs($0.lat) > 0.0001 || abs($0.lng) > 0.0001 }
        guard pts.count >= 2 else { return [] }
        let step = max(1, pts.count / 240)
        var indices = Array(stride(from: 0, to: pts.count, by: step))
        if indices.last != pts.count - 1 { indices.append(pts.count - 1) }
        let meanLat = indices.reduce(0.0) { $0 + pts[$1].lat } / Double(indices.count)
        let k = cos(meanLat * .pi / 180)
        return indices.map { i in
            CGPoint(x: pts[i].lng * k, y: -pts[i].lat)
        }
    }
}
