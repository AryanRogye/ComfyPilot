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
    private var searchContinuation: (tabID: UUID, continuation: CheckedContinuation<Void, Never>)?

    var requestLiveHTML: [UUID: () async -> String] = [:]
    var requestLiveJS: [UUID: (String) async -> String] = [:]
    
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
        
        let searchCont = searchContinuation
        if searchCont?.tabID == tabID {
            searchContinuation = nil
            searchCont?.continuation.resume()
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
    
    /**
     * Function Searches and Loads The Markdown For the search URL
     */
    public func loadSearchHTML(for query: String) async -> String {
        guard let tabID = selectedTab?.id else { return "No active tab." }
        
        navigateSelectedTab(to: query)
        
        await withCheckedContinuation { continuation in
            searchContinuation = (tabID: tabID, continuation: continuation)
        }
        
        // Now the page is loaded, snapshot it
        return await takeSnapshot()
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
    
    func takeSnapshot() async -> String {
        guard let tabID = selectedTab?.id else {
            return "No active tab."
        }
        
        let js = """
    (() => {
        // --- Part 1: Interactive Elements ---
        const nodes = [];
        const selector = [
            'a','button','input','select','textarea',
            '[role]','[aria-label]','[contenteditable="true"]',
            '[tabindex]:not([tabindex="-1"])'
        ].join(',');
    
        const textFor = (el) => (
            el.getAttribute('aria-label') ||
            el.getAttribute('alt') ||
            el.innerText ||
            el.value ||
            el.placeholder ||
            el.title ||
            ''
        ).trim().replace(/\\s+/g, ' ');
    
        const roleFor = (el) => {
            const r = el.getAttribute('role');
            if (r) return r;
            const tag = el.tagName.toLowerCase();
            if (tag === 'a') return 'link';
            if (tag === 'button') return 'button';
            if (tag === 'textarea') return 'textbox';
            if (tag === 'select') return 'combobox';
            if (tag === 'input') {
                const t = (el.type || 'text').toLowerCase();
                if (['button','submit','reset'].includes(t)) return 'button';
                if (t === 'checkbox') return 'checkbox';
                if (t === 'radio') return 'radio';
                return 'textbox';
            }
            return tag;
        };
    
        document.querySelectorAll(selector).forEach(el => {
            const rect = el.getBoundingClientRect();
            const style = window.getComputedStyle(el);
    
            if (
                rect.width === 0 ||
                rect.height === 0 ||
                style.display === 'none' ||
                style.visibility === 'hidden' ||
                Number(style.opacity) === 0
            ) return;
    
            nodes.push({
                id: nodes.length,
                tag: el.tagName.toLowerCase(),
                role: roleFor(el),
                text: textFor(el).slice(0, 200),
                href: el.href || null,
                placeholder: el.placeholder || null,
                bounds: {
                    x: Math.round(rect.x),
                    y: Math.round(rect.y),
                    width: Math.round(rect.width),
                    height: Math.round(rect.height)
                }
            });
        });
    
        // --- Part 2: Readable Text Content ---
        const textBlocks = [];
    
        document.querySelectorAll('h1,h2,h3,h4,h5,h6,p,li,td,th,span,div').forEach(el => {
            const hasContentChild = [...el.children].some(c =>
                ['H1','H2','H3','H4','H5','H6','P','LI','TD','TH'].includes(c.tagName)
            );
            if (hasContentChild) return;
    
            const style = window.getComputedStyle(el);
            const rect = el.getBoundingClientRect();
    
            if (
                rect.width === 0 || rect.height === 0 ||
                style.display === 'none' ||
                style.visibility === 'hidden' ||
                Number(style.opacity) === 0
            ) return;
    
            const text = (el.innerText || '').trim().replace(/\\s+/g, ' ');
            if (text.length < 5) return;
    
            textBlocks.push({
                tag: el.tagName.toLowerCase(),
                text: text.slice(0, 300),
                y: Math.round(rect.y)
            });
        });
    
        // Sort by vertical position so it reads top to bottom
        textBlocks.sort((a, b) => a.y - b.y);
    
        return JSON.stringify({
            interactive: nodes.slice(0, 150),
            content: textBlocks.slice(0, 100)
        });
    })();
    """
        
        if let runner = requestLiveJS[tabID] {
            return await runner(js)
        }
        return "Snapshot unavailable."
    }
}
