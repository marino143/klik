import XCTest
import AppKit
@testable import Klik

final class RecordingSettingsTests: XCTestCase {
    @MainActor
    func testSettingsControls() throws {
        _ = NSApplication.shared
        let keys = ["recordingResolution", "recordingFPS", "recordingQuality"]
        let saved = keys.map { UserDefaults.standard.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, saved) {
                if let value { UserDefaults.standard.set(value, forKey: key) }
                else { UserDefaults.standard.removeObject(forKey: key) }
            }
            SettingsWindowController.shared.close()
        }
        SettingsWindowController.shared.show()
        let window = try XCTUnwrap(SettingsWindowController.shared.window)
        let content = try XCTUnwrap(window.contentView)
        func descendants(_ view: NSView) -> [NSView] {
            [view] + view.subviews.flatMap { descendants($0) }
        }
        let popups = descendants(content).compactMap { $0 as? NSPopUpButton }
        XCTAssertEqual(popups.count, 3)
        for popup in popups {
            for index in 0..<popup.numberOfItems {
                popup.selectItem(at: index)
                XCTAssertTrue(popup.sendAction(popup.action, to: popup.target))
                XCTAssertTrue(popup.titleOfSelectedItem?.hasSuffix(" (current)") == true)
                let current = RecordingSettings()
                if popup === popups[0] { XCTAssertEqual(current.resolution, RecordingSettings.Resolution.allCases[index]) }
                if popup === popups[1] { XCTAssertEqual(current.fps, index == 0 ? 30 : 60) }
                if popup === popups[2] { XCTAssertEqual(current.quality, RecordingSettings.Quality.allCases[index]) }
            }
        }
        for theme in [NSAppearance.Name.aqua, .darkAqua] {
            window.appearance = NSAppearance(named: theme)
            content.layoutSubtreeIfNeeded()
            let image = try XCTUnwrap(content.bitmapImageRepForCachingDisplay(in: content.bounds))
            content.cacheDisplay(in: content.bounds, to: image)
            let png = try XCTUnwrap(image.representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: "/tmp/klik-settings-" + theme.rawValue + ".png"))
        }
    }

    func testDefaultsAndPersistence() {
        let name = "KlikRecordingTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        var settings = RecordingSettings(defaults: defaults)
        XCTAssertEqual(settings.resolution, .p1080)
        XCTAssertEqual(settings.fps, 30)
        XCTAssertEqual(settings.quality, .standard)
        XCTAssertEqual(settings.bitrate(width: 1920, height: 1080), 3_110_400)
        settings.resolution = .native
        settings.fps = 60
        settings.quality = .high
        settings.save(defaults: defaults)
        let loaded = RecordingSettings(defaults: defaults)
        XCTAssertEqual(loaded.resolution, .native)
        XCTAssertEqual(loaded.fps, 60)
        XCTAssertEqual(loaded.quality, .high)
        defaults.set("invalid", forKey: "recordingQuality")
        defaults.set(-1, forKey: "recordingResolution")
        defaults.set(120, forKey: "recordingFPS")
        let fallback = RecordingSettings(defaults: defaults)
        XCTAssertEqual(fallback.resolution, .p1080)
        XCTAssertEqual(fallback.fps, 30)
        XCTAssertEqual(fallback.quality, .standard)
    }

    func testAllPresetsAndDimensions() {
        var settings = RecordingSettings()
        for resolution in RecordingSettings.Resolution.allCases {
            settings.resolution = resolution
            let size = settings.dimensions(width: 3840, height: 2160)
            XCTAssertEqual(size.height, resolution == .native ? 2160 : resolution.rawValue)
            XCTAssertEqual(size.width * 9, size.height * 16)
            let small = settings.dimensions(width: 601, height: 301)
            XCTAssertEqual(small.width, 600)
            XCTAssertEqual(small.height, 300)
            for fps in [30, 60] {
                settings.fps = fps
                var previous = 0
                for quality in RecordingSettings.Quality.allCases {
                    settings.quality = quality
                    let bitrate = settings.bitrate(width: size.width, height: size.height)
                    XCTAssertGreaterThan(bitrate, previous)
                    previous = bitrate
                }
            }
        }
    }
}
