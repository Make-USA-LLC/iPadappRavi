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
    
    // Worker Bank
    var workerBankedMinutes: [String: Double]?
    var isBonusEligible: Bool?
    var bonusIneligibleReason: String?
    
    // 🚨 WEB DASHBOARD FIELDS (Required so iPad doesn't delete them) 🚨
    var price: String?
    var quantity: String?
    var notes: String?
    var status: String?
    var requiresBlending: Bool?
    var blendingStatus: String?
    var techSheetUploaded: Bool?
    var componentsArrived: Bool?
    
    // 🚨 SCHEDULING COMMAND CENTER FIELDS 🚨
    var startDate: String?
    var workerCount: Int?
    var estimatedTotalHours: Double?
    var calculatedEndDate: String?
    var durationDays: Int?
    var shifts: Int?
    
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
    var value: String?
    
    private enum CodingKeys: String, CodingKey {
        case timestamp, type, value
    }
}
