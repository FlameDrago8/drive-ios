//
//  V2ShareCard.swift
//  Drive — v2 "Road Furniture"
//
//  The share card (§6.7): 1080 × 1350 px, drawn at 360 × 450 pt and rendered
//  at 3×. Two variants, #000 and #FFF paper. Static: no state, no animation.
//  Never a map, a route silhouette, a street name or footage.
//
//  Board values are in px at 1080 wide; everything here is that ÷ 3.
//

import SwiftUI
import UIKit

struct V2ShareCard: View {
    let facts: V2DriveFacts
    let focusLine: String?
    let dark: Bool

    init(facts: V2DriveFacts, focusLine: String?, dark: Bool) {
        self.facts = facts
        self.focusLine = focusLine
        self.dark = dark
    }

    /// 72 px margins.
    private static let margin: CGFloat = 24
    private static let inner: CGFloat = 312
    /// Strip: W 936 px, H 200 px (L class ×3).
    private static let zone: CGFloat = 67
    /// Top of the score numeral (800 px).
    private static let scoreTop: CGFloat = 266.67

    private var paper: Color { dark ? V2.fixed(0x000000) : V2.fixed(0xFFFFFF) }

    var body: some View {
        let library = V2Library.shared
        let strip = Self.shareStrip(library.strip(for: facts.id))
        let all = library.snapshot.facts
        let driveNumber: Int? = all.firstIndex(where: { $0.id == facts.id }).map { all.count - $0 }
        let tier: BadgeTier? = library.snapshot.badges.compactMap(\.currentTier).max()
        let stage = ProfileManager.shared.driverType.label
        let stripHeight = V2LaneStrip.metrics(zoneHeight: Self.zone, showMarkers: true, hasClocks: false,
                                              car: .l, showBracket: false).height
        // The parked car sits ~9 pt above the numeral, as drawn.
        let stripTop = Self.scoreTop - 8.67 - stripHeight

        ZStack(alignment: .topLeading) {
            paper

            header
                .frame(width: Self.inner, height: 16)
                .offset(x: Self.margin, y: 24)

            titleRow
                .frame(width: Self.inner, height: 32, alignment: .leading)
                .offset(x: Self.margin, y: 61.33)

            timetable
                .frame(width: Self.inner, height: 38)
                .offset(x: Self.margin, y: 106.67)

            V2LaneStrip(strip: strip,
                        zoneHeight: Self.zone,
                        showMarkers: true,
                        showFocusTags: false,
                        showBracket: false,
                        showStartPin: true,
                        car: V2StripCar(position: .parked, size: .l, color: V2.label, knockout: paper))
                .frame(width: Self.inner)
                .offset(x: Self.margin, y: stripTop)

            score
                .offset(x: Self.margin, y: Self.scoreTop)

            verdict
                .frame(width: Self.inner, alignment: .leading)
                .offset(x: Self.margin, y: 360)

            if let focusLine, !focusLine.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(V2Type.fixedSize(13.6, weight: .semibold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(V2.markerInk, V2.great)
                    Text(verbatim: focusLine)
                        .font(V2Type.fixedSize(12, weight: .semibold))
                        .foregroundStyle(V2.label)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(width: Self.inner, height: 16, alignment: .leading)
                .offset(x: Self.margin, y: 383.33)
            }

            footer(stage: stage, driveNumber: driveNumber, tier: tier)
                .frame(width: Self.inner, height: 14)
                .offset(x: Self.margin, y: 410)
        }
        .frame(width: 360, height: 450, alignment: .topLeading)
        .clipped()
        .environment(\.colorScheme, dark ? .dark : .light)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(stage: stage, driveNumber: driveNumber))
    }

    // MARK: Rows

    /// Drive logo 60 tall + "Drive" 40 Bold (left); "Fri, Oct 16" 36 Regular label2 (right).
    private var header: some View {
        HStack(spacing: 0) {
            HStack(spacing: 4) {
                V2DriveLogo(height: 20)
                Text(verbatim: "Drive")
                    .font(V2Type.fixedSize(13.33, weight: .bold))
                    .foregroundStyle(V2.label)
            }
            Spacer(minLength: 8)
            Text(verbatim: V2Format.shortDate(facts.start))
                .font(V2Type.fixedSize(12))
                .foregroundStyle(V2.label2)
                .lineLimit(1)
        }
    }

    /// Shield 96 + name 72 Bold + BEST / PB tab (48 tall).
    private var titleRow: some View {
        HStack(spacing: 8) {
            if let n = facts.routeNumber {
                V2Plate.route(n, size: 32)
            }
            Text(verbatim: facts.name)
                .font(V2Type.fixedSize(24, weight: .bold))
                .foregroundStyle(V2.label)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let tab = facts.recordTab {
                V2GuideTabView(tab, height: 16)
            }
        }
    }

    /// "3:28 PM ——— P 3:52 PM" with "24 min   8.3 mi" above the line.
    private var timetable: some View {
        HStack(spacing: 10) {
            clock(facts.start)
            GeometryReader { geo in
                let w = geo.size.width
                let lineEnd = max(0, w - 18)
                ZStack(alignment: .topLeading) {
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: 7))
                        p.addLine(to: CGPoint(x: lineEnd, y: 7))
                    }
                    .stroke(V2.paint, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    V2PPlate(size: 14)
                        .position(x: w - 7, y: 7)
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text(verbatim: "\(facts.minutes)")
                            .font(V2Type.fixedSize(13.33, weight: .semibold).monospacedDigit())
                            .foregroundStyle(V2.label)
                        Text(verbatim: " min")
                            .font(V2Type.fixedSize(11.5))
                            .foregroundStyle(V2.label2)
                        Text(verbatim: V2Format.oneDecimal(facts.miles))
                            .font(V2Type.fixedSize(13.33, weight: .semibold).monospacedDigit())
                            .foregroundStyle(V2.label)
                            .padding(.leading, 10.5)
                        Text(verbatim: " mi")
                            .font(V2Type.fixedSize(11.5))
                            .foregroundStyle(V2.label2)
                    }
                    .lineLimit(1)
                    .fixedSize()
                    .frame(width: lineEnd, height: 16)
                    .position(x: lineEnd / 2, y: -6)
                }
            }
            .frame(height: 14)
            clock(facts.end)
        }
    }

    private func clock(_ date: Date) -> some View {
        let parts = V2Format.clockParts(date)
        return HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(verbatim: parts.time)
                .font(V2Type.fixedSize(32, weight: .semibold).width(.condensed).monospacedDigit())
                .foregroundStyle(V2.label)
            if !parts.period.isEmpty {
                Text(verbatim: parts.period)
                    .font(V2Type.fixedSize(19))
                    .foregroundStyle(V2.label2)
            }
        }
        .lineLimit(1)
        .fixedSize()
    }

    /// "91" 280 Bold + grade plate h168 (r47, letter 100).
    private var score: some View {
        HStack(alignment: .lastTextBaseline, spacing: 7.5) {
            Text(verbatim: V2Voice.scoreText(facts.score))
                .font(V2Type.hero(93.33))
                .tracking(-2)
                .foregroundStyle(V2.label)
                .lineLimit(1)
                .fixedSize()
                .frame(height: 86)
            V2GradePlate(score: facts.score, height: 56)
                .alignmentGuide(.lastTextBaseline) { d in d[.bottom] }
        }
    }

    /// "Best School run yet" 48 Semibold + " (was 86)" label2.
    private var verdict: some View {
        var text = facts.verdict.text.trimmingCharacters(in: .whitespaces)
        if text.hasSuffix(".") { text.removeLast() }
        let head = Text(verbatim: text)
            .font(V2Type.fixedSize(16, weight: .semibold))
            .foregroundStyle(V2.label)
        let tail = Text(verbatim: facts.verdict.was.map { " " + $0 } ?? "")
            .font(V2Type.fixedSize(16))
            .foregroundStyle(V2.label2)
        return Text("\(head)\(tail)")
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    /// "Permit · Drive 28" (left); tier Botts' dots (right).
    private func footer(stage: String, driveNumber: Int?, tier: BadgeTier?) -> some View {
        HStack(spacing: 0) {
            Text(verbatim: driveNumber.map { "\(stage) \u{00B7} Drive \($0)" } ?? stage)
                .font(V2Type.fixedSize(10.67))
                .foregroundStyle(V2.label2)
                .lineLimit(1)
            Spacer(minLength: 8)
            if let tier {
                HStack(spacing: 3.33) {
                    ForEach(0..<tier.rawValue, id: \.self) { _ in
                        Circle()
                            .fill(V2.tierColor(tier))
                            .frame(width: 5.33, height: 5.33)
                    }
                }
            }
        }
    }

    // MARK: Helpers

    /// The share strip: markers 1–3, start pin, P, car parked. No Focus tags.
    private static func shareStrip(_ strip: V2Strip) -> V2Strip {
        let markers = strip.markers.map {
            V2StripMarker(number: $0.number, bucket: $0.bucket, band: $0.band, isFocus: false, timeOffset: $0.timeOffset)
        }
        return V2Strip(buckets: strip.buckets, markers: markers, isComplete: true, cleanRun: nil)
    }

    private func spoken(stage: String, driveNumber: Int?) -> String {
        var parts: [String] = ["Drive share card", "\(facts.name), \(V2Format.longDate(facts.start))"]
        parts.append("\(V2Format.clock(facts.start)) to \(V2Format.clock(facts.end)), \(facts.minutes) minutes, \(V2Format.oneDecimal(facts.miles)) miles")
        parts.append("\(V2Voice.scoreText(facts.score)), grade \(facts.grade)")
        parts.append(facts.verdict.text + (facts.verdict.was.map { " " + $0 } ?? ""))
        if let focusLine { parts.append(focusLine) }
        parts.append(driveNumber.map { "\(stage), drive \($0)" } ?? stage)
        return parts.joined(separator: ". ")
    }
}

/// Renders the share card to a PNG-ready image: ImageRenderer at 3×, with the
/// colour scheme set explicitly (ImageRenderer doesn't inherit the screen's).
@MainActor
enum V2ShareRenderer {
    static func render(facts: V2DriveFacts, focusLine: String?, dark: Bool) -> UIImage? {
        let renderer = ImageRenderer(content: V2ShareCard(facts: facts, focusLine: focusLine, dark: dark)
            .environment(\.colorScheme, dark ? .dark : .light))
        renderer.scale = 3
        renderer.isOpaque = true
        return renderer.uiImage
    }
}
