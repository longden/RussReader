//
//  RefreshButton.swift
//  RussReader
//
//  Refresh button component with rotation animation
//

import SwiftUI

struct RefreshButton: View {
    let isRefreshing: Bool
    let action: () -> Void
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            // TimelineView properly stops when paused, unlike repeatForever animations
            TimelineView(.animation(paused: !isRefreshing)) { context in
                Image(systemName: "arrow.clockwise")
                    .rotationEffect(.degrees(isRefreshing ? context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1) * 360 : 0))
            }
            .font(.system(size: 14, weight: .medium))
            .frame(width: 30, height: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .modifier(RefreshButtonModifier(isRefreshing: isRefreshing, isHovered: isHovered))
        .pointerOnHover()
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .help(String(localized: "Refresh feeds", bundle: .module))
        .accessibilityLabel(String(localized: "Refresh feeds", bundle: .module))
    }
}

// Internal modifier that handles availability check
private struct RefreshButtonModifier: ViewModifier {
    let isRefreshing: Bool
    let isHovered: Bool
    
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.modifier(RefreshButtonGlassModifier(isRefreshing: isRefreshing, isHovered: isHovered))
        } else {
            content
                .background(isHovered ? Color.primary.opacity(0.12) : Color.clear)
                .clipShape(Circle())
        }
    }
}
