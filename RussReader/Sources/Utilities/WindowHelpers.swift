//
//  WindowHelpers.swift
//  RussReader
//
//  Window management helper functions
//

import SwiftUI
import AppKit

/// Opens the preferences window, bringing it to front if already open
func openPreferencesWindow(openWindow: OpenWindowAction) {
    // LSUIElement apps must switch to .regular to receive keyboard input and appear in front
    NSApp.setActivationPolicy(.regular)
    
    // First, try to bring existing window to front
    if let existingWindow = NSApp.windows.first(where: { $0.identifier?.rawValue == "preferences" }) {
        existingWindow.level = .floating
        existingWindow.makeKeyAndOrderFront(nil)
        existingWindow.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    } else {
        // If window doesn't exist, open it
        openWindow(id: "preferences")
        DispatchQueue.main.async {
            if let newWindow = NSApp.windows.first(where: { $0.identifier?.rawValue == "preferences" || $0.title == "Preferences" }) {
                newWindow.identifier = NSUserInterfaceItemIdentifier("preferences")
                newWindow.level = .floating
                newWindow.makeKeyAndOrderFront(nil)
                newWindow.orderFrontRegardless()
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
}

/// Opens the add feed window, bringing it to front if already open
func openAddFeedWindow(openWindow: OpenWindowAction) {
    if let existingWindow = NSApp.windows.first(where: { $0.identifier?.rawValue == "addFeed" }) {
        existingWindow.makeKeyAndOrderFront(nil)
        existingWindow.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        return
    }
    
    openWindow(id: "addFeed")
    
    DispatchQueue.main.async {
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "addFeed" || $0.title == "Add Feed" }) {
            window.identifier = NSUserInterfaceItemIdentifier("addFeed")
            window.level = .floating
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
