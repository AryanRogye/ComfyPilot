//
//  MeshGradientView.swift
//  ComfyPilot
//
//  Created by Aryan Rogye on 4/26/26.
//

import SwiftUI


/**
 * Background Of The App
 */
struct MeshGradientView: View {
    
    let wine     = Color(red: 0.10, green: 0.01, blue: 0.05)
    let plum     = Color(red: 0.20, green: 0.04, blue: 0.13)
    let rose     = Color(red: 0.55, green: 0.12, blue: 0.32)
    let hotRose  = Color(red: 0.95, green: 0.20, blue: 0.52)
    let softGlow = Color(red: 1.00, green: 0.45, blue: 0.72)
    
    var body: some View {
        TimelineView(.animation) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            
            let x = 0.5 + 0.18 * sin(time * 0.16)
            let y = 0.5 + 0.16 * cos(time * 0.18)
            
            MeshGradient(
                width: 3,
                height: 3,
                points: [
                    SIMD2<Float>(0.0, 0.0), SIMD2<Float>(0.50, 0.0), SIMD2<Float>(1.0, 0.0),
                    SIMD2<Float>(0.0, 0.5), SIMD2<Float>(Float(x), Float(y)), SIMD2<Float>(1.0, 0.5),
                    SIMD2<Float>(0.0, 1.0), SIMD2<Float>(0.50, 1.0), SIMD2<Float>(1.0, 1.0)
                ],
                colors: [
                    wine, plum, wine,
                    plum, softGlow, hotRose,
                    wine, plum, wine
                ]
            )
            .ignoresSafeArea()
        }
    }
}
