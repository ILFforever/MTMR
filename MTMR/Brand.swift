//
//  Brand.swift
//  Stripe
//
//  The app's name in one place, so renaming it is a one-line change here plus
//  APP_NAME/BUNDLE_ID in the Makefile.
//

import Foundation

enum Brand {
    static let name = "Stripe"

    /// Stripe is a fork of MTMR; configs found in MTMR's folder are imported on first launch.
    static let legacyName = "MTMR"
}
