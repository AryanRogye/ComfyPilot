//
//  WebController.swift
//  ComfyPilot
//
//  Created by Aryan Rogye on 4/26/26.
//

import Foundation

struct WebTab: Identifiable, Equatable {
    let id: UUID
    var title: String
    var url: URL
    var markdown: String
    var links: [URL]

    init(
        id: UUID = UUID(),
        title: String = "New Tab",
        url: URL = URL(string: "https://www.google.com")!,
        html: String = "",
        links: [URL] = []
    ) {
        self.id = id
        self.title = title
        self.url = url
        self.markdown = html
        self.links = links
    }
}

@MainActor
@Observable
final class WebController {

    var tabs: [WebTab] = [WebTab()]
    var selectedTabID: UUID?

    private var pendingContinuation: (tabID: UUID, continuation: CheckedContinuation<String, Never>)?
    
    var requestLiveHTML: [UUID: () async -> String] = [:]

    var selectedTab: WebTab? {
        guard let selectedTabID else { return tabs.first }
        return tabs.first { $0.id == selectedTabID } ?? tabs.first
    }

    var url: URL {
        get { selectedTab?.url ?? URL(string: "https://www.google.com")! }
        set { updateSelectedTab { $0.url = newValue } }
    }

    var html: String {
        get { selectedTab?.markdown ?? "" }
        set { updateSelectedTab { $0.markdown = newValue } }
    }

    var links: [URL] {
        get { selectedTab?.links ?? [] }
        set { updateSelectedTab { $0.links = newValue } }
    }

    init() {
        selectedTabID = tabs.first?.id
    }

    func didLoadPage(for tabID: UUID, url: URL?, title: String, html: String, links: [URL]) {
        guard !html.isEmpty else { return }

        updateTab(id: tabID) {
            if let newURL = url {
                $0.url = newURL
            }
            $0.title = title.isEmpty ? displayTitle(for: $0.url) : title
            $0.markdown = html
            $0.links = links
        }

        let continuation = pendingContinuation
        if continuation?.tabID == tabID {
            pendingContinuation = nil
            continuation?.continuation.resume(returning: html)
        }
    }

    private func updateTab(id: UUID, _ update: (inout WebTab) -> Void) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        var updatedTab = tabs[index]
        update(&updatedTab)
        tabs[index] = updatedTab
    }

    func selectTab(_ id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        selectedTabID = id
    }

    func createTab() {
        let tab = WebTab()
        tabs.append(tab)
        selectedTabID = tab.id
    }

    func closeTab(_ id: UUID) {
        guard tabs.count > 1 else { return }

        let wasSelected = selectedTabID == id
        tabs.removeAll { $0.id == id }

        if wasSelected {
            selectedTabID = tabs.first?.id
        }
    }
    
    func loadCurrentHTML() async -> String {
        guard let tabID = selectedTab?.id else {
            return "No active tab."
        }
        
        if let getter = requestLiveHTML[tabID] {
            let html = await getter()
            self.html = html
            return html
        }
        
        return html.isEmpty ? "No HTML loaded for current page." : html
    }
    
    func fetchMarkdown(for url: URL) async -> String {
        let jinaURL = URL(string: "https://r.jina.ai/\(url.absoluteString)")!
        var request = URLRequest(url: jinaURL)
        request.setValue("text/markdown", forHTTPHeaderField: "Accept")
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }
    
    func loadSearchHTML(for query: String) async -> String {
        let searchURL = searchURL(for: query)
        navigateSelectedTab(to: query)  // still navigate the browser visually
        return await fetchMarkdown(for: searchURL)  // but get content from Jina
    }

    func loadLinkHTML(at index: Int) async -> String {
        let linkIndex = index - 1
        let currentLinks = links
        guard currentLinks.indices.contains(linkIndex) else {
            return "No link exists at index \(index)."
        }
        let linkURL = currentLinks[linkIndex]
        url = linkURL
        return await fetchMarkdown(for: linkURL)
    }

    func navigateSelectedTab(to query: String) {
        url = searchURL(for: query)
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

    private func updateSelectedTab(_ update: (inout WebTab) -> Void) {
        guard let selectedTabID, let index = tabs.firstIndex(where: { $0.id == selectedTabID }) else {
            return
        }

        var updatedTab = tabs[index]
        update(&updatedTab)
        tabs[index] = updatedTab
    }

    private func displayTitle(for url: URL) -> String {
        url.host(percentEncoded: false) ?? url.absoluteString
    }
}
