//
//  MenuContent.swift
//  insomniac
//
//  The menu-bar dropdown (FR-19): a compact, polished panel — hero session
//  card with a countdown ring, a risk-tinted advisory card, settings, and Quit.
//

import SwiftUI

struct MenuContent: View {
    @Environment(AppController.self) private var app

    private var accent: Color { app.menuBarTint ?? .accentColor }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if app.needsCrashRecovery {
                crashRecoveryBanner
            }

            heroCard
            advisoryCard

            if let error = app.lastErrorMessage {
                Label(error, systemImage: "exclamationmark.octagon.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SettingsSection()

            footer
        }
        .padding(16)
        .frame(width: 340)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 9) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [accent, accent.opacity(0.65)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                .frame(width: 28, height: 28)
                .overlay(
                    Image(systemName: app.isActive ? "bolt.fill" : "moon.zzz.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                )
                .shadow(color: accent.opacity(app.isActive ? 0.4 : 0), radius: 5, y: 1)

            Text("Insomniac")
                .font(.system(.title3, design: .rounded).weight(.bold))

            Spacer()

            StatusDot(color: app.isActive ? app.advisory.risk.color : .secondary, active: app.isActive)
        }
    }

    // MARK: - Crash recovery (FR-14)

    private var crashRecoveryBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Sleep is still disabled from a previous run.", systemImage: "arrow.counterclockwise.circle.fill")
                .font(.caption.weight(.medium))
            HStack {
                Button("Restore normal sleep") { app.resolveCrashRecovery() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                Button("Ignore") { app.dismissCrashRecovery() }
                    .controlSize(.small)
            }
        }
        .card(tint: .yellow, fill: 0.16, stroke: 0.30)
    }

    // MARK: - Hero session card (FR-1, FR-3, FR-5, FR-7)

    private var heroCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                if app.isActive {
                    CountdownRing(progress: app.sessionProgress, color: accent, systemImage: "bolt.fill")
                } else {
                    ZStack {
                        Circle().fill(Color.primary.opacity(0.06))
                        Image(systemName: "moon.zzz.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 44, height: 44)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Stay Awake")
                        .font(.headline)
                    Text(app.statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 4)

                Toggle(isOn: Binding(get: { app.isActive }, set: { _ in app.toggle() })) {
                    EmptyView()
                }
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(accent)
                .disabled(app.isBusy)
            }

            Divider().opacity(0.4)

            HStack {
                Label("Auto-off", systemImage: "timer")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("Auto-off", selection: autoOffSelection) {
                    ForEach(AutoOffDuration.allCases) { duration in
                        Text(duration.label).tag(duration)
                    }
                }
                .labelsHidden()
                .frame(width: 140)
            }
        }
        .card(tint: app.isActive ? accent : .primary, fill: app.isActive ? 0.10 : 0.05, stroke: app.isActive ? 0.22 : 0.09)
        .animation(.easeInOut(duration: 0.25), value: app.isActive)
    }

    private var autoOffSelection: Binding<AutoOffDuration> {
        Binding(
            get: { app.isActive ? (app.session?.duration ?? app.effectiveDuration) : app.effectiveDuration },
            set: { newValue in
                if app.isActive { app.reschedule(to: newValue) }
                else { app.chosenDuration = newValue }
            }
        )
    }

    // MARK: - Advisory (FR-12)

    private var advisoryCard: some View {
        let advisory = app.advisory
        return VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 9) {
                ZStack {
                    Circle().fill(advisory.risk.color.opacity(0.18))
                    Image(systemName: advisory.risk.symbolName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(advisory.risk.color)
                }
                .frame(width: 30, height: 30)

                Text(advisory.risk.label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(advisory.risk.color)

                Spacer()

                if !app.isActive && app.preselectedDuration == advisory.suggestedDuration {
                    Text("suggests \(advisory.suggestedDuration.shortLabel)")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }

            Text(advisory.message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                Chip(text: app.thermal.state.displayName, systemImage: "cpu")
                Chip(text: powerChipText,
                     systemImage: app.powerSource.isOnAC ? "powerplug.fill" : "battery.50")
                if app.prefs.weatherEnabled, let c = app.weather.currentCelsius {
                    Chip(text: "\(Int(c.rounded()))°C", systemImage: "thermometer.sun")
                }
            }
        }
        .card(tint: advisory.risk.color, fill: 0.10, stroke: 0.20)
    }

    private var powerChipText: String {
        if app.powerSource.isOnAC { return "AC" }
        if let fraction = app.powerSource.batteryFraction {
            return "Battery \(Int((fraction * 100).rounded()))%"
        }
        return "Battery"
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Spacer()
            Button {
                app.quit()
            } label: {
                Label("Quit", systemImage: "power")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
        }
    }
}
