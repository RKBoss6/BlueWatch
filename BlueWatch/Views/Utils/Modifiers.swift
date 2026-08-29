//
//  Modifiers.swift
//  BlueWatch
//
//  Created by Kabir Onkar on 8/9/26.
//

import SwiftUI

struct LiquidGlassModifier: ViewModifier {
    @Environment(\.colorScheme) var colorScheme
    var cornerRadius: CGFloat
    var backgroundColor: Color
    func body(content: Content) -> some View {
        if #available(iOS 26.0,*) {
            content
                .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
                .overlay(backgroundColor.opacity(colorScheme == .dark ? 0.2 : 0.3), in: .rect(cornerRadius: cornerRadius))

                
        } else {
            content
                .background(in: .rect(cornerRadius: cornerRadius))
        }
    }
}

extension View {
    func liquidGlass(cornerRadius: CGFloat = 24, backgroundColor: Color = .clear) -> some View {
        self.modifier(LiquidGlassModifier(cornerRadius: cornerRadius, backgroundColor: backgroundColor))
    }
}

