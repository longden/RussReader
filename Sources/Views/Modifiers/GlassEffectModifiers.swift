//
//  GlassEffectModifiers.swift
//  RSSReader
//
//  View modifiers for glass effect styling (macOS 26+)
//

import SwiftUI

// MARK: - Glass Effect Capsule

@available(macOS 26.0, *)
struct GlassCapsule<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .glassEffect(.regular, in: .capsule)
    }
}

// MARK: - Glass Effect Modifiers

struct CapsuleGlassModifier: ViewModifier {
    let isActive: Bool
    let isHovered: Bool
    
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(
                    isActive ? .regular.interactive().tint(.primary.opacity(0.15)) : .regular.interactive(),
                    in: .capsule
                )
        } else {
            content
                .background(isActive ? Color.primary.opacity(0.15) : (isHovered ? Color.primary.opacity(0.08) : Color.clear))
                .clipShape(Capsule())
        }
    }
}

struct BadgeGlassModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .glassEffect(.regular.tint(.blue.opacity(0.2)), in: .capsule)
        } else {
            content
        }
    }
}

@available(macOS 26.0, *)
struct RefreshButtonGlassModifier: ViewModifier {
    let isRefreshing: Bool
    let isHovered: Bool
    
    func body(content: Content) -> some View {
        content
            .glassEffect(
                isRefreshing || isHovered ? .regular.interactive().tint(.primary.opacity(0.12)) : .regular.interactive(),
                in: .circle
            )
    }
}
