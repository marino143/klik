import XCTest
import AppKit
@testable import Klik

/// Synthetic objects only: no desktop capture, microphone, user files or playback.
final class IdleResourceLifetimeTests: XCTestCase {
    @MainActor
    func testClosedEditorReleasesCanvasAndImage() {
        _ = NSApplication.shared
        for _ in 0..<20 {
            weak var imageReference: NSImage?
            weak var canvasReference: AnnotationCanvasView?
            weak var controllerReference: EditorWindowController?
            autoreleasepool {
                let image = NSImage(size: NSSize(width: 640, height: 360))
                let controller = EditorWindowController(image: image)
                imageReference = image
                canvasReference = controller.canvasView
                controllerReference = controller
                controller.close()
            }
            XCTAssertNil(controllerReference)
            XCTAssertNil(canvasReference)
            XCTAssertNil(imageReference)
        }
    }

    @MainActor
    func testClosedVideoOverlayReleasesPosterAndState() {
        _ = NSApplication.shared
        for _ in 0..<20 {
            weak var stateReference: VideoMediaState?
            weak var imageReference: NSImage?
            weak var controllerReference: QuickAccessOverlayController?
            autoreleasepool {
                let poster = NSImage(size: NSSize(width: 640, height: 360))
                let state = VideoMediaState(fileURL: URL(fileURLWithPath: "/synthetic-not-opened.mp4"),
                                           poster: poster, isPendingSave: false)
                let controller = QuickAccessOverlayController(media: .video(state))
                stateReference = state
                imageReference = poster
                controllerReference = controller
                controller.close()
            }
            XCTAssertNil(controllerReference)
            XCTAssertNil(stateReference)
            XCTAssertNil(imageReference)
        }
    }

    @MainActor
    func testIdleRecorderAndCoordinatorRelease() {
        for _ in 0..<100 {
            weak var recorderReference: VideoRecordingManager?
            weak var coordinatorReference: CaptureCoordinator?
            autoreleasepool {
                let recorder = VideoRecordingManager()
                let coordinator = CaptureCoordinator()
                recorderReference = recorder
                coordinatorReference = coordinator
                XCTAssertFalse(recorder.isRecording)
                XCTAssertFalse(coordinator.isRecording)
            }
            XCTAssertNil(recorderReference)
            XCTAssertNil(coordinatorReference)
        }
    }

    @MainActor
    func testCancelledTimerReleasesCallbackPayload() {
        final class Payload {}
        let timer = RecordingStopTimer(schedule: { _ in })
        for _ in 0..<100 {
            weak var reference: Payload?
            autoreleasepool {
                let payload = Payload()
                reference = payload
                timer.start(duration: 600) { _ = payload }
            }
            XCTAssertNotNil(reference)
            timer.cancel()
            XCTAssertNil(reference)
        }
    }
}
