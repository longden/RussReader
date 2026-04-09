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
        .help(String(localized: "Refresh feeds"))
        .accessibilityLabel(String(localized: "Refresh feeds"))
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
                .background {
                    Circle()
                        .fill(Color(NSColor.controlBackgroundColor).opacity((isRefreshing || isHovered) ? 0.95 : 0.8))
                        .overlay {
                            Circle()
                                .strokeBorder(Color.primary.opacity((isRefreshing || isHovered) ? 0.18 : 0.1), lineWidth: 1)
                        }
                }
                .clipShape(Circle())
        }
    }
}
