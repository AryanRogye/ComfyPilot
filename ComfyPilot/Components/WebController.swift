//
//  WebController.swift
//  ComfyPilot
//
//  Created by Aryan Rogye on 4/26/26.
//

import Foundation

@MainActor
@Observable
final class WebController {
    
    var url = URL(string: "https://www.google.com")!
    var html = ""
    var links: [URL] = []
    
    private var pendingContinuation: CheckedContinuation<String, Never>?
    
    func didLoadHTML(_ html: String) {
        guard !html.isEmpty else { return }
        
        self.html = html
        
        let continuation = pendingContinuation
        pendingContinuation = nil
        continuation?.resume(returning: html)
    }
    
    func loadSearchHTML(for query: String) async -> String {
        await withCheckedContinuation { continuation in
            pendingContinuation = continuation
            url = searchURL(for: query)
        }
    }
    
    func loadLinkHTML(at index: Int) async -> String {
        let linkIndex = index - 1
        guard links.indices.contains(linkIndex) else {
            return "No link exists at index \(index)."
        }
        
        return await withCheckedContinuation { continuation in
            pendingContinuation = continuation
            url = links[linkIndex]
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
}
