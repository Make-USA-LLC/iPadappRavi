import Foundation
import SwiftSMTP // Make sure you have this package added to your project
import SwiftUI // Needed for @AppStorage

// This struct is used by ContentView to pass login info
struct SmtpSettings {
    let host: String
    let username: String
    let password: String
    let recipient: String
}

// This private struct loads all the "Include..." toggles from UserDefaults
private struct EmailContentSettings {
    // --- NEW @AppStorage PROPERTY ---
    @AppStorage(AppStorageKeys.includeCompanyName) private var includeCompanyName = true
    @AppStorage(AppStorageKeys.includeProjectName) private var includeProjectName = true
    @AppStorage(AppStorageKeys.includeLineLeader) private var includeLineLeader = true
    @AppStorage(AppStorageKeys.includeTimeRemaining) private var includeTimeSummary = true
    @AppStorage(AppStorageKeys.includePauseCount) private var includePauseCount = true
    @AppStorage(AppStorageKeys.includeLunchCount) private var includeLunchCount = true
    @AppStorage(AppStorageKeys.includeScanCount) private var includeScanCount = true
    @AppStorage(AppStorageKeys.includeClockedInWorkers) private var includeClockedInWorkers = true
    @AppStorage(AppStorageKeys.includeTotalTimeWorked) private var includeTotalTimeWorked = false
    @AppStorage(AppStorageKeys.includeWorkerList) private var includeWorkerList = true
    @AppStorage(AppStorageKeys.includePauseLog) private var includePauseLog = true
    @AppStorage(AppStorageKeys.includeLunchLog) private var includeLunchLog = true
    @AppStorage(AppStorageKeys.includeScanHistory) private var includeScanHistory = true
    
    // --- NEW: @AppStorage Properties ---
    @AppStorage(AppStorageKeys.includeCategory) private var includeCategory = true
    @AppStorage(AppStorageKeys.includeProjectSize) private var includeProjectSize = true
    
    // This function builds the text for the email body
    func buildEmailBody(viewModel: WorkerViewModel) -> String {
        
        // Helper to format seconds into HH:MM:SS
        func formatTime(_ seconds: Int) -> String {
            let hours = seconds / 3600
            let minutes = (seconds % 3600) / 60
            let secs = seconds % 60
            // Ensure negative time (if timer overruns) is handled
            if seconds < 0 {
                let posSecs = abs(seconds)
                let posHours = posSecs / 3600
                let posMinutes = (posSecs % 3600) / 60
                let posSecsPart = posSecs % 60
                return String(format: "-%02d:%02d:%02d", posHours, posMinutes, posSecsPart)
            }
            return String(format: "%02d:%02d:%02d", hours, minutes, secs)
        }
        
        // Helper to format dates
        let dateFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d, yyyy 'at' h:mm:ss a"
            return formatter
        }()
        
        var body = "Project Finished Report\n"
        body += "Generated: \(dateFormatter.string(from: Date()))\n"
        body += "--------------------------\n\n"
        
        // Groups Company, Project, and Leader name at the top
        var addedHeaderInfo = false
        
        if includeCompanyName {
            body += "Company Name: \(viewModel.companyName.isEmpty ? "N/A" : viewModel.companyName)\n"
            addedHeaderInfo = true
        }
        
        if includeProjectName {
            body += "Project Name: \(viewModel.projectName.isEmpty ? "N/A" : viewModel.projectName)\n"
            addedHeaderInfo = true
        }
        
        if includeLineLeader {
            body += "Line Leader: \(viewModel.lineLeaderName.isEmpty ? "N/A" : viewModel.lineLeaderName)\n"
            addedHeaderInfo = true
        }
        
        if includeCategory {
            body += "Category: \(viewModel.category.isEmpty ? "N/A" : viewModel.category)\n"
            addedHeaderInfo = true
        }
        
        if includeProjectSize {
            body += "Project Size: \(viewModel.projectSize.isEmpty ? "N/A" : viewModel.projectSize)\n"
            addedHeaderInfo = true
        }
        
        if addedHeaderInfo {
            body += "\n"
        }
        
        if includeTimeSummary {
            let timeGiven = formatTime(viewModel.originalCountdownSeconds)
            let timeRemaining = formatTime(viewModel.countdownSeconds)
            let timeElapsed = formatTime(viewModel.originalCountdownSeconds - viewModel.countdownSeconds)
            
            body += "TIME SUMMARY\n"
            body += "Time Given: \(timeGiven)\n"
            body += "Time Remaining: \(timeRemaining)\n"
            body += "Time Elapsed: \(timeElapsed)\n\n"
        }
        
        body += "ACTIVITY TOTALS\n"
        if includePauseCount {
            body += "Total Pauses: \(viewModel.pauseCount)\n"
        }
        if includeLunchCount {
            body += "Total Lunches: \(viewModel.lunchCount)\n"
        }
        if includeScanCount {
            body += "Total Scans: \(viewModel.scanCount)\n"
        }
        let saveCount = viewModel.projectEvents.filter { $0.type == .save }.count
                body += "Total Saves: \(saveCount)\n"
        
        body += "\n"
        
        body += "WORKER SUMMARY\n"
        
        if includeClockedInWorkers {
            // --- CHANGE 1: Map to Name instead of ID ---
            let currentWorkers = viewModel.workers.values
                .filter { $0.clockInTime != nil }
                .map { viewModel.getWorkerName(id: $0.id) }
                .sorted()
            // -------------------------------------------
            
            body += "Workers Clocked-In (at finish): \(currentWorkers.count)\n"
            if !currentWorkers.isEmpty {
                body += currentWorkers.joined(separator: "\n") + "\n"
            } else {
                body += "None\n"
            }
            body += "\n"
        }
        
        if includeWorkerList {
            // --- CHANGE 2: Map keys to Names ---
            let allWorkers = viewModel.workers.keys.sorted().map { viewModel.getWorkerName(id: $0) }
            // -----------------------------------
            
            body += "All Workers Scanned (Count: \(allWorkers.count)):\n"
            if allWorkers.isEmpty {
                body += "None\n"
            } else {
                body += allWorkers.joined(separator: "\n")
            }
            body += "\n\n"
        }
        
        /*
         In the Email Manager the "Total Time Worked (All Workers):" should be removed.
         
        if includeTotalTimeWorked {
            let totalSecondsWorked = viewModel.workers.values.reduce(0) { $0 + ($1.totalMinutesWorked * 60) }
            let totalWorkTimeFormatted = formatTime(Int(totalSecondsWorked.rounded()))
            body += "Total Time Worked (All Workers): \(totalWorkTimeFormatted)\n\n"
        }
        */
        if includePauseLog {
            body += "--------------------------\n"
            body += "PAUSE LOG\n"
            let events = viewModel.projectEvents.filter { $0.type == .pause }
            if events.isEmpty {
                body += "No pause events logged.\n\n"
            } else {
                for event in events {
                    body += "\(dateFormatter.string(from: event.timestamp))\n"
                }
                body += "\n"
            }
        }
        
        if includeLunchLog {
            body += "--------------------------\n"
            body += "LUNCH LOG\n"
            let events = viewModel.projectEvents.filter { $0.type == .lunch }
            if events.isEmpty {
                body += "No lunch events logged.\n\n"
            } else {
                for event in events {
                    body += "\(dateFormatter.string(from: event.timestamp))\n"
                }
                body += "\n"
            }
        }
        
        if includePauseLog { // Or create a new toggle if you prefer
            body += "--------------------------\n"
            body += "SAVE LOG\n"
            
            let saves = viewModel.projectEvents.filter { $0.type == .save }
            if saves.isEmpty {
                body += "No save events logged.\n"
            } else {
                for event in saves {
                    let dateStr = dateFormatter.string(from: event.timestamp)
                    body += "[\(dateStr)]: Project Saved\n"
                }
            }
            body += "\n"
        }
        
        if includeScanHistory {
            body += "--------------------------\n"
            body += "FULL SCAN HISTORY\n"
            if viewModel.scanHistory.isEmpty {
                body += "No scans logged.\n"
            } else {
                for event in viewModel.scanHistory {
                    let time = dateFormatter.string(from: event.timestamp)
                    // --- CHANGE 3: Lookup Name for ID ---
                    let name = viewModel.getWorkerName(id: event.cardID)
                    body += "[\(time)]: \(name) - \(event.action.rawValue)\n"
                    // ------------------------------------
                }
            }
        }
        
        return body
    }
}



// MARK: - Email Manager
class EmailManager {
        
    // Main static function called by ContentView
    static func sendProjectFinishedEmail(
        viewModel: WorkerViewModel,
        settings: SmtpSettings,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        
        let contentSettings = EmailContentSettings()
        
        let subject: String
        let projectName = viewModel.projectName
        let defaults = UserDefaults.standard
        if !projectName.isEmpty && defaults.bool(forKey: AppStorageKeys.includeProjectName) {
             subject = "Project Finished: \(projectName)"
        } else {
            subject = "Project Finished Report"
        }
        
        let body = contentSettings.buildEmailBody(viewModel: viewModel)
        
        // ** ACTION REQUIRED: Change "sender@your-verified-domain.com" **
        // If using SendGrid's "apikey", the senderEmail must be a verified sender
        let senderEmail = (settings.username == "apikey") ? "sender@your-verified-domain.com" : settings.username
        let from = Mail.User(name: "Timer App", email: senderEmail)
        let to = [Mail.User(email: settings.recipient)]
        
        let mail = Mail(
            from: from,
            to: to,
            subject: subject,
            text: body
        )
        
        let smtp = SMTP(
            hostname: settings.host,
            email: settings.username,
            password: settings.password
        )
        
        // --- THIS IS THE FIX ---
        // We use the completion handler version of .send()
        // This function does NOT throw errors, it passes them to the handler.
        // It runs asynchronously, so no need to wrap in DispatchQueue.
        smtp.send(mail) { (error) in
            // This completion handler might not be on the main thread,
            // so we dispatch back to the main thread to update the UI.
            DispatchQueue.main.async {
                if let error = error {
                    // --- FAILURE PATH ---
                    // An error occurred (no Wi-Fi, bad credentials, etc.)
                    print("SwiftSMTP Error: \(error)")
                    completion(.failure(error))
                } else {
                    // --- SUCCESS PATH ---
                    // Error is nil, so the send was successful
                    print("Email sent successfully")
                    completion(.success(()))
                }
            }
        }
        // --- END FIX ---
    }
}
