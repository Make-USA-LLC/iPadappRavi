//
//  ManualClockOutView.swift
//  RFID Time Tracking
//
//

import SwiftUI

struct ActiveWorkerView: View {
    @EnvironmentObject var viewModel: WorkerViewModel
    
    private var clockedInWorkers: [Worker] {
        viewModel.workers.values
            .filter { $0.clockInTime != nil }
            .sorted { $0.id < $1.id }
    }
    
    var body: some View {
        Form {
            Section(header: Text("Clocked-In Workers"), footer: Text("Currently active on this project.")) {
                if clockedInWorkers.isEmpty {
                    Text("No workers are currently clocked in.")
                        .foregroundColor(.gray)
                } else {
                    ForEach(clockedInWorkers, id: \.id) { worker in
                        // --- UPDATED: Just an HStack (No Button) ---
                        HStack {
                            Text(viewModel.getWorkerName(id: worker.id))
                                .foregroundColor(.primary)
                                .font(.headline)
                            
                            Spacer()
                            
                            if let clockInTime = worker.clockInTime {
                                VStack(alignment: .trailing) {
                                    Text("In at: \(clockInTime.formatted(date: .omitted, time: .shortened))")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    
                                    // Optional: Show duration
                                    Text(calculateDuration(start: clockInTime))
                                        .font(.caption2)
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                        // -------------------------------------------
                    }
                }
            }
        }
        .navigationTitle("Who is In?") // Changed Title
        .navigationBarTitleDisplayMode(.inline)
    }
    
    // Helper to show how long they have been working
    private func calculateDuration(start: Date) -> String {
        let diff = Date().timeIntervalSince(start)
        let hours = Int(diff) / 3600
        let minutes = (Int(diff) % 3600) / 60
        return String(format: "%dh %02dm", hours, minutes)
    }
}
