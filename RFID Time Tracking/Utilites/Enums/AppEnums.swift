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
// PauseType distinguishes normal running, manual pauses, and two
// kinds of lunch pauses (manual 30-min and automatic window-driven).
enum PauseType: Codable {
    case running
    case manual
    case manualLunch // New: For 30-min hard-coded pause
    case autoLunch   // New: For pausing only during a window
    case qcCrew       // "Crew Oversight"
        case qcComponent  // "Component Issues"
        case technician
    
    // This case exists to help migrate older app versions
    case lunch
}

// --- NEW: Enums for View Feedback ---
// Lightweight return types for actions that the UI can react to.
enum ScanFeedback {
    case clockedIn(String)
    case clockedOut(String)
    case ignoredPaused
    case ignoredFinished
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
    
    // Color and icon helper accessors so Views can render consistently
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
