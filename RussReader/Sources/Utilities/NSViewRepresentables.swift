//
//  NSViewRepresentables.swift
//  RussReader
//
//  AppKit integration via NSViewRepresentable wrappers
//

import SwiftUI
import AppKit

// MARK: - Appearance Applier

struct AppearanceApplier: NSViewRepresentable {
    let appearanceMode: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            self.applyAppearance()
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            self.applyAppearance()
        }
    }

    private func applyAppearance() {
        let appearance: NSAppearance? = switch appearanceMode {
        case "dark": NSAppearance(named: .darkAqua)
        case "light": NSAppearance(named: .aqua)
        default: nil
        }
        NSApp.appearance = appearance
    }
}
