//
//  QueueProjectStartSheet.swift
//  RFID Time Tracking
//

//

import SwiftUI

struct QueueProjectStartSheet: View {
    @Binding var isPresented: Bool
    @Binding var lineLeaderName: String
    let queueItem: ProjectQueueItem?
    let workerNames: [String: String] // <--- 1. NEW PROPERTY
    let onStart: () -> Void
    
    @FocusState private var isFieldFocused: Bool
    @State private var isKeyboardVisible = false
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color(UIColor.systemBackground)
                    .onTapGesture {
                        isFieldFocused = false
                        withAnimation { isKeyboardVisible = false }
                    }
                
                VStack(spacing: 25) {
                    Text("Start Project").font(.title).bold()
                    
                    if let item = queueItem {
                        VStack(spacing: 5) {
                            Text(item.project).font(.headline)
                            Text(item.company).foregroundColor(.secondary)
                            Text("\(item.category) • \(item.size)").font(.caption).foregroundColor(.secondary)
                        }
                    }
                    
                    // Input Field
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Line Leader (Scan Card)")
                            .font(.caption)
                            .foregroundColor(.gray)
                        
                        TextField("", text: $lineLeaderName)
                            .focused($isFieldFocused)
                            .font(.system(size: 20))
                            .padding(10)
                            .frame(maxWidth: 300)
                            .background(Color.white.opacity(0.8))
                            .cornerRadius(10)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.5), lineWidth: 1))
                            .onTapGesture {
                                withAnimation { isKeyboardVisible = true }
                            }
                        // --- 2. NEW: LOOKUP LOGIC ---
                            .onChange(of: lineLeaderName) { newValue in
                                if let name = workerNames[newValue] {
                                    lineLeaderName = name
                                    AudioPlayerManager.shared.playSound(named: "Cashier")
                                }
                            }
                        // ----------------------------
                            .onAppear {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                                    isFieldFocused = true
                                }
                            }
                    }
                    
                    HStack(spacing: 20) {
                        Button("Cancel") {
                            isPresented = false
                        }
                        .foregroundColor(.red)
                        .font(.title3)
                        
                        Button("START TIMER") {
                            onStart()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(lineLeaderName.isEmpty)
                        .font(.title3)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, 40)
                
                // Custom Keyboard Overlay
                if isKeyboardVisible {
                    VStack {
                        Spacer()
                        CustomAlphanumericKeyboard(
                            text: $lineLeaderName,
                            isPresented: $isKeyboardVisible,
                            geometry: geo
                        )
                    }
                    .transition(.move(edge: .bottom))
                    .zIndex(10)
                }
            }
        }
    }
}
