//
//  FirebaseManager.swift
//  RFID Time Tracking
//

import Foundation
import Firebase
import FirebaseFirestore
import FirebaseAuth

final class FirebaseManager {

    static let shared = FirebaseManager()

    private let db = Firestore.firestore()
    
    private var fleetListener: ListenerRegistration?
    private var queueListener: ListenerRegistration?

    private init() {}

    // MARK: - AUTH
    func observeAuthState(onAuthenticated: @escaping (User) -> Void) {
        _ = Auth.auth().addStateDidChangeListener { _ , user in
            if let user = user {
                onAuthenticated(user)
            }
        }
    }

    // MARK: - WORKERS
    func listenToWorkers(onUpdate: @escaping ([String: String]) -> Void) {
        db.collection("workers").addSnapshotListener { snapshot, _ in
            guard let docs = snapshot?.documents else { return }

            var cache: [String: String] = [:]
            for doc in docs {
                cache[doc.documentID] = doc.data()["name"] as? String ?? "Unknown"
            }
            onUpdate(cache)
        }
    }

    // MARK: - LINES (NEW)
    func fetchLines(completion: @escaping ([String]) -> Void) {
        db.collection("lines").order(by: "name").getDocuments { snapshot, error in
            guard let docs = snapshot?.documents else {
                print("Error fetching lines: \(error?.localizedDescription ?? "Unknown")")
                completion([])
                return
            }
            let lines = docs.compactMap { $0.data()["name"] as? String }
            completion(lines)
        }
    }
    
    // MARK: - GLOBAL WORKER LOCK (Prevent Double Logins)
    func checkGlobalWorkerStatus(workerId: String, completion: @escaping (String?) -> Void) {
        db.collection("global_active_workers").document(workerId).getDocument { snapshot, error in
            guard let data = snapshot?.data(),
                  let fleetId = data["fleetId"] as? String,
                  let timestamp = (data["timestamp"] as? Timestamp)?.dateValue() else {
                completion(nil)
                return
            }
            
            let twelveHours: TimeInterval = 12 * 60 * 60
            if Date().timeIntervalSince(timestamp) > twelveHours {
                print("⚠️ Found expired lock for \(workerId). Treating as free.")
                completion(nil)
            } else {
                completion(fleetId)
            }
        }
    }

    func setGlobalWorkerActive(workerId: String, fleetId: String) {
        let data: [String: Any] = [
            "fleetId": fleetId,
            "timestamp": FieldValue.serverTimestamp()
        ]
        db.collection("global_active_workers").document(workerId).setData(data)
    }

    func setGlobalWorkerInactive(workerId: String) {
        db.collection("global_active_workers").document(workerId).delete()
    }

    // MARK: - PROJECT QUEUE
    func listenToProjectQueue(onUpdate: @escaping ([ProjectQueueItem]) -> Void) {
        queueListener?.remove()
        queueListener = db.collection("project_queue")
            .order(by: "createdAt", descending: false)
            .addSnapshotListener { snap, _ in
                let items = snap?.documents.compactMap {
                    try? $0.data(as: ProjectQueueItem.self)
                } ?? []
                onUpdate(items)
            }
    }
    
    // MARK: - DROPDOWN CONFIG
    func listenToProjectOptions(
        onUpdate: @escaping (_ categories: [String], _ sizes: [String]) -> Void
    ) {
        db.collection("config")
            .document("project_options")
            .addSnapshotListener { snap, _ in
                guard let data = snap?.data() else { return }
                let categories = (data["categories"] as? [String] ?? []).sorted()
                let sizes = (data["sizes"] as? [String] ?? []).sorted()
                onUpdate(categories, sizes)
            }
    }

    // MARK: - FLEET SYNC
    func connectToFleet(
        fleetId: String,
        onUpdate: @escaping ([String: Any]) -> Void
    ) {
        fleetListener?.remove()

        fleetListener = db.collection("ipads")
            .document(fleetId)
            .addSnapshotListener { snap, _ in
                guard let data = snap?.data() else { return }
                onUpdate(data)
            }
    }

    func pushFleetState(
        fleetId: String,
        data: [String: Any]
    ) {
        db.collection("ipads")
            .document(fleetId)
            .setData(data, merge: true)
    }

    // MARK: - REPORTS
    func saveFinalReport(_ report: [String: Any]) {
        db.collection("reports").addDocument(data: report)
    }
    
    // --- NEW: Save to specific Machine Setup collection ---
    func saveMachineSetupReport(_ report: [String: Any]) {
        db.collection("machine_setup_reports").addDocument(data: report)
    }

    // MARK: - CLEANUP
    func disconnectFleet() {
        fleetListener?.remove()
        fleetListener = nil
        
        queueListener?.remove()
        queueListener = nil
    }
}
