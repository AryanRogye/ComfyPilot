//
//  WebView.swift
//  ComfyPilot
//
//  Created by Aryan Rogye on 4/24/26.
//

import SwiftUI
import WebKit

struct WebView: NSViewRepresentable {
    
    let url: URL
    var onPageLoaded: (URL?, String, String, [URL]) -> Void
    var onRunJSReady: (((@escaping (String) async -> String) -> Void))? = nil
    var onLiveHTMLReady: (((@escaping () async -> String) -> Void))? = nil
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onPageLoaded: onPageLoaded)
    }
    
    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        
        context.coordinator.webView = webView
        context.coordinator.lastLoadedURL = url
        
        onRunJSReady?(context.coordinator.runJavaScript)
        onLiveHTMLReady?(context.coordinator.currentHTML)
        
        webView.load(URLRequest(url: url))
        return webView
    }
    
    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onPageLoaded = onPageLoaded
        
        guard context.coordinator.lastLoadedURL != url else { return }
        context.coordinator.lastLoadedURL = url
        webView.load(URLRequest(url: url))
    }
    
    final class Coordinator: NSObject, WKNavigationDelegate {
        var onPageLoaded: (URL?, String, String, [URL]) -> Void
        var lastLoadedURL: URL?
        weak var webView: WKWebView?
        
        init(onPageLoaded: @escaping (URL?, String, String, [URL]) -> Void) {
            self.onPageLoaded = onPageLoaded
        }
        
        @MainActor
        func currentHTML() async -> String {
            guard let webView else {
                return "No active web view."
            }
            
            return await withCheckedContinuation { continuation in
                webView.evaluateJavaScript("document.documentElement.outerHTML") { result, error in
                    if let html = result as? String {
                        continuation.resume(returning: html)
                    } else {
                        continuation.resume(returning: "Could not read current page HTML.")
                    }
                }
            }
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let currentURL = webView.url
            lastLoadedURL = currentURL
            
            webView.evaluateJavaScript(Self.pageSnapshotJavaScript) { [weak self] result, _ in
                guard
                    let snapshot = result as? [String: Any],
                    let title = snapshot["title"] as? String,
                    let text = snapshot["text"] as? String,
                    let rawLinks = snapshot["links"] as? [[String: String]]
                else { return }
                
                let links: [URL] = rawLinks.compactMap { link in
                    guard let href = link["href"] else { return nil }
                    return URL(string: href)
                }
                
                self?.onPageLoaded(currentURL, title, String(text.prefix(8_000)), links)
            }
        }
        
        @MainActor
        func runJavaScript(_ js: String) async -> String {
            guard let webView else {
                return "No active web view."
            }
            
            return await withCheckedContinuation { continuation in
                webView.evaluateJavaScript(js) { result, error in
                    if let error {
                        continuation.resume(returning: "JavaScript error: \(error.localizedDescription)")
                        return
                    }
                    
                    if let string = result as? String {
                        continuation.resume(returning: string)
                    } else if let result {
                        continuation.resume(returning: String(describing: result))
                    } else {
                        continuation.resume(returning: "")
                    }
                }
            }
        }
        
        private static let pageSnapshotJavaScript = """
        (() => {
            const title = document.title || "";
            const visibleText = document.body?.innerText || "";
            const links = Array.from(document.links)
                .map((link) => {
                    const label = (link.innerText || link.getAttribute("aria-label") || link.href || "").trim().replace(/\\s+/g, " ");
                    return { label, href: link.href };
                })
                .filter((link) => link.label.length > 0 && link.href.length > 0)
                .slice(0, 25);
            const linkText = links
                .map((link, index) => `${index + 1}. ${link.label}\\n${link.href}`)
                .join("\\n");
        
            return {
                title,
                text: `${visibleText}\\n\\nLinks on this page:\\n${linkText}`,
                links
            };
        })()
        """
    }
}
