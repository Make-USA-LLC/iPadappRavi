//
//  ProjectModel.swift
//  RFID Time Tracking
//

//

import Foundation
import FirebaseFirestore

//MARK: ProjectQueueItem
// --- NEW: Structures for Queue and Options ---
struct ProjectQueueItem: Codable, Identifiable, Equatable {
    @DocumentID var id: String?
    var company: String
    var project: String
    var category: String
    var size: String
    var seconds: Int // This is the REMAINING time
    var originalSeconds: Int? // <--- NEW: This holds the Total Budget
    var lineLeaderName: String?
    var createdAt: Date?
    
    // Logs...
    var scanHistory: [ScanEvent]?
    var projectEvents: [ProjectEvent]?
    
    static func == (lhs: ProjectQueueItem, rhs: ProjectQueueItem) -> Bool {
        return lhs.id == rhs.id
    }
}

//MARK: ProjectOptionsConfig
// Helper to decode the options arrays
struct ProjectOptionsConfig: Codable {
    var categories: [String]
    var sizes: [String]
}

//MARK: ProjectEvent
struct ProjectEvent: Codable, Identifiable {
    let id = UUID()
    let timestamp: Date
    let type: ProjectEventType
    
    private enum CodingKeys: String, CodingKey {
        case timestamp, type
    }
}
