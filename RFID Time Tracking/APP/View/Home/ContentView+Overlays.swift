//
//  ContentView+Overlays.swift
//  RFID Time Tracking
//
//  Created by Nikk Bhateja on 10/01/26.
//

import Foundation
import SwiftUI

extension ContentView {
    func keyboardOverlayView() -> some View {
        ZStack {
            Color.black.opacity(0.001)
                .edgesIgnoringSafeArea(.all)
                .onTapGesture {
                    withAnimation {
                        showingCompanyKeyboard = false
                        showingProjectKeyboard = false
                        showingLineLeaderKeyboard = false
                    }
                }
            
            GeometryReader { geo in
                VStack {
                    Spacer()
                    CustomAlphanumericKeyboard(
                        text: $companyNameInput,
                        isPresented: $showingCompanyKeyboard,
                        geometry: geo
                    )
                }
            }
        }
    }
}
