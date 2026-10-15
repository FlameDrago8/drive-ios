//
//  V2FocusModule.swift
//  Drive — v2 "Road Furniture"
//
//  "Your one job" (spec §4.5): the Focus Sign, the job, its coaching body and
//  up to two moment tokens from the drive that set it. Today adds the footnote
//  "Set by Friday's School run"; the Report reuses the card with `footnote: nil`.
//

import SwiftUI

struct V2FocusModule: View {
    private let job: V2FocusJob
    private let moments: [V2Moment]
    private let strip: V2Strip?
    private let footnote: String?
    private let onMoment: (V2Moment) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(job: V2FocusJob, moments: [V2Moment], strip: V2Strip?, footnote: String?,
         onMoment: @escaping (V2Moment) -> Void) {
        self.job = job
        self.moments = moments
        self.strip = strip
        self.footnote = footnote
        self.onMoment = onMoment
    }

    private var tokens: [V2Moment] { Array(moments.prefix(2)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                V2FocusSign(category: job.category, size: 44)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your one job next drive")
                        .font(V2Type.subheadSemibold)
                        .foregroundStyle(V2.label)
                    Text(verbatim: job.title)
                        .font(V2Type.focusTitle)
                        .foregroundStyle(V2.label)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            Text(verbatim: V2Voice.focusBody(job))
                .font(V2Type.body)
                .foregroundStyle(V2.label)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)

            if !tokens.isEmpty {
                // Two share a row; at accessibility sizes they stack (§3.2).
                let layout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                    : AnyLayout(HStackLayout(alignment: .top, spacing: 8))
                layout {
                    ForEach(tokens) { moment in
                        V2MomentToken(moment: moment, strip: strip) {
                            onMoment(moment)
                        }
                    }
                }
                .padding(.top, 16)
            }

            if let footnote, !footnote.isEmpty {
                Text(verbatim: footnote)
                    .font(V2Type.footnote)
                    .foregroundStyle(V2.label2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
            }
        }
        .v2Card(padding: V2.focusPadding)
        .accessibilityElement(children: .contain)
    }
}
