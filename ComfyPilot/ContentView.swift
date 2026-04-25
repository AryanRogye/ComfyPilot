//
//  ContentView.swift
//  ComfyPilot
//
//  Created by Aryan Rogye on 4/24/26.
//

import SwiftUI
import MLXKit

struct ContentView: View {
    
    @State private var loaderService = ModelLoaderService()
    @State private var vm = ChatViewModel()
    @State private var sendingMessage: Bool = false
    
    @State private var loading = false
    @State private var webURL = URL(string: "https://www.google.com")!
    @State private var webHTML = ""
    @State private var webLinks: [URL] = []
    @State private var pendingSearchContinuation: CheckedContinuation<String, Never>?
    
    var body: some View {
        HSplitView {
            WebView(url: webURL, html: $webHTML, links: $webLinks)
                .frame(minWidth: 420)
            
            VStack {
                ChatListView(chatVM: vm)
                    .safeAreaInset(edge: .bottom) {
                        BottomBar(sendingMessage: $sendingMessage) { text in
                            vm.send(text)
                        }
                        
                    }
                }
            .frame(minWidth: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar { Toolbar(loaderService: loaderService) }
        .onAppear {
            vm.onSearch = { query in
                await loadSearchHTML(for: query)
            }
            
            vm.onClickLink = { index in
                await loadLinkHTML(at: index)
            }
        }
        .onChange(of: webHTML) { _, html in
            guard !html.isEmpty else { return }
            
            let continuation = pendingSearchContinuation
            pendingSearchContinuation = nil
            continuation?.resume(returning: html)
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
    
    private func loadModel(model: MLXChatModel) {
        if loading { return }
        Task {
            defer { loading = false }
            loading = true
            
            await vm.load(model.url)
        }
    }
    
    private func searchURL(for query: String) -> URL {
        if let url = URL(string: query), url.scheme == "http" || url.scheme == "https" {
            return url
        }
        
        var components = URLComponents(string: "https://www.google.com/search")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query)
        ]
        return components.url!
    }
    
    private func loadSearchHTML(for query: String) async -> String {
        await withCheckedContinuation { continuation in
            pendingSearchContinuation = continuation
            webURL = searchURL(for: query)
        }
    }
    
    private func loadLinkHTML(at index: Int) async -> String {
        let linkIndex = index - 1
        guard webLinks.indices.contains(linkIndex) else {
            return "No link exists at index \(index)."
        }
        
        return await withCheckedContinuation { continuation in
            pendingSearchContinuation = continuation
            webURL = webLinks[linkIndex]
        }
    }
}

#Preview {
    NavigationStack {
        ContentView()
    }
}
