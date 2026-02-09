//
//  SettingsSelectionView.swift
//  RFID Time Tracking
//
//

import SwiftUI

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
                // --- REMOVED: Manual Setup Section (Moved to Main Screen) ---
                
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
