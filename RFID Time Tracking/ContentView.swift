import SwiftUI
import Combine
import AVFoundation
import FirebaseFirestore
import FirebaseCore
import FirebaseAuth

let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"

// MARK: - App Storage Keys
struct AppStorageKeys {
    // --- Passwords ---
    static let pausePassword = "pausePassword"
    static let resetPassword = "resetPassword"
    static let qcPassword = "qcPassword" // <--- NEW KEY
    
    // --- Email Toggles ---
    static let enableSmtpEmail = "enableSmtpEmail"
    static let includeScanHistory = "includeScanHistory"
    static let includeWorkerList = "includeWorkerList"
    static let includePauseLog = "includePauseLog"
    static let includeLunchLog = "includeLunchLog"
    static let includeLineLeader = "includeLineLeader"
    
    static let smtpRecipient = "smtpRecipient"
    static let smtpHost = "smtpHost"
    static let smtpUsername = "smtpUsername"
    static let smtpPassword = "smtpPassword"
    static let fleetIpadID = "fleetIpadID"
    
    // --- Email Content Toggles ---
    static let includeTimeRemaining = "includeTimeRemaining"
    static let includeClockedInWorkers = "includeClockedInWorkers"
    static let includeTotalTimeWorked = "includeTotalTimeWorked"
    static let includeProjectName = "includeProjectName"
    static let includeCompanyName = "includeCompanyName"
    static let includePauseCount = "includePauseCount"
    static let includeLunchCount = "includeLunchCount"
    static let includeScanCount = "includeScanCount"
    
    // --- NEW KEYS ---
    static let includeCategory = "includeCategory"
    static let includeProjectSize = "includeProjectSize"
}

// MARK: - Models & Settings Structs
struct TimePeriod: Codable, Identifiable, Hashable {
    var id = UUID()
    var start: Date
    var end: Date
}

struct ShiftTime: Codable, Identifiable, Hashable {
    var id = UUID()
    var time: Date
}

struct EditableStringItem: Codable, Identifiable, Hashable {
    var id = UUID()
    var value: String
}

struct Worker: Codable {
    let id: String
    var clockInTime: Date?
    var totalMinutesWorked: TimeInterval
}

struct ProjectQueueItem: Codable, Identifiable, Equatable {
    @DocumentID var id: String?
    var company: String
    var project: String
    var category: String
    var size: String
    var seconds: Int
    var originalSeconds: Int?
    var lineLeaderName: String?
    var createdAt: Date?
    
    var scanHistory: [ScanEvent]?
    var projectEvents: [ProjectEvent]?
    
    static func == (lhs: ProjectQueueItem, rhs: ProjectQueueItem) -> Bool {
        return lhs.id == rhs.id
    }
}

struct ProjectOptionsConfig: Codable {
    var categories: [String]
    var sizes: [String]
}

enum ScanAction: String, Codable {
    case clockIn = "Clocked In"
    case clockOut = "Clocked Out"
}

struct ScanEvent: Codable, Identifiable {
    let id = UUID()
    let cardID: String
    let timestamp: Date
    let action: ScanAction
    
    private enum CodingKeys: String, CodingKey {
        case cardID, timestamp, action
    }
}

enum ProjectEventType: String, Codable {
    case pause = "Pause"
    case lunch = "Lunch"
    case save = "Saved"
    case qcStop = "QC Stop" // <--- NEW CASE
}

struct ProjectEvent: Codable, Identifiable {
    let id = UUID()
    let timestamp: Date
    let type: ProjectEventType
    
    private enum CodingKeys: String, CodingKey {
        case timestamp, type
    }
}

enum PauseType: Codable, Equatable {
    case running
    case manual
    case manualLunch
    case autoLunch
    case qcStop // <--- NEW CASE
    case lunch // Legacy
}

enum ScanFeedback {
    case clockedIn(String)
    case clockedOut(String)
    case ignoredPaused
    case ignoredFinished
}

enum LunchFeedback {
    case success
    case ignoredPaused
    case ignoredNoWorkers
}

enum SaveFeedback {
    case success
    case failedValidation
}

// MARK: - AudioPlayerManager
class AudioPlayerManager {
    static let shared = AudioPlayerManager()
    var player: AVAudioPlayer?
    
    private init() {
        configureAudioSession()
    }
    
    func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to configure audio session: \(error)")
        }
    }
    
    func playSound(named soundName: String) {
        guard let url = Bundle.main.url(forResource: soundName, withExtension: "mp3", subdirectory: "audio") else {
            print("Sound file not found: \(soundName).mp3")
            return
        }
        
        do {
            player = try AVAudioPlayer(contentsOf: url)
            player?.play()
        } catch {
            print("Error playing sound: \(error)")
        }
    }
}

// MARK: - Banner Components
struct BannerAlert {
    var message: String
    var type: BannerType
}

enum BannerType {
    case info
    case warning
    case error
    
    var color: Color {
        switch self {
        case .info: return Color.blue.opacity(0.9)
        case .warning: return Color.orange.opacity(0.9)
        case .error: return Color.red.opacity(0.9)
        }
    }
    
    var icon: String {
        switch self {
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }
}

struct BannerView: View {
    let banner: BannerAlert
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: banner.type.icon)
                .font(.title2)
                .foregroundColor(.white)
            
            Text(banner.message)
                .font(.headline)
                .foregroundColor(.white)
            
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(banner.type.color)
        .cornerRadius(12)
        .padding(.horizontal)
        .shadow(radius: 5)
    }
}

// MARK: - ViewModel
class WorkerViewModel: ObservableObject {
    // --- Services ---
    private var db = Firestore.firestore()
    private var listener: ListenerRegistration?
    private var lastCommandTimestamp: Date?
    private var timer: Timer?
    
    // --- Persistence & Config ---
    @AppStorage(AppStorageKeys.fleetIpadID) var fleetIpadID: String = "" {
        didSet { if !fleetIpadID.isEmpty { connectToFleet() } }
    }
    
    // --- State Variables ---
    @Published var showManualSetup = false
    @Published var workers = [String: Worker]()
    @Published var totalPeopleWorking = 0
    @Published var timerText: String = "00:00:00"
    @Published var isProjectFinished = false
    @Published var shouldTriggerFinishFlow = false
    
    public var countdownSeconds: Int = 0
    @Published var originalCountdownSeconds: Int = 0
    
    // --- Queue & Dropdowns ---
    @Published var triggerQueueItem: ProjectQueueItem? = nil
    @Published var projectQueue: [ProjectQueueItem] = []
    @Published var availableCategories: [String] = ["Fragrance", "Skin Care", "Kitting", "VOC"]
    @Published var availableSizes: [String] = ["100ML", "50ML", "30ML", "15ML", "10ML", "7.5ML", "1.75ML", "4oz", "8oz", "other"]
    var pendingQueueIdToDelete: String? = nil
    
    // --- Pause & Flow State ---
    @Published var isPaused = true
    @Published var pauseState: PauseType = .running
    
    // --- NEW: Bonus Flag ---
    @Published var isBonusCancelled = false
    
    // --- Timer Helpers ---
    private var lastUpdateTime: Date?
    @Published var isCountingDown = false
    @Published var hasUsedLunchBreak = false
    @Published var lunchBreakStartTime: Date?
    @Published var hasPlayedBuzzerAtZero = false
    
    // --- Project Metadata ---
    @Published var projectName: String = ""
    @Published var companyName: String = ""
    @Published var lineLeaderName: String = ""
    @Published var category: String = ""
    @Published var projectSize: String = ""
    
    // --- Statistics ---
    @Published var pauseCount: Int = 0
    @Published var lunchCount: Int = 0
    @Published var scanCount: Int = 0
    @Published var scanHistory: [ScanEvent] = []
    @Published var projectEvents: [ProjectEvent] = []
    
    // --- Settings Arrays ---
    @Published var lunchPeriods: [TimePeriod] = []
    @Published var shiftStartTimes: [ShiftTime] = []
    @Published var categories: [EditableStringItem] = []
    @Published var projectSizes: [EditableStringItem] = []
    
    @Published var workerNameCache: [String: String] = [:]
    
    // MARK: - Initialization
    init() {
        loadState()
        loadCustomAppSettings()
        
        Auth.auth().addStateDidChangeListener { [weak self] auth, user in
            guard let self = self else { return }
            if let user = user {
                print("✅ ViewModel: User authenticated (UID: \(user.uid)).")
                self.startTimer()
                self.fetchWorkerNames()
                self.fetchProjectQueue()
                self.fetchDropdownOptions()
                if !self.fleetIpadID.isEmpty {
                    self.connectToFleet()
                }
            }
        }
    }
    
    // MARK: - Firebase Fetching
    func fetchWorkerNames() {
        db.collection("workers").addSnapshotListener { snapshot, error in
            guard let documents = snapshot?.documents else { return }
            for doc in documents {
                let name = doc.data()["name"] as? String ?? "Unknown"
                self.workerNameCache[doc.documentID] = name
            }
        }
    }
    
    func fetchProjectQueue() {
        db.collection("project_queue").order(by: "createdAt", descending: false).addSnapshotListener { snap, error in
            guard let docs = snap?.documents else { return }
            self.projectQueue = docs.compactMap { try? $0.data(as: ProjectQueueItem.self) }
        }
    }
    
    func fetchDropdownOptions() {
        db.collection("config").document("project_options").addSnapshotListener { snap, error in
            guard let data = snap?.data() else { return }
            self.availableCategories = (data["categories"] as? [String] ?? []).sorted()
            self.availableSizes = (data["sizes"] as? [String] ?? []).sorted()
        }
    }
    
    // MARK: - Logic & Calculation
    func reconstructStateFromLogs() {
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
    
    // MARK: - Cloud Sync (Fleet)
    func connectToFleet() {
        listener?.remove()
        let docRef = db.collection("ipads").document(fleetIpadID)
        listener = docRef.addSnapshotListener { [weak self] snapshot, error in
            guard let self = self, let data = snapshot?.data() else { return }
            
            DispatchQueue.main.async {
                self.restoreFromCloud(data: data)
                
                // Sync Metadata
                if let val = data["companyName"] as? String { self.companyName = val }
                if let val = data["projectName"] as? String { self.projectName = val }
                if let val = data["category"] as? String { self.category = val }
                if let val = data["projectSize"] as? String { self.projectSize = val }
                if let val = data["lineLeaderName"] as? String { self.lineLeaderName = val }
                
                // Sync Logs
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
                
                if logsUpdated { self.reconstructStateFromLogs() }
                
                // Handle Remote Commands
                if let cmd = data["remoteCommand"] as? String, let stamp = (data["commandTimestamp"] as? Timestamp)?.dateValue() {
                    if self.lastCommandTimestamp == nil || stamp > self.lastCommandTimestamp! {
                        self.lastCommandTimestamp = stamp
                        self.handleRemoteCommand(cmd)
                    }
                }
                
                // Sync Time
                if let trueOriginal = data["originalSeconds"] as? Int, trueOriginal > 0 {
                    if self.countdownSeconds == 0 && self.originalCountdownSeconds != trueOriginal {
                        self.originalCountdownSeconds = trueOriginal
                    }
                }
            }
        }
    }
    
    func restoreFromCloud(data: [String: Any]) {
        guard countdownSeconds == 0 && workers.isEmpty && projectName.isEmpty else { return }
        guard let seconds = data["secondsRemaining"] as? Int, seconds > 0 else { return }
        
        if let val = data["companyName"] as? String { self.companyName = val }
        if let val = data["projectName"] as? String { self.projectName = val }
        if let val = data["lineLeaderName"] as? String { self.lineLeaderName = val }
        if let val = data["category"] as? String { self.category = val }
        if let val = data["projectSize"] as? String { self.projectSize = val }
        
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
        
        // Restore Bonus Flag
        if let cancelled = data["bonusCancelled"] as? Bool {
            self.isBonusCancelled = cancelled
        }
    }
    
    func pushStateToCloud() {
        guard !fleetIpadID.isEmpty else { return }
        let activeWorkerIDs = workers.values.filter { $0.clockInTime != nil }.map { $0.id }
        
        let historyArray = scanHistory.map { ["cardID": $0.cardID, "action": $0.action.rawValue, "timestamp": $0.timestamp] }
        let eventsArray = projectEvents.map { ["type": $0.type.rawValue, "timestamp": $0.timestamp] }
        
        let data: [String: Any] = [
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
            "scanHistory": historyArray,
            "projectEvents": eventsArray,
            "bonusCancelled": isBonusCancelled
        ]
        db.collection("ipads").document(fleetIpadID).setData(data, merge: true)
    }
    
    // MARK: - Timer Logic
    private func startTimer() {
        guard !isProjectFinished else { return }
        timer?.invalidate()
        if isCountingDown {
            lastUpdateTime = Date()
            timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in self.updateCountdownTime() }
        }
    }
    
    private func updateCountdownTime() {
        guard isCountingDown else { return }
        
        // Auto-resume logic
        if self.pauseState == .manualLunch, let breakStart = lunchBreakStartTime {
            if Date().timeIntervalSince(breakStart) >= 1800 { resumeTimer() }
        } else if self.pauseState == .autoLunch {
            if !isCurrentlyInLunchWindow() { resumeTimer() }
        }
        
        checkForLunchBreak()
        autoClearLunchLock()
        
        // Timer Tick
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
        let absSec = abs(countdownSeconds)
        timerText = String(format: "%@%02d:%02d:%02d", prefix, absSec / 3600, (absSec % 3600) / 60, absSec % 60)
    }
    
    // MARK: - Actions (Pause, Lunch, Resume, QC)
    func pauseTimer(password: String) -> Bool {
        if password == "REMOTE_OVERRIDE" || password == UserDefaults.standard.string(forKey: AppStorageKeys.pausePassword) ?? "340340" {
            isPaused = true
            pauseState = .manual
            pauseCount += 1
            projectEvents.append(ProjectEvent(timestamp: Date(), type: .pause))
            saveState()
            pushStateToCloud()
            sendHeartbeat()
            return true
        }
        return false
    }
    
    // --- NEW: QC Logic ---
    func engageQCStop(isCrewIssue: Bool) {
        isPaused = true
        pauseState = .qcStop
        pauseCount += 1
        
        if isCrewIssue {
            isBonusCancelled = true
        }
        
        projectEvents.append(ProjectEvent(timestamp: Date(), type: .qcStop))
        
        saveState()
        pushStateToCloud()
        sendHeartbeat()
    }
    
    func resumeTimer() {
        guard !isProjectFinished else { return }
        isPaused = false
        pauseState = .running
        lastUpdateTime = Date()
        lunchBreakStartTime = nil
        startTimer()
        saveState()
        sendHeartbeat()
    }
    
    func checkForLunchBreak() {
        guard pauseState != .manual && pauseState != .manualLunch && pauseState != .qcStop && totalPeopleWorking > 0 && pauseState != .autoLunch else { return }
        if !hasUsedLunchBreak && isCurrentlyInLunchWindow() { startAutoLunch() }
    }
    
    private func isCurrentlyInLunchWindow() -> Bool {
        let currentDate = Date()
        let currentMinutes = Calendar.current.component(.hour, from: currentDate) * 60 + Calendar.current.component(.minute, from: currentDate)
        for period in lunchPeriods {
            let startMinutes = Calendar.current.component(.hour, from: period.start) * 60 + Calendar.current.component(.minute, from: period.start)
            let endMinutes = Calendar.current.component(.hour, from: period.end) * 60 + Calendar.current.component(.minute, from: period.end)
            if startMinutes < endMinutes {
                if currentMinutes >= startMinutes && currentMinutes < endMinutes { return true }
            } else {
                if currentMinutes >= startMinutes || currentMinutes < endMinutes { return true }
            }
        }
        return false
    }
    
    func takeLunchBreak() -> LunchFeedback {
        guard !isProjectFinished else { return .success }
        guard pauseState != .manual && pauseState != .autoLunch && pauseState != .qcStop else { return .ignoredPaused }
        guard totalPeopleWorking > 0 else { return .ignoredNoWorkers }
        
        isPaused = true
        pauseState = .manualLunch
        hasUsedLunchBreak = true
        lunchBreakStartTime = Date()
        lunchCount += 1
        projectEvents.append(ProjectEvent(timestamp: Date(), type: .lunch))
        saveState()
        pushStateToCloud()
        sendHeartbeat()
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
        sendHeartbeat()
    }
    
    func autoClearLunchLock() {
        guard hasUsedLunchBreak else { return }
        let currentMinutes = Calendar.current.component(.hour, from: Date()) * 60 + Calendar.current.component(.minute, from: Date())
        let resetWindows = shiftStartTimes.map {
            let start = Calendar.current.component(.hour, from: $0.time) * 60 + Calendar.current.component(.minute, from: $0.time)
            return (start: start, end: start + 1)
        }
        for window in resetWindows {
            if (currentMinutes >= window.start && currentMinutes < window.end) {
                hasUsedLunchBreak = false
                saveState()
                return
            }
        }
    }
    
    // MARK: - Data Management (Reset/Save)
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
        
        isBonusCancelled = false
        
        saveState()
        pushStateToCloud()
        sendHeartbeat()
    }
    
    func saveJobToQueue() -> SaveFeedback {
        // Validation
        guard !projectName.isEmpty, !companyName.isEmpty else {
            return .failedValidation
        }
        
        let now = Date()
        
        // 1. Clock out active workers for the calculation
        for id in workers.keys {
            if workers[id]?.clockInTime != nil {
                if let clockInTime = workers[id]?.clockInTime {
                    let minutes = now.timeIntervalSince(clockInTime) / 60
                    workers[id]?.totalMinutesWorked += minutes
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
            projectEvents: projectEvents
        )
        
        do {
            try db.collection("project_queue").addDocument(from: item)
            resetData()
            return .success
        } catch {
            print("Error saving to queue: \(error)")
            return .success // Technically a fail, but we usually reset to avoid data lock
        }
    }
    
    func saveFinalReportToFirestore() {
        let idToSave = fleetIpadID.isEmpty ? "Unassigned iPad" : fleetIpadID
        let workerLog = workers.values.map { ["id": $0.id, "name": getWorkerName(id: $0.id), "minutes": $0.totalMinutesWorked] }
        let status = isBonusCancelled ? "cancelled" : "unpaid"
        
        let report: [String: Any] = [
            "company": companyName.isEmpty ? "Unknown" : companyName,
            "project": projectName.isEmpty ? "Unknown" : projectName,
            "leader": lineLeaderName.isEmpty ? "Unknown" : lineLeaderName,
            "category": category,
            "size": projectSize,
            "originalSeconds": originalCountdownSeconds,
            "finalSeconds": countdownSeconds,
            "workerCountAtFinish": totalPeopleWorking,
            "completedAt": FieldValue.serverTimestamp(),
            "ipadId": idToSave,
            "totalScans": scanCount,
            "totalPauses": pauseCount,
            "workerLog": workerLog,
            "bonusStatus": status
        ]
        
        db.collection("reports").addDocument(data: report) { error in
            if let e = error { print("CRITICAL ERROR SAVING REPORT: \(e.localizedDescription)") }
            else { print("Financial Report successfully saved.") }
        }
    }
    
    func finishProject() {
        AudioPlayerManager.shared.playSound(named: "Cashier")
        isPaused = true
        isCountingDown = false
        timer?.invalidate()
        let now = Date()
        for id in workers.keys {
            if let clockInTime = workers[id]?.clockInTime {
                let timeWorkedInMinutes = now.timeIntervalSince(clockInTime) / 60
                workers[id]?.totalMinutesWorked += timeWorkedInMinutes
                scanHistory.append(ScanEvent(cardID: id, timestamp: now, action: .clockOut))
            }
        }
        isProjectFinished = true
        hasUsedLunchBreak = false
        lunchBreakStartTime = nil
        saveFinalReportToFirestore()
        saveState()
        pushStateToCloud()
        sendHeartbeat()
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
        isBonusCancelled = false
        startTimer()
        saveState()
        pushStateToCloud()
        sendHeartbeat()
    }
    
    // MARK: - RFID Handling
    func handleRFIDScan(for id: String) -> ScanFeedback? {
        guard !isProjectFinished, !isPaused else {
            return isProjectFinished ? .ignoredFinished : .ignoredPaused
        }
        scanCount += 1
        let action: ScanAction = workers[id]?.clockInTime != nil ? .clockOut : .clockIn
        scanHistory.append(ScanEvent(cardID: id, timestamp: Date(), action: action))
        
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
            sendHeartbeat()
        }
    }
    
    func clockOut(for id: String) {
        guard var worker = workers[id], let clockInTime = worker.clockInTime else { return }
        if scanHistory.last?.cardID != id {
            scanHistory.append(ScanEvent(cardID: id, timestamp: Date(), action: .clockOut))
            scanCount += 1
        }
        let minutes = Date().timeIntervalSince(clockInTime) / 60
        worker.totalMinutesWorked += minutes
        worker.clockInTime = nil
        workers[id] = worker
        recalcTotalPeopleWorking()
        saveState()
        pushStateToCloud()
        sendHeartbeat()
    }
    
    private func recalcTotalPeopleWorking() {
        totalPeopleWorking = workers.values.filter { $0.clockInTime != nil }.count
    }
    
    // MARK: - Helper Functions
    func handleRemoteCommand(_ command: String) {
        let parts = command.split(separator: "|")
        let action = String(parts[0])
        switch action {
        case "PRELOAD":
            var totalSecs = 0
            if parts.count > 1 {
                let timeParts = parts[1].split(separator: ":")
                if timeParts.count == 3, let h = Int(timeParts[0]), let m = Int(timeParts[1]), let s = Int(timeParts[2]) {
                    totalSecs = (h * 3600) + (m * 60) + s
                    self.originalCountdownSeconds = totalSecs
                    self.countdownSeconds = totalSecs
                }
            }
            self.isPaused = true; self.pauseState = .running; self.isCountingDown = false; self.isProjectFinished = false; self.timerText = "00:00:00"; self.showManualSetup = false; self.isBonusCancelled = false
            
            let tempItem = ProjectQueueItem(id: "REMOTE_PRELOAD", company: self.companyName, project: self.projectName, category: self.category, size: self.projectSize, seconds: totalSecs, lineLeaderName: self.lineLeaderName, createdAt: Date(), scanHistory: self.scanHistory, projectEvents: self.projectEvents)
            self.triggerQueueItem = tempItem
            
        case "TOGGLE": if isPaused { resumeTimer() } else { _ = pauseTimer(password: "REMOTE_OVERRIDE") }
        case "LUNCH": _ = takeLunchBreak()
        case "SAVE": _ = saveJobToQueue() // Ignored feedback for remote
        case "RESET", "SET_TIME":
            if parts.count > 1 {
                let timeParts = parts[1].split(separator: ":")
                if timeParts.count == 3, let h = Int(timeParts[0]), let m = Int(timeParts[1]), let s = Int(timeParts[2]) {
                    resetTimer(hours: h, minutes: m, seconds: s)
                }
            } else { resetData() }
        case "FINISH": self.shouldTriggerFinishFlow = true
        case "CLOCK_OUT": if parts.count > 1 { clockOut(for: String(parts[1])) }
        default: break
        }
    }
    
    func sendHeartbeat() { pushStateToCloud() }
    
    func executeRemoteCommand(_ command: String) { handleRemoteCommand(command) }
    
    // MARK: - Persistence
    public func saveState() {
        let defaults = UserDefaults.standard
        if let encoded = try? JSONEncoder().encode(workers) { defaults.set(encoded, forKey: "savedWorkers") }
        if let encodedHistory = try? JSONEncoder().encode(scanHistory) { defaults.set(encodedHistory, forKey: "scanHistory") }
        if let encodedEvents = try? JSONEncoder().encode(projectEvents) { defaults.set(encodedEvents, forKey: "projectEvents") }
        if let encodedPause = try? JSONEncoder().encode(pauseState) { defaults.set(encodedPause, forKey: "pauseState") }
        
        defaults.set(originalCountdownSeconds, forKey: "originalCountdownSeconds")
        defaults.set(countdownSeconds, forKey: "countdownSeconds")
        defaults.set(isPaused, forKey: "isPaused")
        defaults.set(isCountingDown, forKey: "isCountingDown")
        defaults.set(isProjectFinished, forKey: "isProjectFinished")
        defaults.set(hasUsedLunchBreak, forKey: "hasUsedLunchBreak")
        defaults.set(lunchBreakStartTime, forKey: "lunchBreakStartTime")
        defaults.set(hasPlayedBuzzerAtZero, forKey: "hasPlayedBuzzerAtZero")
        defaults.set(projectName, forKey: "projectName")
        defaults.set(companyName, forKey: "companyName")
        defaults.set(lineLeaderName, forKey: "lineLeaderName")
        defaults.set(category, forKey: "category")
        defaults.set(projectSize, forKey: "projectSize")
        defaults.set(pauseCount, forKey: "pauseCount")
        defaults.set(lunchCount, forKey:"lunchCount")
        defaults.set(scanCount, forKey: "scanCount")
        defaults.set(isBonusCancelled, forKey: "bonusCancelled")
    }
    
    private func loadState() {
        let defaults = UserDefaults.standard
        if let d = defaults.data(forKey: "savedWorkers"), let v = try? JSONDecoder().decode([String: Worker].self, from: d) { workers = v }
        if let d = defaults.data(forKey: "scanHistory"), let v = try? JSONDecoder().decode([ScanEvent].self, from: d) { scanHistory = v }
        if let d = defaults.data(forKey: "projectEvents"), let v = try? JSONDecoder().decode([ProjectEvent].self, from: d) { projectEvents = v }
        
        isPaused = defaults.bool(forKey: "isPaused")
        if let d = defaults.data(forKey: "pauseState"), let v = try? JSONDecoder().decode(PauseType.self, from: d) {
            pauseState = (v == .lunch) ? .manualLunch : v
        } else { pauseState = .running }
        
        originalCountdownSeconds = defaults.integer(forKey: "originalCountdownSeconds")
        countdownSeconds = defaults.integer(forKey: "countdownSeconds")
        isCountingDown = defaults.bool(forKey: "isCountingDown")
        recalcTotalPeopleWorking()
        
        if isCountingDown || isProjectFinished { startTimer(); updateCountdownTime() }
        
        isProjectFinished = defaults.bool(forKey: "isProjectFinished")
        hasUsedLunchBreak = defaults.bool(forKey: "hasUsedLunchBreak")
        lunchBreakStartTime = defaults.object(forKey: "lunchBreakStartTime") as? Date
        hasPlayedBuzzerAtZero = defaults.bool(forKey: "hasPlayedBuzzerAtZero")
        
        companyName = defaults.string(forKey: "companyName") ?? ""
        projectName = defaults.string(forKey: "projectName") ?? ""
        lineLeaderName = defaults.string(forKey: "lineLeaderName") ?? ""
        category = defaults.string(forKey: "category") ?? ""
        projectSize = defaults.string(forKey: "projectSize") ?? ""
        
        pauseCount = defaults.integer(forKey: "pauseCount")
        lunchCount = defaults.integer(forKey: "lunchCount")
        scanCount = defaults.integer(forKey: "scanCount")
        
        isBonusCancelled = defaults.bool(forKey: "bonusCancelled")
    }
    
    func saveCustomAppSettings() {
        if let e = try? JSONEncoder().encode(lunchPeriods) { UserDefaults.standard.set(e, forKey: "lunchPeriods") }
        if let e = try? JSONEncoder().encode(shiftStartTimes) { UserDefaults.standard.set(e, forKey: "shiftStartTimes") }
        if let e = try? JSONEncoder().encode(categories) { UserDefaults.standard.set(e, forKey: "categories") }
        if let e = try? JSONEncoder().encode(projectSizes) { UserDefaults.standard.set(e, forKey: "projectSizes") }
    }
    
    private func loadCustomAppSettings() {
        if let d = UserDefaults.standard.data(forKey: "lunchPeriods"), let v = try? JSONDecoder().decode([TimePeriod].self, from: d) { lunchPeriods = v }
        else { lunchPeriods = [TimePeriod(start: dateFrom(11,30), end: dateFrom(12,0)), TimePeriod(start: dateFrom(18,30), end: dateFrom(19,0)), TimePeriod(start: dateFrom(3,0), end: dateFrom(3,30))] }
        if let d = UserDefaults.standard.data(forKey: "shiftStartTimes"), let v = try? JSONDecoder().decode([ShiftTime].self, from: d) { shiftStartTimes = v }
        else { shiftStartTimes = [ShiftTime(time: dateFrom(6,0)), ShiftTime(time: dateFrom(14,0)), ShiftTime(time: dateFrom(22,0))] }
        if let d = UserDefaults.standard.data(forKey: "categories"), let v = try? JSONDecoder().decode([EditableStringItem].self, from: d) { categories = v }
        else { categories = ["Fragrance", "Skin Care", "Kitting", "VOC"].map { EditableStringItem(value: $0) } }
        if let d = UserDefaults.standard.data(forKey: "projectSizes"), let v = try? JSONDecoder().decode([EditableStringItem].self, from: d) { projectSizes = v }
        else { projectSizes = ["100ML", "50ML", "30ML", "15ML", "10ML", "7.5ML", "1.75ML", "4oz", "8oz", "other"].map { EditableStringItem(value: $0) } }
    }
    
    func dateFrom(_ h:Int, _ m:Int) -> Date { Calendar.current.date(from: DateComponents(hour:h, minute:m)) ?? Date() }
    func getWorkerName(id: String) -> String { return workerNameCache[id] ?? "ID: \(id)" }
}

// MARK: - ContentView
struct ContentView: View {
    @StateObject var viewModel = WorkerViewModel()
    
    // UI State
    @State private var hoursInput = ""
    @State private var minutesInput = ""
    @State private var secondsInput = ""
    @State private var companyNameInput = ""
    @State private var projectNameInput = ""
    @State private var lineLeaderNameInput = ""
    
    // Focus & Inputs
    @FocusState private var isInputFocused: Bool
    @FocusState private var isRFIDFieldFocused: Bool
    @State private var rfidInput = ""
    @State private var selectedField: TimeField? = .hours
    
    // Sheets & Popups
    @State private var passwordField = ""
    @State private var showingPasswordSheet = false
    @State private var showingResetPasswordSheet = false
    @State private var showPasswordError = false
    
    @State private var showingQCPasswordSheet = false
    @State private var showingQCOptionsActionSheet = false
    @State private var showQCPasswordError = false
    
    @State private var showingCompanyKeyboard = false
    @State private var showingProjectKeyboard = false
    @State private var showingLineLeaderKeyboard = false
    @State private var showingTimerInputSheet = false
    
    @State private var showingQueueLeaderSheet = false
    @State private var showingSettingsPasswordSheet = false
    @State private var showingActualSettings = false
    
    @State private var showingEmailAlert = false
    @State private var emailAlertTitle = ""
    @State private var emailAlertMessage = ""
    @State private var isSendingEmail = false
    
    // Settings Binding
    @State private var showingSettingsKeyboard = false
    @State private var settingsKeyboardBinding: Binding<String>?
    @State private var showingSettingsNumericKeyboard = false
    @State private var settingsNumericKeyboardBinding: Binding<String>?
    
    // Queue
    @State private var selectedQueueItem: ProjectQueueItem? = nil
    @State private var queueLineLeaderName = ""
    @State private var isReset = true
    
    // Feedback
    @State private var currentBanner: BannerAlert? = nil
    @State private var bannerTimer: Timer? = nil
    @State private var showCursor = true
    @State private var cursorTimer: Timer?
    
    @Environment(\.scenePhase) private var scenePhase
    
    // AppStorage
    @AppStorage(AppStorageKeys.smtpRecipient) private var smtpRecipient = "productionreports@makeit.buzz"
    @AppStorage(AppStorageKeys.smtpHost) private var smtpHost = "smtp.office365.com"
    @AppStorage(AppStorageKeys.smtpUsername) private var smtpUsername = "alerts@makeit.buzz"
    @AppStorage(AppStorageKeys.smtpPassword) private var smtpPassword = ""
    @AppStorage(AppStorageKeys.enableSmtpEmail) private var enableSmtpEmail = false
    @AppStorage(AppStorageKeys.pausePassword) private var pausePassword = "340340"
    @AppStorage(AppStorageKeys.resetPassword) private var resetPassword = "465465"
    @AppStorage(AppStorageKeys.qcPassword) private var qcPassword = "555555"
    
    enum TimeField { case hours, minutes, seconds }
    
    init() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundColor = .clear
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
    }
    
    private var isProjectInfoInvalid: Bool {
        return companyNameInput.isEmpty || projectNameInput.isEmpty || lineLeaderNameInput.isEmpty || viewModel.category.isEmpty || viewModel.projectSize.isEmpty
    }
    
    private var isStartTimeInvalid: Bool {
        let h = Int(hoursInput) ?? 0
        let m = Int(minutesInput) ?? 0
        let s = Int(secondsInput) ?? 0
        return (h + m + s) == 0
    }
    
    private var shouldShowTimerScreen: Bool {
        return viewModel.isCountingDown || viewModel.isProjectFinished
    }
    
    private var currentYear: String {
        let year = Calendar.current.component(.year, from: Date())
        return String(year)
    }
    
    // MARK: - Helper Views
    @ViewBuilder
    private func inputButton(text: String, action: @escaping () -> Void, width: CGFloat, height: CGFloat, fontSize: CGFloat, isEmpty: Bool) -> some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: fontSize))
                .padding(8)
                .frame(maxWidth: width)
                .frame(minHeight: height)
                .background(Color.white.opacity(0.8))
                .foregroundColor(isEmpty ? .gray : .black)
                .cornerRadius(10)
                .shadow(radius: 3)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.5), lineWidth: 1))
        }
    }
    
    @ViewBuilder
    private func overlayKeyboard(binding: Binding<String>, isPresented: Binding<Bool>) -> some View {
        Color.black.opacity(0.001)
            .edgesIgnoringSafeArea(.all)
            .onTapGesture { withAnimation { isPresented.wrappedValue = false } }
        
        GeometryReader { geo in
            VStack {
                Spacer()
                CustomAlphanumericKeyboard(text: binding, isPresented: isPresented, geometry: geo)
            }
        }
        .transition(.move(edge: .bottom))
    }
    
    // MARK: - Main Body
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
            
            // --- Overlays ---
            
            if showingCompanyKeyboard { overlayKeyboard(binding: $companyNameInput, isPresented: $showingCompanyKeyboard) }
            if showingProjectKeyboard { overlayKeyboard(binding: $projectNameInput, isPresented: $showingProjectKeyboard) }
            if showingLineLeaderKeyboard { overlayKeyboard(binding: $lineLeaderNameInput, isPresented: $showingLineLeaderKeyboard) }
            
            if isSendingEmail {
                Color.black.opacity(0.4).edgesIgnoringSafeArea(.all)
                VStack {
                    ProgressView().scaleEffect(2)
                    Text("Sending Email...").font(.title2).foregroundColor(.white).padding()
                }
                .padding(30).background(Color.black.opacity(0.8)).cornerRadius(20).zIndex(12)
            }
            
            VStack {
                if let banner = currentBanner {
                    BannerView(banner: banner)
                        .onTapGesture { withAnimation(.spring()) { currentBanner = nil; bannerTimer?.invalidate() } }
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                Spacer()
            }
            .padding(.top, 40)
            .zIndex(20)
        }
        
        // MARK: - Modifiers & Sheets
        
        .onChange(of: viewModel.triggerQueueItem) { newItem in
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
        .sheet(isPresented: $showingSettingsPasswordSheet, onDismiss: { showPasswordError = false }) {
            passwordSheetPopup(showError: $showPasswordError, isPresented: $showingSettingsPasswordSheet, title: "Enter Admin Password", correctPassword: "127127") {
                withAnimation { showingActualSettings = true }
            }
        }
        .fullScreenCover(isPresented: $showingQueueLeaderSheet) {
            QueueProjectStartSheet(
                isPresented: $showingQueueLeaderSheet,
                lineLeaderName: $queueLineLeaderName,
                queueItem: selectedQueueItem,
                workerNames: viewModel.workerNameCache,
                onStart: {
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
                
                if showingSettingsKeyboard {
                    Color.black.opacity(0.001).edgesIgnoringSafeArea(.all).onTapGesture {
                        withAnimation { showingSettingsKeyboard = false; settingsKeyboardBinding = nil }
                    }
                    GeometryReader { geo in
                        VStack { Spacer(); if let binding = settingsKeyboardBinding { CustomAlphanumericKeyboard(text: binding, isPresented: $showingSettingsKeyboard, geometry: geo) } }
                    }.transition(.move(edge: .bottom))
                }
                if showingSettingsNumericKeyboard {
                    Color.black.opacity(0.001).edgesIgnoringSafeArea(.all).onTapGesture {
                        withAnimation { showingSettingsNumericKeyboard = false; settingsNumericKeyboardBinding = nil }
                    }
                    GeometryReader { geo in
                        VStack { Spacer(); if let binding = settingsNumericKeyboardBinding { CustomNumericKeyboard(text: binding, isPresented: $showingSettingsNumericKeyboard, geometry: geo) } }
                    }.transition(.move(edge: .bottom))
                }
            }
        }
        .sheet(isPresented: $showingPasswordSheet, onDismiss: { showPasswordError = false }) {
            passwordSheetPopup(showError: $showPasswordError, isPresented: $showingPasswordSheet, title: "Enter Pause Password", correctPassword: pausePassword) {
                _ = viewModel.pauseTimer(password: pausePassword)
            }
        }
        .sheet(isPresented: $showingResetPasswordSheet, onDismiss: { showPasswordError = false }) {
            passwordSheetPopup(showError: $showPasswordError, isPresented: $showingResetPasswordSheet, title: "Enter Reset Password", correctPassword: resetPassword) {
                performReset()
            }
        }
        
        // --- QC SHEETS ---
        .sheet(isPresented: $showingQCPasswordSheet, onDismiss: { showQCPasswordError = false }) {
            passwordSheetPopup(
                showError: $showQCPasswordError,
                isPresented: $showingQCPasswordSheet,
                title: "Enter QC PIN",
                correctPassword: qcPassword
            ) {
                // If Currently in QC Stop Mode -> Resume
                if viewModel.pauseState == .qcStop {
                    viewModel.resumeTimer()
                } else {
                    // We need to dismiss this sheet first, then show the action sheet
                    // Use a small delay to avoid conflict
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        showingQCOptionsActionSheet = true
                    }
                }
            }
        }
        .actionSheet(isPresented: $showingQCOptionsActionSheet) {
            ActionSheet(
                title: Text("QC Stop Reason"),
                message: Text("Select the type of issue causing the stop."),
                buttons: [
                    .default(Text("Component Issue (Pause Only)")) { viewModel.engageQCStop(isCrewIssue: false) },
                    .destructive(Text("Crew Issue (Cancel Bonus)")) { viewModel.engageQCStop(isCrewIssue: true) },
                    .cancel()
                ]
            )
        }
        // ------------------
        
        .sheet(isPresented: $showingTimerInputSheet) {
            GeometryReader { sheetGeometry in
                timerInputScreen(geometry: sheetGeometry)
            }
            .onAppear {
                hoursInput = ""; minutesInput = ""; secondsInput = ""; selectedField = .hours
            }
            .interactiveDismissDisabled()
        }
        .alert(isPresented: $showingEmailAlert) {
            Alert(title: Text(emailAlertTitle), message: Text(emailAlertMessage), dismissButton: .default(Text("OK")))
        }
        .onChange(of: scenePhase) { phase in if phase == .background { viewModel.saveState() } }
        .onAppear {
            startCursorBlink()
            self.companyNameInput = viewModel.companyName
            self.projectNameInput = viewModel.projectName
            self.lineLeaderNameInput = viewModel.lineLeaderName
            DispatchQueue.main.async { if self.shouldShowTimerScreen { self.isRFIDFieldFocused = true } }
        }
        .onChange(of: rfidInput) { newValue in if newValue.isEmpty { self.isRFIDFieldFocused = true } }
        .onChange(of: viewModel.isCountingDown) { isRunning in DispatchQueue.main.async { if isRunning { self.isRFIDFieldFocused = true } } }
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
    
    // MARK: - Sub-Screens
    @ViewBuilder
    private func waitingForCommandScreen() -> some View {
        VStack(spacing: 30) {
            Text(viewModel.fleetIpadID.isEmpty ? "NO ID CONFIG" : "CONNECTED: \(viewModel.fleetIpadID)")
                .font(.headline)
                .padding(10)
                .background(Color.black.opacity(0.4))
                .cornerRadius(8)
                .foregroundColor(viewModel.fleetIpadID.isEmpty ? .red : .green)
            
            if !viewModel.projectQueue.isEmpty {
                Menu {
                    ForEach(viewModel.projectQueue) { job in
                        Button(action: { viewModel.triggerQueueItem = job }) {
                            Text("\(job.project) (\(job.company))")
                        }
                    }
                } label: {
                    HStack {
                        Image(systemName: "tray.full.fill")
                        Text("Select Upcoming Project")
                        Spacer()
                        Image(systemName: "chevron.down")
                    }
                    .font(.title2)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                    .shadow(radius: 5)
                }
                .padding(.horizontal, 40)
            } else {
                Text("No Jobs in Queue").foregroundColor(.gray).font(.caption)
            }
        }
    }
    
    @ViewBuilder
    private func projectInfoScreen(geometry: GeometryProxy) -> some View {
        let g = geometry.size
        let isLandscape = g.width > g.height
        let fieldWidth = min(g.width * 0.8, 600)
        let fieldMinHeight = isLandscape ? 44.0 : 60.0
        let fieldFontSize = min(g.width * (isLandscape ? 0.04 : 0.05), 30)
        let vSpacing = g.height * (isLandscape ? 0.02 : 0.04)
        
        VStack(spacing: vSpacing) {
            inputButton(text: companyNameInput.isEmpty ? "Company Name" : companyNameInput, action: { withAnimation { showingCompanyKeyboard = true } }, width: fieldWidth, height: fieldMinHeight, fontSize: fieldFontSize, isEmpty: companyNameInput.isEmpty)
            inputButton(text: projectNameInput.isEmpty ? "Project Name" : projectNameInput, action: { withAnimation { showingProjectKeyboard = true } }, width: fieldWidth, height: fieldMinHeight, fontSize: fieldFontSize, isEmpty: projectNameInput.isEmpty)
            
            VStack(alignment: .leading, spacing: 2) {
                if !lineLeaderNameInput.isEmpty { Text("Line Leader").font(.caption).foregroundColor(.gray) }
                TextField("Line Leader (Scan Card)", text: $lineLeaderNameInput)
                    .focused($isInputFocused)
                    .font(.system(size: 20))
                    .padding(10)
                    .frame(maxWidth: fieldWidth)
                    .background(Color.white.opacity(0.8))
                    .cornerRadius(10)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.5), lineWidth: 1))
                    .onChange(of: lineLeaderNameInput) { newValue in
                        if let name = viewModel.workerNameCache[newValue] {
                            lineLeaderNameInput = name
                            AudioPlayerManager.shared.playSound(named: "Cashier")
                        }
                    }
            }
            
            HStack {
                Text("Category:").font(.system(size: fieldFontSize * 0.8)).foregroundColor(.gray)
                Spacer()
                Picker("Category", selection: $viewModel.category) {
                    Text("Select").tag("")
                    ForEach(viewModel.availableCategories, id: \.self) { cat in Text(cat).tag(cat) }
                }.pickerStyle(.menu).scaleEffect(1.2)
            }
            .padding(isLandscape ? 8 : 12)
            .frame(maxWidth: fieldWidth).frame(minHeight: fieldMinHeight)
            .background(Color.white.opacity(0.8)).cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.5), lineWidth: 1))
            
            HStack {
                Text("Size:").font(.system(size: fieldFontSize * 0.8)).foregroundColor(.gray)
                Spacer()
                Picker("Size", selection: $viewModel.projectSize) {
                    Text("Select").tag("")
                    ForEach(viewModel.availableSizes, id: \.self) { size in Text(size).tag(size) }
                }.pickerStyle(.menu).scaleEffect(1.2)
            }
            .padding(isLandscape ? 8 : 12)
            .frame(maxWidth: fieldWidth).frame(minHeight: fieldMinHeight)
            .background(Color.white.opacity(0.8)).cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.5), lineWidth: 1))
            
            Spacer().frame(height: vSpacing)
            
            HStack(spacing: 20) {
                Button("Cancel") { withAnimation { viewModel.showManualSetup = false } }
                    .frame(width: 200, height: 75).background(Color.red).foregroundColor(.white).cornerRadius(16).shadow(radius: 6)
                
                Button("Next") {
                    viewModel.companyName = companyNameInput
                    viewModel.projectName = projectNameInput
                    viewModel.lineLeaderName = lineLeaderNameInput
                    viewModel.saveState()
                    showingTimerInputSheet = true
                }
                .frame(width: 200, height: 75).background(isProjectInfoInvalid ? Color.gray : Color.blue).foregroundColor(.white).cornerRadius(16).shadow(radius: 6).disabled(isProjectInfoInvalid)
            }
        }
    }
    
    @ViewBuilder
    private func timerInputScreen(geometry: GeometryProxy) -> some View {
        let g = geometry.size
        let isLandscape = g.width > g.height
        let keyWidth = min(g.width * (isLandscape ? 0.15 : 0.2), 100.0)
        let keyHeight = keyWidth * 0.65
        let boxWidth = min(g.width * (isLandscape ? 0.2 : 0.25), 160.0)
        let boxHeight = boxWidth * 0.55
        let boxFontSize = boxHeight * (isLandscape ? 0.45 : 0.5)
        let startButtonWidth = min(g.width * (isLandscape ? 0.4 : 0.5), 280.0)
        let startButtonHeight = min(g.height * (isLandscape ? 0.11 : 0.09), 70.0)
        let vSpacing = g.height * (isLandscape ? 0.01 : 0.02)
        
        VStack(spacing: vSpacing) {
            Text("Set Timer Duration")
                .font(.system(size: min(g.width * (isLandscape ? 0.04 : 0.05), 30), weight: .semibold))
                .padding(.top, 40).padding(.bottom, vSpacing)
            
            HStack(spacing: g.width * 0.03) {
                timeInputBox(title: "Hours", text: $hoursInput, selected: selectedField == .hours, width: boxWidth, height: boxHeight, fontSize: boxFontSize).onTapGesture { selectedField = .hours }
                timeInputBox(title: "Minutes", text: $minutesInput, selected: selectedField == .minutes, width: boxWidth, height: boxHeight, fontSize: boxFontSize).onTapGesture { selectedField = .minutes }
                timeInputBox(title: "Seconds", text: $secondsInput, selected: selectedField == .seconds, width: boxWidth, height: boxHeight, fontSize: boxFontSize).onTapGesture { selectedField = .seconds }
            }.padding(.bottom, vSpacing)
            
            VStack(spacing: isLandscape ? 6 : 8) {
                ForEach([[1,2,3],[4,5,6],[7,8,9]], id: \.self) { row in
                    HStack(spacing: isLandscape ? 6 : 8) {
                        ForEach(row, id: \.self) { num in numButton("\(num)", width: keyWidth, height: keyHeight) }
                    }
                }
                HStack(spacing: isLandscape ? 6 : 8) {
                    numButton("⌫", color: .red, width: keyWidth, height: keyHeight)
                    numButton("0", width: keyWidth, height: keyHeight)
                    Button("Next") {
                        switch selectedField {
                        case .hours: selectedField = .minutes
                        case .minutes: selectedField = .seconds
                        case .seconds, .none: selectedField = .hours
                        }
                    }.frame(width: keyWidth, height: keyHeight).background(Color.orange).foregroundColor(.white).cornerRadius(14).font(.system(size: keyHeight * 0.4, weight: .semibold))
                }
            }.padding(.bottom, vSpacing)
            
            Button("Start Timer") {
                viewModel.resetTimer(hours: Int(hoursInput) ?? 0, minutes: Int(minutesInput) ?? 0, seconds: Int(secondsInput) ?? 0)
                isReset = false
                showingTimerInputSheet = false
            }
            .padding().font(.system(size: startButtonHeight * 0.4, weight: .bold)).frame(width: startButtonWidth, height: startButtonHeight)
            .background(isStartTimeInvalid ? Color.gray : Color.blue).foregroundColor(.white).cornerRadius(16).shadow(radius: 6).disabled(isStartTimeInvalid)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).background(Color(UIColor.systemGroupedBackground)).edgesIgnoringSafeArea(.all)
    }
    
    // MARK: - Timer Running Screen (Refactored)
    @ViewBuilder
    private func timerRunningScreen() -> some View {
        GeometryReader { geometry in
            let timerFontSize = min(geometry.size.width * 0.18, 200)
            let headerFontSize = min(geometry.size.width * 0.05, 40)
            let subHeaderFontSize = min(geometry.size.width * 0.04, 30)
            let buttonWidth = min(geometry.size.width * 0.28, 220.0)
            let buttonHeight = min(geometry.size.height * 0.10, 80.0)
            let buttonFont = Font.system(size: min(buttonWidth * 0.12, 22), weight: .semibold)
            
            VStack(spacing: 0) {
                // Header Info
                Text(viewModel.timerText)
                    .font(.system(size: timerFontSize, weight: .bold, design: .monospaced))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: timerFontSize * 1.1)
                    .padding(.top, 20)
                
                if !viewModel.companyName.isEmpty {
                    Text(viewModel.companyName)
                        .font(.system(size: headerFontSize, weight: .medium))
                        .foregroundColor(.black)
                        .padding(.bottom, 2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .frame(height: headerFontSize)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                }
                
                if !viewModel.projectName.isEmpty {
                    Text(viewModel.projectName)
                        .font(.system(size: headerFontSize, weight: .medium))
                        .foregroundColor(.black)
                        .padding(.bottom, 2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .frame(height: headerFontSize)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                }
                
                if !viewModel.lineLeaderName.isEmpty {
                    Text("Leader: \(viewModel.lineLeaderName)")
                        .font(.system(size: subHeaderFontSize, weight: .medium))
                        .foregroundColor(.black)
                        .padding(.bottom, 2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .frame(height: subHeaderFontSize)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                }
                
                Text("People Clocked In: \(viewModel.totalPeopleWorking)")
                    .font(.system(size: headerFontSize, weight: .medium))
                    .foregroundColor(.black)
                    .padding(.bottom, 10)
                    .frame(height: headerFontSize)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                
                // Button Grid
                VStack(spacing: 15) {
                    rowOneButtons(width: buttonWidth, height: buttonHeight, font: buttonFont)
                    rowTwoButtons(width: buttonWidth, height: buttonHeight, font: buttonFont)
                    rowThreeButtons(width: buttonWidth, height: buttonHeight, font: buttonFont)
                }
                .padding(.bottom, 20)
                
                // RFID Input
                VStack(spacing: 10) {
                    TextField("Scan RFID Card", text: $rfidInput)
                        .font(.system(size: min(geometry.size.width * 0.04, 28)))
                        .padding()
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(maxWidth: min(geometry.size.width * 0.85, 820))
                        .focused($isRFIDFieldFocused)
                        .onSubmit { handleRFIDSubmit(); self.isRFIDFieldFocused = true }
                        .toolbar {
                            ToolbarItemGroup(placement: .keyboard) {
                                Spacer()
                                Button("Done") { self.isRFIDFieldFocused = false }
                            }
                        }
                }
                .padding(.bottom, 10)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    
    // Helper ViewBuilders for Button Rows to keep type-check complexity low
    @ViewBuilder
    private func rowOneButtons(width: CGFloat, height: CGFloat, font: Font) -> some View {
        HStack(spacing: 20) {
            // Pause/Unpause
            Button(action: { if viewModel.isPaused { viewModel.resumeTimer() } else { showingPasswordSheet = true } }) {
                Text(viewModel.isPaused ? "Unpause" : "Pause")
                    .font(font)
                    .frame(width: width, height: height)
                    .background(viewModel.isPaused ? Color.green : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(14)
            }
            .disabled(viewModel.isProjectFinished || viewModel.pauseState == .qcStop)
            .opacity(viewModel.isProjectFinished || viewModel.pauseState == .qcStop ? 0.5 : 1.0)
            
            // Lunch
            Button(action: {
                let feedback = viewModel.takeLunchBreak()
                if feedback == .ignoredPaused { showBanner(message: "Cannot take lunch while manually paused.", type: .warning) }
                else if feedback == .ignoredNoWorkers { showBanner(message: "Cannot take lunch: No workers clocked in.", type: .warning) }
            }) {
                Text("Lunch")
                    .font(font)
                    .frame(width: width, height: height)
                    .background(viewModel.hasUsedLunchBreak ? Color.gray : Color.orange)
                    .foregroundColor(.white)
                    .cornerRadius(14)
            }
            .disabled(viewModel.hasUsedLunchBreak || viewModel.isProjectFinished || viewModel.pauseState == .manual || viewModel.pauseState == .autoLunch || viewModel.pauseState == .qcStop || viewModel.totalPeopleWorking == 0)
            .opacity(viewModel.hasUsedLunchBreak || viewModel.isProjectFinished || viewModel.pauseState == .manual || viewModel.pauseState == .autoLunch || viewModel.pauseState == .qcStop || viewModel.totalPeopleWorking == 0 ? 0.5 : 1.0)
            
            // Save
            Button(action: {
                let feedback = viewModel.saveJobToQueue()
                if feedback == .failedValidation {
                    showBanner(message: "Cannot Save: Missing Company or Project Name.", type: .error)
                }
            }) {
                Text("Save")
                    .font(font)
                    .frame(width: width, height: height)
                    .background(Color.purple)
                    .foregroundColor(.white)
                    .cornerRadius(14)
            }
            .disabled(viewModel.isProjectFinished)
            .opacity(viewModel.isProjectFinished ? 0.5 : 1.0)
        }
    }
    
    @ViewBuilder
    private func rowTwoButtons(width: CGFloat, height: CGFloat, font: Font) -> some View {
        HStack(spacing: 20) {
            Button(action: { showingQCPasswordSheet = true }) {
                HStack {
                    Image(systemName: viewModel.pauseState == .qcStop ? "lock.open.fill" : "exclamationmark.octagon.fill")
                    Text(viewModel.pauseState == .qcStop ? "QC Resume" : "QC Stop")
                }
                .font(font)
                .frame(width: width * 1.5, height: height)
                .background(viewModel.pauseState == .qcStop ? Color.green : Color.red)
                .foregroundColor(.white)
                .cornerRadius(14)
            }
            .disabled(viewModel.isProjectFinished)
            .opacity(viewModel.isProjectFinished ? 0.5 : 1.0)
        }
    }
    
    @ViewBuilder
    private func rowThreeButtons(width: CGFloat, height: CGFloat, font: Font) -> some View {
        HStack(spacing: 20) {
            Button(action: { showingResetPasswordSheet = true }) {
                Text("Reset")
                    .font(font)
                    .frame(width: width, height: height)
                    .background(Color.red)
                    .foregroundColor(.white)
                    .cornerRadius(14)
            }
            
            Button(action: { sendEmailAndFinishProject() }) {
                Text("Finish")
                    .font(font)
                    .frame(width: width, height: height)
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(14)
            }
            .disabled(isSendingEmail)
            .opacity(isSendingEmail ? 0.5 : 1.0)
        }
    }
    
    private func showBanner(message: String, type: BannerType) {
        bannerTimer?.invalidate()
        withAnimation(.spring()) { currentBanner = BannerAlert(message: message, type: type) }
        bannerTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in withAnimation(.spring()) { currentBanner = nil } }
    }
    
    private func sendEmailAndFinishProject() {
        if !viewModel.isProjectFinished { viewModel.finishProject() }
        guard enableSmtpEmail else {
            emailAlertTitle = "Email Disabled"
            emailAlertMessage = "Email is disabled in settings. The project is finished and the timer is paused."
            showingEmailAlert = true
            return
        }
        isSendingEmail = true
        let settings = SmtpSettings(host: smtpHost, username: smtpUsername, password: smtpPassword, recipient: smtpRecipient)
        EmailManager.sendProjectFinishedEmail(viewModel: viewModel, settings: settings) { result in
            isSendingEmail = false
            switch result {
            case .success:
                emailAlertTitle = "Success"
                emailAlertMessage = "Email sent. Project resetting."
                showingEmailAlert = true
                performReset()
            case .failure(let error):
                emailAlertTitle = "Email Error"
                emailAlertMessage = "Error: \(error.localizedDescription)"
                showingEmailAlert = true
            }
        }
    }
    
    private func performReset() {
        viewModel.resetData()
        isReset = true
        companyNameInput = ""
        projectNameInput = ""
        lineLeaderNameInput = ""
    }
    
    // MARK: - Reusable Views
    @ViewBuilder
    private func timeInputBox(title: String, text: Binding<String>, selected: Bool, width: CGFloat, height: CGFloat, fontSize: CGFloat) -> some View {
        VStack {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.9))
                    .frame(width: width, height: height)
                    .shadow(radius: 4)
                HStack(spacing: 0) {
                    Text(text.wrappedValue)
                        .font(.system(size: fontSize, weight: .semibold))
                    if selected && showCursor {
                        Rectangle()
                            .fill(Color.black)
                            .frame(width: 2, height: fontSize * 1.1)
                            .padding(.leading, 2)
                    }
                }
            }
            Text(title)
                .font(.system(size: fontSize * 0.4))
        }
    }
    
    @ViewBuilder
    private func numButton(_ label: String, color: Color = .gray, width: CGFloat, height: CGFloat) -> some View {
        Button(action: { handleNumberPress(label) }) {
            Text(label)
                .frame(width: width, height: height)
                .background(color.opacity(0.8))
                .foregroundColor(.white)
                .cornerRadius(14)
                .font(.system(size: height * 0.4, weight: .semibold))
        }
    }
    
    private func handleNumberPress(_ label: String) {
        var binding: Binding<String>
        switch selectedField {
        case .hours: binding = $hoursInput
        case .minutes: binding = $minutesInput
        case .seconds: binding = $secondsInput
        case .none: return
        }
        if label == "⌫" {
            if !binding.wrappedValue.isEmpty { binding.wrappedValue.removeLast() }
        } else {
            if selectedField == .hours {
                binding.wrappedValue.append(label)
            } else {
                if binding.wrappedValue.count < 2 { binding.wrappedValue.append(label) }
            }
        }
    }
    
    private func startCursorBlink() {
        cursorTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { _ in withAnimation(.easeInOut(duration: 0.1)) { showCursor.toggle() } }
    }
    
    private func stopCursorBlink() {
        cursorTimer?.invalidate()
        cursorTimer = nil
    }
    
    private func passwordSheetPopup(showError: Binding<Bool>, isPresented: Binding<Bool>, title: String, correctPassword: String, onSuccess: @escaping () -> Void) -> some View {
        GeometryReader { sheetGeometry in
            let g = sheetGeometry.size
            let popupWidth = min(g.width * 0.8, 380.0)
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
                        .font(.headline)
                        .padding(.bottom, 10)
                    
                    SecureField("Password", text: $passwordField)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(width: popupWidth * 0.7)
                    
                    if showError.wrappedValue {
                        Text("Incorrect Password")
                            .foregroundColor(.red)
                    } else {
                        Text(" ")
                            .font(.callout)
                    }
                    
                    VStack(spacing: 12) {
                        ForEach([[1,2,3],[4,5,6],[7,8,9]], id: \.self) { row in
                            HStack(spacing: 12) {
                                ForEach(row, id: \.self) { num in
                                    keypadButton("\(num)", size: 90, fontSize: 36) {
                                        showError.wrappedValue = false
                                        passwordField.append("\(num)")
                                    }
                                }
                            }
                        }
                        HStack(spacing: 12) {
                            keypadButton("⌫", color: .red, size: 90, fontSize: 36) {
                                showError.wrappedValue = false
                                if !passwordField.isEmpty { passwordField.removeLast() }
                            }
                            keypadButton("0", size: 90, fontSize: 36) {
                                showError.wrappedValue = false
                                passwordField.append("0")
                            }
                            keypadButton("OK", color: .blue, size: 90, fontSize: 36) {
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
    
    @ViewBuilder
    private func keypadButton(_ label: String, color: Color = .gray, size: CGFloat, fontSize: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .frame(width: size, height: size)
                .background(color.opacity(0.8))
                .foregroundColor(.white)
                .cornerRadius(14)
                .font(.system(size: fontSize, weight: .semibold))
        }
    }
    
    private func handleRFIDSubmit() {
        if let feedback = viewModel.handleRFIDScan(for: rfidInput) {
            switch feedback {
            case .clockedIn(let id):
                showBanner(message: "Worker \(id) Clocked In", type: .info)
            case .clockedOut(let id):
                showBanner(message: "Worker \(id) Clocked Out", type: .info)
            case .ignoredPaused:
                showBanner(message: "Scan Ignored: Timer is Paused", type: .warning)
            case .ignoredFinished:
                showBanner(message: "Scan Ignored: Project is Finished", type: .warning)
            }
        }
        rfidInput = ""
    }
}
