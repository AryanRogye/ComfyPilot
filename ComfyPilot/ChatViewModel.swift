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
    
    var messages: [ChatMessage] = []
    var sendingMessage = false
    var error: String?
    var showError = false
    
    var onSearch: ((String) async -> String)?
    var onClickLink: ((Int) async -> String)?
    
    public static let linkPattern = #"\[([^\]]+)\]\((https?:\/\/[^\s\)]+)\)"#
    
    private let mlxModelChatVM = MLXChatService()
    
    public func load(_ url: URL) async {
        do {
            try await mlxModelChatVM.loadModel(at: url)
        } catch {
            self.error = error.localizedDescription
            showError = true
        }
    }
    
    var isLoaded: Bool {
        mlxModelChatVM.isLoaded
    }
    
    func send(_ prompt: String) {
        guard isLoaded else { return }
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmed.isEmpty else { return }
        guard !sendingMessage else { return }
        
        sendingMessage = true
        
        let userMessage = ChatMessage(role: .user, content: trimmed)
        messages.append(userMessage)
        
        let assistantID = UUID()
        messages.append(
            ChatMessage(
                id: assistantID,
                role: .assistant,
                content: ""
            )
        )
        
        Task {
            /// at end set the false
            defer {
                Task { @MainActor in
                    self.sendingMessage = false
                }
            }
            
            do {
                let modelMessages = messages
                    .filter { $0.id != assistantID }
                    .map { ModelMessage(role: $0.role.rawValue, content: $0.content) }
                
                let _ = try await mlxModelChatVM.getResponse(
                    messages: modelMessages,
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
    
    private func handleToolCall(
        _ response: ToolCallResponse,
        depth: Int = 0
    ) async throws {
        
        let maxDepth = 3
        
        guard depth < maxDepth else {
            return
        }
        
        let function = response.functionName
        
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
            .map { ModelMessage(role: $0.role.rawValue, content: $0.content) }
        
        modelMessages.append(ModelMessage(role: message.role.rawValue, content: message.content))
        
        messages.append(
            ChatMessage(
                id: assistantID,
                role: .assistant,
                content: ""
            )
        )
        
        let _ = try await mlxModelChatVM.getResponse(
            messages: modelMessages,
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
    
    private func appendToAssistantMessage(id: UUID, chunk: String) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].content += chunk
    }
    
    private func updateAssistantMessage(id: UUID, content: String) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].content = content
    }
    
    private func removeAssistantMessageIfEmpty(id: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        if messages[index].content.isEmpty {
            messages.remove(at: index)
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
