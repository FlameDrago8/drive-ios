//
//  AuthView.swift
//  Drive
//
//  Created by Shiv g on 11/3/25.
//

import SwiftUI
import AuthenticationServices

struct AuthView: View {
    @State private var email = ""
    @State private var password = ""
    @State private var isLoginMode = true
    @ObservedObject private var userManager = UserManager.shared
    @State private var errorMessage = ""
    @State private var appeared = false
    @State private var isSendingReset = false
    @State private var resetConfirmation = ""

    // Focus chain: email → password → submit
    @State private var focusPassword = false

    var body: some View {
        ZStack {
            DS.Colors.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Wordmark
                VStack(spacing: 10) {
                    Text("Drive")
                        .font(DS.Typography.display(56))
                        .tracking(1)
                        .foregroundColor(.white)
                    Text("Drive smarter.")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(DS.Colors.secondary)
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : -20)

                Spacer()

                // Form card
                VStack(spacing: DS.Spacing.l) {

                    // Mode toggle
                    HStack(spacing: 0) {
                        modeToggle("Sign In", active: isLoginMode) {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                isLoginMode = true; errorMessage = ""
                            }
                        }
                        modeToggle("Sign Up", active: !isLoginMode) {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                isLoginMode = false; errorMessage = ""
                            }
                        }
                    }
                    .padding(4)
                    .background(Color.white.opacity(0.07))
                    .clipShape(Capsule())

                    // Fields — enter on email moves to password; enter on password submits
                    VStack(spacing: DS.Spacing.m) {
                        AuthField(
                            label: "Email",
                            text: $email,
                            keyboardType: .emailAddress,
                            submitLabel: .next,
                            onSubmit: { focusPassword = true }
                        )
                        AuthField(
                            label: "Password",
                            text: $password,
                            isSecure: true,
                            submitLabel: .go,
                            requestFocus: $focusPassword,
                            onSubmit: handleAuth
                        )
                    }

                    // Error
                    if !errorMessage.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(.system(size: 13))
                            Text(errorMessage)
                                .font(.system(size: 13, weight: .medium))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .foregroundColor(DS.Colors.scorePoor)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    // Primary CTA
                    Button(action: handleAuth) {
                        Text(isLoginMode ? "Sign In" : "Create Account")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: DS.Radius.l, style: .continuous)
                                    .fill(DS.Colors.accent)
                            )
                    }

                    // Forgot password — only on sign-in
                    if isLoginMode {
                        if !resetConfirmation.isEmpty {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 13))
                                    .foregroundColor(DS.Colors.scoreGreat)
                                Text(resetConfirmation)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(DS.Colors.scoreGreat)
                            }
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        } else {
                            Button(action: handleForgotPassword) {
                                if isSendingReset {
                                    ProgressView().tint(DS.Colors.secondary)
                                } else {
                                    Text("Forgot password?")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(DS.Colors.secondary)
                                }
                            }
                            .disabled(isSendingReset)
                        }
                    }

                    // Divider
                    HStack(spacing: 10) {
                        Rectangle().fill(Color.white.opacity(0.10)).frame(height: 1)
                        Text("or continue with")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(DS.Colors.secondary)
                            .fixedSize()
                        Rectangle().fill(Color.white.opacity(0.10)).frame(height: 1)
                    }

                    // Social sign-in buttons
                    VStack(spacing: DS.Spacing.s) {
                        Button(action: handleGoogleSignIn) {
                            socialButtonLabel(
                                icon: AnyView(googleBadge),
                                label: "Continue with Google"
                            )
                        }
                        .buttonStyle(SocialButtonStyle())

                        Button(action: handleAppleSignIn) {
                            socialButtonLabel(
                                icon: AnyView(
                                    Image(systemName: "apple.logo")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.white)
                                ),
                                label: "Continue with Apple"
                            )
                        }
                        .buttonStyle(SocialButtonStyle())
                    }
                }
                .padding(DS.Spacing.xl)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                        .fill(DS.Colors.bgCard)
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                                .stroke(DS.Colors.cardStroke, lineWidth: 1)
                        )
                )
                .padding(.horizontal, DS.Spacing.l)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 40)

                // Account-creation disclosure (App Review 5.1.1)
                HStack(spacing: 3) {
                    Text("By continuing, you agree to our")
                        .foregroundColor(DS.Colors.secondary)
                    Link("Privacy Policy",
                         destination: URL(string: "https://flamedrago8.github.io/privacy.html")!)
                        .foregroundColor(DS.Colors.accent)
                }
                .font(.system(size: 11, weight: .medium))
                .padding(.top, DS.Spacing.m)
                .opacity(appeared ? 1 : 0)

                Spacer(minLength: 50)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: errorMessage)
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.85).delay(0.15)) {
                appeared = true
            }
        }
    }

    // MARK: – Helpers

    private func socialButtonLabel(icon: AnyView, label: String) -> some View {
        HStack(spacing: 10) {
            icon.frame(width: 20)
            Text(label)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
    }

    private var googleBadge: some View {
        Image(systemName: "globe")
            .font(.system(size: 16, weight: .medium))
            .foregroundColor(.white)
    }

    @ViewBuilder
    private func modeToggle(_ label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(active ? .white : DS.Colors.secondary)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity)
                .background(
                    Group {
                        if active { Capsule().fill(DS.Colors.accent) }
                        else       { Color.clear }
                    }
                )
        }
    }

    // MARK: – Actions

    private func handleAuth() {
        let trimmedEmail    = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedEmail.isEmpty else {
            withAnimation { errorMessage = "Please enter your email address." }
            return
        }
        guard trimmedEmail.contains("@") && trimmedEmail.contains(".") else {
            withAnimation { errorMessage = "Please enter a valid email address." }
            return
        }
        guard !trimmedPassword.isEmpty else {
            withAnimation { errorMessage = "Please enter your password." }
            return
        }
        guard trimmedPassword.count >= 6 else {
            withAnimation { errorMessage = "Password must be at least 6 characters." }
            return
        }

        if isLoginMode {
            userManager.signIn(email: trimmedEmail, password: trimmedPassword) { error in
                withAnimation { errorMessage = error?.localizedDescription ?? "" }
            }
        } else {
            userManager.signUp(email: trimmedEmail, password: trimmedPassword) { error in
                withAnimation { errorMessage = error?.localizedDescription ?? "" }
            }
        }
    }

    private func handleForgotPassword() {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmail.isEmpty else {
            withAnimation { errorMessage = "Enter your email address above, then tap Forgot password." }
            return
        }
        isSendingReset = true
        userManager.sendPasswordReset(email: trimmedEmail) { error in
            isSendingReset = false
            if let error {
                withAnimation { errorMessage = error.localizedDescription }
            } else {
                withAnimation { resetConfirmation = "Reset link sent — check your email." }
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    withAnimation { resetConfirmation = "" }
                }
            }
        }
    }

    private func handleAppleSignIn() {
        userManager.signInWithApple { error in
            guard let error else { return }
            let asErr = error as? ASAuthorizationError
            if asErr?.code != .canceled {
                withAnimation { errorMessage = error.localizedDescription }
            }
        }
    }

    private func handleGoogleSignIn() {
        userManager.signInWithGoogle { error in
            guard let error else { return }
            withAnimation { errorMessage = error.localizedDescription }
        }
    }
}

// MARK: – Social button style

private struct SocialButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.l, style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.13 : 0.07))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.l, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: – Auth Field

struct AuthField: View {
    let label: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default
    var isSecure: Bool = false
    var submitLabel: SubmitLabel = .done
    var requestFocus: Binding<Bool>? = nil
    var onSubmit: (() -> Void)? = nil

    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(focused ? DS.Colors.accent : DS.Colors.secondary)
                .animation(.easeInOut(duration: 0.2), value: focused)

            Group {
                if isSecure {
                    SecureField("", text: $text)
                } else {
                    TextField("", text: $text)
                        .keyboardType(keyboardType)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }
            }
            .focused($focused)
            .submitLabel(submitLabel)
            .onSubmit { onSubmit?() }
            .font(.system(size: 16, weight: .medium))
            .foregroundColor(.white)
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
        }
        // When parent requests focus (e.g. email → password tab)
        .onChange(of: requestFocus?.wrappedValue ?? false) { _, requested in
            if requested {
                focused = true
                requestFocus?.wrappedValue = false
            }
        }
    }
}

// MARK: – Verify Email View

struct VerifyEmailView: View {
    @ObservedObject private var userManager = UserManager.shared
    @State private var isResending = false
    @State private var isChecking  = false
    @State private var resentConfirmed = false
    @State private var errorMessage = ""

    private var email: String {
        userManager.user?.email ?? "your email"
    }

    var body: some View {
        ZStack {
            DS.Colors.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: DS.Spacing.xl) {
                    // Icon
                    ZStack {
                        Circle()
                            .fill(DS.Colors.accent.opacity(0.12))
                            .frame(width: 80, height: 80)
                        PhosphorIcon.fill("envelope", size: 32, color: DS.Colors.accent)
                    }

                    // Text
                    VStack(spacing: DS.Spacing.s) {
                        Text("Verify Your Email")
                            .font(DS.Typography.heading(22))
                            .foregroundColor(.white)
                        Text("We sent a link to\n\(email)")
                            .font(DS.Typography.body(14))
                            .foregroundColor(DS.Colors.secondary)
                            .multilineTextAlignment(.center)
                            .lineSpacing(3)
                    }

                    // Actions
                    VStack(spacing: DS.Spacing.m) {
                        // Primary — check verification
                        Button {
                            isChecking = true
                            errorMessage = ""
                            userManager.reloadUser {
                                isChecking = false
                                if !(userManager.user?.isEmailVerified ?? false) {
                                    withAnimation {
                                        errorMessage = "Email not verified yet. Check your inbox and click the link."
                                    }
                                }
                                // If verified, DriveApp re-evaluates and routes away automatically
                            }
                        } label: {
                            HStack(spacing: DS.Spacing.s) {
                                if isChecking {
                                    ProgressView().tint(.white).scaleEffect(0.85)
                                }
                                Text("I've Verified My Email")
                                    .font(DS.Typography.heading(16))
                                    .foregroundColor(.white)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: DS.Radius.l, style: .continuous)
                                    .fill(DS.Colors.accent)
                            )
                        }
                        .disabled(isChecking)

                        // Secondary — resend
                        Button {
                            isResending = true
                            resentConfirmed = false
                            errorMessage = ""
                            userManager.resendVerificationEmail { error in
                                isResending = false
                                if let error {
                                    withAnimation { errorMessage = error.localizedDescription }
                                } else {
                                    withAnimation { resentConfirmed = true }
                                }
                            }
                        } label: {
                            HStack(spacing: DS.Spacing.xs) {
                                if isResending {
                                    ProgressView().tint(DS.Colors.accent).scaleEffect(0.75)
                                }
                                Text(resentConfirmed ? "Email sent!" : "Resend Email")
                                    .font(DS.Typography.heading(14))
                                    .foregroundColor(resentConfirmed ? DS.Colors.scoreGreat : DS.Colors.accent)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: DS.Radius.l, style: .continuous)
                                    .fill(DS.Colors.accent.opacity(0.10))
                                    .overlay(RoundedRectangle(cornerRadius: DS.Radius.l, style: .continuous)
                                        .stroke(DS.Colors.accent.opacity(0.25), lineWidth: 1))
                            )
                        }
                        .disabled(isResending)
                    }

                    // Error
                    if !errorMessage.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(.system(size: 13))
                            Text(errorMessage)
                                .font(DS.Typography.body(13))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .foregroundColor(DS.Colors.scorePoor)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .padding(DS.Spacing.xl)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                        .fill(DS.Colors.bgCard)
                        .overlay(RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                            .stroke(DS.Colors.cardStroke, lineWidth: 1))
                )
                .padding(.horizontal, DS.Spacing.l)

                // Sign out
                Button {
                    userManager.signOut()
                } label: {
                    Text("Use a different email")
                        .font(DS.Typography.body(13))
                        .foregroundColor(DS.Colors.secondary)
                        .padding(.top, DS.Spacing.xl)
                }

                Spacer()
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: errorMessage)
    }
}

#Preview {
    AuthView().preferredColorScheme(.dark)
}
