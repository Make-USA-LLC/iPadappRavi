import SwiftUI

struct ProceduresView: View {
    @ObservedObject var viewModel: WorkerViewModel
    @Environment(\.presentationMode) var presentationMode
    
    // UI State
    @State private var inputCode = ""
    @State private var targetAction: PauseType? = nil
    @State private var showError = false
    
    // New: Selected Machine for Tech Pause
    @State private var selectedMachine: String? = nil
    
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 20) {
                
                // --- TOP BAR ---
                HStack {
                    Text("Select Procedure")
                        .font(.system(size: 40, weight: .bold)) // Larger Title
                    Spacer()
                    Button("Close") {
                        presentationMode.wrappedValue.dismiss()
                    }
                    .font(.title2)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(10)
                }
                .padding(.top)
                .padding(.horizontal)
                
                // --- SELECTION BUTTONS (Top Half) ---
                HStack(spacing: 25) {
                    // 1. QC CREW PAUSE
                    ProcedureSelectionButton(
                        title: "QC: Crew Oversight",
                        icon: "exclamationmark.triangle.fill",
                        color: .purple,
                        subtitle: nil,
                        isSelected: targetAction == .qcCrew
                    ) {
                        targetAction = .qcCrew
                        inputCode = ""
                        showError = false
                        selectedMachine = nil
                    }
                    
                    // 2. QC COMPONENT PAUSE
                    ProcedureSelectionButton(
                        title: "QC: Component Issue",
                        icon: "shippingbox.fill",
                        color: .blue,
                        subtitle: nil,
                        isSelected: targetAction == .qcComponent
                    ) {
                        targetAction = .qcComponent
                        inputCode = ""
                        showError = false
                        selectedMachine = nil
                    }
                    
                    // 3. TECH PAUSE
                    ProcedureSelectionButton(
                        title: "Machine/Tech Issue",
                        icon: "wrench.fill",
                        color: .orange,
                        subtitle: nil,
                        isSelected: targetAction == .technician
                    ) {
                        targetAction = .technician
                        inputCode = ""
                        showError = false
                        selectedMachine = nil
                    }
                }
                .frame(height: 220) // Larger button area
                .padding(.horizontal)
                
                Divider()
                
                // --- PIN PAD SECTION (Bottom Half) ---
                if let target = targetAction {
                    VStack(spacing: 15) {
                        
                        // NEW: Machine Selection Dropdown
                        if target == .technician {
                            Text("Select Malfunctioning Machine")
                                .font(.headline)
                                .foregroundColor(.gray)
                            
                            Menu {
                                ForEach(viewModel.availableLines, id: \.self) { machine in
                                    Button(action: {
                                        selectedMachine = machine
                                        showError = false
                                    }) {
                                        HStack {
                                            Text(machine)
                                            if selectedMachine == machine {
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                            } label: {
                                HStack {
                                    // Displays the name of the machine here
                                    Text(selectedMachine ?? "Tap to Select Machine")
                                        .font(.title2)
                                        .fontWeight(.medium)
                                        .foregroundColor(selectedMachine == nil ? .gray : .primary)
                                    
                                    Spacer()
                                    
                                    Image(systemName: "chevron.down")
                                        .font(.title3)
                                        .foregroundColor(.gray)
                                }
                                .padding()
                                .background(Color.white)
                                .cornerRadius(12)
                                .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(selectedMachine != nil ? Color.orange : Color.gray.opacity(0.3), lineWidth: 2)
                                )
                            }
                            .frame(maxWidth: 400) // Limit width for cleaner look
                            .padding(.bottom, 10)
                        }
                        
                        // Only show Pin Pad if a machine is selected (for tech pause) or if it's not a tech pause
                        if target != .technician || selectedMachine != nil {
                            
                            Text("Enter \(target == .technician ? "Tech" : "QC") Code")
                                .font(.title)
                                .foregroundColor(.gray)
                            
                            // Code Dots
                            HStack(spacing: 15) {
                                ForEach(0..<4) { index in
                                    Circle()
                                        .stroke(Color.gray, lineWidth: 2)
                                        .background(Circle().fill(inputCode.count > index ? Color.black : Color.clear))
                                        .frame(width: 20, height: 20)
                                }
                            }
                            .padding(.bottom, 10)
                            
                            if showError {
                                Text("Incorrect Code")
                                    .font(.title3)
                                    .bold()
                                    .foregroundColor(.red)
                            } else {
                                Text(" ") // Placeholder to keep layout stable
                                    .font(.title3)
                            }
                            
                            // CUSTOM KEYPAD
                            CustomPinPad(code: $inputCode, onCommit: {
                                attemptUnlock(target: target)
                            })
                            
                        } else if target == .technician && selectedMachine == nil {
                            Spacer()
                            Text("Please select a machine from the dropdown above.")
                                .font(.title3)
                                .foregroundColor(.orange)
                                .padding()
                            Spacer()
                        }
                    }
                    .padding()
                    .background(Color.white)
                    .cornerRadius(20)
                    .shadow(radius: 5)
                    .frame(maxWidth: 600)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    Spacer()
                    Text("Select a procedure above to begin.")
                        .font(.title2)
                        .foregroundColor(.gray.opacity(0.5))
                    Spacer()
                }
            }
        }
        .background(Color(UIColor.systemGroupedBackground))
    }
    
    // MARK: - Logic
    func attemptUnlock(target: PauseType) {
        var success = false
        if target == .technician {
            // Pass the selected machine to the view model
            success = viewModel.toggleTechPause(code: inputCode, line: selectedMachine)
        } else {
            success = viewModel.toggleQCPause(type: target, code: inputCode)
        }
        
        if success {
            presentationMode.wrappedValue.dismiss()
        } else {
            showError = true
            inputCode = ""
            
            // Haptic Feedback for error
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)
        }
    }
}

// MARK: - Subcomponents

struct ProcedureSelectionButton: View {
    let title: String
    let icon: String
    let color: Color
    let subtitle: String?
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 15) {
                Image(systemName: icon)
                    .font(.system(size: 50))
                
                Text(title)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                
                if let sub = subtitle {
                    Text(sub)
                        .font(.caption)
                        .fontWeight(.bold)
                        .padding(6)
                        .background(Color.white.opacity(0.3))
                        .cornerRadius(5)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(isSelected ? color : color.opacity(0.15))
            .foregroundColor(isSelected ? .white : color)
            .cornerRadius(20)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(color, lineWidth: isSelected ? 4 : 2)
            )
            .shadow(color: isSelected ? color.opacity(0.4) : .clear, radius: 10)
            .scaleEffect(isSelected ? 1.02 : 1.0)
            .animation(.spring(), value: isSelected)
        }
    }
}

struct CustomPinPad: View {
    @Binding var code: String
    var onCommit: () -> Void
    
    let columns = [
        GridItem(.fixed(100), spacing: 20),
        GridItem(.fixed(100), spacing: 20),
        GridItem(.fixed(100), spacing: 20)
    ]
    
    var body: some View {
        LazyVGrid(columns: columns, spacing: 20) {
            ForEach(1...9, id: \.self) { num in
                PinButton(label: "\(num)") {
                    if code.count < 4 { code.append("\(num)") }
                }
            }
            
            // Bottom Row
            PinButton(label: "⌫", color: .red.opacity(0.1), textColor: .red) {
                if !code.isEmpty { code.removeLast() }
            }
            
            PinButton(label: "0") {
                if code.count < 4 { code.append("0") }
            }
            
            PinButton(label: "OK", color: .green, textColor: .white) {
                onCommit()
            }
        }
    }
}

struct PinButton: View {
    let label: String
    var color: Color = Color.gray.opacity(0.1)
    var textColor: Color = .primary
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.title)
                .fontWeight(.bold)
                .frame(width: 100, height: 75) // Large touch target
                .background(color)
                .foregroundColor(textColor)
                .cornerRadius(15)
        }
    }
}
