import SwiftUI
import Combine
import AVFoundation

let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"

// MARK: - ContentView
// The main container view that switches between the project setup
// screen and the timer screen. It wires the WorkerViewModel to UI
// controls and implements keyboard overlays, modals, and settings.
struct ContentView: View {
    
    //MARK: Properties
    @ObservedObject var viewModel = WorkerViewModel()
    @State var showPasswordPrompt = false
    @FocusState var isQueueLeaderFieldFocused: Bool
    
    // Inputs for timer setup
    @State var hoursInput = ""
    @State var minutesInput = ""
    @State var secondsInput = ""
    
    // Project metadata inputs (mirrors viewModel values until 'Next')
    @State var companyNameInput: String = ""
    @State var projectNameInput: String = ""
    @State var lineLeaderNameInput: String = ""
    
    // Passwords/modals state
    @State var passwordField = ""
    @State var showingPasswordSheet = false
    @State var showingResetPasswordSheet = false
    
    @State var showPasswordError = false
    
    // RFID entry
    @State var rfidInput = ""
    @FocusState var isRFIDFieldFocused: Bool
    
    // Custom keyboard overlays
    @State var showingCompanyKeyboard = false
    @State var showingProjectKeyboard = false
    @State var showingLineLeaderKeyboard = false
    @State var showingTimerInputSheet = false
    
    @State var selectedField: TimeField? = .hours
    @State var showCursor = true
    @State var cursorTimer: Timer?
    
    @State var isReset = true
    @Environment(\.scenePhase) var scenePhase
    
    // Settings flow state
    @State var showingSettingsPasswordSheet = false
    @State var showingActualSettings = false
    
    // Email flow state
    @State var isSendingEmail = false
    @State var showingEmailAlert = false
    @State var emailAlertTitle = ""
    @State var emailAlertMessage = ""
    
    // Settings keyboard bindings (passed into full-screen settings view)
    @State var showingSettingsKeyboard = false
    @State var settingsKeyboardBinding: Binding<String>?
    
    @State var showingSettingsNumericKeyboard = false
    @State var settingsNumericKeyboardBinding: Binding<String>?
    
    // Banner alert
    @State var currentBanner: BannerAlert? = nil
    @State var bannerTimer: Timer? = nil
    
    // ... existing state variables ...
    @State var showingQueueLeaderSheet = false
    @State var selectedQueueItem: ProjectQueueItem? = nil
    @State var queueLineLeaderName = ""
    
    @State var showingQueueLeaderKeyboard = false
    @FocusState var isInputFocused: Bool
    
    // --- NEW: State for "Who's In" Sheet ---
    @State var showingWhosInSheet = false
    
    // ---Finish Reconfirmation ---
    @State var showingFinishConfirmation = false
    // -----------------------------
    
    // AppStorage-based persisted settings available directly in the view
    @AppStorage(AppStorageKeys.smtpRecipient)  var smtpRecipient = "productionreports@makeit.buzz"
    @AppStorage(AppStorageKeys.smtpHost)  var smtpHost = "smtp.office365.com"
    @AppStorage(AppStorageKeys.smtpUsername)  var smtpUsername = "alerts@makeit.buzz"
    @AppStorage(AppStorageKeys.smtpPassword)  var smtpPassword = ""
    @AppStorage(AppStorageKeys.enableSmtpEmail)  var enableSmtpEmail = false
    
    @AppStorage(AppStorageKeys.pausePassword)  var pausePassword = "340340"
    @AppStorage(AppStorageKeys.resetPassword)  var resetPassword = "465465"
    
    init() {
        // Make navigation bar background transparent to better show the background image
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundColor = .clear
        
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
    }
    
    
    //MARK: COMPUTED PROPERTIES
    // Simple computed properties used to enable/disable buttons in the UI
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
    
    var body: some View {
        ZStack {
            
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
                            // 1. If Timer is running -> Show Timer
                            if shouldShowTimerScreen {
                                timerRunningScreen()
                            }
                            // 2. If Admin requested Manual Setup -> Show Setup
                            else if viewModel.showManualSetup {
                                projectInfoScreen(geometry: geometry)
                            }
                            // 3. Default -> Headless Waiting Screen
                            else {
                                waitingForCommandScreen()
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        
                        VStack {
                            Spacer()
                            Text("Version " + appVersion + " | © " + currentYear + " Make USA LLC") // Incremented version
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
                            Button(action: {
                                showingSettingsPasswordSheet = true
                            }) {
                                Image(systemName: "line.3.horizontal")
                            }
                        }
                    }
                }
                // --- ADD THIS FINISH ALERT BLOCK ---
                        .alert(isPresented: $showingFinishConfirmation) {
                            Alert(
                                title: Text("Finish Project?"),
                                message: Text("Are you sure you want to finish '\(viewModel.projectName)'? This will clock out all workers."),
                                primaryButton: .destructive(Text("Finish")) {
                                    sendEmailAndFinishProject()
                                },
                                secondaryButton: .cancel()
                            )
                        }
                .navigationViewStyle(.stack)
            }
            .edgesIgnoringSafeArea(.all)
            
            // Custom alphanumeric keyboard overlays. They render on top of the
            // main view and capture taps to dismiss.
            if showingCompanyKeyboard {
                Color.black.opacity(0.001)
                    .edgesIgnoringSafeArea(.all)
                    .onTapGesture {
                        withAnimation {
                            showingCompanyKeyboard = false
                        }
                    }
                
                GeometryReader { geo in
                    VStack {
                        Spacer()
                        CustomAlphanumericKeyboard(
                            text: $companyNameInput,
                            isPresented: $showingCompanyKeyboard,
                            geometry: geo
                        )
                    }
                }
                .transition(.move(edge: .bottom))
            }
            
            if showingProjectKeyboard {
                Color.black.opacity(0.001)
                    .edgesIgnoringSafeArea(.all)
                    .onTapGesture {
                        withAnimation {
                            showingProjectKeyboard = false
                        }
                    }
                
                GeometryReader { geo in
                    VStack {
                        Spacer()
                        CustomAlphanumericKeyboard(
                            text: $projectNameInput,
                            isPresented: $showingProjectKeyboard,
                            geometry: geo
                        )
                    }
                }
                .transition(.move(edge: .bottom))
            }
            
            if showingLineLeaderKeyboard {
                Color.black.opacity(0.001)
                    .edgesIgnoringSafeArea(.all)
                    .onTapGesture {
                        withAnimation {
                            showingLineLeaderKeyboard = false
                        }
                    }
                
                GeometryReader { geo in
                    VStack {
                        Spacer()
                        CustomAlphanumericKeyboard(
                            text: $lineLeaderNameInput,
                            isPresented: $showingLineLeaderKeyboard,
                            geometry: geo
                        )
                    }
                }
                .transition(.move(edge: .bottom))
            }
            
            if isSendingEmail {
                // Simple blocking overlay shown while the email send completes
                Color.black.opacity(0.4)
                    .edgesIgnoringSafeArea(.all)
                VStack {
                    ProgressView()
                        .scaleEffect(2)
                    Text("Sending Email...")
                        .font(.title2)
                        .font(.title2)
                        .foregroundColor(.white)
                        .padding()
                }
                .padding(30)
                .background(Color.black.opacity(0.8))
                .cornerRadius(20)
                .zIndex(12)
            }
            
            // --- NEW: BANNER ALERT OVERLAY ---
            VStack {
                if let banner = currentBanner {
                    BannerView(banner: banner)
                        .onTapGesture {
                            withAnimation(.spring()) {
                                currentBanner = nil
                                bannerTimer?.invalidate()
                            }
                        }
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                Spacer() // Pushes banner to the top
            }
            .padding(.top, 40) // Adjust to not cover status bar area
            .zIndex(20) // High zIndex
            
        }
        // End of ZStack
        // --- MODIFIED: Auto-start if Leader exists ---
        // --- MODIFIED: Auto-start if Leader exists ---
        .onChange(of: viewModel.triggerQueueItem) { newItem in
            if let item = newItem {
                // Restore Logs (if they exist)
                viewModel.scanHistory = item.scanHistory ?? []
                viewModel.projectEvents = item.projectEvents ?? []
                // Recalculate pause count/scan count based on restored logs
                viewModel.scanCount = viewModel.scanHistory.count
                viewModel.pauseCount = viewModel.projectEvents.filter { $0.type == .pause }.count
                viewModel.lunchCount = viewModel.projectEvents.filter { $0.type == .lunch }.count
                
                if let savedLeader = item.lineLeaderName, !savedLeader.isEmpty {
                    // AUTO LOAD
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
                    
                    // --- FIX 2: RESTORE ORIGINAL SECONDS ---
                            // resetTimer() just overwrote originalSeconds with the remaining time.
                            // We must overwrite it back with the TRUE original time from the saved file.
                            if let trueOriginal = item.originalSeconds, trueOriginal > 0 {
                                viewModel.originalCountdownSeconds = trueOriginal
                            }
                    
                    viewModel.triggerQueueItem = nil
                } else {
                    // MANUAL SCAN
                    self.selectedQueueItem = item
                    self.queueLineLeaderName = ""
                    self.showingQueueLeaderSheet = true
                    viewModel.triggerQueueItem = nil
                }
            }
        }
        // ----------------------
        .sheet(isPresented: $showingSettingsPasswordSheet, onDismiss: { showPasswordError = false }) {
            passwordSheetPopup(
                showError: $showPasswordError,
                isPresented: $showingSettingsPasswordSheet,
                title: "Enter Admin Password",
                correctPassword: "127127"
            ) {
                withAnimation {
                    showingActualSettings = true
                }
            }
        }
        
        // --- REPLACE THE PREVIOUS .sheet(isPresented: $showingQueueLeaderSheet) WITH THIS ---
        // --- QUEUE PROJECT START SHEET ---
        .fullScreenCover(isPresented: $showingQueueLeaderSheet) {
            QueueProjectStartSheet(
                isPresented: $showingQueueLeaderSheet,
                lineLeaderName: $queueLineLeaderName,
                queueItem: selectedQueueItem,
                workerNames: viewModel.workerNameCache, // <--- THIS WAS MISSING
                onStart: {
                    if let item = selectedQueueItem {
                        // 1. Push Queue Data to ViewModel
                        viewModel.companyName = item.company
                        viewModel.projectName = item.project
                        viewModel.category = item.category
                        viewModel.projectSize = item.size
                        
                        // 2. Push Line Leader
                        viewModel.lineLeaderName = queueLineLeaderName
                        
                        // 3. Mark Queue Item for Deletion
                        viewModel.pendingQueueIdToDelete = item.id
                        
                        // 4. Parse Time and Start
                        let h = item.seconds / 3600
                        let m = (item.seconds % 3600) / 60
                        let s = item.seconds % 60
                        viewModel.resetTimer(hours: h, minutes: m, seconds: s)
                        
                        if let trueOriginal = item.originalSeconds, trueOriginal > 0 {
                                            viewModel.originalCountdownSeconds = trueOriginal
                                        }
                        
                        // 5. Close
                        showingQueueLeaderSheet = false
                    }
                }
            )
        }
        .fullScreenCover(isPresented: $showingActualSettings) {
            ZStack {
                SettingsSelectionView(
                    isPresented: $showingActualSettings,
                    showingSettingsKeyboard: $showingSettingsKeyboard,
                    settingsKeyboardBinding: $settingsKeyboardBinding,
                    showingSettingsNumericKeyboard: $showingSettingsNumericKeyboard,
                    settingsNumericKeyboardBinding: $settingsNumericKeyboardBinding
                )
                .environmentObject(viewModel)
                
                // Additional in-settings keyboard overlays (reused components)
                if showingSettingsKeyboard {
                    Color.black.opacity(0.001)
                        .edgesIgnoringSafeArea(.all)
                        .onTapGesture {
                            withAnimation {
                                showingSettingsKeyboard = false
                                settingsKeyboardBinding = nil
                            }
                        }
                    
                    GeometryReader { geo in
                        VStack {
                            Spacer()
                            if let binding = settingsKeyboardBinding {
                                CustomAlphanumericKeyboard(
                                    text: binding,
                                    isPresented: $showingSettingsKeyboard,
                                    geometry: geo
                                )
                            }
                        }
                    }
                    .transition(.move(edge: .bottom))
                }
                
                if showingSettingsNumericKeyboard {
                    Color.black.opacity(0.001)
                        .edgesIgnoringSafeArea(.all)
                        .onTapGesture {
                            withAnimation {
                                showingSettingsNumericKeyboard = false
                                settingsNumericKeyboardBinding = nil
                            }
                        }
                    
                    GeometryReader { geo in
                        VStack {
                            Spacer()
                            if let binding = settingsNumericKeyboardBinding {
                                CustomNumericKeyboard(
                                    text: binding,
                                    isPresented: $showingSettingsNumericKeyboard,
                                    geometry: geo
                                )
                            }
                        }
                    }
                    .transition(.move(edge: .bottom))
                }
            }
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
                hoursInput = ""
                minutesInput = ""
                secondsInput = ""
                selectedField = .hours
            }
            .interactiveDismissDisabled()
        }
        // --- UPDATED SHEET FOR WHO'S IN ---
                .sheet(isPresented: $showingWhosInSheet, onDismiss: {
                    // 1. AUTO-REFOCUS LOGIC
                    // Wait 0.5s for the sheet to fully disappear, then force focus back to RFID
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.isRFIDFieldFocused = true
                    }
                }) {
                    NavigationView {
                        ActiveWorkerView() // Ensure this is ActiveWorkerView, not ManualClockOutView
                            .environmentObject(viewModel)
                            .toolbar {
                                ToolbarItem(placement: .cancellationAction) {
                                    Button("Close") { showingWhosInSheet = false }
                                }
                            }
                    }
                }

        // ------------------------------
        .alert(isPresented: $showingEmailAlert) {
            Alert(
                title: Text(emailAlertTitle),
                message: Text(emailAlertMessage),
                dismissButton: .default(Text("OK"))
            )
        }
        .onChange(of: scenePhase) { phase in
            if phase == .background {
                viewModel.saveState()
            }
        }
        .onAppear {
            startCursorBlink()
            self.companyNameInput = viewModel.companyName
            self.projectNameInput = viewModel.projectName
            self.lineLeaderNameInput = viewModel.lineLeaderName
            
            DispatchQueue.main.async {
                if self.shouldShowTimerScreen {
                    self.isRFIDFieldFocused = true
                }
            }
        }
        .onChange(of: rfidInput) { newValue in
            if newValue.isEmpty {
                self.isRFIDFieldFocused = true
            }
        }
        .onChange(of: viewModel.isCountingDown) { isRunning in
            DispatchQueue.main.async {
                if isRunning {
                    self.isRFIDFieldFocused = true
                }
            }
        }
        .onChange(of: viewModel.shouldTriggerFinishFlow) { shouldTrigger in
            if shouldTrigger {
                viewModel.shouldTriggerFinishFlow = false
                // This function sends the email, finishes the project, and resets the UI
                sendEmailAndFinishProject()
            }
        }
        .onChange(of: viewModel.companyName) { newValue in
            companyNameInput = newValue
        }
        .onChange(of: viewModel.projectName) { newValue in
            projectNameInput = newValue
        }
        .onChange(of: viewModel.lineLeaderName) { newValue in
            lineLeaderNameInput = newValue
        }
        .onDisappear { stopCursorBlink() }
    }
}

//MARK: PREVIEW
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .previewInterfaceOrientation(.landscapeLeft)
    }
}
