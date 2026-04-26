//
//  Sidebar.swift
//  ComfyPilot
//
//  Created by Aryan Rogye on 4/26/26.
//

import SwiftUI

struct Sidebar: View {
    
    var backgroundColor: some ShapeStyle {
        LinearGradient(
            colors: [.pink.opacity(0.5), .red.opacity(0.5)],
            startPoint: .top,
            endPoint: .bottom
        )
    }
    
    var body: some View {
            VStack {
//                ForEach(browserVM.tabs) { tab in
//                    Text(tab.title)
//                        .lineLimit(1)
//                        .padding(6)
//                        .frame(maxWidth: .infinity)
//                        .background {
//                            RoundedRectangle(cornerRadius: 6)
//                                .fill(.white.opacity(0.3))
//                        }
//                        .padding(.horizontal, 4)
//                }
                Text("This is Sidebar")
                    .foregroundStyle(.white)
            }
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity
            )
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(backgroundColor)
                    .stroke(.white.opacity(0.3), style: .init(lineWidth: 1))
            }
    }
}
