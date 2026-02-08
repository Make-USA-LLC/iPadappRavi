//
//  AudioPlayerManager.swift
//  RFID Time Tracking
//

//

import Foundation
import AVFoundation

// MARK: - MODIFIED: AudioPlayerManager
// Small singleton wrapper around AVAudioPlayer. The original code
// created/played audio inline; this centralizes audio responsibilities
// (playing buzzer/cashier sounds) and configures the AVAudioSession.
class AudioPlayerManager {
    // 1. Make it a singleton (a single, shared instance)
    static let shared = AudioPlayerManager()
    
    // The active audio player instance. Keeping it as an instance
    // property prevents deallocation while a sound is playing.
    var player: AVAudioPlayer?
    
    // 2. Configure the app's audio session on init
    private init() {
        configureAudioSession()
    }
    
    // Sets AVAudioSession category to playback so sounds play even
    // when the device mute switch is on (typical for kiosk-like apps).
    func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to configure audio session: \(error)")
        }
    }
    
    // Play a short bundled mp3 located in the 'audio' subdirectory.
    // The method logs helpful messages when the file isn't found.
    func playSound(named soundName: String) {
        guard let url = Bundle.main.url(forResource: soundName, withExtension: "mp3", subdirectory: "audio") else {
            // This is the most likely error: File is not in the 'audio' folder.
            print("Sound file not found in 'audio' folder: \(soundName).mp3")
            return
        }
        
        // Added for debugging
        print("Found audio file at: \(url.path)")
        
        do {
            // The player is now held in memory by the singleton,
            // so it won't be deallocated mid-play.
            player = try AVAudioPlayer(contentsOf: url)
            player?.play()
        } catch {
            print("Error playing sound: \(error)")
        }
    }
}
