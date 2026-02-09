//
//  EditHoursView.swift
//  RFID Time Tracking
//
//

import SwiftUI

struct EditHoursView: View {
    @EnvironmentObject var viewModel: WorkerViewModel

    var body: some View {
        List {
            Section(header: Text("Select a worker to edit their total logged hours.")) {
                if viewModel.workers.isEmpty {
                    Text("No active workers in this session.")
                        .foregroundColor(.secondary)
                } else {
                    // Sort workers by name
                    ForEach(viewModel.workers.keys.sorted(by: { viewModel.getWorkerName(id: $0) < viewModel.getWorkerName(id: $1) }), id: \.self) { workerID in
                        if let worker = viewModel.workers[workerID] {
                            NavigationLink(destination: EditWorkerTimeView(workerID: workerID)) {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(viewModel.getWorkerName(id: workerID))
                                            .font(.headline)
                                            .foregroundColor(.primary)
                                        
                                        if worker.clockInTime != nil {
                                            Text("Currently Clocked In")
                                                .font(.caption2)
                                                .foregroundColor(.green)
                                                .padding(.top, 1)
                                        }
                                    }
                                    
                                    Spacer()
                                    
                                    Text(formatTime(worker.totalMinutesWorked))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            
            Section {
                VStack(alignment: .leading, spacing: 5) {
                    Label("Warning", systemImage: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.headline)
                    Text("Manually editing hours will adjust the remaining project time and disqualify this project from automatic bonuses on the dashboard.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 5)
            }
        }
        .navigationTitle("Edit Hours")
    }

    func formatTime(_ minutes: Double) -> String {
        let h = Int(minutes / 60)
        let m = Int(minutes.truncatingRemainder(dividingBy: 60))
        return String(format: "%dh %02dm", h, m)
    }
}

// --- UPDATED VIEW WITH FIXED INTERACTION ---
struct EditWorkerTimeView: View {
    @EnvironmentObject var viewModel: WorkerViewModel
    @Environment(\.presentationMode) var presentationMode
    
    let workerID: String
    
    @State private var hoursStr: String = ""
    @State private var minutesStr: String = ""
    
    // Custom Keyboard State
    @State private var showingNumpad = false
    @State private var activeField: EditableField? = nil
    
    enum EditableField {
        case hours, minutes
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                
                // 1. The Form (Content)
                Form {
                    Section(header: Text("Edit Total Hours")) {
                        // HOURS FIELD
                        Button(action: {
                            activeField = .hours
                            withAnimation { showingNumpad = true }
                        }) {
                            HStack {
                                Text("Hours")
                                    .foregroundColor(.primary)
                                Spacer()
                                Text(hoursStr.isEmpty ? "0" : hoursStr)
                                    .foregroundColor(activeField == .hours && showingNumpad ? .blue : .gray)
                                    .fontWeight(activeField == .hours && showingNumpad ? .bold : .regular)
                            }
                        }
                        
                        // MINUTES FIELD
                        Button(action: {
                            activeField = .minutes
                            withAnimation { showingNumpad = true }
                        }) {
                            HStack {
                                Text("Minutes")
                                    .foregroundColor(.primary)
                                Spacer()
                                Text(minutesStr.isEmpty ? "0" : minutesStr)
                                    .foregroundColor(activeField == .minutes && showingNumpad ? .blue : .gray)
                                    .fontWeight(activeField == .minutes && showingNumpad ? .bold : .regular)
                            }
                        }
                    }
                    
                    Section(footer: Text("Changes will immediately adjust the main timer countdown.")) {
                        Button("Save & Update Timer") {
                            saveChanges()
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .foregroundColor(.red)
                    }
                }
                // REMOVED: .disabled(showingNumpad) <--- This was causing the issue
                
                // 2. Invisible Overlay to Dismiss (Only when keyboard is up)
                if showingNumpad {
                    Color.black.opacity(0.001) // Nearly invisible but tappable
                        .edgesIgnoringSafeArea(.all)
                        .onTapGesture {
                            withAnimation { showingNumpad = false }
                        }
                }
                
                // 3. The Custom Keyboard
                if showingNumpad {
                    CustomNumericKeyboard(
                        text: bindingForActiveField(),
                        isPresented: $showingNumpad,
                        geometry: geometry
                    )
                    .transition(.move(edge: .bottom))
                    .zIndex(1)
                }
            }
        }
        .navigationTitle(viewModel.getWorkerName(id: workerID))
        .onAppear {
            loadData()
            
            // Auto-open keyboard for Hours after a short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                activeField = .hours
                withAnimation { showingNumpad = true }
            }
        }
    }
    
    private func bindingForActiveField() -> Binding<String> {
        guard let field = activeField else { return .constant("") }
        switch field {
        case .hours:
            return $hoursStr
        case .minutes:
            return $minutesStr
        }
    }
    
    func loadData() {
        if let w = viewModel.workers[workerID] {
            let total = w.totalMinutesWorked
            let h = Int(total / 60)
            let m = Int(total.truncatingRemainder(dividingBy: 60))
            hoursStr = "\(h)"
            minutesStr = "\(m)"
        }
    }
    
    func saveChanges() {
        let h = Double(hoursStr) ?? 0
        let m = Double(minutesStr) ?? 0
        let total = (h * 60) + m
        viewModel.updateWorkerTotalTime(id: workerID, newTotalMinutes: total)
        presentationMode.wrappedValue.dismiss()
    }
}
