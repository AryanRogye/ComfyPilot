//
//  ContentView.swift
//  ComfyPilot
//
//  Created by Aryan Rogye on 4/24/26.
//

import SwiftUI
import ComfyPilotUI
import MLXKit

struct ContentView: View {
    
    @State private var loaderService = ModelLoaderService()
    @State private var vm = ChatViewModel()
    @State private var webController = WebController()
    @State private var sendingMessage: Bool = false
    
    @State private var loading = false
    
    var body: some View {
        HSplitView {
            WebView(
                url: webController.url,
                html: Binding(
                    get: { webController.html },
                    set: { webController.didLoadHTML($0) }
                ),
                links: Binding(
                    get: { webController.links },
                    set: { webController.links = $0 }
                )
            )
                .frame(minWidth: 420)
            
            ChatSidebar(
                vm: vm,
                sendingMessage: $sendingMessage
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar { Toolbar(loaderService: loaderService) }
        .onAppear {
            vm.onSearch = { query in
                await webController.loadSearchHTML(for: query)
            }
            
            vm.onClickLink = { index in
                await webController.loadLinkHTML(at: index)
            }
        }
        .onChange(of: loaderService.selected) { _, newValue in
            if let newValue {
                loadModel(model: newValue)
            }
        }
        .alert(isPresented: $vm.showError) {
            Alert(
                title: Text("Error"),
                message: Text(vm.error ?? "Unkown Error")
            )
        }
    }
    
    /**
     * Helper to load model, this is important
     */
    private func loadModel(model: MLXChatModel) {
        if loading { return }
        Task {
            defer { loading = false }
            loading = true
            
            await vm.load(model.url)
        }
    }
}

#Preview {
    NavigationStack {
        ContentView()
    }
}
