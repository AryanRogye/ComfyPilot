//
//  ChatMessage.swift
//  ComfyPilot
//
//  Created by Aryan Rogye on 4/24/26.
//

import Foundation
import MLXLMCommon
import MLXKit

public protocol MessageRepresentable: Identifiable, Equatable {
    var id: UUID { get set }
}

public struct ToolMessage: MessageRepresentable, Sendable {
    public var id: UUID
    public let functionName: String
    public let arguments : [String: JSONValue]
    
    public static func == (lhs: ToolMessage, rhs: ToolMessage) -> Bool {
        lhs.id == rhs.id
    }
}

public struct ChatMessage: MessageRepresentable, Sendable {
    
    public var id: UUID
    public let role: Role
    public var content: String
    
    public init(id: UUID = UUID(), role: Role, content: String) {
        self.id = id
        self.role = role
        self.content = content
    }
    
    public static func == (lhs: ChatMessage, rhs: ChatMessage) -> Bool {
        lhs.id == rhs.id &&
        lhs.role == rhs.role &&
        lhs.content == rhs.content
    }
}
