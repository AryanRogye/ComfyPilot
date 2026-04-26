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
    var html: String
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
        self.html = html
        self.links = links
    }
}

@MainActor
@Observable
final class WebController {

    var tabs: [WebTab] = [WebTab()]
    var selectedTabID: UUID?

    private var pendingContinuation: (tabID: UUID, continuation: CheckedContinuation<String, Never>)?

    var selectedTab: WebTab? {
        guard let selectedTabID else { return tabs.first }
        return tabs.first { $0.id == selectedTabID } ?? tabs.first
    }

    var url: URL {
        get { selectedTab?.url ?? URL(string: "https://www.google.com")! }
        set { updateSelectedTab { $0.url = newValue } }
    }

    var html: String {
        get { selectedTab?.html ?? "" }
        set { updateSelectedTab { $0.html = newValue } }
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
            $0.html = html
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

    func loadSearchHTML(for query: String) async -> String {
        let tabID = selectedTab?.id

        return await withCheckedContinuation { continuation in
            if let tabID {
                pendingContinuation = (tabID, continuation)
                navigateSelectedTab(to: query)
            } else {
                continuation.resume(returning: "No active tab.")
            }
        }
    }

    func loadLinkHTML(at index: Int) async -> String {
        let linkIndex = index - 1
        let currentLinks = links
        guard currentLinks.indices.contains(linkIndex) else {
            return "No link exists at index \(index)."
        }
        let tabID = selectedTab?.id

        return await withCheckedContinuation { continuation in
            if let tabID {
                pendingContinuation = (tabID, continuation)
                url = currentLinks[linkIndex]
            } else {
                continuation.resume(returning: "No active tab.")
            }
        }
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
