//
//  SearchToolArguments.swift
//  ComfyPilot
//
//  Created by Aryan Rogye on 4/26/26.
//

import Foundation

public struct SearchToolArguments: Codable {
    public let query: String
    
    public init(query: String) {
        self.query = query
    }
}
