#if DEBUG && os(iOS)
import UIKit

enum ScreenCapture {
    @MainActor
    static func capture(in windowScene: UIWindowScene, excluding overlayWindow: UIWindow) throws -> CapturedScreen {
        let candidateWindows = windowScene.windows
            .filter { $0 !== overlayWindow }
            .filter { !$0.isHidden && $0.alpha > 0.01 }

        guard let targetWindow = candidateWindows.first(where: \.isKeyWindow) ?? candidateWindows.first else {
            throw SamplerError.screenCaptureFailed
        }

        overlayWindow.isHidden = true
        defer {
            overlayWindow.isHidden = false
        }

        let bounds = targetWindow.bounds
        let format = UIGraphicsImageRendererFormat()
        format.scale = targetWindow.screen.scale
        format.opaque = false

        let renderer = UIGraphicsImageRenderer(size: bounds.size, format: format)
        let image = renderer.image { _ in
            targetWindow.drawHierarchy(in: bounds, afterScreenUpdates: false)
        }

        return CapturedScreen(
            screenshot: image,
            bounds: bounds,
            scale: format.scale,
            appName: Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
                ?? "App",
            deviceName: UIDevice.current.model,
            systemVersion: UIDevice.current.systemVersion,
            capturedAt: Date(),
            accessibilityElements: collectAccessibilityElements(in: targetWindow)
        )
    }

    private static func collectAccessibilityElements(in rootView: UIView) -> [AccessibilityElementSnapshot] {
        var snapshots: [AccessibilityElementSnapshot] = []
        collectAccessibilityElements(from: rootView, rootView: rootView, into: &snapshots)
        return snapshots
    }

    private static func collectAccessibilityElements(
        from view: UIView,
        rootView: UIView,
        into snapshots: inout [AccessibilityElementSnapshot]
    ) {
        if let snapshot = snapshot(for: view, rootView: rootView) {
            snapshots.append(snapshot)
        }

        if let accessibilityElements = view.accessibilityElements {
            for element in accessibilityElements {
                if let element = element as? UIAccessibilityElement,
                   let snapshot = snapshot(for: element, rootView: rootView) {
                    snapshots.append(snapshot)
                } else if let childView = element as? UIView {
                    collectAccessibilityElements(from: childView, rootView: rootView, into: &snapshots)
                }
            }
        }

        view.subviews.forEach {
            collectAccessibilityElements(from: $0, rootView: rootView, into: &snapshots)
        }
    }

    private static func snapshot(for view: UIView, rootView: UIView) -> AccessibilityElementSnapshot? {
        guard view.isAccessibilityElement else {
            return nil
        }

        let frame = view.convert(view.bounds, to: rootView)
        guard frame.width > 0, frame.height > 0 else {
            return nil
        }

        return AccessibilityElementSnapshot(
            identifier: view.accessibilityIdentifier,
            label: view.accessibilityLabel,
            value: view.accessibilityValue,
            traits: strings(for: view.accessibilityTraits),
            frame: RectSnapshot(frame)
        )
    }

    private static func snapshot(
        for element: UIAccessibilityElement,
        rootView: UIView
    ) -> AccessibilityElementSnapshot? {
        let screenFrame = element.accessibilityFrame
        guard screenFrame.width > 0, screenFrame.height > 0 else {
            return nil
        }

        let frame = rootView.convert(screenFrame, from: nil)
        return AccessibilityElementSnapshot(
            identifier: element.accessibilityIdentifier,
            label: element.accessibilityLabel,
            value: element.accessibilityValue,
            traits: strings(for: element.accessibilityTraits),
            frame: RectSnapshot(frame)
        )
    }

    private static func strings(for traits: UIAccessibilityTraits) -> [String] {
        var result: [String] = []

        let knownTraits: [(UIAccessibilityTraits, String)] = [
            (.button, "button"),
            (.link, "link"),
            (.header, "header"),
            (.searchField, "searchField"),
            (.image, "image"),
            (.selected, "selected"),
            (.playsSound, "playsSound"),
            (.keyboardKey, "keyboardKey"),
            (.staticText, "staticText"),
            (.summaryElement, "summaryElement"),
            (.notEnabled, "notEnabled"),
            (.updatesFrequently, "updatesFrequently"),
            (.startsMediaSession, "startsMediaSession"),
            (.adjustable, "adjustable"),
            (.allowsDirectInteraction, "allowsDirectInteraction"),
            (.causesPageTurn, "causesPageTurn")
        ]

        for (trait, name) in knownTraits where traits.contains(trait) {
            result.append(name)
        }

        return result
    }
}
#endif
