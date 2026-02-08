//
//  ShiftTimeModel.swift
//  RFID Time Tracking
//

//

import Foundation

struct ShiftTime: Codable, Identifiable, Hashable {
    var id = UUID()
    var time: Date
}
