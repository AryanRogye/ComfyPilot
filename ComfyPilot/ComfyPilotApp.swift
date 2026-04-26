//
//  ComfyPilotApp.swift
//  ComfyPilot
//
//  Created by Aryan Rogye on 4/24/26.
//

import SwiftUI

@main
struct ComfyPilotApp: App {
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                Root()
            }
        }
        .windowStyle(.hiddenTitleBar)
    }
}
