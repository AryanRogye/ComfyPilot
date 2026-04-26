//
//  Sidebar.swift
//  ComfyPilot
//
//  Created by Aryan Rogye on 4/26/26.
//

import SwiftUI

struct Sidebar: View {
    
    @Bindable var webController: WebController
    
    var backgroundColor: some ShapeStyle {
        LinearGradient(
            colors: [.pink.opacity(0.5), .red.opacity(0.5)],
            startPoint: .top,
            endPoint: .bottom
        )
    }
    
    var body: some View {
            VStack(spacing: 8) {
                HStack {
                    Text("Tabs")
                        .font(.headline)
                    
                    Spacer()
                    
                    Button {
                        webController.createTab()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.plain)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.top, 10)
                
                ForEach(webController.tabs) { tab in
                    tabRow(tab)
                }
                
                Spacer()
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
    
    private func tabRow(_ tab: WebTab) -> some View {
        HStack(spacing: 8) {
            Button {
                webController.selectTab(tab.id)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "globe")
                        .font(.caption)
                    
                    Text(tab.title)
                        .lineLimit(1)
                    
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            Button {
                webController.closeTab(tab.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .opacity(webController.tabs.count > 1 ? 1 : 0)
            .disabled(webController.tabs.count == 1)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background {
            RoundedRectangle(cornerRadius: 6)
                .fill(tab.id == webController.selectedTab?.id ? .white.opacity(0.28) : .white.opacity(0.12))
        }
        .padding(.horizontal, 6)
    }
}
