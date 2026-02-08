//
//  CustomKeyboardViews.swift
//  RFID Time Tracking
//

//

import SwiftUI

// --- Custom Alphanumeric Keyboard View ---
// A simple on-screen keyboard used for entering company/project/line-leader text
struct CustomAlphanumericKeyboard: View {
    @Binding var text: String
    @Binding var isPresented: Bool
    let geometry: GeometryProxy
    
    let numbers = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
    let row1 = ["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P"]
    let row2 = ["A", "S", "D", "F", "G", "H", "J", "K", "L"]
    let row3 = ["Z", "X", "C", "V", "B", "N", "M"]
    
    let keyHeight: CGFloat = 65
    let keyCornerRadius: CGFloat = 8
    let horizontalSpacing: CGFloat = 6
    let verticalSpacing: CGFloat = 10
    
    var keyWidth: CGFloat {
        let effectiveWidth = geometry.size.width
        return (effectiveWidth - (11 * horizontalSpacing)) / 10
    }
    
    var body: some View {
        VStack(spacing: verticalSpacing) {
            HStack(spacing: horizontalSpacing) {
                ForEach(numbers, id: \.self) { key in
                    keyButton(key: key, width: keyWidth)
                }
            }
            HStack(spacing: horizontalSpacing) {
                ForEach(row1, id: \.self) { key in
                    keyButton(key: key, width: keyWidth)
                }
            }
            HStack(spacing: horizontalSpacing) {
                Spacer(minLength: (keyWidth / 2) + (horizontalSpacing / 2))
                ForEach(row2, id: \.self) { key in
                    keyButton(key: key, width: keyWidth)
                }
                Spacer(minLength: (keyWidth / 2) + (horizontalSpacing / 2))
            }
            HStack(spacing: horizontalSpacing) {
                Spacer(minLength: (keyWidth * 1.5) + (horizontalSpacing * 1.5))
                ForEach(row3, id: \.self) { key in
                    keyButton(key: key, width: keyWidth)
                }
                Spacer(minLength: (keyWidth * 1.5) + (horizontalSpacing * 1.5))
            }
            HStack(spacing: horizontalSpacing) {
                Button(action: {
                    if !text.isEmpty { text.removeLast() }
                }) {
                    Image(systemName: "delete.left.fill")
                        .font(.system(size: 22))
                        .frame(width: keyWidth * 1.5, height: keyHeight)
                        .background(Color(UIColor.systemGray))
                        .foregroundColor(.white)
                        .cornerRadius(keyCornerRadius)
                        .shadow(color: .black.opacity(0.35), radius: 0.5, x: 0, y: 1)
                }
                Button(action: { text.append(" ") }) {
                    Text("Space")
                        .font(.system(size: 20, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .frame(height: keyHeight)
                        .background(Color.white)
                        .foregroundColor(.primary)
                        .cornerRadius(keyCornerRadius)
                        .shadow(color: .black.opacity(0.35), radius: 0.5, x: 0, y: 1)
                }
                Button(action: {
                    withAnimation { isPresented = false }
                }) {
                    Text("Done")
                        .font(.system(size: 20, weight: .semibold))
                        .frame(width: keyWidth * 1.5, height: keyHeight)
                        .background(Color(UIColor.systemGray))
                        .foregroundColor(.white)
                        .cornerRadius(keyCornerRadius)
                        .shadow(color: .black.opacity(0.35), radius: 0.5, x: 0, y: 1)
                }
            }
        }
        .padding(.horizontal, horizontalSpacing)
        .padding(.vertical, 10)
        .background(Color(UIColor.systemGray3).edgesIgnoringSafeArea(.bottom))
        .frame(maxWidth: .infinity)
        
    }
    
    @ViewBuilder
    private func keyButton(key: String, width: CGFloat) -> some View {
        Button(action: {
            text.append(key)
        }) {
            Text(key)
                .font(.system(size: 26, weight: .medium))
                .frame(width: width)
                .frame(height: keyHeight)
                .background(Color.white)
                .foregroundColor(.primary)
                .cornerRadius(keyCornerRadius)
                .shadow(color: .black.opacity(0.35), radius: 0.5, x: 0, y: 1)
        }
    }
}

// --- NEW: Custom Numeric Keyboard View ---
// Reusable numeric keypad used for editing numeric settings such as passwords.
struct CustomNumericKeyboard: View {
    @Binding var text: String
    @Binding var isPresented: Bool
    let geometry: GeometryProxy
    
    let keyHeight: CGFloat = 65
    let keyCornerRadius: CGFloat = 8
    let horizontalSpacing: CGFloat = 6
    let verticalSpacing: CGFloat = 10
    
    var keyWidth: CGFloat {
        (geometry.size.width - (4 * horizontalSpacing)) / 3
    }
    
    var body: some View {
        VStack(spacing: verticalSpacing) {
            ForEach([[1,2,3],[4,5,6],[7,8,9]], id: \.self) { row in
                HStack(spacing: horizontalSpacing) {
                    ForEach(row, id: \.self) { num in
                        keyButton(key: "\(num)", width: keyWidth)
                    }
                }
            }
            HStack(spacing: horizontalSpacing) {
                Button(action: {
                    if !text.isEmpty { text.removeLast() }
                }) {
                    Image(systemName: "delete.left.fill")
                        .font(.system(size: 22))
                        .frame(width: keyWidth, height: keyHeight)
                        .background(Color(UIColor.systemGray))
                        .foregroundColor(.white)
                        .cornerRadius(keyCornerRadius)
                        .shadow(color: .black.opacity(0.35), radius: 0.5, x: 0, y: 1)
                }
                
                keyButton(key: "0", width: keyWidth)
                
                Button(action: {
                    withAnimation { isPresented = false }
                }) {
                    Text("Done")
                        .font(.system(size: 20, weight: .semibold))
                        .frame(width: keyWidth, height: keyHeight)
                        .background(Color(UIColor.systemGray))
                        .foregroundColor(.white)
                        .cornerRadius(keyCornerRadius)
                        .shadow(color: .black.opacity(0.35), radius: 0.5, x: 0, y: 1)
                }
            }
        }
        .padding(.horizontal, horizontalSpacing)
        .padding(.vertical, 10)
        .background(Color(UIColor.systemGray3).edgesIgnoringSafeArea(.bottom))
        .frame(maxWidth: .infinity)
    }
    
    @ViewBuilder
    private func keyButton(key: String, width: CGFloat) -> some View {
        Button(action: {
            text.append(key)
        }) {
            Text(key)
                .font(.system(size: 26, weight: .medium))
                .frame(width: width)
                .frame(height: keyHeight)
                .background(Color.white)
                .foregroundColor(.primary)
                .cornerRadius(keyCornerRadius)
                .shadow(color: .black.opacity(0.35), radius: 0.5, x: 0, y: 1)
        }
    }
}
