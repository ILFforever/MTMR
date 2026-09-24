//
//  main.swift
//  MTMR
//
//  Explicit entry point so the app doesn't need a storyboard (and therefore
//  doesn't need Xcode's ibtool to build). MTMR is an LSUIElement agent, so the
//  storyboard's main menu was never visible anyway.
//

import Cocoa

// Asset-catalog images are shipped as loose files when building without
// actool, which drops the catalog's "template" rendering flag. Restore it.
for name in ["StatusImage", "brightnessDown", "brightnessUp", "dark-mode-off", "dark-mode-on",
             "dnd-off", "ill_down", "ill_up", "nightShiftOff"] {
    NSImage(named: name)?.isTemplate = true
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
