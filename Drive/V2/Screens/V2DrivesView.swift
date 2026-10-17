//
//  V2DrivesView.swift
//  Drive — v2 "Road Furniture"
//
//  The Drives tab (§6.3): every drive as a 76 pt row with its S-class lane
//  strip, grouped by calendar week of departure and searchable by route,
//  weekday and part of day. A row DRAWs its strip once, the first time an
//  unrevealed drive is seen here (§4.16), and upgrades from the events strip
//  to the trace strip as traces load.
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct V2DrivesView: View {
    @ObservedObject private var library = V2Library.shared
    @ObservedObject private var router = V2Router.shared
    @Environment(\.colorScheme) private var colorScheme

    @State private var searchText = ""
    @State private var tokens: [V2DrivesRouteToken] = []
    @State private var renamingID: UUID? = nil
    @State private var renameHadRoute = false
    @State private var showingRename = false
    @State private var draftName = ""
    /// What the last route hand-off put in the field, kept so it can be told
    /// apart from the user's own search without re-deriving it from a
    /// snapshot that may have changed since (late load, account switch).
    @State private var handoff: V2DrivesHandoff? = nil

    init() {}

    var body: some View {
        Group {
            if library.snapshot.facts.isEmpty {
                V2DrivesEmptyState()
            } else {
                results
                    .searchable(text: $searchText,
                                tokens: $tokens,
                                suggestedTokens: .constant(suggestedTokens),
                                placement: .navigationBarDrawer(displayMode: .always),
                                prompt: Text("Routes, days, places")) { token in
                        Label(token.name, systemImage: "shield")
                    }
            }
        }
        .background(V2.bg.ignoresSafeArea())
        .navigationTitle("Drives")
        .navigationBarTitleDisplayMode(.large)
        .onAppear { applyRouterSearch() }
        .onChange(of: router.drivesSearch) { _, new in
            if !new.isEmpty {
                applyRouterSearch()
            } else if showsHandoff {
                // Cleared by the router (account switch, "more in Drives"):
                // drop the filter it set.
                handoff = nil
                tokens = []
                searchText = ""
            } else {
                handoff = nil
            }
        }
        .onChange(of: searchText) { _, _ in endRouterSearchIfEdited() }
        .onChange(of: tokens) { _, _ in endRouterSearchIfEdited() }
        .alert(renameTitle, isPresented: $showingRename) {
            TextField("Route name", text: $draftName)
                .textInputAutocapitalization(.sentences)
            Button("Save") { saveRename() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(verbatim: renameMessage)
        }
    }

    // MARK: Results

    @ViewBuilder
    private var results: some View {
        let groups = library.weekGroups(query: query)
        if groups.isEmpty {
            if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ContentUnavailableView.search
            } else {
                ContentUnavailableView.search(text: searchText)
            }
        } else {
            List {
                ForEach(groups) { group in
                    Section {
                        ForEach(group.drives) { facts in
                            V2DrivesRow(facts: facts,
                                        dark: colorScheme == .dark,
                                        onRename: { beginRename(facts.id) })
                        }
                    } header: {
                        V2DrivesSectionHeader(group: group)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(V2.bg)
        }
    }

    /// Route tokens search by shield number; free text by name, weekday,
    /// part of day (V2Library.weekGroups matches every word).
    private var query: String {
        (tokens.map { String($0.id) } + [searchText]).joined(separator: " ")
    }

    /// Route shields offered as tokens when the field opens empty. Hidden once
    /// the user types or picks one, so the suggestions never cover results.
    private var suggestedTokens: [V2DrivesRouteToken] {
        guard tokens.isEmpty, searchText.isEmpty else { return [] }
        return library.snapshot.routeNumbers
            .map { V2DrivesRouteToken(id: $0.value, name: $0.key) }
            .sorted { $0.id < $1.id }
    }

    // MARK: Route hand-off (V2Router.drivesSearch, set by Progress route cards)

    /// The search a route hand-off stands for: the route's shield as a token
    /// when it has a number (exact, unlike the name's words), else the name.
    private func routerSearch(_ route: String) -> V2DrivesHandoff? {
        guard let clean = V2DriveFacts.cleanRouteName(route) else { return nil }
        let numbers = library.snapshot.routeNumbers
        if let number = numbers[clean] {
            return V2DrivesHandoff(tokens: [V2DrivesRouteToken(id: number, name: clean)], text: "")
        }
        let key = V2DriveFacts.routeKey(clean)
        if let match = numbers.first(where: { V2DriveFacts.routeKey($0.key) == key }) {
            return V2DrivesHandoff(tokens: [V2DrivesRouteToken(id: match.value, name: match.key)], text: "")
        }
        return V2DrivesHandoff(tokens: [], text: clean)
    }

    /// True while the field still shows exactly what the last hand-off put there.
    private var showsHandoff: Bool {
        guard let handoff else { return false }
        return tokens == handoff.tokens && searchText == handoff.text
    }

    private func applyRouterSearch() {
        guard let search = routerSearch(router.drivesSearch) else { return }
        handoff = search
        tokens = search.tokens
        searchText = search.text
    }

    /// Clearing (or otherwise editing) the search ends the hand-off, so the
    /// next tap on the same route card filters again.
    private func endRouterSearchIfEdited() {
        guard handoff != nil, !showsHandoff else { return }
        handoff = nil
        if !router.drivesSearch.isEmpty { router.drivesSearch = "" }
    }

    // MARK: Rename (DriveStorage.updateRouteTag, same as the Report)

    private var renameTitle: String {
        renameHadRoute ? "Rename route" : "Name this route"
    }

    private func beginRename(_ id: UUID) {
        let current = library.facts(id)?.routeName
        draftName = current ?? ""
        renameHadRoute = current != nil
        renamingID = id
        showingRename = true
    }

    /// "That's Route 1." when the name is (or folds to) a route that already
    /// has a shield, "It'll be Route 4." when it would get a new one.
    private var renameMessage: String {
        guard let id = renamingID else { return "Drives with the same name share a route number." }
        let route = library.resolveRoute(draftName, renaming: id)
        return route.isNew ? "It'll be Route \(route.number)." : "That's Route \(route.number)."
    }

    /// Saves the existing route's spelling when the typed name matches one
    /// ignoring case, spacing and accents, so "school run" joins "School run".
    /// `renamingID` stays set until the next rename so the message doesn't
    /// change while the alert animates out.
    private func saveRename() {
        guard let id = renamingID else { return }
        let name = library.resolveRoute(draftName, renaming: id).name
        guard !name.isEmpty else { return }
        DriveStorage.shared.updateRouteTag(id: id, tag: name)
    }
}

// MARK: - Search token

/// A route shield as a search token. `id` is the shield number.
fileprivate struct V2DrivesRouteToken: Identifiable, Hashable {
    let id: Int
    let name: String
}

/// The search a route hand-off (V2Router.drivesSearch) filled in.
fileprivate struct V2DrivesHandoff: Equatable {
    let tokens: [V2DrivesRouteToken]
    let text: String
}

// MARK: - Section header

/// "This week" 20 Semibold, trailing "5 drives, avg 87" with the numerals
/// in `label` and the words in 15 `label2`.
fileprivate struct V2DrivesSectionHeader: View {
    let group: V2WeekGroup

    var body: some View {
        let count = group.drives.count
        let avg = group.average.map { V2Voice.scoreText($0) }
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(verbatim: group.title)
                .font(V2Type.voiceHeadline)
                .foregroundStyle(V2.label)
                .lineLimit(1)
            Spacer(minLength: 8)
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(verbatim: "\(count)")
                    .font(V2Type.subheadSemibold.monospacedDigit())
                    .foregroundStyle(V2.label)
                Text(verbatim: count == 1 ? " drive" : " drives")
                    .font(V2Type.subhead)
                    .foregroundStyle(V2.label2)
                if let avg {
                    Text(verbatim: ", avg ")
                        .font(V2Type.subhead)
                        .foregroundStyle(V2.label2)
                    Text(verbatim: avg)
                        .font(V2Type.subheadSemibold.monospacedDigit())
                        .foregroundStyle(V2.label)
                }
            }
            .lineLimit(1)
            .fixedSize()
        }
        .textCase(nil)
        .listRowInsets(EdgeInsets(top: 16, leading: 4, bottom: 8, trailing: 4))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(count: count, avg: avg))
        .accessibilityAddTraits(.isHeader)
    }

    private func spoken(count: Int, avg: String?) -> String {
        var s = "\(group.title), \(count) \(count == 1 ? "drive" : "drives")"
        if let avg { s += ", average \(avg)" }
        return s
    }
}

// MARK: - Row

/// One drive (76 pt): day / clock / minutes column, shield + name + record
/// tab over the S-class strip (5 pt dots, start pin, P plate 10), score.
fileprivate struct V2DrivesRow: View {
    let facts: V2DriveFacts
    let dark: Bool
    let onRename: () -> Void

    @ObservedObject private var library = V2Library.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .footnote) private var leftColumn: CGFloat = 60
    /// 0 → 1 once: the §4.16 row reveal. Starts at 1 for revealed drives.
    @State private var reveal: Double

    init(facts: V2DriveFacts, dark: Bool, onRename: @escaping () -> Void) {
        self.facts = facts
        self.dark = dark
        self.onRename = onRename
        _reveal = State(initialValue: V2RevealLedger.shared.isRevealed(facts.id) ? 1 : 0)
    }

    var body: some View {
        ZStack {
            // Hidden link: the whole row pushes the Report without a chevron,
            // and List keeps its stock fill highlight (never a scale).
            NavigationLink(value: V2Destination.report(facts.id)) {
                EmptyView()
            }
            .opacity(0)
            .accessibilityHidden(true)
            content
        }
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
        .listRowBackground(V2.card)
        .listRowSeparatorTint(V2.sep)
        .alignmentGuide(.listRowSeparatorLeading) { d in d[.leading] }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(action: onRename) {
                Label("Rename", systemImage: "signpost.right")
            }
        }
        .contextMenu {
            Button {
                V2Router.shared.push(.report(facts.id))
            } label: {
                Label("Open report", systemImage: "doc.text")
            }
            Button(action: onRename) {
                Label(nameActionTitle, systemImage: "signpost.right")
            }
            ShareLink(item: V2DriveShareFile(id: facts.id, dark: dark),
                      preview: SharePreview(facts.name)) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel)
        .accessibilityHint("Opens the report")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            V2Router.shared.push(.report(facts.id))
        }
        .task(id: facts.id) { await appeared() }
    }

    private var content: some View {
        let strip = library.strip(for: facts.id)
        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: V2Format.shortWeekday(facts.start))
                    .font(V2Type.footnoteSemibold)
                    .foregroundStyle(V2.label2)
                Text(verbatim: V2Format.clock(facts.start))
                    .font(V2Type.measured(15, relativeTo: .footnote))
                    .foregroundStyle(V2.label)
                Text(verbatim: "\(facts.minutes) min")
                    .font(V2Type.footnoteNumbers)
                    .foregroundStyle(V2.label2)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(width: leftColumn, alignment: .leading)

            VStack(alignment: .leading, spacing: 8) {
                nameLine
                if strip.count > 0 {
                    // Reduce Motion: the strip fades in instead of drawing.
                    V2LaneStrip(strip: strip, zoneHeight: 18, showMarkers: true,
                                drawProgress: reduceMotion ? 1 : reveal)
                        .opacity(reduceMotion ? reveal : 1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            trailing
        }
        .padding(.vertical, 10)
        .frame(minHeight: 76)
    }

    private var nameLine: some View {
        HStack(alignment: .center, spacing: 0) {
            if let number = facts.routeNumber {
                V2Plate.route(number, size: 20)
                    .padding(.trailing, 6)
            }
            Text(verbatim: facts.name)
                .font(V2Type.headline)
                .foregroundStyle(V2.label)
                .lineLimit(1)
            if let tab = facts.recordTab {
                V2GuideTabView(tab, height: 16)
                    .padding(.leading, 4)
            }
        }
    }

    @ViewBuilder
    private var trailing: some View {
        if facts.isScored {
            V2RowScore(score: facts.score, gradeMinWidth: 22)
        } else {
            Text("Not scored")
                .font(V2Type.footnote)
                .foregroundStyle(V2.label2)
                .fixedSize()
        }
    }

    private var nameActionTitle: String {
        facts.routeName == nil ? "Name this route" : "Rename route"
    }

    /// "School run, Friday 3:28 PM, 24 minutes, 91 A, best School run yet".
    private var spokenLabel: String {
        var parts = [facts.name,
                     "\(V2Format.weekday(facts.start)) \(V2Format.clock(facts.start))",
                     "\(facts.minutes) \(facts.minutes == 1 ? "minute" : "minutes")"]
        if facts.isScored {
            let letter = facts.grade
                .replacingOccurrences(of: "\u{2212}", with: " minus")
                .replacingOccurrences(of: "+", with: " plus")
            parts.append("\(V2Voice.scoreText(facts.score)) \(letter)")
        } else {
            parts.append("not scored")
        }
        if let tab = facts.recordTab {
            parts.append(tab == .pb ? "personal best" : "best \(facts.routeName ?? facts.name) yet")
        }
        return parts.joined(separator: ", ")
    }

    /// Upgrade to the trace strip, and play the one-time row reveal (§4.16).
    private func appeared() async {
        library.requestTrace(for: facts.id)
        let ledger = V2RevealLedger.shared
        guard reveal < 1 else { return }
        guard !ledger.isRevealed(facts.id) else {
            reveal = 1      // revealed elsewhere (Parked / Report) since this row was made
            return
        }
        ledger.markRevealed(facts.id)
        withAnimation(V2Motion.reduced(.easeOut(duration: 0.3), reduceMotion: reduceMotion)) {
            reveal = 1
        }
    }
}

// MARK: - Share

/// The drive's share card, rendered only when a share target asks for it
/// (so the context menu doesn't render a card per row).
fileprivate struct V2DriveShareFile: Transferable {
    let id: UUID
    let dark: Bool

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { file in
            let data: Data? = await MainActor.run { file.renderPNG() }
            guard let data else { throw V2DrivesShareError.unavailable }
            return data
        }
    }

    @MainActor
    func renderPNG() -> Data? {
        guard let facts = V2Library.shared.facts(id) else { return nil }
        return V2ShareRenderer.render(facts: facts,
                                      focusLine: V2DriveShareFile.focusLine(facts),
                                      dark: dark)?.pngData()
    }

    /// Same rule as the Report's share: only a retired / cleared job is worth a line.
    static func focusLine(_ facts: V2DriveFacts) -> String? {
        guard let check = facts.focusCheck else { return nil }
        switch check.outcome {
        case .retired: return "Job retired: \(V2Voice.jobGerund(check.job.category))"
        case .cleared: return "Job cleared: \(V2Voice.jobGerund(check.job.category))"
        default:       return nil
        }
    }
}

fileprivate enum V2DrivesShareError: Error {
    case unavailable
}

// MARK: - Empty state

/// No drives yet: car XL on a lane line and the promise of a strip.
fileprivate struct V2DrivesEmptyState: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    V2Car(.xl, color: V2.label3, knockout: V2.bg)
                    V2DrivesLaneLine()
                        .frame(height: 2)
                }
                .accessibilityHidden(true)
                Text("Your first drive shows up here as a strip.")
                    .font(V2Type.voiceHeadline)
                    .foregroundStyle(V2.label)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 24)
                Text("A clean drive looks like an empty road.")
                    .font(V2Type.body)
                    .foregroundStyle(V2.label)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 160)
            .padding(.bottom, 32)
            .accessibilityElement(children: .combine)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

/// M-class dashed lane line (2 pt, 6/4) in `paint`.
fileprivate struct V2DrivesLaneLine: View {
    var body: some View {
        Canvas { ctx, size in
            var path = Path()
            path.move(to: CGPoint(x: 0, y: size.height / 2))
            path.addLine(to: CGPoint(x: size.width, y: size.height / 2))
            ctx.stroke(path, with: .color(V2.paint), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
        }
    }
}
