//
//  V2SignInView.swift
//  Drive
//
//  v2 Sign-in (spec §6.10): brand mark 64, one sentence, stock-looking
//  Apple / Google / Email buttons and the consent line. No plates.
//
//  Every behaviour of the launch beta's AuthView is kept: sign-in / sign-up
//  mode, the exact validation rules and error strings, trimming of email AND
//  password, the email → password → submit focus chain, forgot password, and
//  Firebase sign-in through UserManager (Apple must go through
//  `signInWithApple` for the nonce). It stays a root-level screen so Google
//  and Apple can present from the window's root view controller.
//

import SwiftUI
import UIKit

private let v2siWhite = V2.fixed(0xFFFFFF)
private let v2siBlack = V2.fixed(0x000000)

private enum V2SIField: Hashable { case email, password }

struct V2SignInView: View {
    @ObservedObject private var userManager = UserManager.shared

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.displayScale) private var displayScale

    @State private var showingEmail = false
    @State private var isLoginMode = true
    @State private var email = ""
    @State private var password = ""
    @State private var errorMessage = ""
    @State private var isSubmitting = false
    @State private var isSendingReset = false
    @State private var resetConfirmation = ""
    /// Bumped on every reset send so an older 5 s timer can't clear a newer confirmation.
    @State private var resetGeneration = 0

    @FocusState private var focus: V2SIField?

    @ScaledMetric(relativeTo: .headline) private var buttonHeight: CGFloat = 50
    @ScaledMetric(relativeTo: .body) private var labelWidth: CGFloat = 88

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                content
                    .frame(minHeight: proxy.size.height, alignment: .top)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
        }
        .background(V2.bg.ignoresSafeArea())
    }

    private var settle: Animation? {
        V2Motion.reduced(V2Motion.settle, reduceMotion: reduceMotion)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Spacer(minLength: 40)
            Group {
                if showingEmail {
                    emailForm.transition(.opacity)
                } else {
                    options.transition(.opacity)
                }
            }
            consent
        }
        .padding(.horizontal, V2.margin)
        .padding(.top, 56)
        .padding(.bottom, 16)
        .animation(settle, value: errorMessage)
        .animation(settle, value: resetConfirmation)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 24) {
            V2BrandMark(size: 64)
            Text("Coaching for every drive, one job at a time.")
                .font(V2Type.scaled(28, .title1, weight: .bold))
                .foregroundStyle(V2.label)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Options (Apple / Google / Email)

    private var options: some View {
        VStack(spacing: 12) {
            appleButton
            googleButton
            emailButton
            errorLine
        }
    }

    /// Apple's stock treatment: white on dark, black on light.
    private var appleButton: some View {
        let dark = colorScheme == .dark
        return Button(action: handleAppleSignIn) {
            V2SIButtonLabel("Continue with Apple") {
                Image(systemName: "apple.logo")
                    .font(V2Type.headline)
            }
            .foregroundStyle(dark ? v2siBlack : v2siWhite)
            .frame(maxWidth: .infinity, minHeight: buttonHeight)
            .background(dark ? v2siWhite : v2siBlack, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(V2PressableCardStyle())
    }

    private var googleButton: some View {
        Button(action: handleGoogleSignIn) {
            V2SIButtonLabel("Continue with Google") {
                googleBadge
            }
            .foregroundStyle(V2.label)
            .frame(maxWidth: .infinity, minHeight: buttonHeight)
            .background(V2.card, in: Capsule())
            .overlay(Capsule().strokeBorder(V2.sep, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(V2PressableCardStyle())
    }

    /// Official Google "G": keeps its own colours (never tinted) on a white
    /// rounded tile, Google's approved treatment on a dark surface.
    private var googleBadge: some View {
        Image("GoogleLogo")
            .renderingMode(.original)
            .resizable()
            .scaledToFit()
            .frame(width: 16, height: 16)
            .padding(2)
            .background(v2siWhite, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
    }

    private var emailButton: some View {
        Button(action: openEmail) {
            V2SIButtonLabel("Continue with email") {
                Image(systemName: "envelope.fill")
                    .font(V2Type.headline)
            }
            .foregroundStyle(V2.label)
            .frame(maxWidth: .infinity, minHeight: buttonHeight)
            .background(V2.fill, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(V2PressableCardStyle())
    }

    // MARK: - Email form

    private var modeBinding: Binding<Bool> {
        Binding(
            get: { isLoginMode },
            set: { newValue in
                withAnimation(settle) {
                    isLoginMode = newValue
                    errorMessage = ""
                }
            }
        )
    }

    private var emailForm: some View {
        VStack(spacing: 12) {
            Picker("Account", selection: modeBinding) {
                Text("Sign In").tag(true)
                Text("Sign Up").tag(false)
            }
            .pickerStyle(.segmented)
            .padding(.bottom, 4)

            fields

            errorLine

            submitButton
                .padding(.top, 4)

            if isLoginMode {
                forgotRow
            }

            Button(action: closeEmail) {
                Text("Other ways to sign in")
                    .font(V2Type.subheadSemibold)
                    .foregroundStyle(V2.tint)
                    .frame(maxWidth: .infinity, minHeight: V2.rowMin)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .task {
            // Focus once the crossfade has landed; a focus set during the
            // insert transaction is dropped.
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, focus == nil else { return }
            focus = .email
        }
    }

    /// Sign-up states the 6-character rule up front; sign-in just asks.
    private var passwordPrompt: String {
        isLoginMode ? "Required" : "At least 6 characters"
    }

    private var fields: some View {
        VStack(spacing: 0) {
            fieldRow("Email") {
                TextField("Email", text: $email,
                          prompt: Text(verbatim: "name@example.com").foregroundColor(V2.label2))
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .focused($focus, equals: .email)
                    .onSubmit { focus = .password }
            }

            Rectangle()
                .fill(V2.sep)
                .frame(height: 1 / max(displayScale, 1))
                .padding(.leading, 16)
                .accessibilityHidden(true)

            fieldRow("Password") {
                SecureField("Password", text: $password,
                            prompt: Text(verbatim: passwordPrompt).foregroundColor(V2.label2))
                    .textContentType(isLoginMode ? UITextContentType.password : UITextContentType.newPassword)
                    .submitLabel(.go)
                    .focused($focus, equals: .password)
                    .onSubmit(handleAuth)
            }
        }
        .background(V2.card, in: RoundedRectangle(cornerRadius: V2.radiusToken, style: .continuous))
    }

    /// A stock form row: visible label + field. The label is hidden from
    /// VoiceOver because the field's own title ("Email" / "Password") is its
    /// accessibility label. Accessibility sizes stack the label above the field.
    private func fieldRow<Input: View>(_ label: String, @ViewBuilder input: () -> Input) -> some View {
        let stacked = dynamicTypeSize.isAccessibilitySize
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            Text(label)
                .font(V2Type.body)
                .foregroundStyle(V2.label)
                .frame(width: stacked ? nil : labelWidth, alignment: .leading)
                .accessibilityHidden(true)
            input()
                .font(V2Type.body)
                .foregroundStyle(V2.label)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: V2.rowMin, alignment: .leading)
    }

    private var submitButton: some View {
        let title: String = isLoginMode ? "Sign In" : "Create Account"
        return Button(action: handleAuth) {
            ZStack {
                Text(title)
                    .font(V2Type.headline)
                    .opacity(isSubmitting ? 0 : 1)
                if isSubmitting {
                    ProgressView()
                        .tint(v2siWhite)
                }
            }
            .foregroundStyle(v2siWhite)
            .frame(maxWidth: .infinity, minHeight: buttonHeight)
            .background(V2.tintFill, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(V2PressableCardStyle())
        .disabled(isSubmitting)
        .accessibilityLabel(Text(title))
    }

    /// Forgot password: sign-in mode only, spinner while sending, then a
    /// confirmation that clears itself after 5 s.
    @ViewBuilder
    private var forgotRow: some View {
        if !resetConfirmation.isEmpty {
            Text(resetConfirmation)
                .font(V2Type.subhead)
                .foregroundStyle(V2.label)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: V2.rowMin)
                .transition(.opacity)
        } else {
            Button(action: handleForgotPassword) {
                Group {
                    if isSendingReset {
                        ProgressView()
                            .tint(V2.label2)
                    } else {
                        Text("Forgot password?")
                            .font(V2Type.subheadSemibold)
                            .foregroundStyle(V2.tint)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: V2.rowMin)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isSendingReset)
            .accessibilityLabel("Forgot password?")
        }
    }

    // MARK: - Shared lines

    @ViewBuilder
    private var errorLine: some View {
        if !errorMessage.isEmpty {
            Text(errorMessage)
                .font(V2Type.footnote)
                .foregroundStyle(V2.poor)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
                .transition(.opacity)
        }
    }

    /// Account-creation disclosure (App Review 5.1.1). A string literal, so the
    /// markdown links render; links take the tint, the rest stays grey.
    private var consent: some View {
        Text("By continuing, you agree to our [Terms of Use](https://www.velantisco.com/terms) and [Privacy Policy](https://www.velantisco.com/privacy).")
            .font(V2Type.footnote)
            .foregroundColor(V2.label2)
            .tint(V2.tint)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .padding(.top, 20)
    }

    // MARK: - Actions

    private func openEmail() {
        withAnimation(settle) {
            showingEmail = true
            errorMessage = ""
        }
    }

    private func closeEmail() {
        focus = nil
        withAnimation(settle) {
            showingEmail = false
            errorMessage = ""
        }
    }

    private func showError(_ text: String) {
        withAnimation(settle) { errorMessage = text }
        v2siAnnounce(text)
    }

    private func handleAuth() {
        guard !isSubmitting else { return }
        let trimmedEmail    = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedEmail.isEmpty else {
            showError("Please enter your email address.")
            return
        }
        guard trimmedEmail.contains("@") && trimmedEmail.contains(".") else {
            showError("Please enter a valid email address.")
            return
        }
        guard !trimmedPassword.isEmpty else {
            showError("Please enter your password.")
            return
        }
        guard trimmedPassword.count >= 6 else {
            showError("Password must be at least 6 characters.")
            return
        }

        isSubmitting = true
        let finish: (Error?) -> Void = { error in
            isSubmitting = false
            showError(error?.localizedDescription ?? "")
        }
        // Success routes away on its own: the auth listener publishes the user.
        if isLoginMode {
            userManager.signIn(email: trimmedEmail, password: trimmedPassword, completion: finish)
        } else {
            userManager.signUp(email: trimmedEmail, password: trimmedPassword, completion: finish)
        }
    }

    private func handleForgotPassword() {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmail.isEmpty else {
            showError("Enter your email address above, then tap Forgot password.")
            return
        }
        isSendingReset = true
        withAnimation(settle) { errorMessage = "" }
        userManager.sendPasswordReset(email: trimmedEmail) { error in
            isSendingReset = false
            if let error {
                showError(error.localizedDescription)
            } else {
                resetGeneration += 1
                let generation = resetGeneration
                let confirmation = "Reset link sent — check your email."
                withAnimation(settle) { resetConfirmation = confirmation }
                v2siAnnounce(confirmation)
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    guard generation == resetGeneration else { return }
                    withAnimation(settle) { resetConfirmation = "" }
                }
            }
        }
    }

    /// Backing out of either sheet is not an error worth showing.
    private func handleAppleSignIn() {
        userManager.signInWithApple { error in
            guard let error, !UserManager.isUserCancellation(error) else { return }
            showError(error.localizedDescription)
        }
    }

    private func handleGoogleSignIn() {
        userManager.signInWithGoogle { error in
            guard let error, !UserManager.isUserCancellation(error) else { return }
            showError(error.localizedDescription)
        }
    }
}

// MARK: - Helpers

/// Icon + title, centred, for the three sign-in buttons. The icon is decorative.
private struct V2SIButtonLabel<Icon: View>: View {
    let title: String
    let icon: Icon

    init(_ title: String, @ViewBuilder icon: () -> Icon) {
        self.title = title
        self.icon = icon()
    }

    var body: some View {
        HStack(spacing: 8) {
            icon
                .accessibilityHidden(true)
            Text(title)
                .font(V2Type.headline)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }
}

/// Errors and confirmations appear without moving focus, so read them out.
@MainActor
private func v2siAnnounce(_ text: String) {
    guard !text.isEmpty else { return }
    UIAccessibility.post(notification: .announcement, argument: text)
}
