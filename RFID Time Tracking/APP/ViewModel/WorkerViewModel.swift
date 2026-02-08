//
//  WorkerViewModel.swift
//  RFID Time Tracking
//
//

import Foundation
import Combine
import Firebase
import SwiftUI
import FirebaseFirestore
import FirebaseCore
import FirebaseAuth

// MARK: - ViewModel
// The central ObservableObject that contains app state and business logic.
// - Publishes properties the UI binds to
// - Handles RFID scan processing, timer, pause/lunch logic, and persistence
class WorkerViewModel: ObservableObject {
    // --- FIREBASE SYNC ---
    private var db = Firestore.firestore()
    private var listener: ListenerRegistration?
    private var lastCommandTimestamp: Date?
    
    @Published var triggerQueueItem: ProjectQueueItem? = nil
    
    @AppStorage(AppStorageKeys.fleetIpadID) var fleetIpadID: String = "" {
        didSet { if !fleetIpadID.isEmpty { connectToFleet() } }
    }
    
    // --- EXISTING VARIABLES ---
    @Published var showManualSetup = false
    @Published var workers = [String: Worker]()
    @Published var totalPeopleWorking = 0
    @Published var timerText: String = "00:00:00"
    @Published var isProjectFinished = false
    @Published var shouldTriggerFinishFlow = false
    
    private var timer: Timer?
    public var countdownSeconds: Int = 0
    @Published var originalCountdownSeconds: Int = 0
    
    // --- NEW: Dynamic Data ---
    @Published var projectQueue: [ProjectQueueItem] = []
    @Published var availableCategories: [String] = [
        "Fragrance", "Skin Care", "Kitting", "VOC"
    ]
    
    @Published var availableSizes: [String] = [
        "100ML", "50ML", "30ML", "15ML", "10ML", "7.5ML", "1.75ML", "4oz", "8oz", "other"
    ]
    var pendingQueueIdToDelete: String? = nil
    
    @Published var isPaused = true
    @Published var pauseState: PauseType = .running
    
    private var lastUpdateTime: Date?
    @Published var isCountingDown = false
    @Published var hasUsedLunchBreak = false
    @Published var lunchBreakStartTime: Date?
    @Published var hasPlayedBuzzerAtZero = false
    
    // Project Info
    @Published var projectName: String = ""
    @Published var companyName: String = ""
    @Published var lineLeaderName: String = ""
    @Published var category: String = ""
    @Published var projectSize: String = ""
    
    // Counters
    @Published var pauseCount: Int = 0
    @Published var lunchCount: Int = 0
    @Published var scanCount: Int = 0
    
    // Logs
    @Published var scanHistory: [ScanEvent] = []
    @Published var projectEvents: [ProjectEvent] = []
    
    // Settings Lists
    @Published var lunchPeriods: [TimePeriod] = []
    @Published var shiftStartTimes: [ShiftTime] = []
    @Published var categories: [EditableStringItem] = []
    @Published var projectSizes: [EditableStringItem] = []
    
    @Published var workerNameCache: [String: String] = [:]
    
    init() {
        loadState()
        loadCustomAppSettings()

        FirebaseManager.shared.observeAuthState { [weak self] _ in
            guard let self else { return }

            self.startTimer()

            FirebaseManager.shared.listenToWorkers {
                self.workerNameCache = $0
            }

            FirebaseManager.shared.listenToProjectQueue {
                self.projectQueue = $0
            }

            FirebaseManager.shared.listenToProjectOptions { categories, sizes in
                self.availableCategories = categories
                self.availableSizes = sizes
            }

            if !self.fleetIpadID.isEmpty {
                self.connectToFleet()
            }
        }
    }
    
    
    // --- NEW: Replay history to calculate total hours ---
        func reconstructStateFromLogs() {
            print("🔄 Reconstructing worker hours from history logs...")
            
            // 1. Reset Workers Dict
            // We will rebuild it entirely from the logs to ensure accuracy
            var rebuiltWorkers: [String: Worker] = [:]
            
            // 2. Sort history to ensure we replay in chronological order
            let sortedHistory = scanHistory.sorted { $0.timestamp < $1.timestamp }
            
            for event in sortedHistory {
                let id = event.cardID
                
                // Get or Create Worker
                var worker = rebuiltWorkers[id] ?? Worker(id: id, clockInTime: nil, totalMinutesWorked: 0)
                
                if event.action == .clockIn {
                    // Set Clock In Time
                    worker.clockInTime = event.timestamp
                } else if event.action == .clockOut {
                    // Calculate duration if they were clocked in
                    if let start = worker.clockInTime {
                        let minutes = event.timestamp.timeIntervalSince(start) / 60
                        worker.totalMinutesWorked += minutes
                    }
                    // Clear Clock In (they are now out)
                    worker.clockInTime = nil
                }
                
                // Update Dictionary
                rebuiltWorkers[id] = worker
            }
            
            // 3. Apply to ViewModel
            self.workers = rebuiltWorkers
            self.recalcTotalPeopleWorking()
            
            print("✅ Reconstruct Complete. Total Workers: \(workers.count). Active: \(totalPeopleWorking)")
        }

    private func clearRemoteCommand() {
        guard !fleetIpadID.isEmpty else { return }

        FirebaseManager.shared.pushFleetState(
            fleetId: fleetIpadID,
            data: ["remoteCommand": ""]
        )
    }

    
    // --- NEW: Helper to restore state after a crash ---
    func restoreFromCloud(data: [String: Any]) {
        // SAFETY CHECK: Only restore if the iPad is currently "Idle" / Empty.
        // This prevents the cloud from overwriting local work if the internet just blipped.
        guard countdownSeconds == 0 && workers.isEmpty && projectName.isEmpty else { return }
        
        // Check if the cloud actually has an active job (time remaining)
        guard let seconds = data["secondsRemaining"] as? Int, seconds > 0 else { return }
        
        print("⚠️ Local state empty. Restoring active session from Cloud...")
        
        // 1. Restore Project Info
        if let val = data["companyName"] as? String { self.companyName = val }
        if let val = data["projectName"] as? String { self.projectName = val }
        if let val = data["lineLeaderName"] as? String { self.lineLeaderName = val }
        if let val = data["category"] as? String { self.category = val }
        if let val = data["projectSize"] as? String { self.projectSize = val }
        
        // 2. Restore Timer State
        self.countdownSeconds = seconds
        // We approximate the original time if it's not saved, or use seconds
        self.originalCountdownSeconds = seconds
        
        // Important: Restore as PAUSED for safety, so it doesn't tick down while offline
        self.isCountingDown = false
        self.isPaused = true
        self.timerText = "Resumed: Press Start"
        
        // 3. Restore Active Workers
        if let activeIDs = data["activeWorkers"] as? [String] {
            for id in activeIDs {
                // Create a worker entry so they appear in the list.
                // We set a dummy clock-in time because the exact start time isn't in the basic sync data,
                // but this allows them to continue working.
                self.workers[id] = Worker(id: id, clockInTime: Date(), totalMinutesWorked: 0)
            }
            self.totalPeopleWorking = activeIDs.count
        }
        
        print("✅ Restored session from Cloud successfully.")
    }
    
    func handleRemoteCommand(_ command: String) {

        let parts = command.split(separator: "|", omittingEmptySubsequences: true)
        guard let action = parts.first.map(String.init) else { return }

        switch action {

        case "PRELOAD":
            handlePreloadCommand(parts)

        case "TOGGLE":
            if isPaused {
                resumeTimer()
            } else {
                _ = pauseTimer(password: "REMOTE_OVERRIDE")
            }

        case "LUNCH":
            _ = takeLunchBreak()

        case "SAVE":
            saveJobToQueue()

        case "RESET":
            parts.count > 1 ? handleSetTime(parts) : resetData()

        case "SET_TIME":
            handleSetTime(parts)

        case "FINISH":
            shouldTriggerFinishFlow = true

        case "CLOCK_OUT":
            if parts.count > 1 {
                clockOut(for: String(parts[1]))
            }

        default:
            break
        }
    }

    private func handlePreloadCommand(_ parts: [Substring]) {

        let totalSecs = parseTimeToSeconds(from: parts)

        originalCountdownSeconds = totalSecs
        countdownSeconds = totalSecs

        isPaused = true
        pauseState = .running
        isCountingDown = false
        isProjectFinished = false
        timerText = "00:00:00"
        showManualSetup = false

        // DO NOT clear leader name (fleet already synced it)

        triggerQueueItem = ProjectQueueItem(
            id: "REMOTE_PRELOAD",
            company: companyName,
            project: projectName,
            category: category,
            size: projectSize,
            seconds: totalSecs,
            lineLeaderName: lineLeaderName,
            createdAt: Date(),
            scanHistory: scanHistory,
            projectEvents: projectEvents
        )
    }

    private func handleSetTime(_ parts: [Substring]) {
        guard let time = parseHMS(from: parts) else { return }
        resetTimer(hours: time.h, minutes: time.m, seconds: time.s)
    }

    private func parseTimeToSeconds(from parts: [Substring]) -> Int {
        guard let time = parseHMS(from: parts) else { return 0 }
        return (time.h * 3600) + (time.m * 60) + time.s
    }

    private func parseHMS(from parts: [Substring]) -> (h: Int, m: Int, s: Int)? {
        guard parts.count > 1 else { return nil }

        let timeParts = parts[1].split(separator: ":")
        guard timeParts.count == 3,
              let h = Int(timeParts[0]),
              let m = Int(timeParts[1]),
              let s = Int(timeParts[2]) else {
            return nil
        }

        return (h, m, s)
    }

    
    // 2. REPORT STATUS TO DASHBOARD
    // Redirect all heartbeat calls to the main cloud sync function
    func sendHeartbeat() {
        pushStateToCloud()
    }
    
    // 3. EXECUTE COMMANDS FROM WEB
    func executeRemoteCommand(_ command: String) {
        print("Remote Command Received: \(command)")
        let parts = command.split(separator: "|")
        let action = parts[0]
        
        switch action {
        case "TOGGLE":
            if isPaused { resumeTimer() } else { _ = pauseTimer(password: "REMOTE_OVERRIDE") }
            
        case "PAUSE":
            _ = pauseTimer(password: "REMOTE_OVERRIDE")
            
        case "START":
            // If command has time data (START|H:M:S), set it first
            if parts.count > 1 {
                let timeParts = parts[1].split(separator: ":")
                if timeParts.count == 3, let h = Int(timeParts[0]), let m = Int(timeParts[1]), let s = Int(timeParts[2]) {
                    resetTimer(hours: h, minutes: m, seconds: s)
                }
            } else {
                resumeTimer()
            }
            
        case "LUNCH":
            _ = takeLunchBreak()
            
        case "RESET", "SET_TIME":
            if parts.count > 1 {
                let timeParts = parts[1].split(separator: ":")
                if timeParts.count == 3, let h = Int(timeParts[0]), let m = Int(timeParts[1]), let s = Int(timeParts[2]) {
                    resetTimer(hours: h, minutes: m, seconds: s)
                }
            } else {
                // Default reset if no time provided
                resetData()
            }
            
        case "FINISH":
            finishProject()
            
        default:
            break
        }
        
        // Update status immediately after a command
        sendHeartbeat()
    }
    
    // Helper to bypass password for remote commands
    func pauseTimer(password: String) -> Bool {
        // If it's the remote override, skip password check
        if password == "REMOTE_OVERRIDE" || password == UserDefaults.standard.string(forKey: AppStorageKeys.pausePassword) ?? "340340" {
            isPaused = true
            pauseState = .manual
            pauseCount += 1
            projectEvents.append(ProjectEvent(timestamp: Date(), type: .pause))
            saveState()
            pushStateToCloud()
            sendHeartbeat() // Update dashboard
            return true
        }
        return false
    }
    
    // --- FIREBASE LOGIC END ---
    
    
    // ... [KEEP ALL YOUR EXISTING FUNCTIONS BELOW: startTimer, updateCountdownTime, etc.] ...
    // ... [Make sure to call self.sendHeartbeat() inside finishProject() and resetData() too!] ...
    
    private func startTimer() {
        guard !isProjectFinished else { return }
        timer?.invalidate()
        if isCountingDown {
            lastUpdateTime = Date()
            timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                self.updateCountdownTime()
            }
        }
    }
    
    func checkForLunchBreak() {
        guard self.pauseState != .manual && self.pauseState != .manualLunch else { return }
        guard self.totalPeopleWorking > 0 else { return }
        guard self.pauseState != .autoLunch else { return }
        
        if !hasUsedLunchBreak && isCurrentlyInLunchWindow() {
            startAutoLunch()
        }
    }
    
    private func isCurrentlyInLunchWindow() -> Bool {
        let currentDate = Date()
        let cal = Calendar.current
        let currentHour = cal.component(.hour, from: currentDate)
        let currentMinute = cal.component(.minute, from: currentDate)
        let currentTimeInMinutes = currentHour * 60 + currentMinute
        
        for period in lunchPeriods {
            let startHour = cal.component(.hour, from: period.start)
            let startMinute = cal.component(.minute, from: period.start)
            let endHour = cal.component(.hour, from: period.end)
            let endMinute = cal.component(.minute, from: period.end)
            
            let startTimeInMinutes = startHour * 60 + startMinute
            let endTimeInMinutes = endHour * 60 + endMinute
            
            if startTimeInMinutes < endTimeInMinutes {
                if currentTimeInMinutes >= startTimeInMinutes && currentTimeInMinutes < endTimeInMinutes {
                    return true
                }
            } else {
                if currentTimeInMinutes >= startTimeInMinutes || currentTimeInMinutes < endTimeInMinutes {
                    return true
                }
            }
        }
        return false
    }
    
    func takeLunchBreak() -> LunchFeedback {
        guard !isProjectFinished else { return .success }
        
        guard pauseState != .manual && pauseState != .autoLunch else {
            return .ignoredPaused
        }
        guard totalPeopleWorking > 0 else {
            return .ignoredNoWorkers
        }
        
        isPaused = true
        pauseState = .manualLunch
        hasUsedLunchBreak = true
        lunchBreakStartTime = Date()
        lunchCount += 1
        
        projectEvents.append(ProjectEvent(timestamp: Date(), type: .lunch))
        
        saveState()
        pushStateToCloud()
        sendHeartbeat() // Update dashboard
        return .success
    }
    
    func startAutoLunch() {
        guard !isProjectFinished else { return }
        
        isPaused = true
        pauseState = .autoLunch
        hasUsedLunchBreak = true
        lunchBreakStartTime = nil
        lunchCount += 1
        
        projectEvents.append(ProjectEvent(timestamp: Date(), type: .lunch))
        saveState()
        pushStateToCloud()
        sendHeartbeat() // Update dashboard
    }
    
    func autoClearLunchLock() {
        guard hasUsedLunchBreak else { return }
        
        let cal = Calendar.current
        let currentDate = Date()
        let currentHour = cal.component(.hour, from: currentDate)
        let currentMinute = cal.component(.minute, from: currentDate)
        let currentTimeInMinutes = currentHour * 60 + currentMinute
        
        let resetWindows = shiftStartTimes.map {
            let startHour = cal.component(.hour, from: $0.time)
            let startMinute = cal.component(.minute, from: $0.time)
            let windowStart = startHour * 60 + startMinute
            return (start: windowStart, end: windowStart + 1)
        }
        
        for window in resetWindows {
            if (currentTimeInMinutes >= window.start && currentTimeInMinutes < window.end) {
                hasUsedLunchBreak = false
                saveState()
                return
            }
        }
    }

    func finishProject() {
        AudioPlayerManager.shared.playSound(named: "Cashier")
        
        isPaused = true
        isCountingDown = false
        timer?.invalidate()
        
        let now = Date()
        
        // 1. Clock out all workers locally to finalize calculation
        for id in workers.keys {
            if let clockInTime = workers[id]?.clockInTime {
                let timeWorkedInMinutes = now.timeIntervalSince(clockInTime) / 60
                workers[id]?.totalMinutesWorked += timeWorkedInMinutes
                
                let event = ScanEvent(cardID: id, timestamp: now, action: .clockOut)
                scanHistory.append(event)
            }
        }
        
        isProjectFinished = true
        hasUsedLunchBreak = false
        lunchBreakStartTime = nil
        
        // 2. CRITICAL: Save Report immediately (Before Reset)
//        saveFinalReportToFirestore()
        
        // 3. Sync final state to dashboard one last time
        saveState()
        pushStateToCloud()
        sendHeartbeat()
    }
    
    private func updateCountdownTime() {
        guard isCountingDown else { return }
        
        if self.pauseState == .manualLunch, let breakStart = lunchBreakStartTime {
            let elapsed = Date().timeIntervalSince(breakStart)
            if elapsed >= 1800 {
                resumeTimer()
            }
        } else if self.pauseState == .autoLunch {
            if !isCurrentlyInLunchWindow() {
                resumeTimer()
            }
        }
        
        checkForLunchBreak()
        autoClearLunchLock()
        
        if !isPaused && totalPeopleWorking > 0 {
            guard let last = lastUpdateTime else { return }
            let elapsed = Date().timeIntervalSince(last)
            lastUpdateTime = Date()
            
            let people = max(1, totalPeopleWorking)
            let timeToSubtract = max(1, Int(round(elapsed * Double(people))))
            
            let previousSeconds = countdownSeconds
            
            countdownSeconds -= timeToSubtract
            
            if previousSeconds > 0 && countdownSeconds <= 0 {
                if !hasPlayedBuzzerAtZero {
                    AudioPlayerManager.shared.playSound(named: "Buzzer")
                    hasPlayedBuzzerAtZero = true
                    saveState()
                }
            }
            
        } else {
            lastUpdateTime = Date()
        }
        
        let prefix = countdownSeconds < 0 ? "-" : ""
        let absoluteSeconds = abs(countdownSeconds)
        let hours = absoluteSeconds / 3600
        let minutes = (absoluteSeconds % 3600) / 60
        let seconds = absoluteSeconds % 60
        timerText = String(format: "%@%02d:%02d:%02d", prefix, hours, minutes, seconds)
    }
    
    func resetTimer(hours: Int, minutes: Int, seconds: Int) {
        if let qId = pendingQueueIdToDelete {
            db.collection("project_queue").document(qId).delete()
            pendingQueueIdToDelete = nil
        }
        let totalSeconds = hours * 3600 + minutes * 60 + seconds
        countdownSeconds = totalSeconds
        originalCountdownSeconds = totalSeconds
        
        isCountingDown = true
        isPaused = false
        
        startTimer()
        saveState()
        pushStateToCloud()
        sendHeartbeat() // Update
    }
    
    func resumeTimer() {
        guard !isProjectFinished else { return }
        isPaused = false
        pauseState = .running
        lastUpdateTime = Date()
        lunchBreakStartTime = nil
        startTimer()
        saveState()
        sendHeartbeat() // Update
    }
    
    func handleRFIDScan(for id: String) -> ScanFeedback? {
        guard !isProjectFinished, !isPaused else {
            if isProjectFinished { return .ignoredFinished }
            else if isPaused { return .ignoredPaused }
            return nil
        }
        
        scanCount += 1
        
        let action: ScanAction = workers[id]?.clockInTime != nil ? .clockOut : .clockIn
        let event = ScanEvent(cardID: id, timestamp: Date(), action: action)
        scanHistory.append(event)
        
        if action == .clockOut {
            clockOut(for: id)
            return .clockedOut(id)
        } else {
            clockIn(for: id)
            return .clockedIn(id)
        }
    }
    
    
    
    func clockIn(for id: String) {
        var worker = workers[id] ?? Worker(id: id, clockInTime: nil, totalMinutesWorked: 0)
        if worker.clockInTime == nil {
            worker.clockInTime = Date()
            workers[id] = worker
            recalcTotalPeopleWorking()
            saveState()
            pushStateToCloud()
            sendHeartbeat() // Update
        }
    }
    
    func clockOut(for id: String) {
        guard var worker = workers[id], let clockInTime = worker.clockInTime else { return }
        
        let isManualClockOut = scanHistory.last?.cardID != id
        if isManualClockOut {
            let event = ScanEvent(cardID: id, timestamp: Date(), action: .clockOut)
            scanHistory.append(event)
            scanCount += 1
        }
        
        let timeWorkedInMinutes = Date().timeIntervalSince(clockInTime) / 60
        worker.totalMinutesWorked += timeWorkedInMinutes
        worker.clockInTime = nil
        workers[id] = worker
        recalcTotalPeopleWorking()
        saveState()
        pushStateToCloud()
        sendHeartbeat() // Update
    }
    
    private func recalcTotalPeopleWorking() {
        totalPeopleWorking = workers.values.filter { $0.clockInTime != nil }.count
    }
    
    func resetData() {
        workers = [:]
        recalcTotalPeopleWorking()
        countdownSeconds = 0
        timerText = "00:00:00"
        isCountingDown = false
        isPaused = true
        pauseState = .running
        isProjectFinished = false
        hasUsedLunchBreak = false
        lunchBreakStartTime = nil
        hasPlayedBuzzerAtZero = false
        
        // --- ADD THIS LINE ---
        showManualSetup = false // <--- Exits the wizard and returns to "Waiting"
        // ---------------------
        
        projectName = ""
        companyName = ""
        lineLeaderName = ""
        category = ""
        projectSize = ""
        
        pauseCount = 0
        lunchCount = 0
        scanCount = 0
        
        scanHistory = []
        projectEvents = []
        originalCountdownSeconds = 0
        
        saveState()
        pushStateToCloud()
        sendHeartbeat()
    }
    
    
    // QUEUE
    func saveJobToQueue() {
        guard !projectName.isEmpty, !companyName.isEmpty else { return }
        
        // --- FIX 1: AUTO CLOCK OUT EVERYONE ---
        let now = Date()
        
        // 1. Loop through all active workers
        for id in workers.keys {
            if workers[id]?.clockInTime != nil {
                // A. Calculate their time so far
                if let clockInTime = workers[id]?.clockInTime {
                    let timeWorkedInMinutes = now.timeIntervalSince(clockInTime) / 60
                    workers[id]?.totalMinutesWorked += timeWorkedInMinutes
                    workers[id]?.clockInTime = nil // clear local clock in
                }
                
                // B. Add a "System Clock Out" event to the log
                // We use the same ID so the history looks clean
                let event = ScanEvent(cardID: id, timestamp: now, action: .clockOut)
                scanHistory.append(event)
                scanCount += 1
            }
        }
        
        // 2. Update the "People Working" counter to 0
        totalPeopleWorking = 0
        // --------------------------------------
        
        projectEvents.append(ProjectEvent(timestamp: Date(), type: .save))
        
        
        let item = ProjectQueueItem(
                company: companyName,
                project: projectName,
                category: category,
                size: projectSize,
                seconds: countdownSeconds,
                originalSeconds: originalCountdownSeconds,
                lineLeaderName: lineLeaderName,
                createdAt: Date(),
                scanHistory: scanHistory,
                projectEvents: projectEvents // <--- This now includes the .save event
            )
        
        do {
                try db.collection("project_queue").addDocument(from: item)
                // resetData() // (Keep your existing reset logic)
                resetData()
            } catch {
                print("Error saving to queue: \(error)")
            }
    }
    
    // --- Persistence and Settings Loading (Keep your existing helpers) ---
    // (I'm condensing these to save space, but keep your full implementation of saveState/loadState)
    public func saveState() {
        let storage = AppStateStorageManager.shared

        storage.save(workers, forKey: "savedWorkers")
        storage.save(scanHistory, forKey: "scanHistory")
        storage.save(projectEvents, forKey: "projectEvents")
        storage.save(pauseState, forKey: "pauseState")

        storage.save(originalCountdownSeconds, forKey: "originalCountdownSeconds")
        storage.save(countdownSeconds, forKey: "countdownSeconds")
        storage.save(isPaused, forKey: "isPaused")
        storage.save(isCountingDown, forKey: "isCountingDown")
        storage.save(isProjectFinished, forKey: "isProjectFinished")
        storage.save(hasUsedLunchBreak, forKey: "hasUsedLunchBreak")
        storage.save((lunchBreakStartTime ?? Date()) as Date, forKey: "lunchBreakStartTime")
        storage.save(hasPlayedBuzzerAtZero, forKey: "hasPlayedBuzzerAtZero")

        storage.save(projectName, forKey: "projectName")
        storage.save(companyName, forKey: "companyName")
        storage.save(lineLeaderName, forKey: "lineLeaderName")
        storage.save(category, forKey: "category")
        storage.save(projectSize, forKey: "projectSize")

        storage.save(pauseCount, forKey: "pauseCount")
        storage.save(lunchCount, forKey: "lunchCount")
        storage.save(scanCount, forKey: "scanCount")
    }

    
    private func loadState() {
        let storage = AppStateStorageManager.shared

        workers = storage.load([String: Worker].self, forKey: "savedWorkers") ?? [:]
        scanHistory = storage.load([ScanEvent].self, forKey: "scanHistory") ?? []
        projectEvents = storage.load([ProjectEvent].self, forKey: "projectEvents") ?? []

        pauseState = storage.load(PauseType.self, forKey: "pauseState") ?? .running

        originalCountdownSeconds = storage.loadInt(forKey: "originalCountdownSeconds")
        countdownSeconds = storage.loadInt(forKey: "countdownSeconds")

        isPaused = storage.loadBool(forKey: "isPaused")
        isCountingDown = storage.loadBool(forKey: "isCountingDown")
        isProjectFinished = storage.loadBool(forKey: "isProjectFinished")

        hasUsedLunchBreak = storage.loadBool(forKey: "hasUsedLunchBreak")
        lunchBreakStartTime = storage.loadDate(forKey: "lunchBreakStartTime")
        hasPlayedBuzzerAtZero = storage.loadBool(forKey: "hasPlayedBuzzerAtZero")

        projectName = storage.loadString(forKey: "projectName")
        companyName = storage.loadString(forKey: "companyName")
        lineLeaderName = storage.loadString(forKey: "lineLeaderName")
        category = storage.loadString(forKey: "category")
        projectSize = storage.loadString(forKey: "projectSize")

        pauseCount = storage.loadInt(forKey: "pauseCount")
        lunchCount = storage.loadInt(forKey: "lunchCount")
        scanCount = storage.loadInt(forKey: "scanCount")

        recalcTotalPeopleWorking()

        if isCountingDown || isProjectFinished {
            startTimer()
            updateCountdownTime()
        }
    }

    
    func saveCustomAppSettings() {
        if let e = try? JSONEncoder().encode(lunchPeriods) { UserDefaults.standard.set(e, forKey: "lunchPeriods") }
        if let e = try? JSONEncoder().encode(shiftStartTimes) { UserDefaults.standard.set(e, forKey: "shiftStartTimes") }
        if let e = try? JSONEncoder().encode(categories) { UserDefaults.standard.set(e, forKey: "categories") }
        if let e = try? JSONEncoder().encode(projectSizes) { UserDefaults.standard.set(e, forKey: "projectSizes") }
    }
    
    private func loadCustomAppSettings() {
        let storage = AppStateStorageManager.shared

        lunchPeriods = storage.load([TimePeriod].self, forKey: "lunchPeriods")
            ?? [
                TimePeriod(start: dateFrom(11, 30), end: dateFrom(12, 0)),
                TimePeriod(start: dateFrom(18, 30), end: dateFrom(19, 0)),
                TimePeriod(start: dateFrom(3, 0),  end: dateFrom(3, 30))
            ]

        shiftStartTimes = storage.load([ShiftTime].self, forKey: "shiftStartTimes")
            ?? [
                ShiftTime(time: dateFrom(6, 0)),
                ShiftTime(time: dateFrom(14, 0)),
                ShiftTime(time: dateFrom(22, 0))
            ]

        categories = storage.load([EditableStringItem].self, forKey: "categories")
            ?? ["Fragrance", "Skin Care", "Kitting", "VOC"]
                .map { EditableStringItem(value: $0) }

        projectSizes = storage.load([EditableStringItem].self, forKey: "projectSizes")
            ?? ["100ML", "50ML", "30ML", "15ML", "10ML", "7.5ML", "1.75ML", "4oz", "8oz", "other"]
                .map { EditableStringItem(value: $0) }
    }

    
    func dateFrom(_ h:Int, _ m:Int) -> Date { Calendar.current.date(from: DateComponents(hour:h, minute:m)) ?? Date() }
    
    private func setInitialDefaultSettings() { /* Keep your existing code here */ }
    
    // --- Helper to get Real Name ---
    func getWorkerName(id: String) -> String {
        return workerNameCache[id] ?? "ID: \(id)"
    }
}

//MARK: FIREBASE
extension WorkerViewModel {
    // MARK: - FIREBASE LOGIC

    func fetchWorkerNames() {
        // Use FirebaseManager helper instead of raw Firestore
        FirebaseManager.shared.listenToWorkers { [weak self] workersDict in
            guard let self else { return }
            DispatchQueue.main.async {
                // Update workerNameCache safely
                self.workerNameCache = workersDict
            }
        }
    }

    func fetchProjectQueue() {
        FirebaseManager.shared.listenToProjectQueue { [weak self] items in
            guard let self else { return }
            DispatchQueue.main.async {
                self.projectQueue = items
            }
        }
    }

    func fetchDropdownOptions() {
        FirebaseManager.shared.listenToProjectOptions { [weak self] categories, sizes in
            guard let self else { return }
            DispatchQueue.main.async {
                self.availableCategories = categories
                self.availableSizes = sizes
            }
        }
    }

    func connectToFleet() {
        guard !fleetIpadID.isEmpty else { return }
        
        FirebaseManager.shared.connectToFleet(fleetId: fleetIpadID) { [weak self] data in
            guard let self else { return }
            DispatchQueue.main.async {
                
                // 1. Auto-Restore
                self.restoreFromCloud(data: data)
                
                // 2. Sync Basic Settings
                if let val = data["companyName"] as? String { self.companyName = val }
                if let val = data["projectName"] as? String { self.projectName = val }
                if let val = data["category"] as? String { self.category = val }
                if let val = data["projectSize"] as? String { self.projectSize = val }
                if let val = data["lineLeaderName"] as? String { self.lineLeaderName = val }
                
                // 3. RESTORE LOGS
                var logsUpdated = false
                
                if let histArray = data["scanHistory"] as? [[String: Any]] {
                    var loadedHistory: [ScanEvent] = []
                    for dict in histArray {
                        if let cardID = dict["cardID"] as? String,
                           let rawAction = dict["action"] as? String,
                           let stamp = (dict["timestamp"] as? Timestamp)?.dateValue(),
                           let action = ScanAction(rawValue: rawAction) {
                            loadedHistory.append(ScanEvent(cardID: cardID, timestamp: stamp, action: action))
                        }
                    }
                    if self.scanHistory.isEmpty && !loadedHistory.isEmpty {
                        self.scanHistory = loadedHistory
                        self.scanCount = loadedHistory.count
                        logsUpdated = true
                    }
                }
                
                if let eventArray = data["projectEvents"] as? [[String: Any]] {
                    var loadedEvents: [ProjectEvent] = []
                    for dict in eventArray {
                        if let rawType = dict["type"] as? String,
                           let stamp = (dict["timestamp"] as? Timestamp)?.dateValue(),
                           let type = ProjectEventType(rawValue: rawType) {
                            loadedEvents.append(ProjectEvent(timestamp: stamp, type: type))
                        }
                    }
                    if self.projectEvents.isEmpty && !loadedEvents.isEmpty {
                        self.projectEvents = loadedEvents
                        self.pauseCount = loadedEvents.filter { $0.type == .pause }.count
                        self.lunchCount = loadedEvents.filter { $0.type == .lunch }.count
                    }
                }
                
                // --- NEW: RECALCULATE HOURS ---
                // If we just loaded fresh logs from the cloud, rebuild the worker stats
                if logsUpdated {
                    self.reconstructStateFromLogs()
                }
                // ------------------------------
                
                // 4. Handle Commands
                if let cmd = data["remoteCommand"] as? String,
                   let stamp = (data["commandTimestamp"] as? Timestamp)?.dateValue() {
                    
                    if self.lastCommandTimestamp == nil {
                        if abs(Date().timeIntervalSince(stamp)) < 60 {
                            self.lastCommandTimestamp = stamp
                            self.handleRemoteCommand(cmd)
                        } else {
                            self.lastCommandTimestamp = stamp
                        }
                    } else if stamp > self.lastCommandTimestamp! {
                        self.lastCommandTimestamp = stamp
                        self.handleRemoteCommand(cmd)
                    }
                }
                
                // 5. Sync Original Time
                if let trueOriginal = data["originalSeconds"] as? Int, trueOriginal > 0 {
                    // Only accept cloud time if we are NOT currently running a job
                    // This protects us if the cloud is stale/wrong while we are working.
                    if self.countdownSeconds == 0 {
                        if self.originalCountdownSeconds != trueOriginal {
                            self.originalCountdownSeconds = trueOriginal
                        }
                    }
                }                }
        }
    }

    func pushStateToCloud() {
        guard !fleetIpadID.isEmpty else { return }

        let activeWorkerIDs = workers.values
            .filter { $0.clockInTime != nil }
            .map { $0.id }

        let payload: [String: Any] = [
            "isPaused": isPaused,
            "secondsRemaining": countdownSeconds,
            "activeWorkers": activeWorkerIDs,
            "timerText": timerText,
            "workerCount": totalPeopleWorking,
            "companyName": companyName,
            "projectName": projectName,
            "lineLeaderName": lineLeaderName,
            "category": category,
            "projectSize": projectSize,
            "scanHistory": scanHistory.map {
                ["cardID": $0.cardID, "action": $0.action.rawValue, "timestamp": $0.timestamp]
            },
            "projectEvents": projectEvents.map {
                ["type": $0.type.rawValue, "timestamp": $0.timestamp]
            }
        ]

        FirebaseManager.shared.pushFleetState(fleetId: fleetIpadID, data: payload)
    }

    func saveFinalReportToFirestore() {
        let workerLog = workers.values.map {
            ["id": $0.id, "name": getWorkerName(id: $0.id), "minutes": $0.totalMinutesWorked]
        }

        let report: [String: Any] = [
            "company": companyName,
            "project": projectName,
            "leader": lineLeaderName,
            "category": category,
            "size": projectSize,
            "workerLog": workerLog,
            "completedAt": FieldValue.serverTimestamp(),
            "bonusStatus": "unpaid"
        ]

        FirebaseManager.shared.saveFinalReport(report)
    }

}
