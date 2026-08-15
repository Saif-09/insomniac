//
//  SystemTab.swift
//  insomniac
//
//  The "System" tab: a compact control center for the Mac's real sleep/power
//  state. Unlike the Control tab (which shows *our* session), this shows the
//  ground truth straight from the OS — the actual `SleepDisabled` flag, the
//  sleep timers in effect, and every process currently keeping the Mac awake —
//  plus the system-level controls (toggle keep-awake, sleep the display now).
//
//  Data comes from `AppController.systemPower`, refreshed on a short timer while
//  this tab is visible (the `.task` is cancelled automatically when it isn't).
//

import SwiftUI

struct SystemTab: View {
    @Environment(AppController.self) private var app

    private var accent: Color { app.menuBarTint ?? .accentColor }
    private var snapshot: PowerSnapshot? { app.systemPower.snapshot }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            keepAwakeGroup

            if let warning = app.closedLidWarning {
                CaveatCard(text: warning)
            }

            preventersGroup
            systemGroup
            sleepDisplayButton
        }
        .task {
            // Refresh on appear, then poll while the tab is on screen. Cancelled
            // automatically when the tab or popover goes away.
            while !Task.isCancelled {
                await app.systemPower.refresh()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    // MARK: - Keep Awake (control + system truth)

    private var keepAwakeGroup: some View {
        groupCard("Keep Awake") {
            SettingRow(
                icon: app.isActive ? "bolt.fill" : "moon.zzz",
                title: "Stay Awake",
                subtitle: app.isActive ? "\(app.remainingText) left" : "Off"
            ) {
                Toggle("", isOn: Binding(get: { app.isActive }, set: { _ in app.toggle() }))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .tint(accent)
                    .disabled(app.isBusy)
            }
            .rowPadding()

            if PowerSnapshot.reportsSystemSettings {
                separator

                // The authoritative OS flag — lets the user verify our toggle
                // really took effect. A divergence (we're active but the flag is
                // off) is surfaced in orange so it can't hide. Unreadable in the
                // sandboxed build, which doesn't set it either, so the row is
                // omitted there instead of sitting on a permanent "Checking…".
                SettingRow(icon: "gauge.with.dots.needle.bottom.50percent", title: "System sleep flag") {
                    Text(sleepFlag.text)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(sleepFlag.color)
                }
                .rowPadding()
            }
        }
    }

    private var sleepFlag: (text: String, color: Color) {
        switch snapshot?.sleepDisabled {
        case .some(true): return ("Disabled", .green)
        case .some(false): return app.isActive ? ("Not applied", .orange) : ("Normal", .secondary)
        case .none: return ("Checking…", .secondary)
        }
    }

    // MARK: - What's keeping the Mac awake

    private var preventersGroup: some View {
        groupCard("Keeping Your Mac Awake", trailing: {
            if app.systemPower.isRefreshing {
                ProgressView().controlSize(.small).scaleEffect(0.7)
            } else {
                Button { Task { await app.systemPower.refresh() } } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }) {
            let preventers = snapshot?.preventers ?? []
            if preventers.isEmpty {
                emptyPreventers
            } else if preventers.count > 4 {
                ScrollView { preventerRows(preventers) }.frame(maxHeight: 176)
            } else {
                preventerRows(preventers)
            }
        }
    }

    private func preventerRows(_ preventers: [SleepPreventer]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(preventers.enumerated()), id: \.element.id) { index, p in
                if index > 0 { separator }
                preventerRow(p)
            }
        }
    }

    private func preventerRow(_ p: SleepPreventer) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill((p.isSelf ? accent : Color.primary).opacity(p.isSelf ? 0.16 : 0.06))
                Image(systemName: p.isSelf ? "bolt.fill" : p.kind.symbolName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(p.isSelf ? accent : Color.secondary)
            }
            .frame(width: 26, height: 26)

            VStack(alignment: .leading, spacing: 1) {
                Text(p.isSelf ? "Insomniac (this app)" : p.process)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Text(p.kind.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
        }
        .rowPadding()
    }

    private var emptyPreventers: some View {
        HStack(spacing: 10) {
            SettingIcon(systemImage: "moon.zzz.fill")
            VStack(alignment: .leading, spacing: 1) {
                Text("Nothing is keeping your Mac awake").font(.callout)
                Text("It will sleep normally.").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
        }
        .rowPadding()
    }

    // MARK: - System readouts (power, thermal, timers)

    private var systemGroup: some View {
        groupCard("System") {
            SettingRow(
                icon: app.powerSource.isOnAC ? "powerplug.fill" : "battery.50",
                title: "Power"
            ) {
                Text(powerValue).font(.callout.weight(.medium)).foregroundStyle(.secondary)
            }
            .rowPadding()

            separator

            SettingRow(icon: "thermometer.medium", title: "Thermal") {
                Text(app.thermal.state.displayName)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(app.thermal.state.risk.color)
            }
            .rowPadding()

            // The OS sleep timers have no public API — direct-download only.
            if PowerSnapshot.reportsSystemSettings {
                separator

                SettingRow(icon: "display", title: "Display sleeps") {
                    Text(minutesText(snapshot?.displaySleepMinutes))
                        .font(.callout.weight(.medium)).foregroundStyle(.secondary)
                }
                .rowPadding()

                separator

                SettingRow(icon: "powersleep", title: "System sleeps") {
                    Text(minutesText(snapshot?.idleSleepMinutes))
                        .font(.callout.weight(.medium)).foregroundStyle(.secondary)
                }
                .rowPadding()
            }
        }
    }

    private var powerValue: String {
        if app.powerSource.isOnAC {
            if let f = app.powerSource.batteryFraction { return "AC · \(Int((f * 100).rounded()))%" }
            return "AC power"
        }
        if let f = app.powerSource.batteryFraction { return "Battery · \(Int((f * 100).rounded()))%" }
        return "Battery"
    }

    private func minutesText(_ minutes: Int?) -> String {
        guard let minutes else { return "—" }
        if minutes == 0 { return "Never" }
        if minutes == 1 { return "1 min" }
        return "\(minutes) min"
    }

    // MARK: - Actions

    private var sleepDisplayButton: some View {
        Button {
            app.sleepDisplayNow()
        } label: {
            Label("Sleep display now", systemImage: "moon.fill")
                .font(.callout.weight(.medium))
                .frame(maxWidth: .infinity)
        }
        .controlSize(.large)
        .buttonStyle(.bordered)
    }

    // MARK: - Building blocks

    /// A System Settings–style group: an uppercase caption (with optional
    /// trailing accessory) above a single rounded card holding the rows.
    private func groupCard<Trailing: View, Content: View>(
        _ title: String,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() },
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(title.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                Spacer()
                trailing()
            }
            .padding(.horizontal, 4)

            VStack(alignment: .leading, spacing: 0) { content() }
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

    private var separator: some View {
        Divider().opacity(0.5).padding(.leading, 30)
    }

}

private extension View {
    /// Consistent per-row inset inside a grouped card (matches SettingsSection).
    func rowPadding() -> some View {
        padding(.horizontal, 12).padding(.vertical, 10)
    }
}
