//
//  AppSettingsView.swift
//  RFID Time Tracking
//

//

import SwiftUI

// --- MODIFIED: This is the file with the final changes ---
struct AppSettingsView: View {
    @EnvironmentObject var viewModel: WorkerViewModel
    
    @AppStorage(AppStorageKeys.pausePassword) private var pausePassword = "340340"
    @AppStorage(AppStorageKeys.resetPassword) private var resetPassword = "465465"
    
    @State private var timePickerBinding: Binding<Date>?
    @State private var showingTimePicker = false
    
    @Binding var showingSettingsKeyboard: Bool
    @Binding var settingsKeyboardBinding: Binding<String>?
    @Binding var showingSettingsNumericKeyboard: Bool
    @Binding var settingsNumericKeyboardBinding: Binding<String>?
    
    var body: some View {
        Form {
            Section(header: Text("Fleet Management")) {
                TextField("iPad ID (e.g., Prod 1)", text: $viewModel.fleetIpadID)
                    .autocapitalization(.words)
                
                if viewModel.fleetIpadID.isEmpty {
                    Text("Enter an ID to connect to the dashboard.")
                        .foregroundColor(.red)
                        .font(.caption)
                } else {
                    Text("Connected to Fleet Command")
                        .foregroundColor(.green)
                        .font(.caption)
                }
            }
            Section(header: Text("Passwords"), footer: Text("Used for the 'Pause' button on the timer screen.")) {
                Button(action: {
                    withAnimation {
                        settingsNumericKeyboardBinding = $pausePassword
                        showingSettingsNumericKeyboard = true
                    }
                }) {
                    HStack {
                        Text("Pause Password")
                            .foregroundColor(.primary)
                        Spacer()
                        Text(String(repeating: "•", count: pausePassword.count))
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Section(footer: Text("Used for the 'Reset Timer' button on the timer screen.")) {
                Button(action: {
                    withAnimation {
                        settingsNumericKeyboardBinding = $resetPassword
                        showingSettingsNumericKeyboard = true
                    }
                }) {
                    HStack {
                        Text("Reset Password")
                            .foregroundColor(.primary)
                        Spacer()
                        Text(String(repeating: "•", count: resetPassword.count))
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Section(header: Text("Procedure Codes"), footer: Text("Codes required for QC and Technician specific pauses.")) {
                // QC Code Button
                Button(action: {
                    withAnimation {
                        settingsNumericKeyboardBinding = $viewModel.qcCode
                        showingSettingsNumericKeyboard = true
                    }
                }) {
                    HStack {
                        Text("QC Code")
                            .foregroundColor(.primary)
                        Spacer()
                        // Shows bullet points instead of plain text
                        Text(viewModel.qcCode.isEmpty ? "Not Set" : String(repeating: "•", count: viewModel.qcCode.count))
                            .foregroundColor(.secondary)
                    }
                }
                
                // Technician Code Button
                Button(action: {
                    withAnimation {
                        settingsNumericKeyboardBinding = $viewModel.techCode
                        showingSettingsNumericKeyboard = true
                    }
                }) {
                    HStack {
                        Text("Technician Code")
                            .foregroundColor(.primary)
                        Spacer()
                        // Shows bullet points instead of plain text
                        Text(viewModel.techCode.isEmpty ? "Not Set" : String(repeating: "•", count: viewModel.techCode.count))
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Section(header: Text("Lunch Periods"), footer: Text("Set the start and end times for automatic lunch breaks. Tap Edit to delete.")) {
                ForEach($viewModel.lunchPeriods) { $period in
                    HStack {
                        HStack {
                            Text("Start:")
                            Spacer()
                            Text(period.start.formatted(date: .omitted, time: .shortened))
                                .foregroundColor(.blue)
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            timePickerBinding = $period.start
                            showingTimePicker = true
                        }
                        
                        HStack {
                            Text("End:")
                            Spacer()
                            Text(period.end.formatted(date: .omitted, time: .shortened))
                                .foregroundColor(.blue)
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            timePickerBinding = $period.end
                            showingTimePicker = true
                        }
                    }
                }
                .onDelete { offsets in
                    viewModel.lunchPeriods.remove(atOffsets: offsets)
                }
                Button("Add Lunch Period") {
                    viewModel.lunchPeriods.append(TimePeriod(start: viewModel.dateFrom(12, 0), end: viewModel.dateFrom(12, 30)))
                }
            }
            
            Section(header: Text("Shift Start Times"), footer: Text("The 'Lunch Used' flag will auto-reset at these times. Tap Edit to delete.")) {
                ForEach($viewModel.shiftStartTimes) { $shiftTime in
                    HStack {
                        Text("Shift Start")
                        Spacer()
                        Text(shiftTime.time.formatted(date: .omitted, time: .shortened))
                            .foregroundColor(.blue)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        timePickerBinding = $shiftTime.time
                        showingTimePicker = true
                    }
                }
                .onDelete { offsets in
                    viewModel.shiftStartTimes.remove(atOffsets: offsets)
                }
                Button("Add Shift Time") {
                    viewModel.shiftStartTimes.append(ShiftTime(time: viewModel.dateFrom(7, 0)))
                }
            }
            
            Section(header: Text("Manual Overrides"), footer: Text("This will allow the 'Lunch' button on the main screen to be used again.")) {
                Button("Manually Clear Lunch Lock") {
                    viewModel.hasUsedLunchBreak = false
                    viewModel.saveState()
                }
                .disabled(!viewModel.hasUsedLunchBreak)
                Button("Cancel Project Bonus") {
                        viewModel.cancelBonus()
                    }
                    .disabled(!viewModel.isBonusEligible) // Disable if already cancelled
                    .foregroundColor(.red)
            }
            
            Section(header: Text("Categories"), footer: Text("Add, remove, or edit categories for the dropdown menu. Tap Edit to delete.")) {
                ForEach($viewModel.categories) { $item in
                    Button(action: {
                        withAnimation {
                            settingsKeyboardBinding = $item.value
                            showingSettingsKeyboard = true
                        }
                    }) {
                        HStack {
                            Text(item.value)
                                .foregroundColor(.primary)
                            Spacer()
                        }
                    }
                }
                .onDelete { offsets in
                    viewModel.categories.remove(atOffsets: offsets)
                }
                Button("Add Category") {
                    viewModel.categories.append(EditableStringItem(value: "New Category"))
                }
            }
            
            Section(header: Text("Project Sizes"), footer: Text("Add, remove, or edit project sizes for the dropdown menu. Tap Edit to delete.")) {
                ForEach($viewModel.projectSizes) { $item in
                    Button(action: {
                        withAnimation {
                            settingsKeyboardBinding = $item.value
                            showingSettingsKeyboard = true
                        }
                    }) {
                        HStack {
                            Text(item.value)
                                .foregroundColor(.primary)
                            Spacer()
                        }
                    }
                }
                .onDelete { offsets in
                    viewModel.projectSizes.remove(atOffsets: offsets)
                }
                Button("Add Project Size") {
                    viewModel.projectSizes.append(EditableStringItem(value: "New Size"))
                }
            }
        }
        .navigationTitle("App Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                EditButton()
            }
        }
        .onDisappear {
            viewModel.saveCustomAppSettings()
        }
        .sheet(isPresented: $showingTimePicker) {
            if let timePickerBinding = timePickerBinding {
                VStack {
                    DatePicker("Select Time", selection: timePickerBinding, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                    
                    Button("Done") {
                        showingTimePicker = false
                        self.timePickerBinding = nil
                    }
                    .fontWeight(.bold)
                    .padding()
                }
                .presentationDetents([.height(250)])
            }
        }
    }
}
