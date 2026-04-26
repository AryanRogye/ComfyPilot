//
//  Toolbar.swift
//  ComfyPilot
//
//  Created by Aryan Rogye on 4/24/26.
//

import SwiftUI
import MLXKit

struct Toolbar: ToolbarContent {
    
    @Bindable var loaderService : ModelLoaderService
    var onToggleSidebar: () -> Void
    var onToggleChat: () -> Void
    
    var body: some ToolbarContent {
        
        // LEFT side
        ToolbarItem(placement: .navigation) {
            Button(action: onToggleSidebar) {
                Image(systemName: "sidebar.leading")
            }
        }
        
        // RIGHT side
        ToolbarItem(placement: .primaryAction) {
            Button(action: onToggleChat) {
                Image(systemName: "message")
            }
        }
        
        // CENTER / STATUS area
        ToolbarItemGroup(placement: .status) {
            NavigationLink(
                destination: ModelsInfoView(loaderService: loaderService)
            ) {
                Image(systemName: "arrow.down.circle")
            }
        }
    }
}
