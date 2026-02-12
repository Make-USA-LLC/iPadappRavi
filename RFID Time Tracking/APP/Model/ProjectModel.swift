//
//  ProjectModel.swift
//  RFID Time Tracking
//

import Foundation
import FirebaseFirestore

//MARK: ProjectQueueItem
struct ProjectQueueItem: Codable, Identifiable, Equatable {
    @DocumentID var id: String?
    var company: String
    var project: String
    var category: String
    var size: String
    var seconds: Int
    var originalSeconds: Int?
    var lineLeaderName: String?
    var createdAt: Date?
    
    // Logs
    var scanHistory: [ScanEvent]?
    var projectEvents: [ProjectEvent]?
    
    var isBonusEligible: Bool?
    var bonusIneligibleReason: String?
    
    static func == (lhs: ProjectQueueItem, rhs: ProjectQueueItem) -> Bool {
        return lhs.id == rhs.id
    }
}

//MARK: ProjectOptionsConfig
struct ProjectOptionsConfig: Codable {
    var categories: [String]
    var sizes: [String]
}

//MARK: ProjectEvent
struct ProjectEvent: Codable, Identifiable {
    let id = UUID()
    let timestamp: Date
    let type: ProjectEventType
    // --- FIX: Add this property ---
    var value: String?
    
    private enum CodingKeys: String, CodingKey {
        // --- FIX: You MUST include 'value' here ---
        case timestamp, type, value
    }
}
