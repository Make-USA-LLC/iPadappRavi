//
//  EmailSettingsView.swift
//  RFID Time Tracking
//

//

import SwiftUI

// --- RENAMED: from SettingsView to EmailSettingsView ---
struct EmailSettingsView: View {
    @AppStorage(AppStorageKeys.enableSmtpEmail) private var enableSmtpEmail = false
    @AppStorage(AppStorageKeys.includeScanHistory) private var includeScanHistory = true
    @AppStorage(AppStorageKeys.includeWorkerList) private var includeWorkerList = true
    @AppStorage(AppStorageKeys.includePauseLog) private var includePauseLog = true
    @AppStorage(AppStorageKeys.includeLunchLog) private var includeLunchLog = true
    @AppStorage(AppStorageKeys.includeLineLeader) private var includeLineLeader = true
    
    @AppStorage(AppStorageKeys.smtpRecipient) private var smtpRecipient = "productionreports@makeit.buzz"
    @AppStorage(AppStorageKeys.smtpHost) private var smtpHost = "smtp.office365.com"
    @AppStorage(AppStorageKeys.smtpUsername) private var smtpUsername = "alerts@makeit.buzz"
    @AppStorage(AppStorageKeys.smtpPassword) private var smtpPassword = ""
    
    @AppStorage(AppStorageKeys.includeTimeRemaining) private var includeTimeRemaining = true
    @AppStorage(AppStorageKeys.includeClockedInWorkers) private var includeClockedInWorkers = true
    @AppStorage(AppStorageKeys.includeTotalTimeWorked) private var includeTotalTimeWorked = false
    @AppStorage(AppStorageKeys.includeCompanyName) private var includeCompanyName = true
    @AppStorage(AppStorageKeys.includeProjectName) private var includeProjectName = true
    @AppStorage(AppStorageKeys.includePauseCount) private var includePauseCount = true
    @AppStorage(AppStorageKeys.includeLunchCount) private var includeLunchCount = true
    @AppStorage(AppStorageKeys.includeScanCount) private var includeScanCount = true
    
    @AppStorage(AppStorageKeys.includeCategory) private var includeCategory = true
    @AppStorage(AppStorageKeys.includeProjectSize) private var includeProjectSize = true
    
    var body: some View {
        Form {
            Section(header: Text("Email Notifications")) {
                Toggle("Enable Automatic Email", isOn: $enableSmtpEmail)
                    .tint(.blue)
                Text("If disabled, no email will be sent when 'Project Finished' is tapped.")
                    .font(.caption)
            }
            
            Section(header: Text("Email Recipient")) {
                TextField("Recipient Email", text: $smtpRecipient)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
            }
            
            Section(header: Text("Automatic Email (SMTP) Credentials")) {
                TextField("SMTP Host (e.g., smtp.sendgrid.net)", text: $smtpHost)
                    .autocapitalization(.none)
                TextField("SMTP Username (e.g., 'apikey')", text: $smtpUsername)
                    .autocapitalization(.none)
                SecureField("SMTP Password (API Key)", text: $smtpPassword)
                
                Text("WARNING: These settings are for automatic background sending. Using a personal Gmail/Outlook password here is insecure and unreliable. Use a dedicated email service (like SendGrid) and an API key.")
                    .font(.caption)
                    .foregroundColor(.red)
            }
            
            Section(header: Text("Email Content")) {
                Text("Select which items to include in the 'Project Finished' email summary.")
                    .font(.caption)
                
                Toggle("Include Company Name", isOn: $includeCompanyName)
                Toggle("Include Project Name", isOn: $includeProjectName)
                Toggle("Include Line Leader Name", isOn: $includeLineLeader)
                
                Toggle("Include Category", isOn: $includeCategory)
                Toggle("Include Project Size", isOn: $includeProjectSize)
                
                Toggle("Include Time Summary (Given, Remaining, Elapsed)", isOn: $includeTimeRemaining)
                Toggle("Include Pause Count (Total)", isOn: $includePauseCount)
                Toggle("Include Lunch Count (Total)", isOn: $includeLunchCount)
                Toggle("Include Scan Count (Total)", isOn: $includeScanCount)
                
                Toggle("Include Pause Log (Timestamps)", isOn: $includePauseLog)
                Toggle("Include Lunch Log (Timestamps)", isOn: $includeLunchLog)
                Toggle("Include Scan History Log (Timestamps)", isOn: $includeScanHistory)
                Toggle("Include List of All Scanned Workers", isOn: $includeWorkerList)
                
                Toggle("Include Clocked-In Workers (at Finish)", isOn: $includeClockedInWorkers)
//                Toggle("Include Total Time Worked (All Workers)", isOn: $includeTotalTimeWorked)
            }
        }
        .navigationTitle("Email Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}
