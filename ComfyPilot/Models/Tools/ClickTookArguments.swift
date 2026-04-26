//
//  ClickTookArguments.swift
//  ComfyPilot
//
//  Created by Aryan Rogye on 4/26/26.
//

import Foundation

public struct ClickTookArguments: Codable {
    public let index: Int
    
    public init(index: Int) {
        self.index = index
    }
}
