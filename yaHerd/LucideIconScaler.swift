//
//  LucideIconScaler.swift
//  yaHerd
//
//  Created by mm on 11/30/25.
//

import UIKit

extension UIImage {
    func scaled(to size: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        let img = renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: size))
        }
        return img.withRenderingMode(.alwaysTemplate)
    }
}
