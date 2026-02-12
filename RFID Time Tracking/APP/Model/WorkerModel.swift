//
//  WorkerModel.swift
//  RFID Time Tracking
//

//

import Foundation

// MARK: - Worker Model
// Basic in-memory models for workers, scan events, and project events.
// These are Codable so the viewModel can persist them to UserDefaults.
struct Worker: Codable {
    let id: String
    var clockInTime: Date?
    var totalMinutesWorked: TimeInterval // Note: This is stored in MINUTES
}

