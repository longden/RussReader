//
//  FooterGlassButton.swift
//  RussReader
//
//  Footer button component with glass effect (macOS 26+)
//

import SwiftUI

@available(macOS 26.0, *)
struct FooterGlassButton: View {
    let title: String
    let icon: String
    let action: (() -> Void)?
    @State private var isHovered = false
    
    var body: some View {
        Button {
            action?()
        } label: {
            Label(title, systemImage: icon)
                .labelStyle(.iconOnly)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contentShape(Capsule())
        .background(isHovered ? Color.primary.opacity(0.12) : Color.clear)
        .clipShape(Capsule())
        .pointerOnHover()
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .help(title)
    }
}
