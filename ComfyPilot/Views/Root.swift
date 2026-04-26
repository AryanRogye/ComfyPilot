//
//  ContentView.swift
//  ComfyPilot
//
//  Created by Aryan Rogye on 4/24/26.
//

import SwiftUI
import ComfyPilotUI
import MLXKit

struct Root: View {
    @State private var loaderService = ModelLoaderService(selectFirst: true)
    @State private var vm = ChatViewModel()
    @State private var webController = WebController()
    @State private var sendingMessage = false
    @State private var loading = false
    
    @State private var showingSidebar = false
    @State private var showingChat = false
    
    var body: some View {
        ZStack {
            MeshGradientView()
            
            HStack {
                sidebar
                
                VStack(spacing: 0) {
                    TopBar()
                    
                    webView
                }
                .frame(minWidth: 420)
                
                chatSidebar
            }
            .padding(8)
            
        }
        .titlebarAppearsTransparent()
        /// this is if we load a model on start
        .task {
            if let selected = loaderService.selected {
                loadModel(model: selected)
            }
        }
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
                message: Text(vm.error ?? "Unknown Error")
            )
        }
        .toolbar {
            Toolbar(
                loaderService: loaderService,
                onToggleSidebar: {
                    withAnimation(.snappy) {
                        showingSidebar.toggle()
                    }
                },
                onToggleChat: {
                    withAnimation(.snappy) {
                        showingChat.toggle()
                    }
                }
            )
        }
    }
    
    private var webView: some View {
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
        .clipShape(
            .rect(
                bottomLeadingRadius: 8,
                bottomTrailingRadius: 8
            )
        )
    }
    
    @ViewBuilder
    private var sidebar: some View {
        if showingSidebar {
            Sidebar()
                .frame(minWidth: 180, idealWidth: 200, maxWidth: 240)
                .transition(.move(edge: .leading))
        }
    }
    
    @ViewBuilder
    private var chatSidebar: some View {
        if showingChat {
            ChatSidebar(
                vm: vm,
                sendingMessage: $sendingMessage
            )
            .frame(width: 300)
            .transition(.move(edge: .trailing))
        }
    }
    
    /**
     * Helper to load model once a model is selected
     */
    private func loadModel(model: MLXChatModel) {
        if loading { return }
        
        Task {
            loading = true
            defer { loading = false }
            
            await vm.load(model.url)
        }
    }
}

#Preview {
    NavigationStack {
        Root()
    }
}
