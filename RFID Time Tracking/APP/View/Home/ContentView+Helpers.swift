//
//  ContentView+Helpers.swift
//  RFID Time Tracking
//
//

import Foundation
import SwiftUI

//MARK: HELPERS
extension ContentView {
    // Show a transient banner message at the top of the screen. Existing
    // timers are invalidated so the most recent banner controls visibility.
     func showBanner(message: String, type: BannerType) {
        bannerTimer?.invalidate()
        
        withAnimation(.spring()) {
            currentBanner = BannerAlert(message: message, type: type)
        }
        
        bannerTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
            withAnimation(.spring()) {
                currentBanner = nil
            }
        }
    }
    
    // Send an email with the project summary (via EmailManager) and then
    // finish/reset the project. If SMTP is disabled, show an alert to the user.
     func sendEmailAndFinishProject() {
        if !viewModel.isProjectFinished {
            viewModel.finishProject()
        }
        
        guard enableSmtpEmail else {
            emailAlertTitle = "Email Disabled"
            emailAlertMessage = "Email is disabled in settings. The project is finished and the timer is paused."
            showingEmailAlert = true
            return
        }
        
        isSendingEmail = true
        
        let settings = SmtpSettings(
            host: smtpHost,
            username: smtpUsername,
            password: smtpPassword,
            recipient: smtpRecipient
        )
        
        EmailManager.sendProjectFinishedEmail(viewModel: viewModel, settings: settings) { result in
            isSendingEmail = false
            
            switch result {
            case .success:
                viewModel.finishProject()
                emailAlertTitle = "Success"
                emailAlertMessage = "The project summary email has been sent. The project will now reset."
                showingEmailAlert = true
                performReset()
                
            case .failure(let error):
                emailAlertTitle = "Email Error"
                emailAlertMessage = "Email failed to send. Please check network/settings and try again. The timer is paused.\n\nError: \(error.localizedDescription)"
                showingEmailAlert = true
            }
        }
    }
    
    // Reset UI state and the viewModel when a project completes or the
    // operator requested a reset via password-protected flow.
     func performReset() {
        viewModel.resetData()
        isReset = true
        companyNameInput = ""
        projectNameInput = ""
        lineLeaderNameInput = ""
    }
    
    // Handles numeric keypad presses for hours/minutes/seconds input.
    // Hours allow multiple digits; minutes/seconds are capped at 2 digits.
     func handleNumberPress(_ label: String) {
        var binding: Binding<String>
        
        switch selectedField {
        case .hours:
            binding = $hoursInput
        case .minutes:
            binding = $minutesInput
        case .seconds:
            binding = $secondsInput
        case .none:
            return
        }
        
        switch label {
        case "⌫":
            if !binding.wrappedValue.isEmpty {
                binding.wrappedValue.removeLast()
            }
        default:
            if selectedField == .hours {
                binding.wrappedValue.append(label)
            }
            else {
                if binding.wrappedValue.count < 2 {
                    binding.wrappedValue.append(label)
                }
            }
        }
    }
    
    // Blink behavior for the cursor shown in the time input boxes
     func startCursorBlink() {
        cursorTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.1)) { showCursor.toggle() }
        }
    }
    
     func stopCursorBlink() {
        cursorTimer?.invalidate()
        cursorTimer = nil
    }
    
    // Password popup builder used in multiple places. It exposes a simple
    // keypad and returns to the caller via the onSuccess closure when OK.
     func passwordSheetPopup(
        showError: Binding<Bool>,
        isPresented: Binding<Bool>,
        title: String,
        correctPassword: String,
        onSuccess: @escaping () -> Void
    ) -> some View {
        
        return GeometryReader { sheetGeometry in
            
            let g = sheetGeometry.size
            let minDim = min(g.width, g.height)
            
            let keySize = min(minDim * 0.2, 90.0)
            let keyFontSize = keySize * 0.4
            
            let popupWidth = min(g.width * 0.8, 380.0)
            let titleFontSize = min(g.width * 0.05, 22)
            let fieldFontSize = min(g.width * 0.05, 20)
            
            ZStack {
                Color.black.opacity(0.001)
                    .edgesIgnoringSafeArea(.all)
                
                VStack(spacing: 20) {
                    HStack {
                        Spacer()
                        Button("Cancel") {
                            passwordField = ""
                            showError.wrappedValue = false
                            isPresented.wrappedValue = false
                        }
                        .padding(.horizontal)
                        .padding(.top)
                    }
                    
                    Text(title)
                        .font(.system(size: titleFontSize, weight: .semibold))
                        .padding(.bottom, 10)
                    
                    SecureField("Password", text: $passwordField)
                        .font(.system(size: fieldFontSize))
                        .padding(10)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(width: popupWidth * 0.7)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    
                    VStack {
                        if showError.wrappedValue {
                            Text("Incorrect Password")
                                .font(.callout)
                                .foregroundColor(.red)
                        } else {
                            Text(" ")
                                .font(.callout)
                        }
                    }
                    .frame(height: 20)
                    
                    VStack(spacing: 12) {
                        ForEach([[1,2,3],[4,5,6],[7,8,9]], id: \.self) { row in
                            HStack(spacing: 12) {
                                ForEach(row, id: \.self) { num in
                                    keypadButton("\(num)", size: keySize, fontSize: keyFontSize) {
                                        showError.wrappedValue = false
                                        passwordField.append("\(num)")
                                    }
                                }
                            }
                        }
                        HStack(spacing: 12) {
                            keypadButton("⌫", color: .red, size: keySize, fontSize: keyFontSize) {
                                showError.wrappedValue = false
                                if !passwordField.isEmpty { passwordField.removeLast() }
                            }
                            keypadButton("0", size: keySize, fontSize: keyFontSize) {
                                showError.wrappedValue = false
                                passwordField.append("0")
                            }
                            keypadButton("OK", color: .blue, size: keySize, fontSize: keyFontSize) {
                                if passwordField == correctPassword {
                                    onSuccess()
                                    passwordField = ""
                                    showError.wrappedValue = false
                                    isPresented.wrappedValue = false
                                } else {
                                    showError.wrappedValue = true
                                }
                            }
                        }
                    }
                }
                .frame(width: popupWidth)
                .padding(.vertical, 20)
                .background(Color(UIColor.systemBackground))
                .cornerRadius(16)
                .shadow(radius: 10)
                .position(x: g.width / 2, y: g.height / 2)
                
            }
            .background(Color.black.opacity(0.4).edgesIgnoringSafeArea(.all))
        }
        .interactiveDismissDisabled(true)
    }
    
    
    
    // Handle submission from the RFID text field. Shows a banner based
    // on the returned ScanFeedback and clears the input field.
    // In ContentView+Helpers.swift

        func handleRFIDSubmit() {
            // Capture input and clear field immediately so UI feels responsive
            let scannedId = rfidInput
            rfidInput = ""
            
            // Call the new Async function
            viewModel.handleRFIDScan(for: scannedId) { feedback in
                
                // Ensure UI updates happen on the Main Thread
                DispatchQueue.main.async {
                    guard let feedback = feedback else { return }
                    
                    switch feedback {
                    case .clockedIn(let id):
                        self.showBanner(message: "Worker \(id) Clocked In", type: .info)
                        
                    case .clockedOut(let id):
                        self.showBanner(message: "Worker \(id) Clocked Out", type: .info)
                        
                    case .ignoredPaused:
                        self.showBanner(message: "Scan Ignored: Timer is Paused", type: .warning)
                        
                    case .ignoredFinished:
                        self.showBanner(message: "Scan Ignored: Project is Finished", type: .warning)
                        
                    case .alreadyActive(let fleetId):
                        // NEW ALERT
                        self.showBanner(message: "BLOCKED: Worker active on \(fleetId)", type: .error)
                        AudioPlayerManager.shared.playSound(named: "Buzzer") // Optional: Play error sound
                    }
                }
            }
        }}
