//
//  SettingsSelectionView.swift
//  RFID Time Tracking
//
//

import SwiftUI

// --- NEW: Main selection view ---
struct SettingsSelectionView: View {
    @EnvironmentObject var viewModel: WorkerViewModel
    @Binding var isPresented: Bool
    @Binding var showingSettingsKeyboard: Bool
    @Binding var settingsKeyboardBinding: Binding<String>?
    @Binding var showingSettingsNumericKeyboard: Bool
    @Binding var settingsNumericKeyboardBinding: Binding<String>?
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("New Project Setup")) {
                    Button("Manual Setup Wizard") {
                        // Clear old data
                        viewModel.companyName = ""
                        viewModel.projectName = ""
                        viewModel.lineLeaderName = ""
                        
                        // Trigger the view change
                        viewModel.showManualSetup = true
                        isPresented = false // Close the settings menu
                    }
                }
                NavigationLink("App Settings", destination: AppSettingsView(
                    showingSettingsKeyboard: $showingSettingsKeyboard,
                    settingsKeyboardBinding: $settingsKeyboardBinding,
                    showingSettingsNumericKeyboard: $showingSettingsNumericKeyboard,
                    settingsNumericKeyboardBinding: $settingsNumericKeyboardBinding
                ))
                NavigationLink("Email Settings", destination: EmailSettingsView())
                NavigationLink("Manual Clock Out", destination: ManualClockOutView())
            }
            .navigationTitle("Settings")
            .navigationBarItems(trailing: Button("Done") {
                withAnimation {
                    isPresented = false
                }
            })
        }
        .navigationViewStyle(.stack)
    }
}
