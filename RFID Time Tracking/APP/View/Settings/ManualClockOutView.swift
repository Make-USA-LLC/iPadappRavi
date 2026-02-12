//
//  ManualClockOutView.swift
//  RFID Time Tracking
//

//

import SwiftUI

struct ManualClockOutView: View {
    @EnvironmentObject var viewModel: WorkerViewModel
    
    private var clockedInWorkers: [Worker] {
        viewModel.workers.values
            .filter { $0.clockInTime != nil }
            .sorted { $0.id < $1.id }
    }
    
    var body: some View {
        Form {
            Section(header: Text("Clocked-In Workers"), footer: Text("Tap a worker to manually clock them out.")) {
                if clockedInWorkers.isEmpty {
                    Text("No workers are currently clocked in.")
                        .foregroundColor(.gray)
                } else {
                    ForEach(clockedInWorkers, id: \.id) { worker in
                        Button(action: {
                            viewModel.clockOut(for: worker.id)
                        }) {
                            HStack {
                                // --- CHANGE IS HERE: Use getWorkerName ---
                                Text(viewModel.getWorkerName(id: worker.id))
                                    .foregroundColor(.primary)
                                // ----------------------------------------
                                Spacer()
                                if let clockInTime = worker.clockInTime {
                                    Text("Clocked in at: \(clockInTime.formatted(date: .omitted, time: .shortened))")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Manual Clock Out")
        .navigationBarTitleDisplayMode(.inline)
    }
}
