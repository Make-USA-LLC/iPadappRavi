//
//  View+Ext.swift
//  RFID Time Tracking
//

//

import SwiftUI

extension View {
    @ViewBuilder
    func inputButtonViewBuilder(
        text: String,
        width: CGFloat,
        height: CGFloat,
        fontSize: CGFloat,
        isEmpty: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: fontSize))
                .padding(8)
                .frame(maxWidth: width)
                .frame(minHeight: height)
                .background(Color.white.opacity(0.8))
                .foregroundColor(isEmpty ? .gray : .black)
                .cornerRadius(10)
                .shadow(radius: 3)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.gray.opacity(0.5), lineWidth: 1)
                )
        }
    }
}

