//
//  ViewExtensions.swift
//  Liquid Harvest
//
//  Created by Martyn Chamberlin on 11/29/25.
//

import SwiftUI

extension View {
    @ViewBuilder
    func glassEffect() -> some View {
        // Use material backgrounds for glass effect
        // This works on all macOS versions
        self.background(.ultraThinMaterial)
            .background(.regularMaterial.opacity(0.2))
    }
}

