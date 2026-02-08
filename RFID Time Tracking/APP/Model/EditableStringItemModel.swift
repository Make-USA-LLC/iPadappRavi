//
//  EditableStringItemModel.swift
//  RFID Time Tracking
//

//

import Foundation

// MARK: Used for categories and project sizes; value is edited via settings UI
struct EditableStringItem: Codable, Identifiable, Hashable {
    var id = UUID()
    var value: String
}
