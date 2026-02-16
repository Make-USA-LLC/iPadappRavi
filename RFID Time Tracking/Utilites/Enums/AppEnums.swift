//
//  AppEnums.swift
//  RFID Time Tracking
//
//

import Foundation
import SwiftUI

//MARK: Represents the action taken when a card is scanned
enum ScanAction: String, Codable {
    case clockIn = "Clocked In"
    case clockOut = "Clocked Out"
}

// MARK: ProjectEventType
enum ProjectEventType: String, Codable {
    case pause = "Pause"
    case lunch = "Lunch"
    case save = "Saved"
    case qcCrew = "QC (Crew)"
    case qcComponent = "QC (Component)"
    case technician = "Technician"
}


// --- MODIFIED: Enum to track pause reason ---
enum PauseType: Codable {
    case running
    case manual
    case manualLunch
    case autoLunch
    case qcCrew
    case qcComponent
    case technician
    case lunch // Legacy
}

// --- NEW: Enums for View Feedback ---
enum ScanFeedback {
    case clockedIn(String)
    case clockedOut(String)
    case ignoredPaused
    case ignoredFinished
    case alreadyActive(String)
    case invalidScan(String) // <--- ADDED THIS CASE
}

enum LunchFeedback {
    case success
    case ignoredPaused
    case ignoredNoWorkers
}

//MARK: Alert Banner Enum
enum BannerType {
    case info
    case warning
    case error
    
    var color: Color {
        switch self {
        case .info: return Color.blue.opacity(0.9)
        case .warning: return Color.orange.opacity(0.9)
        case .error: return Color.red.opacity(0.9)
        }
    }
    
    var icon: String {
        switch self {
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }
}

enum TimeField { case hours, minutes, seconds }
