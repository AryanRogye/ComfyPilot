//
//  ChatViewModel.swift
//  ComfyPilot
//
//  Created by Aryan Rogye on 4/24/26.
//

import Foundation
import MLXLMCommon
import MLXKit


@MainActor
@Observable
final class ChatViewModel {
    
    /**
     * All Messages
     */
    var messages: [any MessageRepresentable] = []
    
    /// Flag to know if we are currently sending a message or not
    var sendingMessage = false
    
    /// Error Related
    var error: String?
    var showError = false
    
    /// Callback the agent's use based off of the toolcall
    var onSearch: ((String) async -> String)?
    var onClickLink: ((Int) async -> String)?
    
    /// Link Pattern lets us know if in a String what all of the urls are
    public static let linkPattern = #"\[([^\]]+)\]\((https?:\/\/[^\s\)]+)\)"#
    
    /**
     * Internal Service lets us talk to the MLX Model thats loaded
     */
    private let mlxChatService = MLXChatService()
    
    /**
     * Computed Property to know if the MLX model is
     * loaded or not
     */
    var isLoaded: Bool {
        mlxChatService.isLoaded
    }

    private func handleToolCall(
        _ response: ToolCallResponse,
        depth: Int = 0
    ) async throws {
        
        let maxDepth = 3
        
        guard depth < maxDepth else {
            return
        }
        
        let function = response.functionName
        
        messages.append(
            ToolMessage(
                functionName: response.functionName,
                arguments: response.arguments
            )
        )
        
        switch function {
        case "clickLink":
            if case .int(let index) = response.arguments["index"] {
                let args = ClickTookArguments(index: index)
                if let html = await onClickLink?(args.index) {
                    try await respondToToolResult(
                        html,
                        label: "clicked on",
                        depth: depth
                    )
                }
            }
        case "search":
            if case .string(let query) = response.arguments["query"] {
                let args = SearchToolArguments(query: query)
                if let html = await onSearch?(args.query) {
                    try await respondToToolResult(
                        html,
                        label: "searched",
                        depth: depth
                    )
                }
            }
        default:
            break
        }
    }
    
    private func respondToToolResult(
        _ html: String,
        label: String,
        depth: Int
    ) async throws {
        let message = ChatMessage(
            role: .user,
            content: """
                    This is the content of what you \(label):
                    \(html)
                    
                    Use this information to answer the question.
                    If it's not enough, you may search again.
                    If you need to open one of the links, call clickLink with the link number.
                    """
        )
        
        let assistantID = UUID()
        var modelMessages = messages
            .filter { $0.id != assistantID }
            .compactMap { $0 as? ChatMessage }
            .map { ModelMessage(role: $0.role, content: $0.content) }
        
        modelMessages.append(ModelMessage(role: message.role, content: message.content))
        
        let _ = try await mlxChatService.getResponse(
            messages: modelMessages,
            tools: [
                Self.searchTool,
                Self.clickLinkTool
            ],
            completion: { [weak self] (snippet: String) in
                guard let self else { return }
                Task { @MainActor in
                    self.appendToAssistantMessage(
                        id: assistantID,
                        chunk: snippet
                    )
                }
            },
            toolcallCompletionHandler: { toolcallResponse in
                Task { @MainActor in
                    try await self.handleToolCall(toolcallResponse, depth: depth + 1)
                }
            }
        )
    }
    
    // MARK: - Helpers
    
    /**
     * Function adds a message as a role user
     */
    private func addUserMessage(_ content: String) {
        let userMessage = ChatMessage(
            role: .user,
            content: content
        )
        messages.append(userMessage)
    }
    
    /**
     * Function Appends to assistant method if
     * the message doesnt exist yet, it creates it as we go
     * this is important
     */
    private func appendToAssistantMessage(id: UUID, chunk: String) {
        if let index = messages.firstIndex(where: { $0.id == id }) {
            let message = messages[index]
            if var m = message as? ChatMessage {
                m.content += chunk
                messages[index] = m
            }
        } else {
            messages.append(
                ChatMessage(
                    id: id,
                    role: .assistant,
                    content: chunk
                )
            )
        }
    }
    
    private func removeAssistantMessageIfEmpty(id: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        let message = messages[index]
        if let m = message as? ChatMessage {
            if m.content.isEmpty {
                messages.remove(at: index)
            }
        }
    }
    
    private func message(for error: MLXModelChatVideoModelError) -> String {
        switch error {
        case .modelDoesntExist:
            return "Model Doesnt Exist"
        case .errorWhileLoadingContainer(let string):
            return "Error While Loading Container: \(string)"
        case .containerNotConfigured:
            return "Container Not Configured"
        case .cantGenerateResponseNotLoaded:
            return "Not Loaded Cant Generate Response"
        }
    }
}

// MARK: - Loading Model
extension ChatViewModel {
    /**
     * Loads The Model based off the URL provided
     * sets error flags if anything goes wrong
     */
    public func load(_ url: URL) async {
        do {
            try await mlxChatService.loadModel(at: url)
        } catch {
            self.error = error.localizedDescription
            showError = true
        }
    }
}

// MARK: - Send Chat
extension ChatViewModel {
    
    /**
     * Function sends prompt to the loaded MLX Model
     */
    func send(_ prompt: String) {
        
        /// Make sure the model is loaded
        guard isLoaded else {
            error = "Model Not Loaded Yet"
            showError = true
            return
        }
        
        /// make sure we're not currently sending a message
        guard !sendingMessage else { return }
        
        /// Trim Prompt and making sure its not empty
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        /// set flag to true
        sendingMessage = true
        
        /// Creates Users Message
        self.addUserMessage(trimmed)
        
        let assistantID = UUID()
        
        Task {
            /// at end set the false
            defer {
                Task { @MainActor in
                    self.sendingMessage = false
                }
            }
            
            do {
                /**
                 * This removes the current assistant message you're about
                 * to stream into
                 */
                let modelMessages = messages
                    .filter { $0.id != assistantID }
                    .compactMap { $0 as? ChatMessage }
                    .map { ModelMessage(role: $0.role, content: $0.content) }
                
                let _ = try await mlxChatService.getResponse(
                    messages: modelMessages,
                    tools: [
                        Self.searchTool,
                        Self.clickLinkTool
                    ],
                    completion: { [weak self] (snippet: String) in
                        guard let self else { return }
                        Task { @MainActor in
                            self.appendToAssistantMessage(
                                id: assistantID,
                                chunk: snippet
                            )
                        }
                    },
                    toolcallCompletionHandler: { toolcallResponse in
                        Task { @MainActor in
                            try await self.handleToolCall(toolcallResponse)
                        }
                    }
                )
            } catch let e as MLXModelChatVideoModelError {
                await MainActor.run {
                    self.error = self.message(for: e)
                    self.showError = true
                    self.removeAssistantMessageIfEmpty(id: assistantID)
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    self.showError = true
                    self.removeAssistantMessageIfEmpty(id: assistantID)
                }
            }
        }
    }
}

extension ChatViewModel {
    /**
     This section is my prompts that I use to get a toolcall to activate, most of these require searching
     
     Prompt:
     What was the weather today in Chicago
     
     There was currently a new video by SideQuest Drew about exploring epsteins new island, can u look up the free version of the video?
     
     I’m trying to track down a specific JiDion video that includes a meta shout-out to Agent 00. In the video, JiDion actually anticipates that Agent will be reacting to the content on his stream. He looks directly at the camera and tells anyone watching via Agent’s ‘AMP’ stream that they should pause the reaction and go support the original upload on JiDion’s channel first. Does anyone have the link or know which video this was from?
     */
    static let searchTool: [String: any Sendable] = [
        "type": "function",
        "function": [
            "name": "search",
            "description": "Search the web for information",
            "parameters": [
                "type": "object",
                "properties": [
                    "query": [
                        "type": "string",
                        "description": "The search query"
                    ] as [String: any Sendable]
                ] as [String: any Sendable],
                "required": ["query"]
            ] as [String: any Sendable]
        ] as [String: any Sendable]
    ]
    
    static let clickLinkTool: [String: any Sendable] = [
        "type": "function",
        "function": [
            "name": "clickLink",
            "description": "Open one of the numbered links from the current browser page.",
            "parameters": [
                "type": "object",
                "properties": [
                    "index": [
                        "type": "integer",
                        "description": "The 1-based number of the link to open from the current page's Links list."
                    ] as [String: any Sendable]
                ] as [String: any Sendable],
                "required": ["index"]
            ] as [String: any Sendable]
        ] as [String: any Sendable]
    ]
}
