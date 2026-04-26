//
//  TopBar.swift
//  ComfyPilot
//
//  Created by Aryan Rogye on 4/26/26.
//

import SwiftUI

struct TopBar: View {
    
    @State private var search: String = ""
    
    var body: some View {
        HStack {
            TextField("", text: $search)
                .textFieldStyle(.plain)
                .onSubmit {
                    if search.isEmpty { return }
//                    browserVM.createTab(search)
                }
            Spacer()
            Text("Middle")
            Spacer()
            Text("End")
        }
        .padding(.horizontal, 8)
        .foregroundStyle(.black)
        .frame(maxWidth: .infinity, maxHeight: 40)
        .background(.regularMaterial)
        .clipShape(
            .rect(
                topLeadingRadius: 8,
                topTrailingRadius: 8
            )
        )
    }
}
