import SwiftUI
import Combine
import AVFoundation
import FirebaseFirestore

let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"

struct ContentView: View {
    
    //MARK: Properties
    @ObservedObject var viewModel = WorkerViewModel()
    @State var showPasswordPrompt = false
    @FocusState var isQueueLeaderFieldFocused: Bool
    
    // Inputs
    @State var hoursInput = ""
    @State var minutesInput = ""
    @State var secondsInput = ""
    
    @State var companyNameInput: String = ""
    @State var projectNameInput: String = ""
    @State var lineLeaderNameInput: String = ""
    
    // Passwords/Modals
    @State var passwordField = ""
    @State var showingPasswordSheet = false
    @State var showingResetPasswordSheet = false
    @State var showPasswordError = false
    
    // RFID
    @State var rfidInput = ""
    @FocusState var isRFIDFieldFocused: Bool
    
    // Keyboards
    @State var showingCompanyKeyboard = false
    @State var showingProjectKeyboard = false
    @State var showingLineLeaderKeyboard = false
    @State var showingTimerInputSheet = false
    
    @State var selectedField: TimeField? = .hours
    @State var showCursor = true
    @State var cursorTimer: Timer?
    
    @State var isReset = true
    @Environment(\.scenePhase) var scenePhase
    
    // Settings
    @State var showingSettingsPasswordSheet = false
    @State var showingActualSettings = false
    
    // Email
    @State var isSendingEmail = false
    @State var showingEmailAlert = false
    @State var emailAlertTitle = ""
    @State var emailAlertMessage = ""
    
    // Settings Keyboards
    @State var showingSettingsKeyboard = false
    @State var settingsKeyboardBinding: Binding<String>?
    @State var showingSettingsNumericKeyboard = false
    @State var settingsNumericKeyboardBinding: Binding<String>?
    
    // Banner
    @State var currentBanner: BannerAlert? = nil
    @State var bannerTimer: Timer? = nil
    
    // Queue
    @State var showingQueueLeaderSheet = false
    @State var selectedQueueItem: ProjectQueueItem? = nil
    @State var queueLineLeaderName = ""
    @State var showingQueueLeaderKeyboard = false
    @FocusState var isInputFocused: Bool
    
    // Procedures & Sheets
    @State var showingWhosInSheet = false
    @State var showingFinishConfirmation = false
    @State var showingProceduresSheet = false
    @State var showingQCUnlockAlert = false
    @State var qcUnlockCode = ""
    
    // AppStorage
    @AppStorage(AppStorageKeys.smtpRecipient)  var smtpRecipient = "productionreports@makeit.buzz"
    @AppStorage(AppStorageKeys.smtpHost)  var smtpHost = "smtp.office365.com"
    @AppStorage(AppStorageKeys.smtpUsername)  var smtpUsername = "alerts@makeit.buzz"
    @AppStorage(AppStorageKeys.smtpPassword)  var smtpPassword = ""
    @AppStorage(AppStorageKeys.enableSmtpEmail)  var enableSmtpEmail = false
    
    @AppStorage(AppStorageKeys.pausePassword)  var pausePassword = "340340"
    @AppStorage(AppStorageKeys.resetPassword)  var resetPassword = "465465"
    
    //QC Unlock
    @State var showingQCUnlockSheet = false
    
    init() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundColor = .clear
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
    }
    
    //MARK: COMPUTED PROPERTIES
     var isProjectInfoInvalid: Bool {
        return companyNameInput.isEmpty ||
        projectNameInput.isEmpty ||
        lineLeaderNameInput.isEmpty ||
        viewModel.category.isEmpty ||
        viewModel.projectSize.isEmpty
    }
    
     var isStartTimeInvalid: Bool {
        let h = Int(hoursInput) ?? 0
        let m = Int(minutesInput) ?? 0
        let s = Int(secondsInput) ?? 0
        return (h + m + s) == 0
    }
    
     var shouldShowTimerScreen: Bool {
        return viewModel.isCountingDown || viewModel.isProjectFinished
    }
    
     var currentYear: String {
        let year = Calendar.current.component(.year, from: Date())
        return String(year)
    }
    
    // MARK: - BODY
    var body: some View {
        ZStack {
            // 1. MAIN UI LAYER
            mainInterfaceLayer
            
            // 2. OVERLAY LAYER (Keyboards, Banners)
            overlayLayer
        }
        // --- LOGIC TRIGGERS ---
        .onChange(of: viewModel.triggerQueueItem) { newItem in
            handleQueueItemChange(newItem)
        }
        .sheet(isPresented: $showingSettingsPasswordSheet, onDismiss: { showPasswordError = false }) {
            passwordSheetPopup(
                showError: $showPasswordError,
                isPresented: $showingSettingsPasswordSheet,
                title: "Enter Admin Password",
                correctPassword: "127127"
            ) {
                withAnimation { showingActualSettings = true }
            }
        }
        .fullScreenCover(isPresented: $showingQueueLeaderSheet) {
            QueueProjectStartSheet(
                isPresented: $showingQueueLeaderSheet,
                lineLeaderName: $queueLineLeaderName,
                queueItem: selectedQueueItem,
                workerNames: viewModel.workerNameCache,
                onStart: startQueueProject
            )
        }
        .fullScreenCover(isPresented: $showingActualSettings) {
            settingsViewLayer
        }
        .sheet(isPresented: $showingPasswordSheet, onDismiss: { showPasswordError = false }) {
            passwordSheetPopup(
                showError: $showPasswordError,
                isPresented: $showingPasswordSheet,
                title: "Enter Pause Password",
                correctPassword: pausePassword
            ) {
                _ = viewModel.pauseTimer(password: pausePassword)
            }
        }
        .sheet(isPresented: $showingResetPasswordSheet, onDismiss: { showPasswordError = false }) {
            passwordSheetPopup(
                showError: $showPasswordError,
                isPresented: $showingResetPasswordSheet,
                title: "Enter Reset Password",
                correctPassword: resetPassword
            ) {
                performReset()
            }
        }
        .sheet(isPresented: $showingTimerInputSheet) {
            GeometryReader { sheetGeometry in
                timerInputScreen(geometry: sheetGeometry)
            }
            .onAppear {
                hoursInput = ""; minutesInput = ""; secondsInput = ""; selectedField = .hours
            }
            .interactiveDismissDisabled()
        }
        .sheet(isPresented: $showingWhosInSheet, onDismiss: {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.isRFIDFieldFocused = true }
        }) {
            NavigationView {
                ActiveWorkerView()
                    .environmentObject(viewModel)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { showingWhosInSheet = false } } }
            }
        }
        .fullScreenCover(isPresented: $showingProceduresSheet) {
            ProceduresView(viewModel: viewModel)
        }
        .sheet(isPresented: $showingQCUnlockSheet) {
            UnlockView(viewModel: viewModel, isPresented: $showingQCUnlockSheet)
        }
        .alert(isPresented: $showingEmailAlert) {
            Alert(title: Text(emailAlertTitle), message: Text(emailAlertMessage), dismissButton: .default(Text("OK")))
        }
        .onChange(of: scenePhase) { phase in
            if phase == .background { viewModel.saveState() }
        }
        .onAppear {
            startCursorBlink()
            self.companyNameInput = viewModel.companyName
            self.projectNameInput = viewModel.projectName
            self.lineLeaderNameInput = viewModel.lineLeaderName
            DispatchQueue.main.async { if self.shouldShowTimerScreen { self.isRFIDFieldFocused = true } }
        }
        .onChange(of: rfidInput) { newValue in
            if newValue.isEmpty { self.isRFIDFieldFocused = true }
        }
        .onChange(of: viewModel.isCountingDown) { isRunning in
            DispatchQueue.main.async { if isRunning { self.isRFIDFieldFocused = true } }
        }
        .onChange(of: viewModel.shouldTriggerFinishFlow) { shouldTrigger in
            if shouldTrigger {
                viewModel.shouldTriggerFinishFlow = false
                sendEmailAndFinishProject()
            }
        }
        .onChange(of: viewModel.companyName) { newValue in companyNameInput = newValue }
        .onChange(of: viewModel.projectName) { newValue in projectNameInput = newValue }
        .onChange(of: viewModel.lineLeaderName) { newValue in lineLeaderNameInput = newValue }
        .onDisappear { stopCursorBlink() }
    }
    
    // MARK: - Sub-Views to Fix Compiler Timeout
    
    var mainInterfaceLayer: some View {
        GeometryReader { geometry in
            NavigationView {
                ZStack {
                    Image("MakeLogo-copy")
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .edgesIgnoringSafeArea(.all)
                        .opacity(0.35)
                    
                    VStack {
                        if shouldShowTimerScreen {
                            timerRunningScreen()
                        } else if viewModel.showManualSetup {
                            projectInfoScreen(geometry: geometry)
                        } else {
                            waitingForCommandScreen()
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    
                    VStack {
                        Spacer()
                        Text("Version " + appVersion + " | © " + currentYear + " Make USA LLC")
                    }
                    .font(.caption)
                    .foregroundColor(.black)
                    .padding(.bottom, 40)
                    .ignoresSafeArea(.keyboard)
                }
                .navigationTitle(shouldShowTimerScreen ? "Timer Running" : "Set Project Info")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: { showingSettingsPasswordSheet = true }) {
                            Image(systemName: "line.3.horizontal")
                        }
                    }
                }
            }
            .navigationViewStyle(.stack)
        }
        .edgesIgnoringSafeArea(.all)
    }
    
    var overlayLayer: some View {
        Group {
            if showingCompanyKeyboard {
                keyboardOverlay(text: $companyNameInput, isPresented: $showingCompanyKeyboard)
            }
            
            if showingProjectKeyboard {
                keyboardOverlay(text: $projectNameInput, isPresented: $showingProjectKeyboard)
            }
            
            if showingLineLeaderKeyboard {
                keyboardOverlay(text: $lineLeaderNameInput, isPresented: $showingLineLeaderKeyboard)
            }
            
            if isSendingEmail {
                loadingOverlay(text: "Sending Email...")
            }
            
            VStack {
                if let banner = currentBanner {
                    BannerView(banner: banner)
                        .onTapGesture {
                            withAnimation(.spring()) { currentBanner = nil; bannerTimer?.invalidate() }
                        }
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                Spacer()
            }
            .padding(.top, 40)
            .zIndex(20)
        }
    }
    
    var settingsViewLayer: some View {
        ZStack {
            SettingsSelectionView(
                isPresented: $showingActualSettings,
                showingSettingsKeyboard: $showingSettingsKeyboard,
                settingsKeyboardBinding: $settingsKeyboardBinding,
                showingSettingsNumericKeyboard: $showingSettingsNumericKeyboard,
                settingsNumericKeyboardBinding: $settingsNumericKeyboardBinding
            )
            .environmentObject(viewModel)
            
            if showingSettingsKeyboard {
                keyboardOverlay(text: Binding(get: { settingsKeyboardBinding?.wrappedValue ?? "" }, set: { settingsKeyboardBinding?.wrappedValue = $0 }), isPresented: $showingSettingsKeyboard)
            }
            
            if showingSettingsNumericKeyboard {
                numericKeyboardOverlay(text: Binding(get: { settingsNumericKeyboardBinding?.wrappedValue ?? "" }, set: { settingsNumericKeyboardBinding?.wrappedValue = $0 }), isPresented: $showingSettingsNumericKeyboard)
            }
        }
    }
    
    // MARK: - Logic Helpers
    func handleQueueItemChange(_ newItem: ProjectQueueItem?) {
        if let item = newItem {
            viewModel.scanHistory = item.scanHistory ?? []
            viewModel.projectEvents = item.projectEvents ?? []
            viewModel.scanCount = viewModel.scanHistory.count
            viewModel.pauseCount = viewModel.projectEvents.filter { $0.type == .pause }.count
            viewModel.lunchCount = viewModel.projectEvents.filter { $0.type == .lunch }.count
            
            if let savedLeader = item.lineLeaderName, !savedLeader.isEmpty {
                viewModel.companyName = item.company
                viewModel.projectName = item.project
                viewModel.category = item.category
                viewModel.projectSize = item.size
                viewModel.lineLeaderName = savedLeader
                viewModel.pendingQueueIdToDelete = item.id
                
                let h = item.seconds / 3600
                let m = (item.seconds % 3600) / 60
                let s = item.seconds % 60
                viewModel.resetTimer(hours: h, minutes: m, seconds: s)
                
                if let trueOriginal = item.originalSeconds, trueOriginal > 0 {
                    viewModel.originalCountdownSeconds = trueOriginal
                }
                
                viewModel.triggerQueueItem = nil
            } else {
                self.selectedQueueItem = item
                self.queueLineLeaderName = ""
                self.showingQueueLeaderSheet = true
                viewModel.triggerQueueItem = nil
            }
        }
    }
    
    func startQueueProject() {
        if let item = selectedQueueItem {
            viewModel.companyName = item.company
            viewModel.projectName = item.project
            viewModel.category = item.category
            viewModel.projectSize = item.size
            viewModel.lineLeaderName = queueLineLeaderName
            viewModel.pendingQueueIdToDelete = item.id
            
            let h = item.seconds / 3600
            let m = (item.seconds % 3600) / 60
            let s = item.seconds % 60
            viewModel.resetTimer(hours: h, minutes: m, seconds: s)
            
            if let trueOriginal = item.originalSeconds, trueOriginal > 0 {
                viewModel.originalCountdownSeconds = trueOriginal
            }
            showingQueueLeaderSheet = false
        }
    }
    
    func keyboardOverlay(text: Binding<String>, isPresented: Binding<Bool>) -> some View {
        ZStack {
            Color.black.opacity(0.001)
                .edgesIgnoringSafeArea(.all)
                .onTapGesture { withAnimation { isPresented.wrappedValue = false } }
            
            GeometryReader { geo in
                VStack {
                    Spacer()
                    CustomAlphanumericKeyboard(
                        text: text,
                        isPresented: isPresented,
                        geometry: geo
                    )
                }
            }
            .transition(.move(edge: .bottom))
        }
    }
    
    func numericKeyboardOverlay(text: Binding<String>, isPresented: Binding<Bool>) -> some View {
        ZStack {
            Color.black.opacity(0.001)
                .edgesIgnoringSafeArea(.all)
                .onTapGesture { withAnimation { isPresented.wrappedValue = false } }
            
            GeometryReader { geo in
                VStack {
                    Spacer()
                    CustomNumericKeyboard(
                        text: text,
                        isPresented: isPresented,
                        geometry: geo
                    )
                }
            }
            .transition(.move(edge: .bottom))
        }
    }
    
    func loadingOverlay(text: String) -> some View {
        ZStack {
            Color.black.opacity(0.4).edgesIgnoringSafeArea(.all)
            VStack {
                ProgressView().scaleEffect(2)
                Text(text).font(.title2).foregroundColor(.white).padding()
            }
            .padding(30)
            .background(Color.black.opacity(0.8))
            .cornerRadius(20)
        }
        .zIndex(12)
    }
}

struct UnlockView: View {
    @ObservedObject var viewModel: WorkerViewModel
    @Binding var isPresented: Bool
    
    @State private var inputCode = ""
    @State private var showError = false
    
    var body: some View {
        VStack(spacing: 20) {
            
            // Header
            HStack {
                Text("Unlock Dashboard")
                    .font(.system(size: 30, weight: .bold))
                Spacer()
                Button("Cancel") {
                    isPresented = false
                }
                .padding()
                .background(Color.gray.opacity(0.2))
                .cornerRadius(8)
            }
            .padding()
            
            Spacer()
            
            // Status Message
            VStack(spacing: 10) {
                if viewModel.pauseState == .technician {
                    Text("⚠️ MACHINE ISSUE REPORTED")
                        .font(.headline)
                        .foregroundColor(.orange)
                    Text("Enter Tech Code to Resume")
                        .foregroundColor(.gray)
                } else {
                    Text("⚠️ QC PAUSE ACTIVE")
                        .font(.headline)
                        .foregroundColor(.purple)
                    Text("Enter QC Code to Resume")
                        .foregroundColor(.gray)
                }
                
                // Code Display (Dots)
                HStack(spacing: 15) {
                    ForEach(0..<4) { index in
                        Circle()
                            .stroke(Color.gray, lineWidth: 2)
                            .background(Circle().fill(inputCode.count > index ? Color.black : Color.clear))
                            .frame(width: 20, height: 20)
                    }
                }
                .padding(.vertical)
                
                if showError {
                    Text("Incorrect Code")
                        .font(.caption)
                        .bold()
                        .foregroundColor(.red)
                } else {
                    Text(" ")
                        .font(.caption)
                }
            }
            
            // Pin Pad
            CustomUnlockPinPad(code: $inputCode, onCommit: {
                attemptUnlock()
            })
            .frame(maxWidth: 400)
            
            Spacer()
        }
        .background(Color(UIColor.systemGroupedBackground))
    }
    
    func attemptUnlock() {
        var success = false
        
        // Determine which unlock function to call based on the current pause state
        if viewModel.pauseState == .technician {
            // Unlocking logic for Tech Pause
            success = viewModel.toggleTechPause(code: inputCode)
        } else {
            // Unlocking logic for QC Pause (Crew or Component)
            success = viewModel.toggleQCPause(type: viewModel.pauseState, code: inputCode)
        }
        
        if success {
            isPresented = false
        } else {
            showError = true
            inputCode = ""
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)
        }
    }
}

// MARK: - Local Components
// Including these here ensures they are available to UnlockView even if not defined globally.

struct CustomUnlockPinPad: View {
    @Binding var code: String
    var onCommit: () -> Void
    
    let columns = [
        GridItem(.fixed(90), spacing: 20),
        GridItem(.fixed(90), spacing: 20),
        GridItem(.fixed(90), spacing: 20)
    ]
    
    var body: some View {
        LazyVGrid(columns: columns, spacing: 20) {
            ForEach(1...9, id: \.self) { num in
                UnlockPinButton(label: "\(num)") {
                    if code.count < 4 { code.append("\(num)") }
                }
            }
            
            UnlockPinButton(label: "⌫", color: .red.opacity(0.1), textColor: .red) {
                if !code.isEmpty { code.removeLast() }
            }
            
            UnlockPinButton(label: "0") {
                if code.count < 4 { code.append("0") }
            }
            
            UnlockPinButton(label: "OK", color: .green, textColor: .white) {
                onCommit()
            }
        }
    }
}

struct UnlockPinButton: View {
    let label: String
    var color: Color = Color.gray.opacity(0.1)
    var textColor: Color = .primary
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.title)
                .fontWeight(.bold)
                .frame(width: 90, height: 70)
                .background(color)
                .foregroundColor(textColor)
                .cornerRadius(12)
        }
    }
}



