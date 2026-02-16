import SwiftUI

// MARK: - VIEW BUILDERS EXTENSION
extension ContentView {
    
    // MARK: - Waiting For Command
    @ViewBuilder
    func waitingForCommandScreen() -> some View {
        VStack(spacing: 30) {
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
                    .frame(minWidth: 300)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                    .shadow(radius: 5)
                }
                .padding(.horizontal, 40)
            } else {
                Text("No Jobs in Queue")
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.gray.opacity(0.5))
                    .cornerRadius(8)
            }
            
            // --- NEW: MACHINE SETUP BUTTON ---
            Button(action: {
                showingMachineSetupSheet = true
            }) {
                HStack {
                    Image(systemName: "gearshape.2.fill")
                    Text("Machine Setup")
                }
                .font(.title2)
                .padding()
                .frame(minWidth: 300)
                .background(Color.purple)
                .foregroundColor(.white)
                .cornerRadius(12)
                .shadow(radius: 5)
            }
            .padding(.horizontal, 40)
            // ---------------------------------
            
            Button(action: {
                viewModel.companyName = ""
                viewModel.projectName = ""
                viewModel.lineLeaderName = ""
                withAnimation { viewModel.showManualSetup = true }
            }) {
                HStack {
                    Image(systemName: "square.and.pencil")
                    Text("Manual Project Setup")
                }
                .font(.title2)
                .padding()
                .frame(minWidth: 300)
                .background(Color.orange)
                .foregroundColor(.white)
                .cornerRadius(12)
                .shadow(radius: 5)
            }
            .padding(.horizontal, 40)
        }
    }
    
    // MARK: - Project Info Screen
    @ViewBuilder
    func projectInfoScreen(geometry: GeometryProxy) -> some View {
        let g = geometry.size
        let isLandscape = g.width > g.height
        
        let fieldWidth = min(g.width * 0.8, 600)
        let fieldMinHeight = isLandscape ? 44.0 : 60.0
        let fieldFontSize = min(g.width * (isLandscape ? 0.04 : 0.05), 30)
        let vSpacing = g.height * (isLandscape ? 0.02 : 0.04)
        
        VStack(spacing: vSpacing) {
            
            inputButtonViewBuilder(
                text: companyNameInput.isEmpty ? "Company Name" : companyNameInput,
                width: fieldWidth,
                height: fieldMinHeight,
                fontSize: fieldFontSize,
                isEmpty: companyNameInput.isEmpty
            ) {
                withAnimation { showingCompanyKeyboard = true }
            }
            
            inputButtonViewBuilder(
                text: projectNameInput.isEmpty ? "Project Name" : projectNameInput,
                width: fieldWidth,
                height: fieldMinHeight,
                fontSize: fieldFontSize,
                isEmpty: projectNameInput.isEmpty
            ) {
                withAnimation { showingProjectKeyboard = true }
            }
            
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
    
    // MARK: - Timer Input Screen
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
                viewModel.resetTimer(hours: h, minutes: m, seconds: s)
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
    
    // MARK: - Machine Setup Running Screen (Refined)
    @ViewBuilder
    func machineSetupRunningScreen() -> some View {
        GeometryReader { geometry in
            let timerFontSize = min(geometry.size.width * 0.18, 200)
            let headerFontSize = min(geometry.size.width * 0.05, 40)
            
            VStack(spacing: 0) {
                // HEADER TITLE
                Text("MACHINE SETUP MODE")
                    .font(.headline)
                    .padding(8)
                    .background(Color.purple.opacity(0.2))
                    .cornerRadius(8)
                    .padding(.top, 40)
                
                // TIMER DISPLAY
                Text(viewModel.timerText)
                    .font(.system(size: timerFontSize, weight: .bold, design: .monospaced))
                    .minimumScaleFactor(0.5).lineLimit(1).foregroundColor(.black)
                    .frame(maxWidth: .infinity).frame(height: timerFontSize * 1.1)
                
                // INFO
                if !viewModel.companyName.isEmpty {
                    Text(viewModel.companyName).font(.system(size: headerFontSize, weight: .medium))
                        .foregroundColor(.black).padding(.bottom, 2).frame(maxWidth: .infinity)
                }
                
                if !viewModel.projectName.isEmpty {
                    Text(viewModel.projectName).font(.system(size: headerFontSize, weight: .medium))
                        .foregroundColor(.black).padding(.bottom, 2).frame(maxWidth: .infinity)
                }
                
                // In setup mode, "Line Leader" is used to store the "Setup: Line Name" string
                if !viewModel.lineLeaderName.isEmpty {
                    Text(viewModel.lineLeaderName).font(.title3)
                        .foregroundColor(.gray).padding(.bottom, 20).frame(maxWidth: .infinity)
                }
                
                // --- WORKER COUNT & WHO'S IN ---
                HStack(spacing: 15) {
                    Text("People Clocked In: \(viewModel.totalPeopleWorking)")
                        .font(.system(size: headerFontSize, weight: .medium))
                        .foregroundColor(.black)
                    
                    Button(action: {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        isRFIDFieldFocused = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { showingWhosInSheet = true }
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: "list.bullet.rectangle.portrait")
                            Text("Who's In?")
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
                
                Spacer()
                
                // --- VISIBLE RFID INPUT (MOVED UP) ---
                VStack(spacing: 10) {
                    TextField("Scan RFID Card", text: $rfidInput)
                        .font(.system(size: min(geometry.size.width * 0.04, 28)))
                        .padding().textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(maxWidth: min(geometry.size.width * 0.85, 820))
                        .focused($isRFIDFieldFocused)
                        .onSubmit { handleRFIDSubmit(); self.isRFIDFieldFocused = true }
                        .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { self.isRFIDFieldFocused = false } } }
                }
                .padding(.bottom, 20)
                // --------------------------
                
                // CONTROLS (Pause, Lunch, Finish ONLY - MATCHING COLORS)
                let buttonWidth = min(geometry.size.width * 0.28, 220.0)
                let buttonHeight = min(geometry.size.height * 0.12, 100.0)
                let buttonFont = Font.system(size: min(buttonWidth * 0.12, 24), weight: .semibold)
                
                HStack(spacing: 30) {
                    // PAUSE (Blue/Green)
                    Button(action: { if viewModel.isPaused { viewModel.resumeTimer() } else { showingPasswordSheet = true } }) {
                        Text(viewModel.isPaused ? "Unpause" : "Pause")
                            .font(buttonFont)
                            .frame(width: buttonWidth, height: buttonHeight)
                            .background(viewModel.isPaused ? Color.green : Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(14)
                    }
                    .disabled(viewModel.isProjectFinished)
                    
                    // LUNCH (Orange/Gray)
                    Button(action: {
                        let feedback = viewModel.takeLunchBreak()
                        if feedback == .ignoredPaused { showBanner(message: "Cannot take lunch while manually paused.", type: .warning) }
                        else if feedback == .ignoredNoWorkers { showBanner(message: "Cannot take lunch: No workers clocked in.", type: .warning) }
                    }) {
                        Text("Lunch")
                            .font(buttonFont)
                            .frame(width: buttonWidth, height: buttonHeight)
                            .background(viewModel.hasUsedLunchBreak ? Color.gray : Color.orange)
                            .foregroundColor(.white)
                            .cornerRadius(14)
                    }
                    .disabled(viewModel.hasUsedLunchBreak || viewModel.isProjectFinished || viewModel.pauseState == .manual || viewModel.pauseState == .autoLunch || viewModel.totalPeopleWorking == 0)
                    .opacity(viewModel.hasUsedLunchBreak || viewModel.isProjectFinished || viewModel.pauseState == .manual || viewModel.pauseState == .autoLunch || viewModel.totalPeopleWorking == 0 ? 0.5 : 1.0)
                    
                    // FINISH (Green)
                    Button(action: { showingFinishConfirmation = true }) {
                        Text("Finish")
                            .font(buttonFont)
                            .frame(width: buttonWidth, height: buttonHeight)
                            .background(Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(14)
                    }
                    .disabled(isSendingEmail)
                    .alert(isPresented: $showingFinishConfirmation) {
                        Alert(
                            title: Text("Finish Setup?"),
                            message: Text("Are you sure you want to finish the setup for '\(viewModel.projectName)'?"),
                            primaryButton: .destructive(Text("Finish")) { sendEmailAndFinishProject() },
                            secondaryButton: .cancel()
                        )
                    }
                }
                .padding(.bottom, 60)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    
    // MARK: - Timer Running Screen
    @ViewBuilder
    func timerRunningScreen() -> some View {
        GeometryReader { geometry in
            let timerFontSize = min(geometry.size.width * 0.18, 200)
            let headerFontSize = min(geometry.size.width * 0.05, 40)
            let subHeaderFontSize = min(geometry.size.width * 0.04, 30)
            
            VStack(spacing: 0) {
                // TIMER DISPLAY
                Text(viewModel.timerText)
                    .font(.system(size: timerFontSize, weight: .bold, design: .monospaced))
                    .minimumScaleFactor(0.5).lineLimit(1).foregroundColor(.black)
                    .frame(maxWidth: .infinity).frame(height: timerFontSize * 1.1).padding(.top, 20)
                
                // INFO
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
                
                // --- WHO'S IN & PROCEDURES BUTTONS ---
                HStack(spacing: 15) {
                    Text("People Clocked In: \(viewModel.totalPeopleWorking)")
                        .font(.system(size: headerFontSize, weight: .medium))
                        .foregroundColor(.black)
                    
                    Button(action: {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        isRFIDFieldFocused = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { showingWhosInSheet = true }
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: "list.bullet.rectangle.portrait")
                            Text("Who's In?")
                        }
                        .font(.system(size: headerFontSize * 0.5, weight: .bold))
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(Color.blue.opacity(0.1))
                        .foregroundColor(.blue)
                        .cornerRadius(8)
                    }
                    
                    Button(action: { showingProceduresSheet = true }) {
                        HStack(spacing: 5) {
                            Image(systemName: "exclamationmark.triangle")
                            Text("Procedures")
                        }
                        .font(.system(size: headerFontSize * 0.5, weight: .bold))
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(Color.purple.opacity(0.1))
                        .foregroundColor(.purple)
                        .cornerRadius(8)
                    }
                    .disabled(viewModel.isProjectFinished)
                    .opacity(viewModel.isProjectFinished ? 0.5 : 1.0)
                }
                .padding(.bottom, 10)
                .frame(maxWidth: .infinity)
                
                let buttonWidth = min(geometry.size.width * 0.28, 220.0)
                let buttonHeight = min(geometry.size.height * 0.10, 80.0)
                let buttonFont = Font.system(size: min(buttonWidth * 0.12, 22), weight: .semibold)
                
                // CONTROLS
                VStack(spacing: 15) {
                    // --- LOCKED STATE OVERLAY LOGIC ---
                    if viewModel.pauseState == .qcCrew || viewModel.pauseState == .qcComponent {
                        VStack(spacing: 10) {
                            Text("⚠️ QC PAUSE ⚠️").font(.largeTitle).bold().foregroundColor(.red)
                            Text(viewModel.pauseState == .qcCrew ? "CREW OVERSIGHT" : "COMPONENT ISSUE").font(.title)
                            Button("ENTER QC CODE TO UNLOCK") {
                                showingQCUnlockAlert = true
                                showingQCUnlockSheet = true
                            }
                            .font(.title).bold()
                            .padding()
                            .background(Color.red).foregroundColor(.white).cornerRadius(10)
                        }
                        .frame(maxWidth: .infinity, maxHeight: 180)
                        .background(Color.white.opacity(0.9))
                    } else if viewModel.pauseState == .technician {
                        VStack(spacing: 10) {
                            Text("🔧 TECH PAUSE 🔧").font(.largeTitle).bold().foregroundColor(.orange)
                            Text(viewModel.techIssueLine.isEmpty ? "MACHINE MALFUNCTION" : viewModel.techIssueLine)
                                .font(.title)
                                .multilineTextAlignment(.center)
                            Button("RESUME") { viewModel.resumeTimer() }
                                .font(.title).bold().padding().background(Color.green).foregroundColor(.white).cornerRadius(10)
                        }
                        .frame(maxWidth: .infinity, maxHeight: 180)
                        .background(Color.white.opacity(0.9))
                    } else {
                        // NORMAL CONTROLS
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
                            
                            Button(action: { viewModel.saveJobToQueue() }) {
                                Text("Save").font(buttonFont).frame(width: buttonWidth, height: buttonHeight)
                                    .background(Color.purple).foregroundColor(.white).cornerRadius(14)
                            }
                            .disabled(viewModel.isProjectFinished).opacity(viewModel.isProjectFinished ? 0.5 : 1.0)
                        }
                        
                        HStack(spacing: 20) {
                            Button(action: { showingResetPasswordSheet = true }) {
                                Text("Reset").font(buttonFont).frame(width: buttonWidth, height: buttonHeight)
                                    .background(Color.red).foregroundColor(.white).cornerRadius(14)
                            }
                            
                            Button(action: { showingFinishConfirmation = true }) {
                                Text("Finish").font(buttonFont).frame(width: buttonWidth, height: buttonHeight)
                                    .background(Color.green).foregroundColor(.white).cornerRadius(14)
                            }
                            .disabled(isSendingEmail).opacity(isSendingEmail ? 0.5 : 1.0)
                            .alert(isPresented: $showingFinishConfirmation) {
                                Alert(
                                    title: Text("Finish Project?"),
                                    message: Text("Are you sure you want to finish '\(viewModel.projectName)'? This will clock out all workers."),
                                    primaryButton: .destructive(Text("Finish")) { sendEmailAndFinishProject() },
                                    secondaryButton: .cancel()
                                )
                            }
                        }
                    }
                }
                .padding(.bottom, 20)
                
                // RFID Input
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
            .alert("QC Unlock", isPresented: $showingQCUnlockAlert) {
                SecureField("QC Code", text: $qcUnlockCode)
                Button("Unlock") {
                    _ = viewModel.toggleQCPause(type: viewModel.pauseState, code: qcUnlockCode)
                    qcUnlockCode = ""
                }
                Button("Cancel", role: .cancel) { }
            }
        }
    }
    
    // MARK: - Helpers
    @ViewBuilder
    func inputButtonViewBuilder(text: String, width: CGFloat, height: CGFloat, fontSize: CGFloat, isEmpty: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(text)
                    .font(.system(size: fontSize))
                    .foregroundColor(isEmpty ? .gray : .black)
                Spacer()
            }
            .padding()
            .frame(maxWidth: width)
            .frame(height: height)
            .background(Color.white.opacity(0.8))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.gray.opacity(0.5), lineWidth: 1)
            )
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
