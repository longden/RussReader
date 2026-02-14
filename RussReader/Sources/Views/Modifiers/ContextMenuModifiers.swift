//
//  ContextMenuModifiers.swift
//  RussReader
//
//  View modifiers for context menus and utility modifiers
//

import SwiftUI
import AppKit

// MARK: - Feed Item Context Menu

struct FeedItemContextMenu: ViewModifier {
    let item: FeedItem
    let store: FeedStore
    
    func body(content: Content) -> some View {
        content
            .contextMenu {
                Button(item.isRead ? String(localized: "Mark as Unread") : String(localized: "Mark as Read")) {
                    store.toggleRead(item)
                }
                Button(item.isStarred ? String(localized: "Unstar") : String(localized: "Star")) {
                    store.toggleStarred(item)
                }
                Divider()
                Button(String(localized: "Mark all above as read")) {
                    store.markItemsAboveAsRead(item)
                }
                .disabled(store.filteredItems.first?.id == item.id)
                Button(String(localized: "Mark all below as read")) {
                    store.markItemsBelowAsRead(item)
                }
                .disabled(store.filteredItems.last?.id == item.id)
                Divider()
                Button(String(localized: "Share")) {
                    store.shareItem(item)
                }
                Button(String(localized: "Copy Link")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(item.link, forType: .string)
                }
            }
    }
}

// MARK: - Section Divider

struct SectionDivider: ViewModifier {
    var alignment: Alignment = .bottom
    
    func body(content: Content) -> some View {
        content
            .overlay(
                Rectangle()
                    .frame(height: 1)
                    .foregroundStyle(Color.primary.opacity(0.1)),
                alignment: alignment
            )
    }
}

// MARK: - View Extension

extension View {
    func feedItemContextMenu(item: FeedItem, store: FeedStore) -> some View {
        modifier(FeedItemContextMenu(item: item, store: store))
    }
    
    func sectionDivider(alignment: Alignment = .bottom) -> some View {
        modifier(SectionDivider(alignment: alignment))
    }
}
