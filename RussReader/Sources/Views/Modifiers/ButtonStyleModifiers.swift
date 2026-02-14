//
//  ButtonStyleModifiers.swift
//  RussReader
//
//  View modifiers for button styling and interactions
//

import SwiftUI

// MARK: - Header Button Styles

struct HeaderButtonStyle: ViewModifier {
    @State private var isHovered = false
    
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .labelStyle(.iconOnly)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
                .glassEffect(
                    isHovered ? .regular.interactive().tint(.primary.opacity(0.15)) : .regular.interactive(),
                    in: .circle
                )
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isHovered = hovering
                    }
                }
        } else {
            content
                .labelStyle(.iconOnly)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
    }
}

struct HeaderButtonHoverModifier: ViewModifier {
    @State private var isHovered = false
    
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .foregroundStyle(.primary)
                .glassEffect(
                    isHovered ? .regular.interactive().tint(.primary.opacity(0.15)) : .regular.interactive(),
                    in: .circle
                )
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isHovered = hovering
                    }
                }
        } else {
            content
        }
    }
}

// MARK: - View Extension for Button Styles

extension View {
    func headerButtonStyle() -> some View {
        modifier(HeaderButtonStyle())
    }
    
    func pointerOnHover() -> some View {
        self.onHover { hovering in
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}
