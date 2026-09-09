import SwiftUI
import UIKit
import XCTest
@testable import TresFort

@MainActor
final class ThemeAccessibilityTests: XCTestCase {
    // The gradient interpolates between bg and bgTop. All component channels
    // lie within these surfaces, so testing each bounds the text contrast.
    // The native iOS 26.2 contrast audit reports false positives over this
    // gradient. This policy checks the resolved colors themselves; decorative
    // dim and intentionally disabled text have a different purpose.
    func testEnabledTextContrastAcrossDarkSurfaces() {
        for foreground in [Theme.text, Theme.muted, Theme.accent, Theme.done, Theme.danger] {
            for background in [Theme.bg, Theme.bgTop, Theme.surface, Theme.surface2] {
                let ratio = (luminance(foreground) + 0.05) / (luminance(background) + 0.05)
                XCTAssertGreaterThanOrEqual(ratio, 4.5, "Enabled text must retain WCAG AA contrast")
            }
        }
    }

    func testPrimaryActionTextContrast() {
        XCTAssertGreaterThanOrEqual((luminance(Theme.accent) + 0.05) / 0.05, 4.5)
    }

    private func luminance(_ color: Color) -> Double {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        let resolved = UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
        XCTAssertTrue(resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha))
        XCTAssertEqual(alpha, 1)
        let linear = [red, green, blue].map { component -> Double in
            let value = Double(component)
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return zip(linear, [0.2126, 0.7152, 0.0722]).reduce(0) { $0 + $1.0 * $1.1 }
    }
}
