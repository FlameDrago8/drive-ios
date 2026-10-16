//
//  V2ProfileRows.swift
//  Drive — v2 "Road Furniture"
//
//  Row building blocks for the Profile & Settings sheet (§6.10): stock inset
//  grouped rows, plain text with SF Symbols at .semibold, no plates on
//  Settings rows (§4.1 placement rule 3). Colours from V2 tokens only.
//

import SwiftUI

/// The mini Driver Card row heading the sheet: avatar (tier ring, PERMIT tab
/// for learners), name, licence type and drive count. Pushes the Driver Card.
struct V2ProfileHeaderRow: View {
    let imageData: Data?
    let seed: String
    let name: String
    let tier: BadgeTier?
    let driverType: DriverType
    let drives: Int

    var body: some View {
        HStack(spacing: 14) {
            V2Avatar(imageData: imageData,
                     seed: seed,
                     name: name,
                     size: 56,
                     ring: tier.map { V2.tierColor($0) },
                     permit: driverType == .learner)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: name)
                    .font(V2Type.voiceHeadline)
                    .foregroundStyle(V2.label)
                    .lineLimit(2)
                Text(verbatim: "\(driverType.label) · \(V2ProfileCopy.drives(drives))")
                    .font(V2Type.subhead)
                    .foregroundStyle(V2.label2)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name), \(driverType.label), \(V2ProfileCopy.drives(drives))")
        .accessibilityHint("Opens your Driver Card")
    }
}

/// "Title ........ value >" — a stock value row. `value` is label2 and
/// truncates; the chevron is decoration (label3).
struct V2ProfileValueRow: View {
    let title: String
    let value: String?
    var chevron: Bool = true

    var body: some View {
        HStack(spacing: 12) {
            Text(verbatim: title)
                .font(V2Type.body)
                .foregroundStyle(V2.label)
            Spacer(minLength: 8)
            if let value, !value.isEmpty {
                Text(verbatim: value)
                    .font(V2Type.body)
                    .foregroundStyle(V2.label2)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if chevron {
                V2ProfileChevron()
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// One line of row text in a given colour: `tint` for actions, `poor` for
/// destructive ones, `label` otherwise.
struct V2ProfileRowText: View {
    let text: String
    var color: Color = V2.label

    init(_ text: String, color: Color = V2.label) {
        self.text = text
        self.color = color
    }

    var body: some View {
        HStack(spacing: 0) {
            Text(verbatim: text)
                .font(V2Type.body)
                .foregroundStyle(color)
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}

/// Car row (§6.10): car M + "2019 Honda Civic", or a quiet car and
/// "Add your car" when nothing is saved yet.
struct V2ProfileCarRow: View {
    let carName: String

    var body: some View {
        HStack(spacing: 12) {
            V2Car(.m, color: carName.isEmpty ? V2.label3 : V2.label, knockout: V2.card)
            if carName.isEmpty {
                Text("Add your car")
                    .font(V2Type.body)
                    .foregroundStyle(V2.tint)
            } else {
                Text(verbatim: carName)
                    .font(V2Type.body)
                    .foregroundStyle(V2.label)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            V2ProfileChevron()
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(carName.isEmpty ? String("Add your car") : "Car, \(carName)")
    }
}

/// An external page (legal, support). Opens in the browser.
struct V2ProfileLinkRow: View {
    let title: String
    let url: URL

    var body: some View {
        Link(destination: url) {
            HStack(spacing: 12) {
                Text(verbatim: title)
                    .font(V2Type.body)
                    .foregroundStyle(V2.label)
                Spacer(minLength: 8)
                V2ProfileChevron(systemName: "arrow.up.right")
            }
            .contentShape(Rectangle())
        }
        .accessibilityHint("Opens in your browser")
    }
}

/// Trailing row glyph: SF Symbol at .semibold, decoration only.
struct V2ProfileChevron: View {
    var systemName: String = "chevron.right"

    var body: some View {
        Image(systemName: systemName)
            .font(V2Type.footnoteSemibold)
            .foregroundStyle(V2.label3)
            .accessibilityHidden(true)
    }
}

/// A switch's label: the title over one footnote line saying when it fires.
struct V2ProfileToggleLabel: View {
    let title: String
    let detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: title)
                .font(V2Type.body)
                .foregroundStyle(V2.label)
            if let detail {
                Text(verbatim: detail)
                    .font(V2Type.footnote)
                    .foregroundStyle(V2.label2)
            }
        }
    }
}

/// A per-user notification switch (`V2UserKey.scoped(keyName)`, absent = on)
/// that NotificationManager / the Parked notifier read when they fire. Only a
/// real flip writes the key, so an untouched switch keeps following the default.
struct V2NotifyToggle: View {
    let title: String
    let detail: String
    let keyName: String
    /// Not named `onChange`, which would shadow the View modifier in `body`.
    let switched: (Bool) -> Void
    @State private var isOn: Bool

    init(_ title: String, detail: String, keyName: String,
         onChange: @escaping (Bool) -> Void = { _ in }) {
        self.title = title
        self.detail = detail
        self.keyName = keyName
        self.switched = onChange
        _isOn = State(initialValue: NotificationManager.preference(keyName))
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            V2ProfileToggleLabel(title: title, detail: detail)
        }
        .onChange(of: isOn) { _, on in
            UserDefaults.standard.set(on, forKey: V2UserKey.scoped(keyName))
            switched(on)
        }
    }
}

enum V2ProfileCopy {
    /// "No drives yet" / "1 drive" / "28 drives".
    static func drives(_ count: Int) -> String {
        switch count {
        case ..<1: return "No drives yet"
        case 1:    return "1 drive"
        default:   return "\(count.formatted()) drives"
        }
    }
}
