//
//  ContentView+ViewBuilders.swift
//  RFID Time Tracking
//
//
import Foundation
import SwiftUI

//MARK: VIEW BUILDERS
extension ContentView {
    @ViewBuilder
     func waitingForCommandScreen() -> some View {
        VStack(spacing: 30) {
            // Connection Status
            Text(viewModel.fleetIpadID.isEmpty ? "NO ID CONFIG" : "CONNECTED: \(viewModel.fleetIpadID)")
                .font(.headline)
                .padding(10)
                .background(Color.black.opacity(0.4))
                .cornerRadius(8)
                .foregroundColor(viewModel.fleetIpadID.isEmpty ? .red : .green)
            
            if !viewModel.projectQueue.isEmpty {
                Menu {
                    ForEach(viewModel.projectQueue) { job in
                        Button(action: {
                            // --- NEW CODE (Uses Smart Trigger) ---
                            // This sends the job to the .onChange listener,
                            // which checks for a saved leader name and skips the popup if found.
                            viewModel.triggerQueueItem = job
                        }) {
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
    
    // MARK: - NEW: Project Info Screen (Screen 1)
    @ViewBuilder
     func projectInfoScreen(geometry: GeometryProxy) -> some View {
        let g = geometry.size
        let isLandscape = g.width > g.height
        
        let fieldWidth = min(g.width * 0.8, 600)
        let fieldMinHeight = isLandscape ? 44.0 : 60.0
        let fieldFontSize = min(g.width * (isLandscape ? 0.04 : 0.05), 30)
        let vSpacing = g.height * (isLandscape ? 0.02 : 0.04)
        
        VStack(spacing: vSpacing) {
            // --- 2. STANDARD INPUTS ---
            
            inputButtonViewBuilder(text: companyNameInput.isEmpty ? "Company Name" : companyNameInput, width: fieldWidth, height: fieldMinHeight, fontSize: fieldFontSize, isEmpty: companyNameInput.isEmpty) {
                withAnimation {
                    showingCompanyKeyboard = true
                }
            }
            
            inputButtonViewBuilder(text: projectNameInput.isEmpty ? "Project Name" : projectNameInput, width: fieldWidth, height: fieldMinHeight, fontSize: fieldFontSize, isEmpty: projectNameInput.isEmpty) {
                withAnimation {
                    showingProjectKeyboard = true
                }
            }
            
            // --- LINE LEADER SCAN INPUT ---
            VStack(alignment: .leading, spacing: 2) {
                if !lineLeaderNameInput.isEmpty {
                    Text("Line Leader").font(.caption).foregroundColor(.gray)
                }
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
            
            // --- 3. DYNAMIC CATEGORY DROPDOWN ---
            HStack {
                Text("Category:")
                    .font(.system(size: fieldFontSize * 0.8))
                    .foregroundColor(.gray)
                Spacer()
                Picker("Category", selection: $viewModel.category) {
                    Text("Select").tag("")
                    ForEach(viewModel.availableCategories, id: \.self) { cat in
                        Text(cat).tag(cat)
                    }
                }
                .pickerStyle(.menu)
                .scaleEffect(1.2)
            }
            .padding(isLandscape ? 8 : 12)
            .frame(maxWidth: fieldWidth)
            .frame(minHeight: fieldMinHeight)
            .background(Color.white.opacity(0.8))
            .cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.5), lineWidth: 1))
            
            // --- 4. DYNAMIC SIZE DROPDOWN ---
            HStack {
                Text("Size:")
                    .font(.system(size: fieldFontSize * 0.8))
                    .foregroundColor(.gray)
                Spacer()
                Picker("Size", selection: $viewModel.projectSize) {
                    Text("Select").tag("")
                    ForEach(viewModel.availableSizes, id: \.self) { size in
                        Text(size).tag(size)
                    }
                }
                .pickerStyle(.menu)
                .scaleEffect(1.2)
            }
            .padding(isLandscape ? 8 : 12)
            .frame(maxWidth: fieldWidth)
            .frame(minHeight: fieldMinHeight)
            .background(Color.white.opacity(0.8))
            .cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.5), lineWidth: 1))
            
            Spacer().frame(height: vSpacing)
            
            HStack(spacing: 20) {
                Button("Cancel") {
                    withAnimation { viewModel.showManualSetup = false }
                }
                .frame(width: 200, height: 75)
                .background(Color.red)
                .foregroundColor(.white)
                .cornerRadius(16)
                .shadow(radius: 6)
                
                Button("Next") {
                    viewModel.companyName = companyNameInput
                    viewModel.projectName = projectNameInput
                    viewModel.lineLeaderName = lineLeaderNameInput
                    viewModel.saveState()
                    showingTimerInputSheet = true
                }
                .frame(width: 200, height: 75)
                .background(isProjectInfoInvalid ? Color.gray : Color.blue)
                .foregroundColor(.white)
                .cornerRadius(16)
                .shadow(radius: 6)
                .disabled(isProjectInfoInvalid)
            }
        }
    }
    
    // MARK: - MODIFIED: Timer Input Screen (Screen 2)
    @ViewBuilder
     func timerInputScreen(geometry: GeometryProxy) -> some View {
        
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
                .padding(.top, 40)
                .padding(.bottom, vSpacing)
            
            HStack(spacing: g.width * 0.03) {
                timeInputBox(title: "Hours", text: $hoursInput, selected: selectedField == .hours, width: boxWidth, height: boxHeight, fontSize: boxFontSize)
                    .onTapGesture { selectedField = .hours }
                timeInputBox(title: "Minutes", text: $minutesInput, selected: selectedField == .minutes, width: boxWidth, height: boxHeight, fontSize: boxFontSize)
                    .onTapGesture { selectedField = .minutes }
                timeInputBox(title: "Seconds", text: $secondsInput, selected: selectedField == .seconds, width: boxWidth, height: boxHeight, fontSize: boxFontSize)
                    .onTapGesture { selectedField = .seconds }
            }
            .padding(.bottom, vSpacing)
            
            VStack(spacing: isLandscape ? 6 : 8) {
                ForEach([[1,2,3],[4,5,6],[7,8,9]], id: \.self) { row in
                    HStack(spacing: isLandscape ? 6 : 8) {
                        ForEach(row, id: \.self) { num in
                            numButton("\(num)", width: keyWidth, height: keyHeight)
                        }
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
                    }
                    .frame(width: keyWidth, height: keyHeight)
                    .background(Color.orange)
                    .foregroundColor(.white)
                    .cornerRadius(14)
                    .font(.system(size: keyHeight * 0.4, weight: .semibold))
                }
            }
            .padding(.bottom, vSpacing)
            
            Button("Start Timer") {
                let h = Int(hoursInput) ?? 0
                let m = Int(minutesInput) ?? 0
                let s = Int(secondsInput) ?? 0
                
                viewModel.resetTimer(
                    hours: h,
                    minutes: m,
                    seconds: s
                )
                isReset = false
                showingTimerInputSheet = false
            }
            .padding()
            .font(.system(size: startButtonHeight * 0.4, weight: .bold))
            .frame(width: startButtonWidth, height: startButtonHeight)
            .background(isStartTimeInvalid ? Color.gray : Color.blue)
            .foregroundColor(.white)
            .cornerRadius(16)
            .shadow(radius: 6)
            .disabled(isStartTimeInvalid)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(UIColor.systemGroupedBackground))
        .edgesIgnoringSafeArea(.all)
    }
    
    
    // MARK: - Timer Running Screen
    // Main operational UI where the operator scans RFID cards and controls
    // the running timer (pause, lunch, reset, finish project).
    @ViewBuilder
     func timerRunningScreen() -> some View {
        GeometryReader { geometry in
            // SCALED DOWN SIZES (approx 20% smaller than before)
            let timerFontSize = min(geometry.size.width * 0.18, 200)
            let headerFontSize = min(geometry.size.width * 0.05, 40)
            let subHeaderFontSize = min(geometry.size.width * 0.04, 30)
            
            VStack(spacing: 0) {
                Text(viewModel.timerText)
                    .font(.system(size: timerFontSize, weight: .bold, design: .monospaced))
                    .minimumScaleFactor(0.5).lineLimit(1).foregroundColor(.black)
                    .frame(maxWidth: .infinity).frame(height: timerFontSize * 1.1).padding(.top, 20)
                
                if !viewModel.companyName.isEmpty {
                    Text(viewModel.companyName).font(.system(size: headerFontSize, weight: .medium))
                        .foregroundColor(.black).padding(.bottom, 2).lineLimit(1).minimumScaleFactor(0.5).frame(height: headerFontSize).frame(maxWidth: .infinity).multilineTextAlignment(.center)
                }
                
                if !viewModel.projectName.isEmpty {
                    Text(viewModel.projectName).font(.system(size: headerFontSize, weight: .medium))
                        .foregroundColor(.black).padding(.bottom, 2).lineLimit(1).minimumScaleFactor(0.5).frame(height: headerFontSize).frame(maxWidth: .infinity).multilineTextAlignment(.center)
                }
                
                if !viewModel.lineLeaderName.isEmpty {
                    Text("Leader: \(viewModel.lineLeaderName)").font(.system(size: subHeaderFontSize, weight: .medium))
                        .foregroundColor(.black).padding(.bottom, 2).lineLimit(1).minimumScaleFactor(0.5).frame(height: subHeaderFontSize).frame(maxWidth: .infinity).multilineTextAlignment(.center)
                }
                
                // --- MODIFIED: ADD "Who's In" Button Next to Counter ---
                HStack(spacing: 15) {
                    Text("People Clocked In: \(viewModel.totalPeopleWorking)")
                        .font(.system(size: headerFontSize, weight: .medium))
                        .foregroundColor(.black)
                    
                    // The button that triggers the sheet
                                        Button(action: {
                                            // 1. Close the keyboard (stop editing)
                                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                                            
                                            // 2. Clear focus state specifically
                                            isRFIDFieldFocused = false
                                            
                                            // 3. Wait 0.1s for keyboard to slide down, THEN open sheet
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                                showingWhosInSheet = true
                                            }
                                        }) {
                                            HStack(spacing: 5) {
                                                Image(systemName: "list.bullet.rectangle.portrait")
                                                Text("Who?")
                                            }
                                            .font(.system(size: headerFontSize * 0.5, weight: .bold))
                                            .padding(.vertical, 8)
                                            .padding(.horizontal, 12)
                                            .background(Color.blue.opacity(0.1))
                                            .foregroundColor(.blue)
                                            .cornerRadius(8)
                                        }
                }
                .padding(.bottom, 10)
                .frame(maxWidth: .infinity)
                // --------------------------------------------------------
                
                // REDUCED BUTTON SIZES
                let buttonWidth = min(geometry.size.width * 0.28, 220.0)
                let buttonHeight = min(geometry.size.height * 0.10, 80.0)
                let buttonFont = Font.system(size: min(buttonWidth * 0.12, 22), weight: .semibold)
                
                // --- SPLIT INTO 2 ROWS FOR BETTER FIT ---
                VStack(spacing: 15) {
                    
                    // ROW 1: PAUSE, LUNCH, SAVE
                    HStack(spacing: 20) {
                        Button(action: { if viewModel.isPaused { viewModel.resumeTimer() } else { showingPasswordSheet = true } }) {
                            Text(viewModel.isPaused ? "Unpause" : "Pause")
                                .font(buttonFont).frame(width: buttonWidth, height: buttonHeight)
                                .background(viewModel.isPaused ? Color.green : Color.blue).foregroundColor(.white).cornerRadius(14)
                        }
                        .disabled(viewModel.isProjectFinished).opacity(viewModel.isProjectFinished ? 0.5 : 1.0)
                        
                        Button(action: {
                            let feedback = viewModel.takeLunchBreak()
                            if feedback == .ignoredPaused { showBanner(message: "Cannot take lunch while manually paused.", type: .warning) }
                            else if feedback == .ignoredNoWorkers { showBanner(message: "Cannot take lunch: No workers clocked in.", type: .warning) }
                        }) {
                            Text("Lunch").font(buttonFont).frame(width: buttonWidth, height: buttonHeight)
                                .background(viewModel.hasUsedLunchBreak ? Color.gray : Color.orange).foregroundColor(.white).cornerRadius(14)
                        }
                        .disabled(viewModel.hasUsedLunchBreak || viewModel.isProjectFinished || viewModel.pauseState == .manual || viewModel.pauseState == .autoLunch || viewModel.totalPeopleWorking == 0)
                        .opacity(viewModel.hasUsedLunchBreak || viewModel.isProjectFinished || viewModel.pauseState == .manual || viewModel.pauseState == .autoLunch || viewModel.totalPeopleWorking == 0 ? 0.5 : 1.0)
                        
                        // --- NEW SAVE BUTTON ---
                        Button(action: { viewModel.saveJobToQueue() }) {
                            Text("Save").font(buttonFont).frame(width: buttonWidth, height: buttonHeight)
                                .background(Color.purple).foregroundColor(.white).cornerRadius(14)
                        }
                        .disabled(viewModel.isProjectFinished).opacity(viewModel.isProjectFinished ? 0.5 : 1.0)
                    }
                    
                    // ROW 2: RESET, FINISH
                    HStack(spacing: 20) {
                        Button(action: { showingResetPasswordSheet = true }) {
                            Text("Reset").font(buttonFont).frame(width: buttonWidth, height: buttonHeight)
                                .background(Color.red).foregroundColor(.white).cornerRadius(14)
                        }
                        
                        Button(action: { sendEmailAndFinishProject() }) {
                            Text("Finish").font(buttonFont).frame(width: buttonWidth, height: buttonHeight)
                                .background(Color.green).foregroundColor(.white).cornerRadius(14)
                        }
                        .disabled(isSendingEmail).opacity(isSendingEmail ? 0.5 : 1.0)
                    }
                }
                .padding(.bottom, 20)
                
                // RFID Input Field
                VStack(spacing: 10) {
                    TextField("Scan RFID Card", text: $rfidInput)
                        .font(.system(size: min(geometry.size.width * 0.04, 28)))
                        .padding().textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(maxWidth: min(geometry.size.width * 0.85, 820))
                        .focused($isRFIDFieldFocused)
                        .onSubmit { handleRFIDSubmit(); self.isRFIDFieldFocused = true }
                        .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { self.isRFIDFieldFocused = false } } }
                }
                .padding(.bottom, 10)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    
    @ViewBuilder
     func timeInputBox(title: String, text: Binding<String>, selected: Bool, width: CGFloat, height: CGFloat, fontSize: CGFloat) -> some View {
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
     func numButton(_ label: String, color: Color = .gray, width: CGFloat, height: CGFloat) -> some View {
        Button(action: { handleNumberPress(label) }) {
            Text(label)
                .frame(width: width, height: height)
                .background(color.opacity(0.8))
                .foregroundColor(.white)
                .cornerRadius(14)
                .font(.system(size: height * 0.4, weight: .semibold))
        }
    }
    
    @ViewBuilder
     func keypadButton(_ label: String, color: Color = .gray, size: CGFloat, fontSize: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .frame(width: size, height: size)
                .background(color.opacity(0.8))
                .foregroundColor(.white)
                .cornerRadius(14)
                .font(.system(size: fontSize, weight: .semibold))
        }
    }
}
