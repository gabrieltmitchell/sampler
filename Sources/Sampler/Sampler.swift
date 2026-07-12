#if os(iOS)
import UIKit
#endif
import Foundation

@MainActor
public enum Sampler {
    public static let version = "0.2.0"

#if DEBUG && os(iOS)
    private static var controller: SamplerController?
    private static var isHiddenUntilRestart = false
    private static var pendingEndpoint: URL?
    private static var sceneActivationObserver: NSObjectProtocol?

    public static func start(in windowScene: UIWindowScene? = nil, endpoint: URL? = nil) {
        guard !isHiddenUntilRestart, controller == nil else {
            return
        }

        guard let scene = windowScene ?? UIApplication.shared.activeWindowScene else {
            scheduleStartWhenSceneActivates(endpoint: endpoint)
            return
        }

        start(in: scene, endpoint: endpoint)
    }

    public static func startOnce(endpoint: URL? = nil) {
        start(in: nil, endpoint: endpoint)
    }

    public static func start(endpoint: URL) {
        start(in: nil, endpoint: endpoint)
    }

    public static func stop() {
        removeSceneActivationObserver()
        pendingEndpoint = nil
        controller?.stop()
        controller = nil
    }

    static func hideUntilRestart() {
        isHiddenUntilRestart = true
        stop()
    }

    private static func start(in windowScene: UIWindowScene, endpoint: URL?) {
        guard !isHiddenUntilRestart, controller == nil else {
            return
        }

        removeSceneActivationObserver()
        pendingEndpoint = nil

        let newController = SamplerController(windowScene: windowScene, endpoint: endpoint)
        controller = newController
        newController.start()
    }

    private static func scheduleStartWhenSceneActivates(endpoint: URL?) {
        pendingEndpoint = endpoint

        guard sceneActivationObserver == nil else {
            return
        }

        sceneActivationObserver = NotificationCenter.default.addObserver(
            forName: UIScene.didActivateNotification,
            object: nil,
            queue: .main
        ) { notification in
            Task { @MainActor in
                guard let scene = notification.object as? UIWindowScene ?? UIApplication.shared.activeWindowScene else {
                    return
                }
                start(in: scene, endpoint: pendingEndpoint)
            }
        }
    }

    private static func removeSceneActivationObserver() {
        guard let sceneActivationObserver else {
            return
        }
        NotificationCenter.default.removeObserver(sceneActivationObserver)
        self.sceneActivationObserver = nil
    }
#else
    #if os(iOS)
    public static func start(in windowScene: UIWindowScene? = nil, endpoint: URL? = nil) {}

    public static func startOnce(endpoint: URL? = nil) {}

    public static func start(endpoint: URL) {}
    #else
    public static func start() {}

    public static func startOnce() {}
    #endif

    public static func stop() {}
#endif
}

#if DEBUG && os(iOS)
private extension UIApplication {
    var activeWindowScene: UIWindowScene? {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? connectedScenes.compactMap { $0 as? UIWindowScene }.first
    }
}

@MainActor
final class SamplerController {
    private weak var windowScene: UIWindowScene?
    private var overlayWindow: OverlayWindow?
    private var rootViewController: OverlayRootViewController?
    private let endpoint: URL?

    init(windowScene: UIWindowScene, endpoint: URL?) {
        self.windowScene = windowScene
        self.endpoint = endpoint
    }

    func start() {
        guard let windowScene else {
            return
        }

        let rootViewController = OverlayRootViewController()
        rootViewController.agentEndpoint = endpoint
        rootViewController.delegate = self

        let overlayWindow = OverlayWindow(windowScene: windowScene)
        overlayWindow.rootViewController = rootViewController
        overlayWindow.isHidden = false

        self.rootViewController = rootViewController
        self.overlayWindow = overlayWindow
    }

    func stop() {
        overlayWindow?.isHidden = true
        overlayWindow = nil
        rootViewController = nil
    }
}

extension SamplerController: OverlayRootViewControllerDelegate {
    func overlayRootViewControllerDidRequestAnnotation(_ viewController: OverlayRootViewController) {
        guard let windowScene, let overlayWindow else {
            return
        }

        do {
            let capture = try ScreenCapture.capture(in: windowScene, excluding: overlayWindow)
            overlayWindow.makeKey()
            overlayWindow.isAnnotationModeActive = true
            viewController.enterAnnotationMode(with: capture)
        } catch {
            viewController.showTransientMessage(error.localizedDescription)
        }
    }

    func overlayRootViewControllerDidCloseAnnotation(_ viewController: OverlayRootViewController) {
        overlayWindow?.isAnnotationModeActive = false
        viewController.exitAnnotationMode()
        restoreAppKeyWindow()
    }

    func overlayRootViewControllerDidRequestHideUntilRestart(_ viewController: OverlayRootViewController) {
        restoreAppKeyWindow()
        Sampler.hideUntilRestart()
    }

    func overlayRootViewControllerDidFinishAnnotation(_ viewController: OverlayRootViewController) {
        overlayWindow?.isAnnotationModeActive = false
    }

    private func restoreAppKeyWindow() {
        guard let windowScene, let overlayWindow else {
            return
        }

        windowScene.windows
            .filter { $0 !== overlayWindow && $0.windowLevel == .normal && !$0.isHidden }
            .first?
            .makeKey()
    }
}
#endif
