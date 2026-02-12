//
//  RFID_Time_TrackingApp.swift
//  RFID Time Tracking
//
//  Created by Daniel Sarasohn on 10/8/25.
//

import SwiftUI
import FirebaseCore
import FirebaseAuth // <--- ADD THIS

@main
struct RFID_Time_TrackingApp: App {
    
    // Register the adapter to handle setup
    init() {
        FirebaseApp.configure()
        
        // --- NEW: AUTONOMOUS LOGIN ---
        // This signs the iPad in silently in the background.
        // No user interaction required.
        Auth.auth().signInAnonymously { authResult, error in
            if let error = error {
                print("CRITICAL ERROR: Fleet Login Failed - \(error.localizedDescription)")
            } else {
                print("Fleet Device Authenticated. UID: \(authResult?.user.uid ?? "Unknown")")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
