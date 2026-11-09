//
//  LanternView.swift
//  Journal-Whisper
//
//  The lantern companion, drawn in SwiftUI. `brightness` (0–1) sets how far
//  its glow reaches: in Insights it follows the days written this week. The
//  flame flickers gently unless Reduce Motion is on.
//

import SwiftUI

struct LanternView: View {
    /// 0 = a small ember, 1 = glowing brightly.
    var brightness: Double = 0.6
    /// Show the little face (the companion) or a plain lantern.
    var showsFace = true
    var size: CGFloat = 180

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var flicker = false

    var body: some View {
        let level = min(max(brightness, 0), 1)
        ZStack {
            // Glow: two soft discs that grow with brightness.
            Circle()
                .fill(Theme.glow.opacity(0.15 + 0.25 * level))
                .frame(width: size * (0.55 + 0.45 * level))
            Circle()
                .fill(Theme.glow.opacity(0.2 + 0.3 * level))
                .frame(width: size * (0.35 + 0.25 * level))

            Canvas { context, canvasSize in
                draw(in: &context, size: canvasSize, level: level)
            }
            .frame(width: size, height: size)
        }
        .frame(width: size, height: size)
        .scaleEffect(flicker ? 1.0 : 0.985, anchor: .bottom)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { flicker = true }
        }
        .accessibilityHidden(true)
    }

    /// Lantern on a 220×220 grid, scaled to `size`.
    private func draw(in context: inout GraphicsContext, size: CGSize, level: Double) {
        let s = size.width / 220
        func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> CGRect {
            CGRect(x: x * s, y: y * s, width: w * s, height: h * s)
        }
        let line = StrokeStyle(lineWidth: 6 * s, lineCap: .round, lineJoin: .round)

        // Handle
        var handle = Path()
        handle.addArc(center: CGPoint(x: 110 * s, y: 46 * s), radius: 14 * s,
                      startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        context.stroke(handle, with: .color(Theme.outline), style: line)

        // Cap
        let cap = Path(roundedRect: rect(80, 46, 60, 14), cornerRadius: 6 * s)
        context.fill(cap, with: .color(Theme.brass))
        context.stroke(cap, with: .color(Theme.outline), style: line)

        // Glass
        let glass = Path(roundedRect: rect(84, 60, 52, 78), cornerRadius: 12 * s)
        context.fill(glass, with: .color(Theme.glass))
        context.stroke(glass, with: .color(Theme.outline), style: line)

        // Flame grows a little with brightness.
        let flameTop = 92 - 14 * level
        var flame = Path()
        flame.move(to: CGPoint(x: 110 * s, y: flameTop * s))
        flame.addCurve(to: CGPoint(x: 110 * s, y: 122 * s),
                       control1: CGPoint(x: 98 * s, y: (flameTop + 16) * s),
                       control2: CGPoint(x: 100 * s, y: 116 * s))
        flame.addCurve(to: CGPoint(x: 110 * s, y: flameTop * s),
                       control1: CGPoint(x: 120 * s, y: 116 * s),
                       control2: CGPoint(x: 122 * s, y: (flameTop + 16) * s))
        context.fill(flame, with: .color(Theme.flame))

        if showsFace {
            for x in [102.0, 118.0] {
                context.fill(Path(ellipseIn: rect(x - 3.5, 98.5, 7, 7)), with: .color(Theme.outline))
            }
            var smile = Path()
            smile.move(to: CGPoint(x: 104 * s, y: 110 * s))
            smile.addQuadCurve(to: CGPoint(x: 116 * s, y: 110 * s), control: CGPoint(x: 110 * s, y: 115 * s))
            context.stroke(smile, with: .color(Theme.outline), style: StrokeStyle(lineWidth: 3 * s, lineCap: .round))
        }

        // Base
        let base = Path(roundedRect: rect(76, 136, 68, 16), cornerRadius: 6 * s)
        context.fill(base, with: .color(Theme.brass))
        context.stroke(base, with: .color(Theme.outline), style: line)

        // Book underneath
        let book = Path(roundedRect: rect(40, 160, 140, 36), cornerRadius: 10 * s)
        context.fill(book, with: .color(Theme.buttonFill))
        context.stroke(book, with: .color(Theme.outline), style: line)
        var pages = Path()
        pages.move(to: CGPoint(x: 54 * s, y: 172 * s))
        pages.addLine(to: CGPoint(x: 166 * s, y: 172 * s))
        context.stroke(pages, with: .color(Theme.page), style: StrokeStyle(lineWidth: 5 * s, lineCap: .round))
    }
}

#Preview {
    HStack {
        LanternView(brightness: 0.1, size: 120)
        LanternView(brightness: 0.5, size: 120)
        LanternView(brightness: 1, size: 120)
    }
    .padding()
    .background(Theme.background)
}
