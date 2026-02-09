//
//  FirebaseManager.swift
//  RFID Time Tracking
//
//

import Foundation
import Firebase
import FirebaseFirestore
import FirebaseAuth

final class FirebaseManager {

    static let shared = FirebaseManager()

    private let db = Firestore.firestore()
    
    // --- FIX: Add a variable to hold the queue listener ---
    private var fleetListener: ListenerRegistration?
    private var queueListener: ListenerRegistration?
    // -----------------------------------------------------

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

    // MARK: - PROJECT QUEUE
    func listenToProjectQueue(onUpdate: @escaping ([ProjectQueueItem]) -> Void) {
        // --- FIX: Remove existing listener before adding a new one ---
        queueListener?.remove()
        // ------------------------------------------------------------

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

    // MARK: - CLEANUP
    func disconnectFleet() {
        fleetListener?.remove()
        fleetListener = nil
        
        queueListener?.remove()
        queueListener = nil
    }
}
