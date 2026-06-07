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
            self.applyAppearance(to: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            self.applyAppearance(to: nsView)
        }
    }

    private func applyAppearance(to view: NSView) {
        let appearance: NSAppearance? = switch appearanceMode {
        case "dark": NSAppearance(named: .darkAqua)
        case "light": NSAppearance(named: .aqua)
        default: nil
        }
        NSApp.appearance = appearance
        view.window?.appearance = appearance
    }
}
