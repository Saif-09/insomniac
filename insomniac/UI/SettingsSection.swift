//
//  SettingsSection.swift
//  insomniac
//
//  Collapsible preferences: thermal cutoff level, advisory behaviour, weather,
//  and the privileged-helper setup (M4). Kept out of the main flow to keep the
//  menu light (Non-Goal: not a dashboard).
//

import SwiftUI

struct SettingsSection: View {
    @Environment(AppController.self) private var app
    @State private var expanded = false

    var body: some View {
        @Bindable var prefs = app.prefs

        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 10) {
                cutoffPicker
                batteryCutoffControls
                Toggle("Turn screen off when lid closes", isOn: $prefs.turnOffScreenOnLidClose)
                    .font(.caption)
                Toggle("Use advisor's suggested duration", isOn: $prefs.respectAdvisorySuggestion)
                    .font(.caption)
                weatherControls
                Divider()
                helperRow
            }
            .padding(.top, 6)
        } label: {
            Label("Settings", systemImage: "gearshape").font(.subheadline)
        }
    }

    // Thermal cutoff (FR-13) — serious (default) or critical.
    private var cutoffPicker: some View {
        @Bindable var prefs = app.prefs
        return HStack {
            Text("Auto-stop at").font(.caption)
            Spacer()
            Picker("Auto-stop at", selection: $prefs.thermalCutoff) {
                Text("Serious").tag(ProcessInfo.ThermalState.serious)
                Text("Critical").tag(ProcessInfo.ThermalState.critical)
            }
            .labelsHidden()
            .frame(width: 120)
        }
    }

    // Battery safety cutoff — auto-stop the session on low battery.
    private var batteryCutoffControls: some View {
        @Bindable var prefs = app.prefs
        return VStack(alignment: .leading, spacing: 6) {
            Toggle("Auto-stop on low battery", isOn: $prefs.batteryCutoffEnabled)
                .font(.caption)
            if prefs.batteryCutoffEnabled {
                HStack {
                    Text("Stop at").font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    Picker("Stop at", selection: $prefs.batteryCutoffPercent) {
                        ForEach([10, 15, 20, 30, 40], id: \.self) { percent in
                            Text("\(percent)%").tag(percent)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 90)
                }
            }
        }
    }

    // Weather (FR-15/17). Location is detected automatically — no manual city.
    private var weatherControls: some View {
        @Bindable var prefs = app.prefs
        return VStack(alignment: .leading, spacing: 6) {
            Toggle("Use local weather (ambient nudge)", isOn: $prefs.weatherEnabled)
                .font(.caption)
                .onChange(of: prefs.weatherEnabled) { _, enabled in
                    if enabled { Task { await app.refreshWeatherIfEnabled() } }
                }

            if prefs.weatherEnabled {
                weatherStatusRow
            }
        }
    }

    @ViewBuilder
    private var weatherStatusRow: some View {
        switch app.weatherLocationState {
        case .idle:
            EmptyView()
        case .requesting:
            Label("Detecting your location…", systemImage: "location")
                .font(.caption2).foregroundStyle(.secondary)
        case .located(let area):
            let temp = app.weather.currentCelsius.map { " · \(Int($0.rounded()))°C" } ?? ""
            Label((area ?? "Current location") + temp, systemImage: "location.fill")
                .font(.caption2).foregroundStyle(.secondary)
        case .unavailable:
            HStack {
                Label("Couldn't determine your location", systemImage: "exclamationmark.triangle")
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Button("Retry") { Task { await app.retryWeather() } }
                    .controlSize(.small)
            }
        }
    }

    // Privileged helper (M4, FR-9): silent toggling after one-time setup.
    private var helperRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Silent toggling (no password)", systemImage: "key.fill").font(.caption)
            switch app.helperInstaller.state {
            case .enabled:
                Label("Helper installed", systemImage: "checkmark.seal.fill")
                    .font(.caption2).foregroundStyle(.green)
            case .requiresApproval:
                VStack(alignment: .leading, spacing: 4) {
                    Text("Approve the helper in System Settings to finish setup.")
                        .font(.caption2).foregroundStyle(.secondary)
                    Button("Open Login Items") { app.helperInstaller.openApprovalSettings() }
                        .controlSize(.small)
                }
            case .failed(let message):
                Text(message).font(.caption2).foregroundStyle(.red)
            case .notRegistered:
                HStack {
                    Text("Uses a password prompt each time.")
                        .font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    Button("Install helper") { app.helperInstaller.install() }
                        .controlSize(.small)
                }
            }
        }
    }
}
