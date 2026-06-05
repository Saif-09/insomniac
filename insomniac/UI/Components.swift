//
//  Components.swift
//  insomniac
//
//  Small reusable building blocks for a more polished menu UI: card surfaces,
//  the countdown ring, status dot, and pill chips.
//

import SwiftUI

// MARK: - Card surface

private struct CardModifier: ViewModifier {
    var tint: Color
    var fillOpacity: Double
    var strokeOpacity: Double

    func body(content: Content) -> some View {
        content
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(tint.opacity(fillOpacity))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(tint.opacity(strokeOpacity), lineWidth: 1)
            )
    }
}

extension View {
    /// A subtle grouped "card" surface. Pass a `tint` to color it (e.g. the
    /// accent for an active session, or a risk color for the advisory).
    func card(tint: Color = .primary, fill: Double = 0.05, stroke: Double = 0.09) -> some View {
        modifier(CardModifier(tint: tint, fillOpacity: fill, strokeOpacity: stroke))
    }
}

// MARK: - Countdown ring

struct CountdownRing: View {
    /// Remaining fraction, 1 → 0.
    var progress: Double
    var color: Color
    var systemImage: String
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.10), lineWidth: 4)
            Circle()
                .trim(from: 0, to: max(0.001, progress))
                .stroke(
                    color.gradient,
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.4), value: progress)
            Image(systemName: systemImage)
                .font(.system(size: size * 0.34, weight: .semibold))
                .foregroundStyle(color)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Status dot

struct StatusDot: View {
    var color: Color
    var active: Bool
    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .overlay(
                Circle().fill(color.opacity(0.35))
                    .frame(width: 16, height: 16)
                    .opacity(active ? 1 : 0)
            )
    }
}

// MARK: - Settings building blocks

/// A leading glyph for a settings row — a plain monochrome SF Symbol on a
/// fixed-width column so every row's text aligns (macOS System Settings style).
struct SettingIcon: View {
    var systemImage: String
    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 14))
            .foregroundStyle(.secondary)
            .frame(width: 20, alignment: .center)
    }
}

/// A settings row: leading icon, title/subtitle, and arbitrary trailing content
/// (a picker, switch, value, etc.). Always fills the row width so every row's
/// trailing control right-aligns to the same edge.
struct SettingRow<Trailing: View>: View {
    var icon: String
    var title: String
    var subtitle: String?
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 10) {
            SettingIcon(systemImage: icon)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.callout)
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            trailing()
        }
        .frame(maxWidth: .infinity)
    }
}

/// A settings row with a trailing switch — built on `SettingRow` so its switch
/// aligns with the pickers and buttons in sibling rows.
struct SettingToggleRow: View {
    var icon: String
    var title: String
    var subtitle: String?
    @Binding var isOn: Bool

    var body: some View {
        SettingRow(icon: icon, title: title, subtitle: subtitle) {
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }
}

// MARK: - Pill chip

struct Chip: View {
    var text: String
    var systemImage: String
    var tint: Color = .secondary

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption2.weight(.medium))
            .foregroundStyle(tint == .secondary ? Color.secondary : tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule().fill((tint == .secondary ? Color.primary : tint).opacity(0.08))
            )
    }
}
