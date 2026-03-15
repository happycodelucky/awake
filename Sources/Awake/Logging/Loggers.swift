//
//  Loggers.swift
//  Awake
//
//  Created by Paul Bates on 3/11/26.
//

import OSLog

extension Logger {
    /// Using your bundle identifier is a great way to ensure a unique identifier.
    private static let subsystem = Bundle.main.bundleIdentifier!

    /// All app related logging
    static let app = Logger(subsystem: subsystem, category: "app")

    /// Logging related to external api usage
    static let apis = Logger(subsystem: subsystem, category: "apis")
}
