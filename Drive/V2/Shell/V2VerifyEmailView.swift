//
//  V2VerifyEmailView.swift
//  Drive
//
//  v2 Verify Email (spec §6.10): "One tap left.", Open Mail, and a quiet
//  "Resend link" that enables 30 s after appearing / after the last send,
//  with no visible countdown.
//
//  Routing is automatic: `reloadUser` re-publishes the same User with
//  `isEmailVerified == true` and DriveApp moves on to onboarding or home. v2
//  drops v1's big check button, so this view reloads on appear and every
//  time the app comes back to the foreground (the user just tapped the link
//  in Mail); a quiet "I've verified" button stays as a manual fallback.
//

import SwiftUI
import UIKit

private let v2veWhite = V2.fixed(0xFFFFFF)

struct V2VerifyEmailView: View {
    @ObservedObject private var userManager = UserManager.shared

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var canResend = false
    /// Bumped after every successful send to restart the 30 s gate.
    @State private var resendCycle = 0
    @State private var isResending = false
    @State private var sentConfirmed = false
    @State private var isChecking = false
    @State private var errorMessage = ""

    @ScaledMetric(relativeTo: .headline) private var buttonHeight: CGFloat = 50

    /// Seconds before "Resend link" enables, after appearing or a send.
    private let resendDelay: Double = 30

    private var email: String {
        userManager.user?.email ?? "your email"
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                content
                    .frame(minHeight: proxy.size.height, alignment: .top)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(V2.bg.ignoresSafeArea())
        .onAppear {
            userManager.reloadUser {}
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { userManager.reloadUser {} }
        }
        .task(id: resendCycle) {
            canResend = false
            try? await Task.sleep(for: .seconds(resendDelay))
            guard !Task.isCancelled else { return }
            canResend = true
            sentConfirmed = false
        }
    }

    private var settle: Animation? {
        V2Motion.reduced(V2Motion.settle, reduceMotion: reduceMotion)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Spacer(minLength: 40)
            actions
        }
        .padding(.horizontal, V2.margin)
        .padding(.top, 56)
        .padding(.bottom, 16)
        .animation(settle, value: errorMessage)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 24) {
            V2DriveLogo(height: 72)
            VStack(alignment: .leading, spacing: 12) {
                Text("One tap left.")
                    .font(V2Type.scaled(28, .title1, weight: .bold))
                    .foregroundStyle(V2.label)
                    .accessibilityAddTraits(.isHeader)
                Text("We sent a link to \(Text(verbatim: email).fontWeight(.semibold)). Open it on this iPhone and you're in.")
                    .font(V2Type.body)
                    .foregroundStyle(V2.label)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Actions

    private var actions: some View {
        VStack(spacing: 8) {
            openMailButton
            errorLine
            resendButton
            verifiedButton
            differentEmailButton
        }
    }

    private var openMailButton: some View {
        Button(action: openMail) {
            Text("Open Mail")
                .font(V2Type.headline)
                .foregroundStyle(v2veWhite)
                .frame(maxWidth: .infinity, minHeight: buttonHeight)
                .background(V2.tintFill, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(V2PressableCardStyle())
        .padding(.bottom, 4)
    }

    /// Grey while gated (blue means tappable), "Sent." after a send, then
    /// quietly back to "Resend link" when the gate lifts.
    private var resendButton: some View {
        let title: String = (sentConfirmed && !canResend) ? "Sent." : "Resend link"
        let enabled = canResend && !isResending
        return Button(action: resend) {
            Group {
                if isResending {
                    ProgressView()
                        .tint(V2.label2)
                } else {
                    Text(title)
                        .font(V2Type.subheadSemibold)
                        .foregroundStyle(enabled ? V2.tint : V2.label2)
                }
            }
            .frame(maxWidth: .infinity, minHeight: V2.rowMin)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(Text(title))
    }

    private var verifiedButton: some View {
        Button(action: checkVerified) {
            HStack(spacing: 8) {
                if isChecking {
                    ProgressView()
                        .tint(V2.label2)
                }
                Text("I've verified")
                    .font(V2Type.subheadSemibold)
                    .foregroundStyle(V2.tint)
            }
            .frame(maxWidth: .infinity, minHeight: V2.rowMin)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isChecking)
    }

    private var differentEmailButton: some View {
        Button {
            userManager.signOut()
        } label: {
            Text("Use a different email")
                .font(V2Type.subheadSemibold)
                .foregroundStyle(V2.tint)
                .frame(maxWidth: .infinity, minHeight: V2.rowMin)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var errorLine: some View {
        if !errorMessage.isEmpty {
            Text(errorMessage)
                .font(V2Type.footnote)
                .foregroundStyle(V2.poor)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 4)
                .transition(.opacity)
        }
    }

    // MARK: - Behaviour

    private func showError(_ text: String) {
        withAnimation(settle) { errorMessage = text }
        v2veAnnounce(text)
    }

    private func openMail() {
        guard let url = URL(string: "message://") else { return }
        UIApplication.shared.open(url)
    }

    private func resend() {
        guard canResend, !isResending else { return }
        isResending = true
        withAnimation(settle) { errorMessage = "" }
        userManager.resendVerificationEmail { error in
            isResending = false
            if let error {
                // Nothing was sent, so the gate stays open for a retry.
                showError(error.localizedDescription)
            } else {
                canResend = false
                sentConfirmed = true
                resendCycle += 1
                v2veAnnounce("Sent.")
            }
        }
    }

    /// Manual fallback for when the automatic foreground check hasn't caught it.
    private func checkVerified() {
        isChecking = true
        withAnimation(settle) { errorMessage = "" }
        userManager.reloadUser {
            isChecking = false
            if !(userManager.user?.isEmailVerified ?? false) {
                showError("Email not verified yet. Check your inbox and click the link.")
            }
            // If verified, DriveApp re-evaluates and routes away automatically.
        }
    }
}

/// Status lines appear without moving focus, so read them out.
@MainActor
private func v2veAnnounce(_ text: String) {
    guard !text.isEmpty else { return }
    UIAccessibility.post(notification: .announcement, argument: text)
}
