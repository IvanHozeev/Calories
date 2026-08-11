//
//  Item.swift
//  Calories
//
//  Created by Ivan Hozeyev on 11/08/2026.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
