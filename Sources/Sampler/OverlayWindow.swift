#if DEBUG && os(iOS)
import UIKit

protocol OverlayRootViewControllerDelegate: AnyObject {
    func overlayRootViewControllerDidRequestAnnotation(_ viewController: OverlayRootViewController)
    func overlayRootViewControllerDidCloseAnnotation(_ viewController: OverlayRootViewController)
    func overlayRootViewControllerDidFinishAnnotation(_ viewController: OverlayRootViewController)
    func overlayRootViewControllerDidRequestHideUntilRestart(_ viewController: OverlayRootViewController)
}

final class OverlayWindow: UIWindow {
    var isAnnotationModeActive = false

    override init(windowScene: UIWindowScene) {
        super.init(windowScene: windowScene)
        backgroundColor = .clear
        windowLevel = .alert + 1
        accessibilityIdentifier = "sampler_overlay_window"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hitView = super.hitTest(point, with: event)

        guard !isHidden, alpha > 0, isUserInteractionEnabled else {
            return nil
        }

        guard isAnnotationModeActive else {
            guard
                let rootViewController = rootViewController as? OverlayRootViewController,
                let hitView,
                rootViewController.isWidgetView(hitView)
            else {
                return nil
            }

            return hitView
        }

        return hitView
    }
}

final class OverlayRootViewController: UIViewController {
    weak var delegate: OverlayRootViewControllerDelegate?
    var agentEndpoint: URL?

    private let widget = FloatingAnnotationWidget()
    private var annotationViewController: AnnotationViewController?
    private var messageView: UIView?
    private var agentClient: SamplerAgentClient?
    private var isAgentSendAvailable = false
    private var widgetCenter: CGPoint?
    private var collapsedWidgetCenter: CGPoint?
    private var selectedAnnotationColor: UIColor = .systemBlue
    private var clearsAnnotationsAfterSend = false
    private var selectedTheme: OverlayTheme = .light
    private var selectedCopyFormat: CopyFormat = .annotatedScreenshot
    private lazy var settingsBackgroundTapGesture = UITapGestureRecognizer(
        target: self,
        action: #selector(handleSettingsBackgroundTap(_:))
    )

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        configureSettingsBackgroundTap()
        configureWidget()
        configureAgentClient()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        if widgetCenter == nil {
            let safeBounds = view.safeAreaLayoutGuide.layoutFrame
            let diameter = FloatingAnnotationWidget.collapsedSize
            widgetCenter = CGPoint(
                x: safeBounds.maxX - diameter / 2 - 18,
                y: safeBounds.maxY - diameter / 2 - 24
            )
        }

        widget.center = widgetCenter ?? view.center
    }

    func isWidgetView(_ candidate: UIView) -> Bool {
        candidate === widget || candidate.isDescendant(of: widget)
    }

    func enterAnnotationMode(with capture: CapturedScreen) {
        let annotationViewController = AnnotationViewController(capture: capture)
        annotationViewController.annotationColor = selectedAnnotationColor
        annotationViewController.overlayTheme = selectedTheme
        annotationViewController.copyFormat = selectedCopyFormat
        annotationViewController.clearsAnnotationsAfterSend = clearsAnnotationsAfterSend
        addChild(annotationViewController)
        annotationViewController.view.frame = view.bounds
        annotationViewController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.insertSubview(annotationViewController.view, belowSubview: widget)
        annotationViewController.didMove(toParent: self)
        self.annotationViewController = annotationViewController

        view.window?.makeKey()
        widget.setMode(.expanded, animated: true)
        moveWidgetToAnnotationToolbarPosition()
    }

    func exitAnnotationMode() {
        guard let annotationViewController else {
            widget.setMode(.collapsed, animated: true)
            restoreCollapsedWidgetPosition()
            return
        }

        widget.setMode(.collapsed, animated: true)
        restoreCollapsedWidgetPosition()

        annotationViewController.fadeDimmingOut { [weak self] in
            guard let self else {
                return
            }

            annotationViewController.willMove(toParent: nil)
            annotationViewController.view.removeFromSuperview()
            annotationViewController.removeFromParent()
            self.annotationViewController = nil
        }
    }

    func showTransientMessage(_ message: String) {
        messageView?.removeFromSuperview()

        let toastView = ToastView(title: message, iconName: "info.circle.fill", overlayTheme: selectedTheme)
        toastView.alpha = 0
        toastView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(toastView)
        messageView = toastView

        NSLayoutConstraint.activate([
            toastView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            toastView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            toastView.heightAnchor.constraint(greaterThanOrEqualToConstant: 42),
            toastView.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, multiplier: 0.86)
        ])

        toastView.transform = CGAffineTransform(translationX: 0, y: -64)
        UIView.animate(
            withDuration: 0.28,
            delay: 0,
            usingSpringWithDamping: 0.86,
            initialSpringVelocity: 0.25,
            options: [.allowUserInteraction]
        ) {
            toastView.alpha = 1
            toastView.transform = .identity
        } completion: { _ in
            UIView.animate(withDuration: 0.18, delay: 1.4, options: [.curveEaseIn]) {
                toastView.alpha = 0
                toastView.transform = CGAffineTransform(translationX: 0, y: -24)
            } completion: { _ in
                toastView.removeFromSuperview()
            }
        }
    }

    private func configureWidget() {
        widget.onActivate = { [weak self] in
            guard let self else {
                return
            }
            delegate?.overlayRootViewControllerDidRequestAnnotation(self)
        }
        widget.onClose = { [weak self] in
            guard let self else {
                return
            }
            delegate?.overlayRootViewControllerDidCloseAnnotation(self)
        }
        widget.onCopy = { [weak self] in
            self?.annotationViewController?.copyAgentContext()
        }
        widget.onShare = { [weak self] in
            self?.annotationViewController?.shareFullExport()
        }
        widget.onSendToAgent = { [weak self] in
            guard let self, let agentClient, isAgentSendAvailable else {
                self?.showTransientMessage("MCP not set up")
                return
            }
            annotationViewController?.sendToAgent(using: agentClient)
        }
        widget.onSettingsOpen = { [weak self] in
            self?.openSettingsSheet()
        }
        widget.onSettingsClose = { [weak self] in
            self?.closeSettingsSheet()
        }
        widget.onHideUntilRestart = { [weak self] in
            guard let self else {
                return
            }
            animateHideUntilRestart()
        }
        widget.onColorChange = { [weak self] color in
            self?.selectedAnnotationColor = color
            self?.annotationViewController?.annotationColor = color
        }
        widget.onClearAfterSendChange = { [weak self] isOn in
            self?.clearsAnnotationsAfterSend = isOn
            self?.annotationViewController?.clearsAnnotationsAfterSend = isOn
        }
        widget.onThemeChange = { [weak self] theme in
            self?.selectedTheme = theme
            self?.overrideUserInterfaceStyle = theme.userInterfaceStyle
            self?.annotationViewController?.overlayTheme = theme
        }
        widget.onCopyFormatChange = { [weak self] copyFormat in
            self?.selectedCopyFormat = copyFormat
            self?.annotationViewController?.copyFormat = copyFormat
        }

        widget.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(handleWidgetPan(_:))))
        view.addSubview(widget)
    }

    private func configureAgentClient() {
        guard let endpoint = agentEndpoint ?? SamplerAgentClient.defaultEndpoint else {
            return
        }

        let client = SamplerAgentClient(endpoint: endpoint)
        agentClient = client
        Task { [weak self] in
            let isReachable = await client.isReachable()
            await MainActor.run {
                self?.isAgentSendAvailable = isReachable
                self?.widget.setAgentSendAvailable(isReachable, animated: true)
            }
        }
    }

    private func configureSettingsBackgroundTap() {
        settingsBackgroundTapGesture.cancelsTouchesInView = true
        settingsBackgroundTapGesture.delegate = self
        view.addGestureRecognizer(settingsBackgroundTapGesture)
    }

    private func openSettingsSheet() {
        annotationViewController?.view.isUserInteractionEnabled = false
        moveWidgetToSettingsSheetPosition()
    }

    private func closeSettingsSheet() {
        annotationViewController?.view.isUserInteractionEnabled = true
        widget.setMode(.expanded, animated: true)
        moveWidgetToAnnotationToolbarPosition()
    }

    @objc private func handleSettingsBackgroundTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended, widget.mode == .settings else {
            return
        }

        closeSettingsSheet()
    }

    @objc private func handleWidgetPan(_ gesture: UIPanGestureRecognizer) {
        guard widget.mode == .collapsed else {
            return
        }

        let translation = gesture.translation(in: view)
        let currentCenter = widgetCenter ?? widget.center
        let nextCenter = CGPoint(x: currentCenter.x + translation.x, y: currentCenter.y + translation.y)
        widgetCenter = clampedWidgetCenter(nextCenter)
        widget.center = widgetCenter ?? widget.center
        gesture.setTranslation(.zero, in: view)

        if gesture.state == .ended || gesture.state == .cancelled {
            snapWidgetToNearestEdge()
        }
    }

    private func clampedWidgetCenter(_ center: CGPoint) -> CGPoint {
        let safeBounds = view.safeAreaLayoutGuide.layoutFrame.insetBy(dx: 12, dy: 12)
        let halfWidth = widget.bounds.width / 2
        let halfHeight = widget.bounds.height / 2

        return CGPoint(
            x: min(max(center.x, safeBounds.minX + halfWidth), safeBounds.maxX - halfWidth),
            y: min(max(center.y, safeBounds.minY + halfHeight), safeBounds.maxY - halfHeight)
        )
    }

    private func snapWidgetToNearestEdge() {
        let safeBounds = view.safeAreaLayoutGuide.layoutFrame.insetBy(dx: 18, dy: 18)
        let currentCenter = widgetCenter ?? widget.center
        let targetX = currentCenter.x < view.bounds.midX
            ? safeBounds.minX + widget.bounds.width / 2
            : safeBounds.maxX - widget.bounds.width / 2
        let target = clampedWidgetCenter(CGPoint(x: targetX, y: currentCenter.y))
        widgetCenter = target

        UIView.animate(
            withDuration: 0.24,
            delay: 0,
            usingSpringWithDamping: 0.82,
            initialSpringVelocity: 0.4,
            options: [.allowUserInteraction]
        ) {
            self.widget.center = target
        }
    }

    private func moveWidgetToAnnotationToolbarPosition() {
        collapsedWidgetCenter = widgetCenter ?? widget.center

        let safeFrame = view.safeAreaLayoutGuide.layoutFrame
        let target = CGPoint(
            x: view.bounds.midX,
            y: min(view.bounds.maxY - FloatingAnnotationWidget.expandedSize.height / 2 - 14, safeFrame.maxY - FloatingAnnotationWidget.expandedSize.height / 2 + 10)
        )
        widgetCenter = target

        UIView.animate(
            withDuration: 0.28,
            delay: 0,
            usingSpringWithDamping: 0.84,
            initialSpringVelocity: 0.22,
            options: [.allowUserInteraction, .curveEaseInOut]
        ) {
            self.widget.center = target
        }
    }

    private func moveWidgetToSettingsSheetPosition() {
        let settingsSize = FloatingAnnotationWidget.settingsSize(in: view.bounds)
        let target = CGPoint(
            x: view.bounds.midX,
            y: view.bounds.maxY - settingsSize.height / 2 - 14
        )
        widgetCenter = target

        UIView.animate(
            withDuration: 0.28,
            delay: 0,
            usingSpringWithDamping: 0.86,
            initialSpringVelocity: 0.18,
            options: [.allowUserInteraction, .curveEaseInOut]
        ) {
            self.widget.center = target
        }
    }

    private func restoreCollapsedWidgetPosition() {
        let restoredCenter = collapsedWidgetCenter ?? CGPoint(
            x: view.safeAreaLayoutGuide.layoutFrame.maxX - FloatingAnnotationWidget.collapsedSize / 2 - 18,
            y: view.safeAreaLayoutGuide.layoutFrame.maxY - FloatingAnnotationWidget.collapsedSize / 2 - 24
        )
        widgetCenter = clampedWidgetCenter(restoredCenter)

        UIView.animate(
            withDuration: 0.24,
            delay: 0,
            usingSpringWithDamping: 0.84,
            initialSpringVelocity: 0.2,
            options: [.allowUserInteraction, .curveEaseInOut]
        ) {
            self.widget.center = self.widgetCenter ?? restoredCenter
        }
    }

    private func animateHideUntilRestart() {
        widget.setMode(.expanded, animated: true)
        moveWidgetToAnnotationToolbarPosition()

        UIView.animate(
            withDuration: 0.14,
            delay: 0.16,
            options: [.curveEaseIn, .beginFromCurrentState, .allowUserInteraction]
        ) {
            self.widget.alpha = 0
            self.widget.transform = CGAffineTransform(scaleX: 0.86, y: 0.86)
        } completion: { [weak self] _ in
            guard let self else {
                return
            }
            delegate?.overlayRootViewControllerDidRequestHideUntilRestart(self)
        }
    }
}

extension OverlayRootViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard gestureRecognizer === settingsBackgroundTapGesture else {
            return true
        }

        guard widget.mode == .settings else {
            return false
        }

        let pointInWidget = touch.location(in: widget)
        return !widget.bounds.contains(pointInWidget)
    }
}

final class FloatingAnnotationWidget: UIControl {
    enum Mode {
        case collapsed
        case expanded
        case settings
    }

    static let collapsedSize: CGFloat = 54
    static let expandedSize = CGSize(width: 258, height: 54)

    static func settingsSize(in bounds: CGRect) -> CGSize {
        CGSize(
            width: max(280, bounds.width - 24),
            height: min(max(458, bounds.height * 0.58), bounds.height - 28)
        )
    }

    var onActivate: (() -> Void)?
    var onClose: (() -> Void)?
    var onCopy: (() -> Void)?
    var onShare: (() -> Void)?
    var onSendToAgent: (() -> Void)?
    var onSettingsOpen: (() -> Void)?
    var onSettingsClose: (() -> Void)?
    var onHideUntilRestart: (() -> Void)?
    var onColorChange: ((UIColor) -> Void)?
    var onClearAfterSendChange: ((Bool) -> Void)?
    var onThemeChange: ((OverlayTheme) -> Void)?
    var onCopyFormatChange: ((CopyFormat) -> Void)?

    private(set) var mode: Mode = .collapsed
    private var overlayTheme: OverlayTheme = .light {
        didSet {
            applyTheme()
        }
    }
    private var copyFormat: CopyFormat = .annotatedScreenshot {
        didSet {
            updateCopyFormatButton(from: oldValue, animated: true)
        }
    }

    private let iconView = UIImageView(
        image: UIImage(named: "Sampler_Logo", in: .module, compatibleWith: nil)?
            .withRenderingMode(.alwaysTemplate)
    )
    private let toolbarView = UIStackView()
    private let settingsView = UIView()
    private let clipboardHelpView = UIView()
    private var settingsPageViews: [UIView] = []
    private let feedbackGenerator = UIImpactFeedbackGenerator(style: .light)
    private var themedButtons: [UIButton] = []
    private var elevatedButtons: [UIButton] = []
    private var primaryLabels: [UILabel] = []
    private var secondaryLabels: [UILabel] = []
    private var mutedLabels: [UILabel] = []
    private var dividers: [UIView] = []
    private var chevronViews: [UIImageView] = []
    private var themeToggleButton: UIButton?
    private var copyFormatValueLabel: UILabel?
    private var copyFormatIndicatorDots: [UIView] = []
    private var colorButtons: [ColorOptionButton] = []
    private var clearAfterSendButton: AnimatedCheckboxButton?
    private var sendToAgentButton: UIButton?

    override init(frame: CGRect) {
        super.init(frame: CGRect(origin: .zero, size: CGSize(width: Self.collapsedSize, height: Self.collapsedSize)))
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setMode(_ mode: Mode, animated: Bool) {
        self.mode = mode
        let size: CGSize
        switch mode {
        case .collapsed:
            size = CGSize(width: Self.collapsedSize, height: Self.collapsedSize)
        case .expanded:
            size = Self.expandedSize
        case .settings:
            size = Self.settingsSize(in: superview?.bounds ?? UIScreen.main.bounds)
        }

        let changes = {
            self.bounds.size = size
            self.layer.cornerRadius = size.height / 2
            self.iconView.alpha = mode == .collapsed ? 1 : 0
            self.toolbarView.alpha = mode == .expanded ? 1 : 0
            self.settingsView.alpha = mode == .settings ? 1 : 0
            if mode != .settings {
                self.resetSettingsPages()
            }
            self.layer.cornerRadius = mode == .settings ? 40 : size.height / 2
            self.layoutIfNeeded()
        }

        guard animated else {
            changes()
            return
        }

        UIView.animate(
            withDuration: 0.26,
            delay: 0,
            usingSpringWithDamping: 0.84,
            initialSpringVelocity: 0.2,
            options: [.allowUserInteraction, .curveEaseInOut],
            animations: changes
        )
    }

    private func configure() {
        layer.cornerRadius = Self.collapsedSize / 2
        layer.shadowColor = overlayTheme.shadowColor
        layer.shadowOpacity = 0.22
        layer.shadowRadius = 12
        layer.shadowOffset = CGSize(width: 0, height: 5)
        accessibilityIdentifier = "sampler_widget"

        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)

        toolbarView.alpha = 0
        toolbarView.axis = .horizontal
        toolbarView.alignment = .center
        toolbarView.distribution = .equalSpacing
        toolbarView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(toolbarView)

        let copy = makeButton(systemName: "doc.on.doc", pointSize: 13, imageSize: 22, action: #selector(copyTapped))
        let share = makeButton(systemName: "square.and.arrow.up", action: #selector(shareTapped))
        let sendToAgent = makeButton(systemName: "paperplane.fill", pointSize: 14, imageSize: 22, action: #selector(sendToAgentTapped))
        sendToAgent.accessibilityLabel = "Send to Agent"
        sendToAgent.accessibilityHint = "Starts MCP setup help when sampler-mcp is not reachable"
        sendToAgent.alpha = 0.34
        self.sendToAgentButton = sendToAgent
        let settings = makeButton(systemName: "gearshape", action: #selector(settingsTapped))
        let divider = UIView()
        divider.translatesAutoresizingMaskIntoConstraints = false
        dividers.append(divider)
        let close = makeButton(systemName: "xmark", pointSize: 14, action: #selector(closeTapped))
        [copy, share, sendToAgent, settings, divider, close].forEach(toolbarView.addArrangedSubview)

        configureSettingsView()

        addTarget(self, action: #selector(primaryTapped), for: .touchUpInside)

        NSLayoutConstraint.activate([
            iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 29),
            iconView.heightAnchor.constraint(equalToConstant: 29),

            toolbarView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            toolbarView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            toolbarView.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            toolbarView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            divider.widthAnchor.constraint(equalToConstant: 1),
            divider.heightAnchor.constraint(equalToConstant: 24)
        ])

        feedbackGenerator.prepare()
        applyTheme()
    }

    func setAgentSendAvailable(_ isAvailable: Bool, animated: Bool) {
        guard let sendToAgentButton else {
            return
        }

        let changes = {
            sendToAgentButton.alpha = isAvailable ? 1 : 0.34
            self.layoutIfNeeded()
        }

        guard animated else {
            changes()
            return
        }

        UIView.animate(
            withDuration: 0.18,
            delay: 0,
            options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseInOut],
            animations: changes
        )
    }

    private func makeButton(
        systemName: String,
        pointSize: CGFloat = 15,
        imageSize: CGFloat = 24,
        width: CGFloat = 32,
        action: Selector
    ) -> UIButton {
        let button = UIButton(type: .system)
        button.addTarget(self, action: action, for: .touchUpInside)
        button.backgroundColor = .clear
        button.translatesAutoresizingMaskIntoConstraints = false
        button.accessibilityTraits.insert(.button)
        button.setImage(
            UIImage(
                systemName: systemName,
                withConfiguration: UIImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
            ),
            for: .normal
        )
        button.imageView?.contentMode = .scaleAspectFit
        themedButtons.append(button)

        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: width),
            button.heightAnchor.constraint(equalToConstant: 32)
        ])
        return button
    }

    private func configureSettingsView() {
        settingsView.alpha = 0
        settingsView.clipsToBounds = true
        settingsView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(settingsView)

        let closeButton = UIButton(type: .system)
        closeButton.layer.cornerRadius = 18
        closeButton.setImage(UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .bold)), for: .normal)
        closeButton.addTarget(self, action: #selector(settingsCloseTapped), for: .touchUpInside)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        settingsView.addSubview(closeButton)
        themedButtons.append(closeButton)
        elevatedButtons.append(closeButton)

        let themeToggleButton = UIButton(type: .system)
        themeToggleButton.backgroundColor = overlayTheme.elevatedControlBackground
        themeToggleButton.layer.cornerRadius = 18
        themeToggleButton.addTarget(self, action: #selector(themeToggleTapped), for: .touchUpInside)
        themeToggleButton.translatesAutoresizingMaskIntoConstraints = false
        settingsView.addSubview(themeToggleButton)
        self.themeToggleButton = themeToggleButton
        themedButtons.append(themeToggleButton)
        elevatedButtons.append(themeToggleButton)

        let titleLabel = UILabel()
        titleLabel.text = "Sampler"
        titleLabel.font = .roundedSystemFont(ofSize: 26, weight: .bold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        settingsView.addSubview(titleLabel)
        primaryLabels.append(titleLabel)

        let versionLabel = UILabel()
        versionLabel.text = "V\(Sampler.version)"
        versionLabel.font = .monospacedSystemFont(ofSize: 12, weight: .semibold)
        versionLabel.translatesAutoresizingMaskIntoConstraints = false
        settingsView.addSubview(versionLabel)
        mutedLabels.append(versionLabel)

        let titleDivider = makeDivider()

        let copyFormatRow = makeSettingsRow(title: "Copy Format")
        copyFormatRow.addTarget(self, action: #selector(copyFormatTapped), for: .touchUpInside)
        let copyFormatValueLabel = UILabel()
        copyFormatValueLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        copyFormatValueLabel.textAlignment = .right
        copyFormatValueLabel.translatesAutoresizingMaskIntoConstraints = false
        copyFormatRow.addSubview(copyFormatValueLabel)
        self.copyFormatValueLabel = copyFormatValueLabel
        secondaryLabels.append(copyFormatValueLabel)

        let copyFormatIndicatorStack = UIStackView()
        copyFormatIndicatorStack.axis = .vertical
        copyFormatIndicatorStack.alignment = .center
        copyFormatIndicatorStack.spacing = 5
        copyFormatIndicatorStack.isUserInteractionEnabled = false
        copyFormatIndicatorStack.translatesAutoresizingMaskIntoConstraints = false
        copyFormatRow.addSubview(copyFormatIndicatorStack)

        copyFormatIndicatorDots = (0..<2).map { _ in
            let dot = UIView()
            dot.layer.cornerRadius = 3
            dot.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                dot.widthAnchor.constraint(equalToConstant: 6),
                dot.heightAnchor.constraint(equalToConstant: 6)
            ])
            copyFormatIndicatorStack.addArrangedSubview(dot)
            return dot
        }

        let copyFormatDivider = makeDivider()

        let hideRow = makeSettingsRow(title: "Hide Until Restart")
        let hideSwitch = UISwitch()
        hideSwitch.onTintColor = .systemBlue
        hideSwitch.addTarget(self, action: #selector(hideUntilRestartChanged(_:)), for: .valueChanged)
        hideSwitch.translatesAutoresizingMaskIntoConstraints = false
        hideRow.addSubview(hideSwitch)

        let firstDivider = makeDivider()

        let markerLabel = makeSettingsLabel("Marker Color")
        let colorRow = UIStackView()
        colorRow.axis = .horizontal
        colorRow.alignment = .center
        colorRow.distribution = .equalSpacing
        colorRow.translatesAutoresizingMaskIntoConstraints = false
        settingsView.addSubview(colorRow)

        let colors: [UIColor] = [.systemPurple, .systemBlue, .systemCyan, .systemGreen, .systemYellow, .systemOrange, .systemRed]
        colorButtons = colors.map { color in
            let button = ColorOptionButton(color: color)
            button.isSelected = color.hexString == UIColor.systemBlue.hexString
            button.addTarget(self, action: #selector(colorTapped(_:)), for: .touchUpInside)
            return button
        }
        colorButtons.forEach(colorRow.addArrangedSubview)

        let secondDivider = makeDivider()

        let clearRow = makeSettingsRow(title: "Clear on copy/send")
        let clearButton = AnimatedCheckboxButton()
        clearButton.translatesAutoresizingMaskIntoConstraints = false
        clearButton.addTarget(self, action: #selector(clearAfterSendTapped(_:)), for: .touchUpInside)
        clearRow.addSubview(clearButton)
        clearAfterSendButton = clearButton

        let helpDivider = makeDivider()
        let clipboardRow = makeLinksRow(title: "Copy to Mac Setup", action: #selector(openClipboardHelp))
        let clipboardDivider = makeDivider()
        let helpRow = makeLinksRow(title: "Help & Feedback", action: #selector(openHelpAndFeedback))
        let bottomDivider = makeDivider()
        let linksRow = makeLinksRow(title: "GitHub & Docs", action: #selector(openGitHubAndDocs))

        NSLayoutConstraint.activate([
            settingsView.leadingAnchor.constraint(equalTo: leadingAnchor),
            settingsView.trailingAnchor.constraint(equalTo: trailingAnchor),
            settingsView.topAnchor.constraint(equalTo: topAnchor),
            settingsView.bottomAnchor.constraint(equalTo: bottomAnchor),

            closeButton.trailingAnchor.constraint(equalTo: settingsView.trailingAnchor, constant: -16),
            closeButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 36),
            closeButton.heightAnchor.constraint(equalToConstant: 36),

            themeToggleButton.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -8),
            themeToggleButton.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
            themeToggleButton.widthAnchor.constraint(equalToConstant: 36),
            themeToggleButton.heightAnchor.constraint(equalToConstant: 36),

            titleLabel.leadingAnchor.constraint(equalTo: settingsView.leadingAnchor, constant: 20),
            titleLabel.topAnchor.constraint(equalTo: settingsView.topAnchor, constant: 22),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: versionLabel.leadingAnchor, constant: -8),

            versionLabel.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 8),
            versionLabel.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor, constant: 1),
            versionLabel.trailingAnchor.constraint(lessThanOrEqualTo: themeToggleButton.leadingAnchor, constant: -12),

            titleDivider.leadingAnchor.constraint(equalTo: settingsView.leadingAnchor, constant: 20),
            titleDivider.trailingAnchor.constraint(equalTo: settingsView.trailingAnchor, constant: -20),
            titleDivider.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            titleDivider.heightAnchor.constraint(equalToConstant: 1),

            copyFormatRow.leadingAnchor.constraint(equalTo: settingsView.leadingAnchor, constant: 20),
            copyFormatRow.trailingAnchor.constraint(equalTo: settingsView.trailingAnchor, constant: -20),
            copyFormatRow.topAnchor.constraint(equalTo: titleDivider.bottomAnchor, constant: 12),
            copyFormatRow.heightAnchor.constraint(equalToConstant: 34),

            copyFormatValueLabel.trailingAnchor.constraint(equalTo: copyFormatIndicatorStack.leadingAnchor, constant: -10),
            copyFormatValueLabel.centerYAnchor.constraint(equalTo: copyFormatRow.centerYAnchor),
            copyFormatValueLabel.leadingAnchor.constraint(greaterThanOrEqualTo: copyFormatRow.leadingAnchor, constant: 120),

            copyFormatIndicatorStack.trailingAnchor.constraint(equalTo: copyFormatRow.trailingAnchor, constant: -8),
            copyFormatIndicatorStack.centerYAnchor.constraint(equalTo: copyFormatRow.centerYAnchor),

            copyFormatDivider.leadingAnchor.constraint(equalTo: settingsView.leadingAnchor, constant: 20),
            copyFormatDivider.trailingAnchor.constraint(equalTo: settingsView.trailingAnchor, constant: -20),
            copyFormatDivider.topAnchor.constraint(equalTo: copyFormatRow.bottomAnchor, constant: 12),
            copyFormatDivider.heightAnchor.constraint(equalToConstant: 1),

            hideRow.leadingAnchor.constraint(equalTo: settingsView.leadingAnchor, constant: 20),
            hideRow.trailingAnchor.constraint(equalTo: settingsView.trailingAnchor, constant: -20),
            hideRow.topAnchor.constraint(equalTo: copyFormatDivider.bottomAnchor, constant: 12),
            hideRow.heightAnchor.constraint(equalToConstant: 34),

            hideSwitch.trailingAnchor.constraint(equalTo: hideRow.trailingAnchor),
            hideSwitch.centerYAnchor.constraint(equalTo: hideRow.centerYAnchor),

            firstDivider.leadingAnchor.constraint(equalTo: settingsView.leadingAnchor, constant: 20),
            firstDivider.trailingAnchor.constraint(equalTo: settingsView.trailingAnchor, constant: -20),
            firstDivider.topAnchor.constraint(equalTo: hideRow.bottomAnchor, constant: 12),
            firstDivider.heightAnchor.constraint(equalToConstant: 1),

            markerLabel.leadingAnchor.constraint(equalTo: settingsView.leadingAnchor, constant: 20),
            markerLabel.topAnchor.constraint(equalTo: firstDivider.bottomAnchor, constant: 12),

            colorRow.leadingAnchor.constraint(equalTo: settingsView.leadingAnchor, constant: 20),
            colorRow.trailingAnchor.constraint(equalTo: settingsView.trailingAnchor, constant: -20),
            colorRow.topAnchor.constraint(equalTo: markerLabel.bottomAnchor, constant: 10),
            colorRow.heightAnchor.constraint(equalToConstant: 36),

            secondDivider.leadingAnchor.constraint(equalTo: settingsView.leadingAnchor, constant: 20),
            secondDivider.trailingAnchor.constraint(equalTo: settingsView.trailingAnchor, constant: -20),
            secondDivider.topAnchor.constraint(equalTo: colorRow.bottomAnchor, constant: 12),
            secondDivider.heightAnchor.constraint(equalToConstant: 1),

            clearRow.leadingAnchor.constraint(equalTo: settingsView.leadingAnchor, constant: 20),
            clearRow.trailingAnchor.constraint(equalTo: settingsView.trailingAnchor, constant: -20),
            clearRow.topAnchor.constraint(equalTo: secondDivider.bottomAnchor, constant: 12),
            clearRow.heightAnchor.constraint(equalToConstant: 30),

            clearButton.trailingAnchor.constraint(equalTo: clearRow.trailingAnchor),
            clearButton.centerYAnchor.constraint(equalTo: clearRow.centerYAnchor),
            clearButton.widthAnchor.constraint(equalToConstant: 24),
            clearButton.heightAnchor.constraint(equalToConstant: 24),

            helpDivider.leadingAnchor.constraint(equalTo: settingsView.leadingAnchor, constant: 20),
            helpDivider.trailingAnchor.constraint(equalTo: settingsView.trailingAnchor, constant: -20),
            helpDivider.topAnchor.constraint(equalTo: clearRow.bottomAnchor, constant: 12),
            helpDivider.heightAnchor.constraint(equalToConstant: 1),

            clipboardRow.leadingAnchor.constraint(equalTo: settingsView.leadingAnchor, constant: 20),
            clipboardRow.trailingAnchor.constraint(equalTo: settingsView.trailingAnchor, constant: -20),
            clipboardRow.topAnchor.constraint(equalTo: helpDivider.bottomAnchor, constant: 12),
            clipboardRow.heightAnchor.constraint(equalToConstant: 30),

            clipboardDivider.leadingAnchor.constraint(equalTo: settingsView.leadingAnchor, constant: 20),
            clipboardDivider.trailingAnchor.constraint(equalTo: settingsView.trailingAnchor, constant: -20),
            clipboardDivider.topAnchor.constraint(equalTo: clipboardRow.bottomAnchor, constant: 12),
            clipboardDivider.heightAnchor.constraint(equalToConstant: 1),

            helpRow.leadingAnchor.constraint(equalTo: settingsView.leadingAnchor, constant: 20),
            helpRow.trailingAnchor.constraint(equalTo: settingsView.trailingAnchor, constant: -20),
            helpRow.topAnchor.constraint(equalTo: clipboardDivider.bottomAnchor, constant: 12),
            helpRow.heightAnchor.constraint(equalToConstant: 30),

            bottomDivider.leadingAnchor.constraint(equalTo: settingsView.leadingAnchor, constant: 20),
            bottomDivider.trailingAnchor.constraint(equalTo: settingsView.trailingAnchor, constant: -20),
            bottomDivider.topAnchor.constraint(equalTo: helpRow.bottomAnchor, constant: 12),
            bottomDivider.heightAnchor.constraint(equalToConstant: 1),

            linksRow.leadingAnchor.constraint(equalTo: settingsView.leadingAnchor, constant: 20),
            linksRow.trailingAnchor.constraint(equalTo: settingsView.trailingAnchor, constant: -20),
            linksRow.topAnchor.constraint(equalTo: bottomDivider.bottomAnchor, constant: 12),
            linksRow.bottomAnchor.constraint(equalTo: settingsView.bottomAnchor, constant: -24),
            linksRow.heightAnchor.constraint(equalToConstant: 30)
        ])

        settingsPageViews = [
            closeButton,
            themeToggleButton,
            titleLabel,
            versionLabel,
            titleDivider,
            copyFormatRow,
            copyFormatValueLabel,
            copyFormatIndicatorStack,
            copyFormatDivider,
            hideRow,
            firstDivider,
            markerLabel,
            colorRow,
            secondDivider,
            clearRow,
            helpDivider,
            clipboardRow,
            clipboardDivider,
            helpRow,
            bottomDivider,
            linksRow
        ]

        configureClipboardHelpView()
    }

    private func configureClipboardHelpView() {
        clipboardHelpView.alpha = 0
        clipboardHelpView.isHidden = true
        clipboardHelpView.backgroundColor = .clear
        clipboardHelpView.translatesAutoresizingMaskIntoConstraints = false
        settingsView.addSubview(clipboardHelpView)

        let backButton = UIButton(type: .system)
        backButton.setImage(UIImage(systemName: "chevron.left", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)), for: .normal)
        backButton.addTarget(self, action: #selector(closeClipboardHelp), for: .touchUpInside)
        backButton.translatesAutoresizingMaskIntoConstraints = false
        clipboardHelpView.addSubview(backButton)
        themedButtons.append(backButton)

        let titleLabel = UILabel()
        titleLabel.text = "Copy to Mac"
        titleLabel.font = .roundedSystemFont(ofSize: 22, weight: .bold)
        titleLabel.numberOfLines = 0
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        clipboardHelpView.addSubview(titleLabel)
        primaryLabels.append(titleLabel)

        let titleDivider = UIView()
        titleDivider.translatesAutoresizingMaskIntoConstraints = false
        clipboardHelpView.addSubview(titleDivider)
        dividers.append(titleDivider)

        let bodyStack = UIStackView(arrangedSubviews: [
            makeClipboardHelpLabel(
                "Use Copy-to-clipboard to seamlessly paste annotations from Sampler to your Mac.",
                emphasis: .primary
            ),
            makeClipboardHelpLabel("Requirements: same Apple ID, Bluetooth, Wi-Fi, and Handoff enabled."),
            makeClipboardHelpLabel("iPhone: Settings > General > AirPlay & Continuity > Handoff: On"),
            makeClipboardHelpLabel("Mac: System Settings > General > AirDrop & Handoff > Allow Handoff between this Mac and your iCloud devices: On"),
            makeClipboardHelpLabel("Tip: keep both devices nearby and unlocked. If it stalls, toggle Wi-Fi/Bluetooth or restart both devices.")
        ])
        bodyStack.axis = .vertical
        bodyStack.spacing = 14
        bodyStack.translatesAutoresizingMaskIntoConstraints = false
        clipboardHelpView.addSubview(bodyStack)

        NSLayoutConstraint.activate([
            clipboardHelpView.leadingAnchor.constraint(equalTo: settingsView.leadingAnchor),
            clipboardHelpView.trailingAnchor.constraint(equalTo: settingsView.trailingAnchor),
            clipboardHelpView.topAnchor.constraint(equalTo: settingsView.topAnchor),
            clipboardHelpView.bottomAnchor.constraint(equalTo: settingsView.bottomAnchor),

            backButton.leadingAnchor.constraint(equalTo: clipboardHelpView.leadingAnchor, constant: 18),
            backButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            backButton.widthAnchor.constraint(equalToConstant: 36),
            backButton.heightAnchor.constraint(equalToConstant: 36),

            titleLabel.leadingAnchor.constraint(equalTo: backButton.trailingAnchor, constant: 8),
            titleLabel.topAnchor.constraint(equalTo: clipboardHelpView.topAnchor, constant: 24),
            titleLabel.trailingAnchor.constraint(equalTo: clipboardHelpView.trailingAnchor, constant: -20),

            titleDivider.leadingAnchor.constraint(equalTo: clipboardHelpView.leadingAnchor, constant: 20),
            titleDivider.trailingAnchor.constraint(equalTo: clipboardHelpView.trailingAnchor, constant: -20),
            titleDivider.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 18),
            titleDivider.heightAnchor.constraint(equalToConstant: 1),

            bodyStack.leadingAnchor.constraint(equalTo: clipboardHelpView.leadingAnchor, constant: 22),
            bodyStack.trailingAnchor.constraint(equalTo: clipboardHelpView.trailingAnchor, constant: -22),
            bodyStack.topAnchor.constraint(equalTo: titleDivider.bottomAnchor, constant: 22)
        ])
    }

    private enum ClipboardHelpEmphasis {
        case primary
        case secondary
    }

    private func makeClipboardHelpLabel(_ text: String, emphasis: ClipboardHelpEmphasis = .secondary) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 15, weight: .medium)
        label.numberOfLines = 0
        switch emphasis {
        case .primary:
            primaryLabels.append(label)
        case .secondary:
            secondaryLabels.append(label)
        }
        return label
    }

    private func makeSettingsLabel(_ title: String) -> UILabel {
        let label = UILabel()
        label.text = title
        label.font = .systemFont(ofSize: 16, weight: .medium)
        label.translatesAutoresizingMaskIntoConstraints = false
        settingsView.addSubview(label)
        secondaryLabels.append(label)
        return label
    }

    private func makeSettingsRow(title: String) -> UIControl {
        let row = UIControl()
        row.translatesAutoresizingMaskIntoConstraints = false
        settingsView.addSubview(row)

        let label = makeSettingsLabel(title)
        label.removeFromSuperview()
        row.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            label.centerYAnchor.constraint(equalTo: row.centerYAnchor)
        ])
        return row
    }

    private func makeDivider() -> UIView {
        let divider = UIView()
        divider.translatesAutoresizingMaskIntoConstraints = false
        settingsView.addSubview(divider)
        dividers.append(divider)
        return divider
    }

    private func makeLinksRow(title: String, action: Selector) -> UIControl {
        let row = UIControl()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.addTarget(self, action: action, for: .touchUpInside)
        settingsView.addSubview(row)

        let label = UILabel()
        label.text = title
        label.font = .systemFont(ofSize: 16, weight: .medium)
        label.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(label)
        secondaryLabels.append(label)

        let chevron = UIImageView(
            image: UIImage(
                systemName: "chevron.forward",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
            )
        )
        chevron.contentMode = .scaleAspectFit
        chevron.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(chevron)
        chevronViews.append(chevron)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            label.centerYAnchor.constraint(equalTo: row.centerYAnchor),

            chevron.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            chevron.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            chevron.widthAnchor.constraint(equalToConstant: 10),
            chevron.heightAnchor.constraint(equalToConstant: 16)
        ])

        return row
    }

    @objc private func primaryTapped() {
        guard mode == .collapsed else {
            return
        }

        triggerHaptic()
        onActivate?()
    }

    @objc private func hideUntilRestartChanged(_ sender: UISwitch) {
        guard sender.isOn else {
            return
        }
        triggerHaptic()
        onHideUntilRestart?()
    }

    @objc private func openGitHubAndDocs() {
        triggerHaptic()
        guard let url = URL(string: "https://github.com/gabrieltmitchell/sampler") else {
            return
        }
        UIApplication.shared.open(url)
    }

    @objc private func openHelpAndFeedback() {
        triggerHaptic()
        guard let url = URL(string: "https://github.com/gabrieltmitchell/sampler/issues") else {
            return
        }
        UIApplication.shared.open(url)
    }

    @objc private func openClipboardHelp() {
        triggerHaptic()
        layoutIfNeeded()
        let pageWidth = settingsView.bounds.width
        clipboardHelpView.isHidden = false
        clipboardHelpView.alpha = 1
        clipboardHelpView.transform = CGAffineTransform(translationX: pageWidth, y: 0)

        UIView.animate(
            withDuration: 0.28,
            delay: 0,
            usingSpringWithDamping: 0.9,
            initialSpringVelocity: 0.2,
            options: [.curveEaseInOut, .allowUserInteraction]
        ) {
            self.settingsPageViews.forEach { $0.transform = CGAffineTransform(translationX: -pageWidth, y: 0) }
            self.clipboardHelpView.alpha = 1
            self.clipboardHelpView.transform = .identity
        }
    }

    @objc private func closeClipboardHelp() {
        triggerHaptic()
        let pageWidth = settingsView.bounds.width

        UIView.animate(
            withDuration: 0.28,
            delay: 0,
            usingSpringWithDamping: 0.9,
            initialSpringVelocity: 0.2,
            options: [.curveEaseInOut, .allowUserInteraction]
        ) {
            self.settingsPageViews.forEach { $0.transform = .identity }
            self.clipboardHelpView.transform = CGAffineTransform(translationX: pageWidth, y: 0)
        } completion: { _ in
            self.clipboardHelpView.alpha = 0
            self.clipboardHelpView.isHidden = true
            self.clipboardHelpView.transform = .identity
        }
    }

    private func resetSettingsPages() {
        settingsPageViews.forEach { $0.transform = .identity }
        clipboardHelpView.alpha = 0
        clipboardHelpView.isHidden = true
        clipboardHelpView.transform = .identity
    }

    private func applyTheme() {
        overrideUserInterfaceStyle = overlayTheme.userInterfaceStyle
        backgroundColor = overlayTheme.widgetBackground
        iconView.tintColor = overlayTheme.primaryText
        settingsView.backgroundColor = .clear
        clipboardHelpView.backgroundColor = .clear

        themedButtons.forEach {
            $0.tintColor = overlayTheme.primaryText
        }
        primaryLabels.forEach {
            $0.textColor = overlayTheme.primaryText
        }
        secondaryLabels.forEach {
            $0.textColor = overlayTheme.secondaryText
        }
        mutedLabels.forEach {
            $0.textColor = overlayTheme.mutedText
        }
        dividers.forEach {
            $0.backgroundColor = overlayTheme.divider
        }
        chevronViews.forEach {
            $0.tintColor = overlayTheme.mutedText
        }

        elevatedButtons.forEach {
            $0.backgroundColor = overlayTheme.elevatedControlBackground
        }
        themeToggleButton?.setImage(
            UIImage(
                systemName: overlayTheme == .light ? "moon.fill" : "sun.max.fill",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
            ),
            for: .normal
        )
        updateCopyFormatButton()
        clearAfterSendButton?.applyTheme(overlayTheme)
        colorButtons.forEach { $0.applyTheme(overlayTheme) }
    }

    private func updateCopyFormatButton(from previousFormat: CopyFormat? = nil, animated: Bool = false) {
        let activeIndex = copyFormat == .annotatedScreenshot ? 0 : 1
        let changes = {
            self.copyFormatValueLabel?.text = self.copyFormat.displayTitle
            self.copyFormatValueLabel?.textColor = self.overlayTheme.secondaryText
            for (index, dot) in self.copyFormatIndicatorDots.enumerated() {
                dot.backgroundColor = index == activeIndex
                    ? self.overlayTheme.primaryText
                    : self.overlayTheme.divider
            }
        }

        guard animated, previousFormat != nil else {
            changes()
            return
        }

        UIView.animate(
            withDuration: 0.18,
            delay: 0,
            options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseInOut],
            animations: changes
        )
    }

    @objc private func colorTapped(_ sender: ColorOptionButton) {
        triggerHaptic()
        colorButtons.forEach { $0.isSelected = $0 === sender }
        onColorChange?(sender.color)
    }

    @objc private func clearAfterSendTapped(_ sender: AnimatedCheckboxButton) {
        triggerHaptic()
        sender.setChecked(!sender.isChecked, animated: true)
        onClearAfterSendChange?(sender.isSelected)
    }

    @objc private func themeToggleTapped() {
        triggerHaptic()
        overlayTheme = overlayTheme.toggled
        onThemeChange?(overlayTheme)
    }

    @objc private func copyFormatTapped() {
        triggerHaptic()
        copyFormat = copyFormat.toggled
        onCopyFormatChange?(copyFormat)
    }

    @objc private func closeTapped() {
        triggerHaptic()
        onClose?()
    }

    @objc private func settingsTapped() {
        triggerHaptic()
        setMode(.settings, animated: true)
        onSettingsOpen?()
    }

    @objc private func settingsCloseTapped() {
        triggerHaptic()
        setMode(.expanded, animated: true)
        onSettingsClose?()
    }

    @objc private func copyTapped() {
        triggerHaptic()
        onCopy?()
    }

    @objc private func shareTapped() {
        triggerHaptic()
        onShare?()
    }

    @objc private func sendToAgentTapped() {
        triggerHaptic()
        onSendToAgent?()
    }

    private func triggerHaptic() {
        feedbackGenerator.impactOccurred()
        feedbackGenerator.prepare()
    }
}

private extension UIFont {
    static func roundedSystemFont(ofSize size: CGFloat, weight: UIFont.Weight) -> UIFont {
        let systemFont = UIFont.systemFont(ofSize: size, weight: weight)
        guard let roundedDescriptor = systemFont.fontDescriptor.withDesign(.rounded) else {
            return systemFont
        }
        return UIFont(descriptor: roundedDescriptor, size: size)
    }
}

private final class ColorOptionButton: UIControl {
    let color: UIColor
    private let innerCircle = UIView()

    override var isSelected: Bool {
        didSet {
            updateSelection(animated: true)
        }
    }

    init(color: UIColor) {
        self.color = color
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 36),
            heightAnchor.constraint(equalToConstant: 36)
        ])
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func applyTheme(_ theme: OverlayTheme) {
        updateSelection(animated: false)
    }

    private func configure() {
        backgroundColor = .clear
        layer.cornerRadius = 18
        layer.borderColor = color.cgColor

        innerCircle.backgroundColor = color
        innerCircle.layer.cornerRadius = 14
        innerCircle.isUserInteractionEnabled = false
        innerCircle.translatesAutoresizingMaskIntoConstraints = false
        addSubview(innerCircle)

        NSLayoutConstraint.activate([
            innerCircle.centerXAnchor.constraint(equalTo: centerXAnchor),
            innerCircle.centerYAnchor.constraint(equalTo: centerYAnchor),
            innerCircle.widthAnchor.constraint(equalToConstant: 28),
            innerCircle.heightAnchor.constraint(equalToConstant: 28)
        ])

        updateSelection(animated: false)
    }

    private func updateSelection(animated: Bool) {
        let changes = {
            self.layer.borderWidth = self.isSelected ? 3 : 0
            self.innerCircle.transform = self.isSelected
                ? CGAffineTransform(scaleX: 0.86, y: 0.86)
                : .identity
            self.innerCircle.alpha = self.isSelected ? 0.96 : 1
        }

        guard animated else {
            changes()
            return
        }

        UIView.animate(
            withDuration: 0.22,
            delay: 0,
            usingSpringWithDamping: 0.72,
            initialSpringVelocity: 0.35,
            options: [.allowUserInteraction, .beginFromCurrentState],
            animations: changes
        )
    }
}

private final class AnimatedCheckboxButton: UIControl {
    private let checkmarkView = UIImageView(
        image: UIImage(
            systemName: "checkmark",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .bold)
        )
    )

    private(set) var isChecked = false
    private var overlayTheme: OverlayTheme = .light

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setChecked(_ checked: Bool, animated: Bool) {
        isChecked = checked
        isSelected = checked

        let changes = {
            self.backgroundColor = checked ? self.overlayTheme.primaryText : .clear
            self.layer.borderColor = self.overlayTheme.primaryText.withAlphaComponent(checked ? 0.85 : 0.28).cgColor
            self.checkmarkView.alpha = checked ? 1 : 0
            self.checkmarkView.transform = checked ? .identity : CGAffineTransform(scaleX: 0.55, y: 0.55)
        }

        guard animated else {
            changes()
            return
        }

        UIView.animate(
            withDuration: 0.18,
            delay: 0,
            usingSpringWithDamping: 0.82,
            initialSpringVelocity: 0.25,
            options: [.allowUserInteraction, .beginFromCurrentState],
            animations: changes
        )
    }

    func applyTheme(_ theme: OverlayTheme) {
        overlayTheme = theme
        checkmarkView.tintColor = theme.widgetBackground
        setChecked(isChecked, animated: false)
    }

    private func configure() {
        layer.borderWidth = 2
        layer.cornerRadius = 6
        backgroundColor = .clear

        checkmarkView.alpha = 0
        checkmarkView.transform = CGAffineTransform(scaleX: 0.55, y: 0.55)
        checkmarkView.contentMode = .scaleAspectFit
        checkmarkView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(checkmarkView)

        NSLayoutConstraint.activate([
            checkmarkView.centerXAnchor.constraint(equalTo: centerXAnchor),
            checkmarkView.centerYAnchor.constraint(equalTo: centerYAnchor),
            checkmarkView.widthAnchor.constraint(equalToConstant: 14),
            checkmarkView.heightAnchor.constraint(equalToConstant: 14)
        ])
        applyTheme(overlayTheme)
    }
}
#endif
