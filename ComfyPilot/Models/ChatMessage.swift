//
//  ChatMessage.swift
//  ComfyPilot
//
//  Created by Aryan Rogye on 4/24/26.
//

import Foundation

public struct ChatMessage: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let role: Role
    public var content: String
    
    public init(id: UUID = UUID(), role: Role, content: String) {
        self.id = id
        self.role = role
        self.content = content
    }
    
    public enum Role: String, Sendable {
        case user
        case assistant
        case system
    }
}
