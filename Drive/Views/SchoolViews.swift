//
//  SchoolViews.swift
//  Drive
//
//  Shared school UI components.
//  All views gracefully render nothing / show solo-mode when SchoolManager.orgId is nil.
//

import SwiftUI

// MARK: – Consent Sheet

/// Presented after code validation succeeds, before orgId is written to Firestore.
struct SchoolConsentSheet: View {
    let school: SchoolManager.PendingSchool
    let onAgree: () -> Void
    let onCancel: () -> Void

    @State private var appeared = false

    var body: some View {
        ZStack {
            Color(red: 0.07, green: 0.07, blue: 0.11).ignoresSafeArea()

            VStack(spacing: 0) {
                Capsule()
                    .fill(Color.white.opacity(0.15))
                    .frame(width: 36, height: 4)
                    .padding(.top, DS.Spacing.m)

                VStack(spacing: DS.Spacing.xl) {

                    // Hero
                    VStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(DS.Colors.accent.opacity(0.12))
                                .frame(width: 72, height: 72)
                            Image(systemName: "building.2.fill")
                                .font(.system(size: 28, weight: .semibold))
                                .foregroundColor(DS.Colors.accent)
                        }
                        .scaleEffect(appeared ? 1 : 0.6)
                        .animation(.spring(duration: 0.5, bounce: 0.35), value: appeared)

                        Text("Join \(school.name)?")
                            .font(.system(size: 22, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, DS.Spacing.m)

                    // Disclosure
                    VStack(alignment: .leading, spacing: DS.Spacing.m) {
                        disclosureRow(
                            icon: "eye.fill",
                            color: DS.Colors.accent,
                            text: "Your driving sessions — scores, metrics, and flagged events — will be visible to instructors at \(school.name)."
                        )
                        disclosureRow(
                            icon: "flag.fill",
                            color: DS.Colors.scoreOkay,
                            text: "Instructors may set in-app goals that appear on your home screen."
                        )
                        disclosureRow(
                            icon: "person.fill.checkmark",
                            color: DS.Colors.scoreGreat,
                            text: "You can leave the school at any time in Settings."
                        )
                    }
                    .padding(.horizontal, 4)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 10)
                    .animation(.spring(duration: 0.45, bounce: 0.05).delay(0.15), value: appeared)

                    // Actions
                    VStack(spacing: DS.Spacing.s) {
                        Button(action: onAgree) {
                            Text("I Agree — Join School")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    RoundedRectangle(cornerRadius: DS.Radius.l, style: .continuous)
                                        .fill(DS.Colors.accent)
                                )
                        }
                        Button(action: onCancel) {
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
        .presentationDetents([.fraction(0.70)])
        .presentationDragIndicator(.hidden)
        .preferredColorScheme(.dark)
        .onAppear { appeared = true }
    }

    private func disclosureRow(icon: String, color: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: DS.Spacing.m) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 32, height: 32)
                .background(color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(DS.Colors.secondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

// MARK: – School Banner (HomeView)

/// Compact banner shown at the top of HomeView when a student is linked to a school.
struct SchoolBannerView: View {
    @ObservedObject var manager: SchoolManager

    var body: some View {
        if let name = manager.schoolName {
            VStack(spacing: 0) {
                if !manager.subscriptionActive {
                    // Subscription lapsed
                    HStack(spacing: DS.Spacing.s) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.orange)
                        Text("Contact \(name) to reactivate access.")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.orange.opacity(0.9))
                        Spacer()
                    }
                    .padding(.horizontal, DS.Spacing.l)
                    .padding(.vertical, DS.Spacing.s)
                    .background(Color.orange.opacity(0.10))
                    .overlay(
                        Rectangle()
                            .fill(Color.orange.opacity(0.25))
                            .frame(height: 0.5),
                        alignment: .bottom
                    )
                } else {
                    // Active
                    HStack(spacing: DS.Spacing.s) {
                        Image(systemName: "building.2.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(DS.Colors.accent)
                        Text(name.uppercased())
                            .font(.system(size: 10, weight: .heavy))
                            .tracking(1.2)
                            .foregroundColor(DS.Colors.accent)
                        Spacer()
                        Text("LINKED")
                            .font(.system(size: 9, weight: .heavy))
                            .tracking(1)
                            .foregroundColor(DS.Colors.scoreGreat.opacity(0.7))
                    }
                    .padding(.horizontal, DS.Spacing.l)
                    .padding(.vertical, 7)
                    .background(DS.Colors.accent.opacity(0.07))
                    .overlay(
                        Rectangle()
                            .fill(DS.Colors.accent.opacity(0.15))
                            .frame(height: 0.5),
                        alignment: .bottom
                    )
                }
            }
        }
    }
}

// MARK: – Instructor Goals Card (HomeView)

/// Card showing goals set by the instructor. Hidden when goals list is empty.
struct InstructorGoalsCard: View {
    let goals: [SchoolManager.InstructorGoal]

    var body: some View {
        if !goals.isEmpty {
            VStack(alignment: .leading, spacing: DS.Spacing.s) {
                HStack {
                    Image(systemName: "flag.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(DS.Colors.scoreOkay)
                    Text("INSTRUCTOR GOALS")
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(1.2)
                        .foregroundColor(DS.Colors.secondary)
                    Spacer()
                }

                ForEach(goals) { goal in
                    HStack(alignment: .top, spacing: DS.Spacing.s) {
                        Circle()
                            .fill(DS.Colors.scoreOkay.opacity(0.5))
                            .frame(width: 6, height: 6)
                            .padding(.top, 5)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(goal.title)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.primary)
                            if let body = goal.body {
                                Text(body)
                                    .font(.system(size: 12, weight: .regular))
                                    .foregroundColor(DS.Colors.secondary)
                                    .lineSpacing(2)
                            }
                        }
                        Spacer()
                    }
                }
            }
            .padding(DS.Spacing.l)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous)
                    .fill(DS.Colors.bgCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous)
                            .stroke(DS.Colors.cardStroke)
                    )
            )
        }
    }
}

// MARK: – School Code Entry Field (reusable)

struct SchoolCodeField: View {
    @Binding var code: String
    @FocusState.Binding var focused: Bool
    let errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("School Code")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(focused ? DS.Colors.accent : DS.Colors.secondary)
                .animation(.easeInOut(duration: 0.2), value: focused)

            TextField("e.g. DRIVE123", text: $code)
                .focused($focused)
                .font(.system(size: 16, weight: .medium, design: .monospaced))
                .foregroundColor(.white)
                .autocapitalization(.allCharacters)
                .disableAutocorrection(true)
                .submitLabel(.done)
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
                .background(Color.white.opacity(focused ? 0.09 : 0.06))
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous)
                        .stroke(
                            focused ? DS.Colors.accent.opacity(0.7) : Color.white.opacity(0.10),
                            lineWidth: focused ? 1.5 : 1
                        )
                )
                .animation(.easeInOut(duration: 0.2), value: focused)

            if let err = errorMessage {
                Text(err)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.red.opacity(0.8))
            }
        }
    }
}
