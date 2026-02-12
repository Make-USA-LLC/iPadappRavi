//
//  TimePeriodModel.swift
//  RFID Time Tracking
//

//

import Foundation

// MARK: Lightweight codable types used to persist UI-managed lists (lunch windows, shift times)
struct TimePeriod: Codable, Identifiable, Hashable {
    var id = UUID()
    var start: Date
    var end: Date
}
