//
//  SettingsSection.swift
//  insomniac
//
//  Collapsible preferences: lid-close display-off, thermal cutoff, battery
//  cutoff, advisory behaviour, weather, and the privileged-helper setup (M4).
//  Kept out of the main flow to keep the menu light (Non-Goal: not a dashboard).
//
//  Clean macOS System Settings look: the whole header row toggles the section,
//  rows are monochrome-icon cells in one grouped card with hairline separators,
//  and the section reveals in place (no slide-from-top jump).
//

import SwiftUI

struct SettingsSection: View {
    @Environment(AppController.self) private var app
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if expanded {
                rows
                    .padding(.top, 10)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: expanded)
    }

    // MARK: - Header (entire row toggles)

    private var header: some View {
        Button {
            expanded.toggle()
        } label: {
            HStack(spacing: 10) {
                SettingIcon(systemImage: "gearshape.fill")
                Text("Settings").font(.callout.weight(.semibold))
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(expanded ? 0 : -90))
            }
            .contentShape(Rectangle()) // full-width hit target
        }
        .buttonStyle(.plain)
    }

    // MARK: - Rows

    private var rows: some View {
        // Ordered core → smart → setup: an active session's behaviour and its
        // safety cutoffs first, the optional smart suggestions next, and the
        // one-time privileged-helper setup last.
        VStack(alignment: .leading, spacing: 14) {
            group("While awake") {
                lidRow
                separator
                batteryRows
                separator
                thermalRow
            }
            group("Suggestions") {
                advisorRow
                separator
                weatherRows
            }
            group("Setup") {
                helperRow.rowPadding()
            }
        }
    }

    // MARK: - Grouped card

    /// A System Settings–style group: a small uppercase header above a single
    /// rounded card holding the rows.
    private func group<Content: View>(
        _ title: String,
        @ViewBuilder _ content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
                .padding(.leading, 4)
            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
    }

    /// Hairline separator inset to align with the row text.
    private var separator: some View {
        Divider().opacity(0.5).padding(.leading, 30)
    }

    // MARK: - Individual rows

    private var lidRow: some View {
        @Bindable var prefs = app.prefs
        return SettingToggleRow(
            icon: "macbook",
            title: "Turn screen off when lid closes",
            isOn: $prefs.turnOffScreenOnLidClose
        )
        .rowPadding()
    }

    private var batteryRows: some View {
        @Bindable var prefs = app.prefs
        return VStack(alignment: .leading, spacing: 8) {
            SettingToggleRow(
                icon: "battery.25percent",
                title: "Auto-stop on low battery",
                isOn: $prefs.batteryCutoffEnabled
            )
            if prefs.batteryCutoffEnabled {
                HStack {
                    Text("Stop at").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Picker("Stop at", selection: $prefs.batteryCutoffPercent) {
                        ForEach([10, 15, 20, 30, 40], id: \.self) { percent in
                            Text("\(percent)%").tag(percent)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 90)
                }
                .padding(.leading, 30)
            }
        }
        .rowPadding()
    }

    private var thermalRow: some View {
        @Bindable var prefs = app.prefs
        return SettingRow(icon: "thermometer.medium", title: "Auto-stop at") {
            Picker("Auto-stop at", selection: $prefs.thermalCutoff) {
                Text("Serious").tag(ProcessInfo.ThermalState.serious)
                Text("Critical").tag(ProcessInfo.ThermalState.critical)
            }
            .labelsHidden()
            .frame(width: 110)
        }
        .rowPadding()
    }

    private var advisorRow: some View {
        @Bindable var prefs = app.prefs
        return SettingToggleRow(
            icon: "wand.and.stars",
            title: "Use advisor's suggested duration",
            isOn: $prefs.respectAdvisorySuggestion
        )
        .rowPadding()
    }

    private var weatherRows: some View {
        @Bindable var prefs = app.prefs
        return VStack(alignment: .leading, spacing: 8) {
            SettingToggleRow(
                icon: "cloud.sun.fill",
                title: "Use local weather", subtitle: "ambient nudge",
                isOn: $prefs.weatherEnabled
            )
            .onChange(of: prefs.weatherEnabled) { _, enabled in
                if enabled { Task { await app.refreshWeatherIfEnabled() } }
            }
            if prefs.weatherEnabled {
                weatherStatusRow.padding(.leading, 30)
            }
        }
        .rowPadding()
    }

    @ViewBuilder
    private var weatherStatusRow: some View {
        switch app.weatherLocationState {
        case .idle:
            EmptyView()
        case .requesting:
            Label("Detecting your location…", systemImage: "location")
                .font(.caption).foregroundStyle(.secondary)
        case .located(let area):
            let temp = app.weather.currentCelsius.map { " · \(Int($0.rounded()))°C" } ?? ""
            Label((area ?? "Current location") + temp, systemImage: "location.fill")
                .font(.caption).foregroundStyle(.secondary)
        case .unavailable:
            HStack {
                Label("Couldn't determine your location", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Retry") { Task { await app.retryWeather() } }
                    .controlSize(.small)
            }
        }
    }

    // Privileged helper (M4, FR-9): silent toggling after one-time setup.
    private var helperRow: some View {
        HStack(spacing: 10) {
            SettingIcon(systemImage: "key.fill")
            VStack(alignment: .leading, spacing: 2) {
                Text("Silent toggling").font(.callout)
                helperStatus
            }
            Spacer(minLength: 8)
            helperAction
        }
    }

    @ViewBuilder
    private var helperStatus: some View {
        switch app.helperInstaller.state {
        case .enabled:
            Label("No password needed", systemImage: "checkmark.seal.fill")
                .font(.caption).foregroundStyle(.green)
        case .requiresApproval:
            Text("Approve in System Settings to finish.")
                .font(.caption).foregroundStyle(.secondary)
        case .failed(let message):
            Text(message).font(.caption).foregroundStyle(.red)
        case .notRegistered:
            Text("Uses a password prompt each time.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var helperAction: some View {
        switch app.helperInstaller.state {
        case .enabled:
            EmptyView()
        case .requiresApproval:
            Button("Open Login Items") { app.helperInstaller.openApprovalSettings() }
                .controlSize(.small)
        case .failed, .notRegistered:
            Button("Install") { app.helperInstaller.install() }
                .controlSize(.small)
        }
    }
}

private extension View {
    /// Consistent per-row inset inside the grouped card.
    func rowPadding() -> some View {
        padding(.horizontal, 12).padding(.vertical, 10)
    }
}
