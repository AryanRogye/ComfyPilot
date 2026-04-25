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
    
    var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            NavigationLink(destination: ModelsInfoView(
                loaderService: loaderService
            )) {
                Image(systemName: "arrow.down.circle")
            }
        }
        ToolbarItem(placement: .navigation) {
            Button {
                loaderService.openModelFolder()
            } label: {
                Image(systemName: "folder")
            }
        }
    }
}
