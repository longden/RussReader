//
//  FilterTabButton.swift
//  RSSReader
//
//  Filter tab button component for feed filtering
//

import SwiftUI

@available(macOS 26.0, *)
struct FilterTabButton: View {
    let filter: FeedFilter
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            Label {
                Text(filter.localizedName)
            } icon: {
                Image(systemName: filter.icon)
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(isSelected ? .primary : .secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contentShape(Capsule())
        .modifier(CapsuleGlassModifier(isActive: isSelected, isHovered: isHovered))
        .pointerOnHover()
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}
