//
//  DriveShareCard.swift
//  Drive
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Transferable wrapper for share sheet

struct RenderedDriveCard: Transferable {
    let image: UIImage

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { card in
            card.image.pngData() ?? Data()
        }
    }
}

// MARK: - Share Card View
// Designed for ImageRenderer — no @State animations, all values are static.

struct DriveShareCard: View {
    let session: DriveSession

    // Local color constants (no DS import needed for widget/renderer contexts)
    private static let accent    = Color(red: 0.08, green: 0.56, blue: 1.00)
    private static let secondary = Color(white: 0.48)
    private static let bg        = Color(red: 0.039, green: 0.039, blue: 0.059)
    private static let bgDeep    = Color(red: 0.051, green: 0.055, blue: 0.078)

    private var metricItems: [(String, String, Color)]? {
        guard let m = session.metrics else { return nil }
        return [
            ("Braking",      grade(for: m.braking),      scoreColor(for: m.braking)),
            ("Acceleration", grade(for: m.acceleration), scoreColor(for: m.acceleration)),
            ("Cornering",    grade(for: m.cornering),    scoreColor(for: m.cornering)),
            ("Smoothness",   grade(for: m.smoothness),   scoreColor(for: m.smoothness)),
        ]
    }

    var body: some View {
        VStack(spacing: 0) {

            // ── Header
            HStack {
                Text("DRIVE")
                    .font(.system(size: 12, weight: .heavy))
                    .tracking(5)
                    .foregroundColor(Self.accent)
                Spacer()
                Text(session.date.formatted(.dateTime.month(.abbreviated).day().year()))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Self.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.top, 26)

            // ── Score arc (static — no animate)
            ZStack {
                Circle()
                    .trim(from: 0, to: 0.75)
                    .stroke(Color.white.opacity(0.06),
                            style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .frame(width: 150, height: 150)
                    .rotationEffect(.degrees(135))

                Circle()
                    .trim(from: 0, to: (session.score / 100.0) * 0.75)
                    .stroke(
                        AngularGradient(
                            colors: [scoreColor(for: session.score).opacity(0.4),
                                     scoreColor(for: session.score)],
                            center: .center,
                            startAngle: .degrees(0), endAngle: .degrees(270)
                        ),
                        style: StrokeStyle(lineWidth: 12, lineCap: .round)
                    )
                    .frame(width: 150, height: 150)
                    .rotationEffect(.degrees(135))
                    .shadow(color: scoreColor(for: session.score).opacity(0.5), radius: 8)

                VStack(spacing: 2) {
                    Text("\(Int(session.score))")
                        .font(.system(size: 48, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                    Text("SCORE")
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(3)
                        .foregroundColor(Self.secondary)
                }
            }
            .padding(.vertical, 20)

            // ── Grade + stats row
            HStack(spacing: 24) {
                cardStat(value: grade(for: session.score), label: "GRADE",
                         color: scoreColor(for: session.score), size: 30)

                Rectangle().fill(Color.white.opacity(0.12)).frame(width: 1, height: 36)

                cardStat(value: "\(Int(session.duration / 60))m", label: "DURATION", size: 20)

                if let tag = session.routeTag, !tag.isEmpty {
                    Rectangle().fill(Color.white.opacity(0.12)).frame(width: 1, height: 36)
                    cardStat(value: tag, label: "ROUTE", color: Self.accent, size: 13)
                }
            }
            .padding(.bottom, 20)

            // ── Metric grid (only when real scoring data is available)
            if let metrics = metricItems {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(metrics, id: \.0) { label, gradeStr, color in
                        HStack(spacing: 10) {
                            Text(gradeStr)
                                .font(.system(size: 20, weight: .black, design: .rounded))
                                .foregroundColor(color)
                            Text(label)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 11)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(color.opacity(0.11))
                                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(color.opacity(0.22), lineWidth: 1))
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }

            // ── Footer
            HStack {
                Text("drive")
                    .font(.system(size: 10, weight: .black))
                    .tracking(4)
                    .foregroundColor(Self.secondary.opacity(0.4))
                Spacer()
                Image(systemName: "car.fill")
                    .font(.system(size: 10))
                    .foregroundColor(Self.secondary.opacity(0.35))
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .overlay(alignment: .top) {
                Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1)
            }
        }
        .frame(width: 360)
        .background(
            LinearGradient(colors: [Self.bg, Self.bgDeep],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func cardStat(value: String, label: String,
                           color: Color = .white, size: CGFloat) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: size, weight: .black, design: .rounded))
                .foregroundColor(color)
                .lineLimit(1)
            Text(label)
                .font(.system(size: 9, weight: .heavy))
                .tracking(2)
                .foregroundColor(Self.secondary)
        }
    }
}
