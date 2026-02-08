//
//  AppStorageKeys.swift
//  RFID Time Tracking
//

//

import Foundation

// MARK:  Centralized keys for UserDefaults/AppStorage so strings are not scattered
struct AppStorageKeys {
    // --- Passwords ---
    static let pausePassword = "pausePassword"
    static let resetPassword = "resetPassword"
    
    // --- Email Toggles ---
    static let enableSmtpEmail = "enableSmtpEmail"
    static let includeScanHistory = "includeScanHistory"
    static let includeWorkerList = "includeWorkerList"
    static let includePauseLog = "includePauseLog"
    static let includeLunchLog = "includeLunchLog"
    static let includeLineLeader = "includeLineLeader"
    
    static let smtpRecipient = "smtpRecipient"
    
    static let smtpHost = "smtpHost"
    static let smtpUsername = "smtpUsername"
    static let smtpPassword = "smtpPassword"
    static let fleetIpadID = "fleetIpadID"
    
    // --- Email Content Toggles ---
    static let includeTimeRemaining = "includeTimeRemaining"
    static let includeClockedInWorkers = "includeClockedInWorkers"
    static let includeTotalTimeWorked = "includeTotalTimeWorked"
    
    static let includeProjectName = "includeProjectName"
    static let includeCompanyName = "includeCompanyName"
    static let includePauseCount = "includePauseCount"
    static let includeLunchCount = "includeLunchCount"
    static let includeScanCount = "includeScanCount"
    
    // --- NEW KEYS ---
    static let includeCategory = "includeCategory"
    static let includeProjectSize = "includeProjectSize"
}
