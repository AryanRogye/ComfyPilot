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

    func makeCoordinator() -> Coordinator {
        Coordinator(onPageLoaded: onPageLoaded)
    }

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        context.coordinator.lastLoadedURL = url
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.lastLoadedURL != url else { return }
        context.coordinator.lastLoadedURL = url
        webView.load(URLRequest(url: url))
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var onPageLoaded: (URL?, String, String, [URL]) -> Void
        var lastLoadedURL: URL?

        init(onPageLoaded: @escaping (URL?, String, String, [URL]) -> Void) {
            self.onPageLoaded = onPageLoaded
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
