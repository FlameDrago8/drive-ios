//
//  Building.swift
//  DriveUI — redesign skeleton
//
//  The few shared pieces. Everything else on screen is stock SwiftUI.
//

import SwiftUI

// MARK: - Card

extension View {
    /// Grouped surface: system secondary background, 22 pt continuous
    /// corners, no stroke, no shadow.
    func driveCard(padding: CGFloat = Theme.Metrics.cardPadding) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius, style: .continuous))
    }
}

// MARK: - Score

/// The numeral stays the label color; only the grade carries the band color.
struct ScoreReadout: View {
    enum Size { case hero, large, row }

    let score: Double
    var size: Size = .large

    @ScaledMetric(relativeTo: .largeTitle) private var heroSize: CGFloat = 96
    @ScaledMetric(relativeTo: .largeTitle) private var largeSize: CGFloat = 34

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: size == .hero ? 10 : 5) {
            Text("\(Int(score.rounded()))")
                .font(numeralFont)
                .kerning(size == .hero ? -3 : -0.5)
                .monospacedDigit()
                .contentTransition(.numericText(value: score))
            Text(ScoreScale.grade(score))
                .font(gradeFont)
                .foregroundStyle(ScoreBand(score).labelColor)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Score \(Int(score.rounded())), \(ScoreScale.grade(score))")
    }

    private var numeralFont: Font {
        switch size {
        case .hero:  .system(size: heroSize, weight: .bold)
        case .large: .system(size: largeSize, weight: .bold)
        case .row:   .title2.weight(.bold)
        }
    }

    private var gradeFont: Font {
        switch size {
        case .hero:  .title.weight(.bold)
        case .large: .headline.weight(.bold)
        case .row:   .footnote.weight(.bold)
        }
    }
}

// MARK: - Section header

/// Sentence-case bold header with an optional trailing detail. No ALL CAPS.
struct SectionHeader: View {
    let title: String
    var detail: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.title2.weight(.bold))
            Spacer()
            if let detail {
                Text(detail).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 4)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Moment chip

/// ▶ 4:12 — jumps the footage to a moment. Tint = tappable.
struct MomentChip: View {
    let offset: TimeInterval
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(DriveFormat.offset(offset), systemImage: "play.fill")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .labelStyle(.titleAndIcon)
                .imageScale(.small)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(.small)
        .tint(Theme.tint)
        .accessibilityLabel("Play from \(DriveFormat.offset(offset))")
    }
}

// MARK: - Stat cell

struct StatCell: View {
    let value: String
    var unit: String? = nil
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(.title3.weight(.semibold)).monospacedDigit()
                if let unit {
                    Text(unit).font(.footnote).foregroundStyle(.secondary)
                }
            }
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Value bar

/// Sub-score bar. Neutral when 85+, band-colored below.
struct ValueBar: View {
    let value: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.fill)
                Capsule()
                    .fill(ScoreBand(value).barColor)
                    .frame(width: geo.size.width * min(max(value, 0), 100) / 100)
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}
