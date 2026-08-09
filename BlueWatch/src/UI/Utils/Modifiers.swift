//
//  Modifiers.swift
//  BlueWatch
//
//  Created by Kabir Onkar on 8/9/26.
//

import SwiftUI

struct LiquidGlassModifier: ViewModifier {
    var cornerRadius: CGFloat
    
    func body(content: Content) -> some View {
        if #available(iOS 26.0,*) {
            content
                .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
                
        } else {
            content
                .background(in: .rect(cornerRadius: cornerRadius))
        }
    }
}

extension View {
    func liquidGlass(cornerRadius: CGFloat = 24) -> some View {
        self.modifier(LiquidGlassModifier(cornerRadius: cornerRadius))
    }
}

