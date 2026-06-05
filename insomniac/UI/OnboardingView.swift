//
//  OnboardingView.swift
//  insomniac
//
//  First-launch welcome + feature introduction. Because Insomniac is a
//  MenuBarExtra app with no Dock icon and no main window, a brand-new user has
//  no idea where it went after launching. This walkthrough introduces the
//  features and — crucially — points to the menu-bar icon at the top-right
//  (the live arrow is driven by `OnboardingController`).
//

import SwiftUI

struct OnboardingView: View {
    /// Called when the user reaches/confirms the "find me in the menu bar"
    /// step — the controller pops the live arrow near the real icon.
    var onRevealPointer: () -> Void
    /// Called when the user finishes — the controller closes everything and
    /// marks onboarding complete.
    var onFinish: () -> Void

    @State private var step = 0
    @State private var didReveal = false

    private let lastStep = 2

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 32)
                .padding(.top, 36)

            footer
                .padding(.horizontal, 28)
                .padding(.bottom, 22)
                .padding(.top, 8)
        }
        .frame(width: 460, height: 560)
        .background(
            LinearGradient(
                colors: [Color.accentColor.opacity(0.12), Color.clear],
                startPoint: .top, endPoint: .center
            )
            .ignoresSafeArea()
        )
    }

    // MARK: - Per-step content

    @ViewBuilder
    private var content: some View {
        switch step {
        case 0: welcomeStep
        case 1: featuresStep
        default: menuBarStep
        }
    }

    private var welcomeStep: some View {
        VStack(spacing: 18) {
            Spacer()
            appMark(size: 92, icon: "moon.zzz.fill")
            VStack(spacing: 8) {
                Text("Welcome to Insomniac")
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .multilineTextAlignment(.center)
                Text("Keep your Mac awake — even with the lid closed — without cooking it.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .transition(.opacity)
    }

    private var featuresStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("What it does")
                .font(.system(.title, design: .rounded).weight(.bold))
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.bottom, 4)

            FeatureRow(
                icon: "macbook.and.visionpro", tint: .accentColor,
                title: "Lid-closed stay-awake",
                subtitle: "Flip one switch and your Mac keeps running with the lid shut."
            )
            FeatureRow(
                icon: "timer", tint: .blue,
                title: "Auto-off timer",
                subtitle: "Pick a duration — it turns itself off so you never forget."
            )
            FeatureRow(
                icon: "thermometer.medium", tint: .orange,
                title: "Thermal & battery safety",
                subtitle: "Stops automatically if your Mac gets too hot or the battery runs low."
            )
            FeatureRow(
                icon: "wand.and.stars", tint: .purple,
                title: "Smart advice",
                subtitle: "Suggests a safe duration based on heat, power, and load."
            )
            Spacer()
        }
        .transition(.opacity)
    }

    private var menuBarStep: some View {
        VStack(spacing: 18) {
            Spacer()
            MenuBarIllustration()
                .frame(height: 92)

            VStack(spacing: 8) {
                Text("Find Insomniac up here ↑")
                    .font(.system(.title, design: .rounded).weight(.bold))
                    .multilineTextAlignment(.center)
                Text("Insomniac has no Dock icon — it lives in the **menu bar** at the top-right of your screen. Look for the \(Image(systemName: "moon.zzz")) moon icon. Click it anytime to stay awake.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !didReveal {
                Button {
                    didReveal = true
                    onRevealPointer()
                } label: {
                    Label("Show me where", systemImage: "arrow.up.right.circle.fill")
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.top, 4)
            } else {
                Label("Look at the top-right of your screen", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.green)
                    .padding(.top, 4)
            }
            Spacer()
        }
        .transition(.opacity)
    }

    // MARK: - Footer (page dots + nav)

    private var footer: some View {
        HStack {
            Button("Back") {
                withAnimation(.easeInOut(duration: 0.2)) { step -= 1 }
            }
            .buttonStyle(.borderless)
            .opacity(step == 0 ? 0 : 1)
            .disabled(step == 0)

            Spacer()

            HStack(spacing: 7) {
                ForEach(0...lastStep, id: \.self) { i in
                    Circle()
                        .fill(i == step ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 7, height: 7)
                }
            }

            Spacer()

            if step < lastStep {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { step += 1 }
                } label: {
                    Label("Next", systemImage: "chevron.right")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button("Get Started") { onFinish() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    // MARK: - Shared bits

    private func appMark(size: CGFloat, icon: String) -> some View {
        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color.accentColor, Color.accentColor.opacity(0.6)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            )
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: icon)
                    .font(.system(size: size * 0.46, weight: .bold))
                    .foregroundStyle(.white)
            )
            .shadow(color: Color.accentColor.opacity(0.35), radius: 16, y: 6)
    }
}

// MARK: - Feature row

private struct FeatureRow: View {
    var icon: String
    var tint: Color
    var title: String
    var subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(tint.opacity(0.16))
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Menu bar illustration

/// A small mock of the macOS menu bar with our icon highlighted at the right,
/// so users recognise the strip they're looking for at the top of the screen.
private struct MenuBarIllustration: View {
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    HStack(spacing: 14) {
                        Image(systemName: "apple.logo").font(.system(size: 11, weight: .semibold))
                        Text("Finder").font(.system(size: 11, weight: .semibold))
                        Spacer()
                        Image(systemName: "wifi").font(.system(size: 10))
                        Image(systemName: "battery.100").font(.system(size: 10))
                        // Our icon — highlighted.
                        Image(systemName: "moon.zzz")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.accentColor)
                            .padding(4)
                            .background(
                                Circle().fill(Color.accentColor.opacity(pulse ? 0.28 : 0.0))
                            )
                            .scaleEffect(pulse ? 1.15 : 1.0)
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                )
                .frame(height: 30)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
                )

            Image(systemName: "arrow.up")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color.accentColor)
                .offset(x: 150)
                .opacity(0.9)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}
