//
//  TearDown.swift
//  Stripe
//
//  Items that run background work (timers, processes, audio listeners) stop it
//  in tearDown(), which the bar calls when it replaces them. Without this, each
//  reload (every edit in Settings) left the old items' work running forever,
//  since repeating timers and observers keep their items alive.
//

import Cocoa

protocol TearDownable: AnyObject {
    func tearDown()
}

func tearDownItems<S: Sequence>(_ items: S) {
    for case let item as TearDownable in items {
        item.tearDown()
    }
}
