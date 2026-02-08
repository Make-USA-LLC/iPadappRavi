//
//  ScanEventModel.swift
//  RFID Time Tracking
//

//

import Foundation

struct ScanEvent: Codable, Identifiable {
    let id = UUID()
    let cardID: String
    let timestamp: Date
    let action: ScanAction
    
    private enum CodingKeys: String, CodingKey {
        case cardID, timestamp, action
    }
}
