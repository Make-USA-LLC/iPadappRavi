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
class WorkerViewModel: ObservableObject {
    // --- FIREBASE SYNC ---
    private var db = Firestore.firestore()
    private var listener: ListenerRegistration?
    private var lastCommandTimestamp: Date?
    
    // --- Cloud Sync Throttle ---
    private var lastCloudPushTime: Date = Date.distantPast
    private let cloudPushInterval: TimeInterval = 5.0
    
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
    
    // --- BONUS LOGIC ---
    @Published var isBonusEligible: Bool = true
    @Published var bonusIneligibleReason: String = ""
    
    // --- CODES ---
    @AppStorage("qcCode") var qcCode: String = "0340"
    @AppStorage("techCode") var techCode: String = "6253"
    
    private var timer: Timer?
    public var countdownSeconds: Int = 0
    @Published var originalCountdownSeconds: Int = 0
    
    // --- NEW: Dynamic Data ---
    @Published var projectQueue: [ProjectQueueItem] = []
    @Published var availableCategories: [String] = [ "Fragrance", "Skin Care", "Kitting", "VOC" ]
    @Published var availableSizes: [String] = [ "100ML", "50ML", "30ML", "15ML", "10ML", "7.5ML", "1.75ML", "4oz", "8oz", "other" ]
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
    @Published var techIssueLine: String = ""
    
    //Lines
    @Published var availableLines: [String] = []
    @Published var techLineName: String = ""
    
    init() {
        loadState()
        loadCustomAppSettings()
        self.fetchLines()
        FirebaseManager.shared.observeAuthState { [weak self] _ in
            guard let self else { return }
            self.startTimer()
            FirebaseManager.shared.listenToWorkers { self.workerNameCache = $0 }
            FirebaseManager.shared.listenToProjectQueue { self.projectQueue = $0 }
            FirebaseManager.shared.listenToProjectOptions { categories, sizes in
                self.availableCategories = categories
                self.availableSizes = sizes
            }
            if !self.fleetIpadID.isEmpty { self.connectToFleet() }
        }
    }
    
    // MARK: - Admin Functions
    func updateWorkerTotalTime(id: String, newTotalMinutes: Double) {
        print("🛠️ Updating Worker: \(id). New Total: \(newTotalMinutes)")
        
        guard var worker = workers[id] else {
            print("❌ Worker ID \(id) not found in active workers list.")
            return
        }
        
        let oldMinutes = worker.totalMinutesWorked
        let differenceInMinutes = newTotalMinutes - oldMinutes
        let differenceInSeconds = Int(differenceInMinutes * 60)
        
        worker.totalMinutesWorked = newTotalMinutes
        workers[id] = worker
        
        countdownSeconds -= differenceInSeconds
        
        // Ensure bonus logic triggers safely with a small tolerance
        if abs(differenceInMinutes) > 0.01 {
            isBonusEligible = false
            bonusIneligibleReason = "Worker hours manually edited"
        }
        
        saveState()
        pushStateToCloud(force: true)
    }
    
    func cancelBonus() {
        print("🚫 Manually cancelling bonus")
        isBonusEligible = false
        bonusIneligibleReason = "Manually cancelled by admin"
        saveState()
        pushStateToCloud(force: true)
    }
    
    func reconstructStateFromLogs() {
        print("🔄 Reconstructing worker hours from history logs...")
        var rebuiltWorkers: [String: Worker] = [:]
        let sortedHistory = scanHistory.sorted { $0.timestamp < $1.timestamp }
        
        for event in sortedHistory {
            let id = event.cardID
            var worker = rebuiltWorkers[id] ?? Worker(id: id, clockInTime: nil, totalMinutesWorked: 0)
            
            if event.action == .clockIn {
                worker.clockInTime = event.timestamp
            } else if event.action == .clockOut {
                if let start = worker.clockInTime {
                    let minutes = event.timestamp.timeIntervalSince(start) / 60
                    worker.totalMinutesWorked += minutes
                }
                worker.clockInTime = nil
            }
            rebuiltWorkers[id] = worker
        }
        self.workers = rebuiltWorkers
        self.recalcTotalPeopleWorking()
    }

    private func clearRemoteCommand() {
        guard !fleetIpadID.isEmpty else { return }
        FirebaseManager.shared.pushFleetState(fleetId: fleetIpadID, data: ["remoteCommand": ""])
    }

    func restoreFromCloud(data: [String: Any]) {
        guard countdownSeconds == 0 && workers.isEmpty && projectName.isEmpty else { return }
        guard let seconds = data["secondsRemaining"] as? Int, seconds > 0 else { return }
        
        if let val = data["companyName"] as? String { self.companyName = val }
        if let val = data["projectName"] as? String { self.projectName = val }
        if let val = data["lineLeaderName"] as? String { self.lineLeaderName = val }
        if let val = data["category"] as? String { self.category = val }
        if let val = data["projectSize"] as? String { self.projectSize = val }
        
        if let val = data["isBonusEligible"] as? Bool { self.isBonusEligible = val }
        if let val = data["bonusIneligibleReason"] as? String { self.bonusIneligibleReason = val }
        
        self.countdownSeconds = seconds
        self.originalCountdownSeconds = seconds
        self.isCountingDown = false
        self.isPaused = true
        self.timerText = "Resumed: Press Start"
        
        if let activeIDs = data["activeWorkers"] as? [String] {
            for id in activeIDs {
                self.workers[id] = Worker(id: id, clockInTime: Date(), totalMinutesWorked: 0)
            }
            self.totalPeopleWorking = activeIDs.count
        }
    }
    
    // MARK: - REMOTE COMMANDS
    func handleRemoteCommand(_ command: String) {
        print("📡 Received Remote Command: \(command)")
        
        let parts = command.split(separator: "|", omittingEmptySubsequences: false)
        guard let action = parts.first.map(String.init) else { return }

        switch action {
        case "PRELOAD":
            let cleanParts = command.split(separator: "|", omittingEmptySubsequences: true)
            handlePreloadCommand(cleanParts)
            
        case "TOGGLE":
            if isPaused { resumeTimer() } else { _ = pauseTimer(password: "REMOTE_OVERRIDE") }
            
        case "LUNCH":
            _ = takeLunchBreak()
            
        case "SAVE":
            saveJobToQueue()
            
        case "RESET":
            let cleanParts = command.split(separator: "|", omittingEmptySubsequences: true)
            cleanParts.count > 1 ? handleSetTime(cleanParts) : resetData()
            
        case "SET_TIME":
            let cleanParts = command.split(separator: "|", omittingEmptySubsequences: true)
            handleSetTime(cleanParts)
            
        case "FINISH":
            shouldTriggerFinishFlow = true
            
        case "CLOCK_OUT":
            if parts.count > 1 {
                let id = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
                clockOut(for: id)
            }
            
        // --- UPDATED: ROBUST EDIT PARSING ---
        case "EDIT_WORKER":
            if parts.count > 2 {
                let rawId = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
                let rawMins = String(parts[2]).trimmingCharacters(in: .whitespacesAndNewlines)
                if let minutes = Double(rawMins) {
                    updateWorkerTotalTime(id: rawId, newTotalMinutes: minutes)
                }
            }
        // ------------------------------------
            
        case "CANCEL_BONUS":
            cancelBonus()
            
        case "QC_PAUSE_CREW":
            _ = toggleQCPause(type: .qcCrew, code: "REMOTE_OVERRIDE")
            
        case "QC_PAUSE_COMP":
            _ = toggleQCPause(type: .qcComponent, code: "REMOTE_OVERRIDE")
            
        case "TECH_PAUSE":
            // 1. Check if there is a line name attached (e.g., "TECH_PAUSE|Line 1")
                        var lineParam: String? = nil
                        if parts.count > 1 {
                            lineParam = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                        
                        // 2. Pass the line to the toggle function
                        _ = toggleTechPause(code: "REMOTE_OVERRIDE", line: lineParam)

        default: break
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
            projectEvents: projectEvents,
            isBonusEligible: true,
            bonusIneligibleReason: ""
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
        guard timeParts.count == 3, let h = Int(timeParts[0]), let m = Int(timeParts[1]), let s = Int(timeParts[2]) else { return nil }
        return (h, m, s)
    }
    
    func sendHeartbeat(force: Bool = false) {
        pushStateToCloud(force: force)
    }
    
    // MARK: - PAUSE LOGIC
    func pauseTimer(password: String) -> Bool {
        if password == "REMOTE_OVERRIDE" || password == UserDefaults.standard.string(forKey: AppStorageKeys.pausePassword) ?? "340340" {
            isPaused = true
            pauseState = .manual
            pauseCount += 1
            projectEvents.append(ProjectEvent(timestamp: Date(), type: .pause))
            saveState()
            pushStateToCloud(force: true)
            return true
        }
        return false
    }
    
    func toggleQCPause(type: PauseType, code: String) -> Bool {
            guard code == qcCode || code == "REMOTE_OVERRIDE" else { return false }
            
            if isPaused && pauseState == type {
                pauseState = .running
                resumeTimer()
                return true
            }
            
            isPaused = true
            pauseState = type
            if type == .qcCrew {
                isBonusEligible = false
                bonusIneligibleReason = "QC Pause: Crew Oversight"
            }
            
            // --- CHANGED: Log specific QC type ---
            let eventType: ProjectEventType = (type == .qcCrew) ? .qcCrew : .qcComponent
            projectEvents.append(ProjectEvent(timestamp: Date(), type: eventType))
            // -------------------------------------
            
            saveState()
            pushStateToCloud(force: true)
            return true
        }

    func toggleTechPause(code: String, line: String? = nil) -> Bool {
            guard code == techCode || code == "REMOTE_OVERRIDE" else { return false }
            
            if isPaused && pauseState == .technician {
                resumeTimer()
                return true
            }
            
            isPaused = true
            pauseState = .technician
            
            // Update the transient state for the UI
            if let l = line {
                self.techIssueLine = l
            }
            
            // --- CHANGED: Store the line name in the event history ---
            projectEvents.append(ProjectEvent(timestamp: Date(), type: .technician, value: line))
            // ---------------------------------------------------------
            
            saveState()
            pushStateToCloud(force: true)
            return true
        }
    
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
        
        guard pauseState != .manual && pauseState != .autoLunch else { return .ignoredPaused }
        guard totalPeopleWorking > 0 else { return .ignoredNoWorkers }
        
        isPaused = true
        pauseState = .manualLunch
        hasUsedLunchBreak = true
        lunchBreakStartTime = Date()
        lunchCount += 1
        
        projectEvents.append(ProjectEvent(timestamp: Date(), type: .lunch))
        saveState()
        pushStateToCloud(force: true)
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
        pushStateToCloud(force: true)
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
        guard !isProjectFinished else { return }
        isProjectFinished = true // Immediate Lock

        AudioPlayerManager.shared.playSound(named: "Cashier")
        
        isPaused = true
        isCountingDown = false
        timer?.invalidate()
        let now = Date()
        
        for id in workers.keys {
            if let clockInTime = workers[id]?.clockInTime {
                let timeWorkedInMinutes = now.timeIntervalSince(clockInTime) / 60
                workers[id]?.totalMinutesWorked += timeWorkedInMinutes
                let event = ScanEvent(cardID: id, timestamp: now, action: .clockOut)
                scanHistory.append(event)
            }
        }
        
        hasUsedLunchBreak = false
        lunchBreakStartTime = nil
        
        saveFinalReportToFirestore()
        saveState()
        pushStateToCloud(force: true)
        sendHeartbeat(force: true)
    }
    
    private func updateCountdownTime() {
        guard isCountingDown else { return }
        
        if self.pauseState == .manualLunch, let breakStart = lunchBreakStartTime {
            if Date().timeIntervalSince(breakStart) >= 1800 { resumeTimer() }
        } else if self.pauseState == .autoLunch {
            if !isCurrentlyInLunchWindow() { resumeTimer() }
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
        
        saveState()
        pushStateToCloud(force: false)
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
        pushStateToCloud(force: true)
    }
    
    func resumeTimer() {
        guard !isProjectFinished else { return }
        
        // --- PREVENT UNAUTHORIZED RESUME ---
        // QC Pauses must be unpaused via the specific toggle functions (with code)
        if pauseState == .qcCrew || pauseState == .qcComponent { return }
        
        isPaused = false
        pauseState = .running
        lastUpdateTime = Date()
        lunchBreakStartTime = nil
        startTimer()
        saveState()
        pushStateToCloud(force: true)
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
    
    // Inside WorkerViewModel

    func fetchLines() {
        print("🔍 STARTING FETCH: Attempting to fetch from collection 'lines'...")
        
        db.collection("lines").addSnapshotListener { [weak self] snapshot, error in
            // 1. Check for basic connection errors
            if let error = error {
                print("❌ CRITICAL ERROR: Could not fetch lines. Reason: \(error.localizedDescription)")
                return
            }
            
            // 2. Check if snapshot exists and is empty
            guard let documents = snapshot?.documents else {
                print("⚠️ WARNING: Snapshot is nil (No data found).")
                return
            }
            
            print("✅ CONNECTION SUCCESS: Found \(documents.count) documents in 'lines'.")
            
            // 3. Check the actual data inside
            for doc in documents {
                print("   - Doc ID: \(doc.documentID), Data: \(doc.data())")
            }
            
            // 4. Attempt mapping
            let lines = documents.compactMap { doc -> String? in
                let name = doc.data()["name"] as? String
                if name == nil {
                    print("   ⚠️ WARNING: Document \(doc.documentID) is missing field 'name' or it is not a String.")
                }
                return name
            }
            
            print("📊 FINAL COUNT: Successfully mapped \(lines.count) lines: \(lines)")
            
            DispatchQueue.main.async {
                self?.availableLines = lines.sorted()
            }
        }
    }
    func clockIn(for id: String) {
        var worker = workers[id] ?? Worker(id: id, clockInTime: nil, totalMinutesWorked: 0)
        if worker.clockInTime == nil {
            worker.clockInTime = Date()
            workers[id] = worker
            recalcTotalPeopleWorking()
            saveState()
            pushStateToCloud(force: true)
        }
    }
    
    func clockOut(for id: String) {
        guard var worker = workers[id], let clockInTime = worker.clockInTime else { return }
        if scanHistory.last?.cardID != id {
            scanHistory.append(ScanEvent(cardID: id, timestamp: Date(), action: .clockOut))
            scanCount += 1
        }
        worker.totalMinutesWorked += Date().timeIntervalSince(clockInTime) / 60
        worker.clockInTime = nil
        workers[id] = worker
        recalcTotalPeopleWorking()
        saveState()
        pushStateToCloud(force: true)
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
        showManualSetup = false
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
        isBonusEligible = true
        bonusIneligibleReason = ""
        saveState()
        pushStateToCloud(force: true)
    }
    
    func saveJobToQueue() {
        guard !projectName.isEmpty, !companyName.isEmpty else { return }
        
        let now = Date()
        for id in workers.keys {
            if workers[id]?.clockInTime != nil {
                if let clockInTime = workers[id]?.clockInTime {
                    workers[id]?.totalMinutesWorked += now.timeIntervalSince(clockInTime) / 60
                    workers[id]?.clockInTime = nil
                }
                scanHistory.append(ScanEvent(cardID: id, timestamp: now, action: .clockOut))
                scanCount += 1
            }
        }
        totalPeopleWorking = 0
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
                projectEvents: projectEvents,
                isBonusEligible: isBonusEligible,
                bonusIneligibleReason: bonusIneligibleReason
            )
        
        do {
            try db.collection("project_queue").addDocument(from: item)
            resetData()
        } catch {
            print("Error saving to queue: \(error)")
        }
    }
    
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
        storage.save(isBonusEligible, forKey: "isBonusEligible")
        storage.save(bonusIneligibleReason, forKey: "bonusIneligibleReason")
        storage.save(lastCommandTimestamp ?? Date(), forKey: "lastCommandTimestamp")
        
    }

    private func loadState() {
        let storage = AppStateStorageManager.shared
        lastCommandTimestamp = storage.loadDate(forKey: "lastCommandTimestamp") ?? Date()
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
        isBonusEligible = storage.loadBool(forKey: "isBonusEligible")
        bonusIneligibleReason = storage.loadString(forKey: "bonusIneligibleReason")
        recalcTotalPeopleWorking()
        if isCountingDown || isProjectFinished {
            startTimer()
            updateCountdownTime()
        }
    }
    
    // --- (Keeping existing fetch methods) ---
    func fetchWorkerNames() { FirebaseManager.shared.listenToWorkers { [weak self] in self?.workerNameCache = $0 } }
    func fetchProjectQueue() { FirebaseManager.shared.listenToProjectQueue { [weak self] in self?.projectQueue = $0 } }
    func fetchDropdownOptions() { FirebaseManager.shared.listenToProjectOptions { [weak self] c, s in self?.availableCategories = c; self?.availableSizes = s } }
    
    func connectToFleet() {
        guard !fleetIpadID.isEmpty else { return }
        FirebaseManager.shared.connectToFleet(fleetId: fleetIpadID) { [weak self] data in
            guard let self else { return }
            DispatchQueue.main.async {
                self.restoreFromCloud(data: data)
                
                if let val = data["companyName"] as? String, !val.isEmpty { self.companyName = val }
                if let val = data["projectName"] as? String, !val.isEmpty { self.projectName = val }
                if let val = data["category"] as? String { self.category = val }
                if let val = data["projectSize"] as? String { self.projectSize = val }
                if let val = data["lineLeaderName"] as? String, !val.isEmpty { self.lineLeaderName = val }
                
                if let val = data["isBonusEligible"] as? Bool { if self.isBonusEligible != val { self.isBonusEligible = val } }
                if let val = data["bonusIneligibleReason"] as? String { self.bonusIneligibleReason = val }

                var logsUpdated = false
                if let histArray = data["scanHistory"] as? [[String: Any]] {
                    var loadedHistory: [ScanEvent] = []
                    for dict in histArray {
                        if let cardID = dict["cardID"] as? String, let rawAction = dict["action"] as? String, let stamp = (dict["timestamp"] as? Timestamp)?.dateValue(), let action = ScanAction(rawValue: rawAction) {
                            loadedHistory.append(ScanEvent(cardID: cardID, timestamp: stamp, action: action))
                        }
                    }
                    if self.scanHistory.isEmpty && !loadedHistory.isEmpty { self.scanHistory = loadedHistory; self.scanCount = loadedHistory.count; logsUpdated = true }
                }
                
                if let eventArray = data["projectEvents"] as? [[String: Any]] {
                    var loadedEvents: [ProjectEvent] = []
                    for dict in eventArray {
                        if let rawType = dict["type"] as? String, let stamp = (dict["timestamp"] as? Timestamp)?.dateValue(), let type = ProjectEventType(rawValue: rawType) {
                            loadedEvents.append(ProjectEvent(timestamp: stamp, type: type))
                        }
                    }
                    if self.projectEvents.isEmpty && !loadedEvents.isEmpty { self.projectEvents = loadedEvents; self.pauseCount = loadedEvents.filter { $0.type == .pause }.count; self.lunchCount = loadedEvents.filter { $0.type == .lunch }.count }
                }
                
                if logsUpdated { self.reconstructStateFromLogs() }
                
                if let cmd = data["remoteCommand"] as? String, let stamp = (data["commandTimestamp"] as? Timestamp)?.dateValue() {
                    if self.lastCommandTimestamp == nil || stamp > self.lastCommandTimestamp! {
                        self.lastCommandTimestamp = stamp
                        self.handleRemoteCommand(cmd)
                    }
                }
                
                if let trueOriginal = data["originalSeconds"] as? Int, trueOriginal > 0 {
                    if self.countdownSeconds == 0 && self.originalCountdownSeconds != trueOriginal {
                        self.originalCountdownSeconds = trueOriginal
                    }
                }
            }
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
        lunchPeriods = storage.load([TimePeriod].self, forKey: "lunchPeriods") ?? [TimePeriod(start: dateFrom(11, 30), end: dateFrom(12, 0)), TimePeriod(start: dateFrom(18, 30), end: dateFrom(19, 0)), TimePeriod(start: dateFrom(3, 0),  end: dateFrom(3, 30))]
        shiftStartTimes = storage.load([ShiftTime].self, forKey: "shiftStartTimes") ?? [ShiftTime(time: dateFrom(6, 0)), ShiftTime(time: dateFrom(14, 0)), ShiftTime(time: dateFrom(22, 0))]
        categories = storage.load([EditableStringItem].self, forKey: "categories") ?? ["Fragrance", "Skin Care", "Kitting", "VOC"].map { EditableStringItem(value: $0) }
        projectSizes = storage.load([EditableStringItem].self, forKey: "projectSizes") ?? ["100ML", "50ML", "30ML", "15ML", "10ML", "7.5ML", "1.75ML", "4oz", "8oz", "other"].map { EditableStringItem(value: $0) }
    }
    func dateFrom(_ h:Int, _ m:Int) -> Date { Calendar.current.date(from: DateComponents(hour:h, minute:m)) ?? Date() }
    func getWorkerName(id: String) -> String { return workerNameCache[id] ?? "ID: \(id)" }
    
    // --- UPDATED PUSH LOGIC ---
    func pushStateToCloud(force: Bool = false) {
            guard !fleetIpadID.isEmpty else { return }
            
            let now = Date()
            if !force {
                if now.timeIntervalSince(lastCloudPushTime) < cloudPushInterval { return }
            }
            lastCloudPushTime = now

            let activeWorkerIDs = workers.values.filter { $0.clockInTime != nil }.map { $0.id }

            var payload: [String: Any] = [
                "isPaused": isPaused,
                "secondsRemaining": countdownSeconds,
                "lastUpdateTime": FieldValue.serverTimestamp(),
                "activeWorkers": activeWorkerIDs,
                "timerText": timerText,
                "workerCount": totalPeopleWorking,
                "companyName": companyName,
                "projectName": projectName,
                "lineLeaderName": lineLeaderName,
                "category": category,
                "projectSize": projectSize,
                "isBonusEligible": isBonusEligible,
                "bonusIneligibleReason": bonusIneligibleReason,
                "techIssueLine": techIssueLine, // <--- ADD THIS
                "scanHistory": scanHistory.map { ["cardID": $0.cardID, "action": $0.action.rawValue, "timestamp": $0.timestamp] },
                "projectEvents": projectEvents.map { ["type": $0.type.rawValue, "timestamp": $0.timestamp] }
            ]
            
            if originalCountdownSeconds > 0 {
                if companyName.isEmpty { payload.removeValue(forKey: "companyName") }
                if projectName.isEmpty { payload.removeValue(forKey: "projectName") }
                if lineLeaderName.isEmpty { payload.removeValue(forKey: "lineLeaderName") }
            }
            
            FirebaseManager.shared.pushFleetState(fleetId: fleetIpadID, data: payload)
        }
    
    func saveFinalReportToFirestore() {
            let workerLog = workers.values.map { ["id": $0.id, "name": getWorkerName(id: $0.id), "minutes": $0.totalMinutesWorked] }

            // --- SAFE MAPPING ---
            // We convert the struct array into a Dictionary array [[String: Any]]
            let eventLog = projectEvents.map { event -> [String: Any] in
                return [
                    "type": event.type.rawValue,
                    "timestamp": event.timestamp,
                    "value": event.value ?? "" // Handle nil values safely
                ]
            }
            
            let report: [String: Any] = [
                "company": companyName,
                "project": projectName,
                "leader": lineLeaderName,
                "category": category,
                "size": projectSize,
                
                "originalSeconds": originalCountdownSeconds,
                "finalSeconds": countdownSeconds,
                
                "workerLog": workerLog,
                "eventLog": eventLog, // <--- Pass the mapped dictionary, NOT the struct array
                
                "completedAt": FieldValue.serverTimestamp(),
                "bonusEligible": isBonusEligible,
                "bonusIneligibleReason": isBonusEligible ? "" : (bonusIneligibleReason.isEmpty ? "One or More employees did not properly clock in" : bonusIneligibleReason)
            ]
            
            FirebaseManager.shared.saveFinalReport(report)
        }
}
