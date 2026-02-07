//
//  ContextMenuModifiers.swift
//  RSSReader
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
                Button(item.isRead ? String(localized: "Mark as Unread", bundle: .module) : String(localized: "Mark as Read", bundle: .module)) {
                    store.toggleRead(item)
                }
                Button(item.isStarred ? String(localized: "Unstar", bundle: .module) : String(localized: "Star", bundle: .module)) {
                    store.toggleStarred(item)
                }
                Divider()
                Button(String(localized: "Mark all above as read", bundle: .module)) {
                    store.markItemsAboveAsRead(item)
                }
                .disabled(store.filteredItems.first?.id == item.id)
                Button(String(localized: "Mark all below as read", bundle: .module)) {
                    store.markItemsBelowAsRead(item)
                }
                .disabled(store.filteredItems.last?.id == item.id)
                Divider()
                Button(String(localized: "Share", bundle: .module)) {
                    store.shareItem(item)
                }
                Button(String(localized: "Copy Link", bundle: .module)) {
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
