//
//  MenuBarPointer.swift
//  insomniac
//
//  The floating "I live up here" coach-mark shown in a borderless panel just
//  below the menu bar, pointing UP at the real Insomniac icon. Hosted by
//  `OnboardingController`, which positions the panel and aligns the arrow tip
//  to the actual icon.
//

import SwiftUI

struct MenuBarPointer: View {
    /// Transparent slack baked around the visible bubble so the shadow and the
    /// arrow are never clipped by the hosting panel's bounds.
    static let hInset: CGFloat = 14
    static let vInset: CGFloat = 10

    /// Horizontal shift of the arrow tip relative to the bubble's center, so it
    /// can point at the icon even when the bubble is clamped to stay on screen.
    var arrowOffsetX: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            // Upward arrow pointing at the real menu-bar icon above.
            Triangle()
                .fill(Color.accentColor)
                .frame(width: 22, height: 12)
                .offset(x: arrowOffsetX, y: 1)

            HStack(spacing: 10) {
                Image(systemName: "moon.zzz.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Insomniac lives here")
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .foregroundStyle(.white)
                    Text("Click the moon anytime")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.85))
                }
                // Never truncate — let the bubble grow to the text's width.
                .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.accentColor)
            )
            .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
        }
        .padding(.horizontal, Self.hInset)
        .padding(.vertical, Self.vInset)
        .fixedSize()
    }
}

/// A simple upward-pointing triangle for the speech-bubble tip.
private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}
