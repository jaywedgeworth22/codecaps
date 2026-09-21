import AppKit
@testable import CodeCaps
import XCTest

final class PlatformLogoTests: XCTestCase {
    func testGrokBotLogoLoadsAsTemplateForDarkModeInversion() {
        // Grok Bot should load as a template in both template and standard modes
        // so that it inverts between Light mode (dark sphere) and Dark mode (light sphere).
        let templateImage = PlatformLogoImage.load(providerKey: "grok-bot", style: .template)
        XCTAssertNotNil(templateImage, "Grok Bot template image should load successfully.")
        XCTAssertTrue(templateImage?.isTemplate == true, "Grok Bot template mark must have isTemplate == true.")

        let standardImage = PlatformLogoImage.load(providerKey: "grok-bot", style: .standard)
        XCTAssertNotNil(standardImage, "Grok Bot standard image should load successfully.")
        XCTAssertTrue(standardImage?.isTemplate == true, "Grok Bot standard mark must adapt to Dark mode as a template.")
    }

    func testStandardPreservesBrandColorForNonMonochromeMarks() {
        let claudeStandard = PlatformLogoImage.load(providerKey: "claude", style: .standard)
        XCTAssertNotNil(claudeStandard, "Claude standard mark should load.")
        XCTAssertFalse(claudeStandard?.isTemplate == true, "Claude standard mark must preserve full brand color.")

        let claudeTemplate = PlatformLogoImage.load(providerKey: "claude", style: .template)
        XCTAssertNotNil(claudeTemplate, "Claude template mark should load.")
        XCTAssertTrue(claudeTemplate?.isTemplate == true, "Claude template mark must have isTemplate == true.")
    }

    func testFallbackSymbolsAreDefined() {
        XCTAssertEqual(PlatformLogoImage.fallbackSymbolName(for: "grok-bot"), "bolt.badge.a")
        XCTAssertEqual(PlatformLogoImage.fallbackSymbolName(for: "grok"), "bolt")
        XCTAssertEqual(PlatformLogoImage.fallbackSymbolName(for: "unknown"), "gauge.with.dots.needle.50percent")
    }
}
