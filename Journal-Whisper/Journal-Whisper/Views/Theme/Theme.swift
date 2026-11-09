//
//  Theme.swift
//  Journal-Whisper
//
//  "Cozy Adventure": warm cream, a teal accent and lantern colours, with light
//  and dark steps. Playful in touch (chunky buttons, haptics), calm in content.
//  Every text/background pair here meets WCAG AA (4.5:1) in both modes.
//

import SwiftUI
import UIKit

enum Theme {
    /// Page background.
    static let background = Color(light: 0xFFF4E6, dark: 0x1E1611)
    /// Cards and tiles.
    static let surface = Color(light: 0xFFFFFF, dark: 0x2A201A)
    static let border = Color(light: 0xF0D9BC, dark: 0x3D2F25)
    static let ink = Color(light: 0x3E2A1F, dark: 0xF7EBD8)
    static let inkSecondary = Color(light: 0x5C4A3D, dark: 0xCDBBA6)
    /// Tint for text, icons and controls: 5.2:1 on cream, about 7:1 on the dark background.
    static let accent = Color(light: 0x23766D, dark: 0x4DB6A9)
    /// Filled buttons. White text on it is 5.2:1 in both modes.
    static let buttonFill = Color(hex: 0x23766D)
    /// The chunky button's bottom edge.
    static let accentEdge = Color(light: 0x174E48, dark: 0x0F3B36)
    static let accentSoft = Color(light: 0xD9EFEC, dark: 0x1C3A36)

    // Lantern
    static let glow = Color(light: 0xFFD27A, dark: 0xFFC85A)
    static let glass = Color(hex: 0xFFE29A)
    static let flame = Color(hex: 0xF2913D)
    static let brass = Color(hex: 0xC9763C)
    static let outline = Color(hex: 0x4A2E1F)
    static let page = Color(hex: 0xF7EBD8)
}

extension Color {
    init(hex: UInt32) {
        self.init(uiColor: UIColor(hex: hex))
    }

    /// A colour with separate light and dark appearances.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xff) / 255,
            green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255,
            alpha: 1
        )
    }
}

/// The chunky, game-feel button: a solid face on a darker edge that presses
/// down when tapped, with a light haptic.
struct ChunkyButtonStyle: ButtonStyle {
    var fill: Color = Theme.buttonFill
    var edge: Color = Theme.accentEdge
    var foreground: Color = .white

    private static let depth: CGFloat = 5

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        return configuration.label
            .font(.system(.title3, design: .rounded, weight: .heavy))
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(fill, in: .rect(cornerRadius: 18))
            // Face and label sink onto the edge when pressed…
            .offset(y: pressed ? Self.depth : 0)
            // …which stays put underneath (offset doesn't move layout, so this sits at the resting spot).
            .background(RoundedRectangle(cornerRadius: 18).fill(edge).offset(y: Self.depth))
            .padding(.bottom, Self.depth)
            .animation(.spring(duration: 0.15), value: pressed)
            .sensoryFeedback(.impact(weight: .light), trigger: pressed) { _, isPressed in isPressed }
    }
}

extension ButtonStyle where Self == ChunkyButtonStyle {
    static var chunky: ChunkyButtonStyle { ChunkyButtonStyle() }
}
