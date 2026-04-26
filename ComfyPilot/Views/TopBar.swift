//
//  TopBar.swift
//  ComfyPilot
//
//  Created by Aryan Rogye on 4/26/26.
//

import SwiftUI

struct TopBar: View {
    
    @Bindable var webController: WebController
    @State private var search: String = ""
    
    var body: some View {
        HStack {
            TextField(currentAddress, text: $search)
                .textFieldStyle(.plain)
                .onSubmit {
                    let trimmed = search.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    webController.navigateSelectedTab(to: trimmed)
                    search = ""
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
    
    private var currentAddress: String {
        webController.selectedTab?.url.absoluteString ?? "Search or enter website"
    }
}
