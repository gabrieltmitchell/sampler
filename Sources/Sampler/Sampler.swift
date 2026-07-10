#if os(iOS)
import UIKit
#endif

@MainActor
public enum Sampler {
#if DEBUG && os(iOS)
    private static var controller: SamplerController?
    private static var isHiddenUntilRestart = false

    public static func start(in windowScene: UIWindowScene? = nil) {
        guard !isHiddenUntilRestart, controller == nil else {
            return
        }

        guard let scene = windowScene ?? UIApplication.shared.activeWindowScene else {
            assertionFailure(SamplerError.noActiveWindowScene.localizedDescription)
            return
        }

        let newController = SamplerController(windowScene: scene)
        controller = newController
        newController.start()
    }

    public static func stop() {
        controller?.stop()
        controller = nil
    }

    static func hideUntilRestart() {
        isHiddenUntilRestart = true
        stop()
    }
#else
    #if os(iOS)
    public static func start(in windowScene: UIWindowScene? = nil) {}
    #else
    public static func start() {}
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

    init(windowScene: UIWindowScene) {
        self.windowScene = windowScene
    }

    func start() {
        guard let windowScene else {
            return
        }

        let rootViewController = OverlayRootViewController()
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
