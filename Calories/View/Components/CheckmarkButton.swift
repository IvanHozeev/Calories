//
//  CheckmarkButton.swift
//  Calories
//
//  Created by Ivan Hozeyev on 14/08/2026.
//

import SwiftUI

struct CheckmarkButton: View {
    var action: () -> Void
    
    var body: some View {
        Button {
            action()
        } label: {
            Label("Сохранить", systemImage: "checkmark")
        }
        .labelStyle(.iconOnly)
    }
    
}
