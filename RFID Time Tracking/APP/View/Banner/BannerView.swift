//
//  BannerView.swift
//  RFID Time Tracking
//
//

import SwiftUI

struct BannerView: View {
    let banner: BannerAlert
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: banner.type.icon)
                .font(.title2)
                .foregroundColor(.white)
            
            Text(banner.message)
                .font(.headline)
                .foregroundColor(.white)
            
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(banner.type.color)
        .cornerRadius(12)
        .padding(.horizontal)
        .shadow(radius: 5)
    }
}

#Preview {
    BannerView(banner: .init(message: "Alert", type: .error))
}
