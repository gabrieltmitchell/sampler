#if DEBUG && os(iOS)
import UIKit

final class AnnotationViewController: UIViewController {
    private enum Constants {
        static let tapAnnotationSize = CGSize(width: 44, height: 44)
    }

    private let capture: CapturedScreen
    private let imageView = UIImageView()
    private let dimmingView = UIView()
    private let markerLayerView = UIView()
    private var annotations: [Annotation] = []
    private var markersByAnnotationID: [UUID: AnnotationMarkerView] = [:]
    private var draftView: AnnotationDraftView?
    private var currentAnnotationSurfaceOffset: CGFloat = 0
    private var dragStartPoint: CGPoint = .zero
    private var lastHapticTickPoint: CGPoint?
    private var keyboardFrameInView: CGRect?
    private let dragHapticGenerator = UISelectionFeedbackGenerator()
    var annotationColor: UIColor = .systemBlue
    var overlayTheme: OverlayTheme = .light {
        didSet {
            overrideUserInterfaceStyle = overlayTheme.userInterfaceStyle
            draftView?.overlayTheme = overlayTheme
        }
    }
    var copyFormat: CopyFormat = .annotatedScreenshot
    var clearsAnnotationsAfterSend = false

    init(capture: CapturedScreen) {
        self.capture = capture
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureViews()
        configureGestures()
        configureKeyboardAvoidance()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        fadeDimmingIn()
    }

    func fadeDimmingOut(completion: @escaping () -> Void) {
        UIView.animate(
            withDuration: 0.24,
            delay: 0,
            options: [.curveEaseInOut, .beginFromCurrentState]
        ) {
            self.dimmingView.alpha = 0
        } completion: { _ in
            completion()
        }
    }

    private func fadeDimmingIn() {
        UIView.animate(
            withDuration: 0.28,
            delay: 0,
            options: [.curveEaseInOut, .beginFromCurrentState]
        ) {
            self.dimmingView.alpha = 1
        }
    }

    func copyAgentContext() {
        guard !annotations.isEmpty else {
            showToast(title: "Add an Annotation First", iconName: "exclamationmark.bubble.fill")
            return
        }

        ExportBuilder.copyAgentContext(capture: capture, annotations: annotations, format: copyFormat)
        showToast(title: "Copied to Clipboard", iconName: "checkmark.circle.fill")
        if clearsAnnotationsAfterSend {
            clearAnnotations()
        }
    }

    func shareFullExport() {
        guard !annotations.isEmpty else {
            showToast(title: "Add an Annotation First", iconName: "exclamationmark.bubble.fill")
            return
        }

        do {
            let exportURL = try ExportBuilder.buildZip(capture: capture, annotations: annotations)
            let activityViewController = UIActivityViewController(activityItems: [exportURL], applicationActivities: nil)
            activityViewController.popoverPresentationController?.sourceView = view
            activityViewController.popoverPresentationController?.sourceRect = CGRect(
                x: view.bounds.midX,
                y: view.bounds.midY,
                width: 1,
                height: 1
            )
            activityViewController.completionWithItemsHandler = { [weak self] _, completed, _, _ in
                guard completed, self?.clearsAnnotationsAfterSend == true else {
                    return
                }
                self?.clearAnnotations()
            }
            present(activityViewController, animated: true)
        } catch {
            showToast(title: error.localizedDescription)
        }
    }

    func sendToAgent(using client: SamplerAgentClient) {
        guard !annotations.isEmpty else {
            showToast(title: "Add an Annotation First", iconName: "exclamationmark.bubble.fill")
            return
        }

        showToast(title: "Sending to Agent...", iconName: "paperplane.fill")
        let annotationsToSend = annotations
        Task { [weak self] in
            guard let self else {
                return
            }

            do {
                try await client.send(capture: capture, annotations: annotationsToSend)
                await MainActor.run {
                    showToast(title: "Sent to Agent", iconName: "checkmark.circle.fill")
                    if clearsAnnotationsAfterSend {
                        clearAnnotations()
                    }
                }
            } catch {
                await MainActor.run {
                    showToast(title: error.localizedDescription)
                }
            }
        }
    }

    private func configureViews() {
        overrideUserInterfaceStyle = overlayTheme.userInterfaceStyle
        view.backgroundColor = .clear

        imageView.image = capture.screenshot
        imageView.contentMode = .scaleToFill
        imageView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(imageView)

        dimmingView.backgroundColor = UIColor.black.withAlphaComponent(0.08)
        dimmingView.alpha = 0
        dimmingView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(dimmingView)

        markerLayerView.backgroundColor = .clear
        markerLayerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(markerLayerView)

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: view.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            dimmingView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            dimmingView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            dimmingView.topAnchor.constraint(equalTo: view.topAnchor),
            dimmingView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            markerLayerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            markerLayerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            markerLayerView.topAnchor.constraint(equalTo: view.topAnchor),
            markerLayerView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func configureGestures() {
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handleAnnotationPan(_:)))
        panGesture.delegate = self
        view.addGestureRecognizer(panGesture)

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleAnnotationTap(_:)))
        tapGesture.cancelsTouchesInView = false
        tapGesture.delegate = self
        view.addGestureRecognizer(tapGesture)
    }

    @objc private func handleAnnotationPan(_ gesture: UIPanGestureRecognizer) {
        guard draftView == nil || draftView?.state == .drafting else {
            return
        }

        let point = gesture.location(in: view)

        switch gesture.state {
        case .began:
            dragStartPoint = point
            lastHapticTickPoint = nil
            dragHapticGenerator.prepare()
            let draftView = AnnotationDraftView()
            draftView.annotationColor = annotationColor
            draftView.overlayTheme = overlayTheme
            draftView.frame = CGRect(origin: point, size: .zero)
            markerLayerView.addSubview(draftView)
            self.draftView = draftView
        case .changed:
            draftView?.frame = normalizedRect(from: dragStartPoint, to: point)
            emitDragHapticIfNeeded(for: gesture, at: point)
        case .ended, .cancelled, .failed:
            lastHapticTickPoint = nil
            finishDraft()
        default:
            break
        }
    }

    @objc private func handleAnnotationTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else {
            return
        }

        let point = gesture.location(in: markerLayerView)

        if let draftView, draftView.state == .commenting {
            guard !draftView.containsInteractivePoint(point) else {
                return
            }

            dismissDraft(draftView)
            return
        }

        guard draftView == nil else {
            return
        }

        beginTapDraft(at: point)
    }

    private func finishDraft() {
        guard let draftView else {
            return
        }

        let rect = draftView.frame.standardized
        guard rect.width >= 32, rect.height >= 32 else {
            UIView.animate(withDuration: 0.16, animations: {
                draftView.alpha = 0
                draftView.transform = CGAffineTransform(scaleX: 0.78, y: 0.78)
            }, completion: { _ in
                draftView.removeFromSuperview()
            })
            self.draftView = nil
            return
        }

        draftView.onSubmit = { [weak self, weak draftView] comment in
            guard let self, let draftView else {
                return
            }
            commit(draftView: draftView, comment: comment)
        }
        draftView.onCancel = { [weak self, weak draftView] in
            guard let self, let draftView else {
                return
            }
            dismissDraft(draftView)
        }
        draftView.onDelete = { [weak self, weak draftView] in
            guard let self, let draftView else {
                return
            }
            dismissDraft(draftView)
        }
        draftView.onFrameChanged = { [weak self] in
            self?.avoidKeyboardIfNeeded(animated: true)
        }
        draftView.annotationRect = rect
        draftView.annotationColor = annotationColor
        draftView.prefersFullWidthCommentLayout = true
        draftView.keepsCommentAttachedToAnnotation = false
        draftView.showsPointIndicator = true
        draftView.showsSelectionOutline = true
        draftView.beginCommenting()
        avoidKeyboardIfNeeded(animated: true)
    }

    private func beginTapDraft(at point: CGPoint) {
        let annotationRect = centeredTapRect(at: point)
        let draftView = AnnotationDraftView()
        draftView.annotationColor = annotationColor
        draftView.overlayTheme = overlayTheme
        draftView.prefersFullWidthCommentLayout = true
        draftView.showsPointIndicator = true
        draftView.frame = annotationRect
        markerLayerView.addSubview(draftView)
        self.draftView = draftView

        draftView.onSubmit = { [weak self, weak draftView] comment in
            guard let self, let draftView else {
                return
            }
            commit(draftView: draftView, comment: comment)
        }
        draftView.onCancel = { [weak self, weak draftView] in
            guard let self, let draftView else {
                return
            }
            dismissDraft(draftView)
        }
        draftView.onDelete = { [weak self, weak draftView] in
            guard let self, let draftView else {
                return
            }
            dismissDraft(draftView)
        }
        draftView.onFrameChanged = { [weak self] in
            self?.avoidKeyboardIfNeeded(animated: true)
        }
        draftView.annotationRect = annotationRect
        draftView.beginCommenting()
        avoidKeyboardIfNeeded(animated: true)
    }

    private func commit(draftView: AnnotationDraftView, comment: String) {
        let trimmedComment = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedComment.isEmpty else {
            showToast(title: "Add a Comment First")
            return
        }

        applyAnnotationSurfaceOffset(0, animated: true)

        let originalRect = (draftView.annotationRect ?? draftView.frame).standardized
        let matches = capture.accessibilityElements.filter {
            $0.frame.cgRect.intersects(originalRect)
        }

        if let editingAnnotationID = draftView.editingAnnotationID,
           let annotationIndex = annotations.firstIndex(where: { $0.id == editingAnnotationID }),
           let marker = markersByAnnotationID[editingAnnotationID] {
            annotations[annotationIndex].comment = trimmedComment
            annotations[annotationIndex].matchedElements = matches

            draftView.collapseToward(frame: marker.frame) {
                draftView.removeFromSuperview()
                marker.alpha = 1
                marker.transform = .identity
            }

            self.draftView = nil
            return
        }

        let number = annotations.count + 1
        let annotation = Annotation(
            id: UUID(),
            number: number,
            rect: RectSnapshot(originalRect),
            comment: trimmedComment,
            matchedElements: matches,
            borderColorHex: annotationColor.hexString
        )
        annotations.append(annotation)

        let marker = AnnotationMarkerView(number: number)
        marker.annotationID = annotation.id
        marker.markerColor = annotationColor
        marker.addTarget(self, action: #selector(annotationMarkerTapped(_:)), for: .touchUpInside)
        let markerSize: CGFloat = 30
        let markerFrame = centeredMarkerRect(in: originalRect, markerSize: markerSize)
        marker.frame = markerFrame
        marker.alpha = 0
        marker.transform = CGAffineTransform(scaleX: 0.74, y: 0.74)
        markerLayerView.addSubview(marker)
        markersByAnnotationID[annotation.id] = marker

        draftView.collapseToward(frame: markerFrame) {
            draftView.removeFromSuperview()
            marker.alpha = 1
            marker.transform = .identity
        }

        self.draftView = nil
    }

    @objc private func annotationMarkerTapped(_ marker: AnnotationMarkerView) {
        guard
            draftView == nil,
            let annotationID = marker.annotationID,
            let annotationIndex = annotations.firstIndex(where: { $0.id == annotationID })
        else {
            return
        }

        let annotation = annotations[annotationIndex]
        let originalRect = annotation.rect.cgRect
        let isTapAnnotation = isTapAnnotationRect(originalRect)
        let draftView = AnnotationDraftView()
        draftView.frame = originalRect
        draftView.annotationRect = originalRect
        draftView.annotationColor = UIColor(hexString: annotation.borderColorHex) ?? annotationColor
        draftView.overlayTheme = overlayTheme
        draftView.prefersFullWidthCommentLayout = true
        draftView.keepsCommentAttachedToAnnotation = isTapAnnotation
        draftView.showsPointIndicator = true
        draftView.showsSelectionOutline = !isTapAnnotation
        draftView.editingAnnotationID = annotation.id
        draftView.onSubmit = { [weak self, weak draftView] comment in
            guard let self, let draftView else {
                return
            }
            commit(draftView: draftView, comment: comment)
        }
        draftView.onCancel = { [weak self, weak draftView] in
            guard let self, let draftView else {
                return
            }
            dismissDraft(draftView)
        }
        draftView.onDelete = { [weak self, weak draftView] in
            guard let self, let draftView else {
                return
            }
            deleteAnnotation(from: draftView)
        }
        draftView.onFrameChanged = { [weak self] in
            self?.avoidKeyboardIfNeeded(animated: true)
        }

        markerLayerView.addSubview(draftView)
        self.draftView = draftView
        draftView.beginCommenting(initialComment: annotation.comment, submitTitle: "Save")
        avoidKeyboardIfNeeded(animated: true)
    }

    private func deleteAnnotation(from draftView: AnnotationDraftView) {
        guard let annotationID = draftView.editingAnnotationID else {
            dismissDraft(draftView)
            return
        }

        draftView.dismissKeyboard()
        applyAnnotationSurfaceOffset(0, animated: true)

        if let index = annotations.firstIndex(where: { $0.id == annotationID }) {
            annotations.remove(at: index)
        }

        let marker = markersByAnnotationID.removeValue(forKey: annotationID)

        UIView.animate(
            withDuration: 0.18,
            delay: 0,
            options: [.curveEaseInOut]
        ) {
            draftView.alpha = 0
            draftView.transform = CGAffineTransform(scaleX: 0.88, y: 0.88)
            marker?.alpha = 0
            marker?.transform = CGAffineTransform(scaleX: 0.6, y: 0.6)
        } completion: { _ in
            draftView.removeFromSuperview()
            marker?.removeFromSuperview()
        }

        self.draftView = nil
    }

    func clearAnnotations() {
        applyAnnotationSurfaceOffset(0, animated: true)
        draftView?.removeFromSuperview()
        draftView = nil
        annotations.removeAll()
        markersByAnnotationID.values.forEach { $0.removeFromSuperview() }
        markersByAnnotationID.removeAll()
    }

    private func dismissDraft(_ draftView: AnnotationDraftView) {
        draftView.dismissKeyboard()
        applyAnnotationSurfaceOffset(0, animated: true)

        draftView.collapseForDismissal {
            draftView.removeFromSuperview()
        }

        self.draftView = nil
    }

    private func normalizedRect(from start: CGPoint, to end: CGPoint) -> CGRect {
        let x = min(start.x, end.x)
        let y = min(start.y, end.y)
        let width = abs(end.x - start.x)
        let height = abs(end.y - start.y)
        return CGRect(x: x, y: y, width: width, height: height).intersection(view.bounds)
    }

    private func emitDragHapticIfNeeded(for gesture: UIPanGestureRecognizer, at point: CGPoint) {
        let velocity = gesture.velocity(in: view)
        let speed = hypot(velocity.x, velocity.y)
        let tickDistance = max(6, min(30, 900 / max(speed, 60)))

        if let lastHapticTickPoint {
            let traveled = hypot(point.x - lastHapticTickPoint.x, point.y - lastHapticTickPoint.y)
            guard traveled >= tickDistance else {
                return
            }
        }

        dragHapticGenerator.selectionChanged()
        dragHapticGenerator.prepare()
        lastHapticTickPoint = point
    }

    private func configureKeyboardAvoidance() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillChangeFrame(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillHide(_:)),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
    }

    @objc private func keyboardWillChangeFrame(_ notification: Notification) {
        guard
            let endFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
        else {
            return
        }

        let convertedFrame = view.convert(endFrame, from: nil)
        keyboardFrameInView = convertedFrame.intersects(view.bounds) ? convertedFrame : nil
        avoidKeyboardIfNeeded(animated: true, notification: notification)
    }

    @objc private func keyboardWillHide(_ notification: Notification) {
        keyboardFrameInView = nil
        applyAnnotationSurfaceOffset(0, animated: true, notification: notification)
    }

    private func avoidKeyboardIfNeeded(animated: Bool, notification: Notification? = nil) {
        guard
            let draftView,
            draftView.state == .commenting,
            let keyboardFrameInView
        else {
            return
        }

        if draftView.prefersFullWidthCommentLayout {
            if draftView.keepsCommentAttachedToAnnotation {
                avoidKeyboardForAnchoredDraft(draftView, animated: animated, notification: notification)
            } else {
                avoidKeyboardForDetachedDraft(draftView, animated: animated, notification: notification)
            }
            return
        }

        let bottomPadding: CGFloat = 28
        let topLimit = view.safeAreaInsets.top + 18
        let visibleBottom = keyboardFrameInView.minY - bottomPadding
        var targetFrame = draftView.frame

        if targetFrame.maxY > visibleBottom {
            targetFrame.origin.y -= targetFrame.maxY - visibleBottom
        }

        if targetFrame.minY < topLimit {
            targetFrame.origin.y = topLimit
        }

        guard targetFrame != draftView.frame else {
            return
        }

        let changes = {
            draftView.frame = targetFrame
        }

        guard animated else {
            changes()
            return
        }

        let duration = notification?.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval ?? 0.24
        let curveRawValue = notification?.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt ?? UInt(UIView.AnimationCurve.easeInOut.rawValue)
        let options = UIView.AnimationOptions(rawValue: curveRawValue << 16)

        UIView.animate(
            withDuration: duration,
            delay: 0,
            options: [options, .beginFromCurrentState, .allowUserInteraction],
            animations: changes
        )
    }

    private func avoidKeyboardForAnchoredDraft(
        _ draftView: AnnotationDraftView,
        animated: Bool,
        notification: Notification?
    ) {
        guard let keyboardFrameInView else {
            return
        }

        let bottomPadding: CGFloat = 28
        let topPadding: CGFloat = view.safeAreaInsets.top + 18
        let visibleBottom = keyboardFrameInView.minY - bottomPadding
        let requiredOffset = max(0, draftView.frame.maxY - visibleBottom)
        let pointTop = draftView.annotationRect?.minY ?? draftView.frame.minY
        let maxOffsetBeforePOIHitsTop = max(0, pointTop - topPadding)
        let targetOffset = min(requiredOffset, maxOffsetBeforePOIHitsTop)

        applyAnnotationSurfaceOffset(targetOffset, animated: animated, notification: notification)
    }

    private func avoidKeyboardForDetachedDraft(
        _ draftView: AnnotationDraftView,
        animated: Bool,
        notification: Notification?
    ) {
        guard let keyboardFrameInView else {
            return
        }

        let bottomPadding: CGFloat = 28
        let topLimit = view.safeAreaInsets.top + 18
        let visibleBottom = keyboardFrameInView.minY - bottomPadding
        var targetFrame = draftView.frame

        if targetFrame.maxY > visibleBottom {
            targetFrame.origin.y -= targetFrame.maxY - visibleBottom
        }

        if targetFrame.minY < topLimit {
            targetFrame.origin.y = topLimit
        }

        guard targetFrame != draftView.frame else {
            return
        }

        let changes = {
            draftView.frame = targetFrame
            draftView.layoutIfNeeded()
            draftView.bringCommentEditorToFront()
        }

        guard animated else {
            changes()
            return
        }

        let duration = notification?.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval ?? 0.24
        let curveRawValue = notification?.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt ?? UInt(UIView.AnimationCurve.easeInOut.rawValue)
        let options = UIView.AnimationOptions(rawValue: curveRawValue << 16)

        UIView.animate(
            withDuration: duration,
            delay: 0,
            options: [options, .beginFromCurrentState, .allowUserInteraction],
            animations: changes
        )
    }

    private func applyAnnotationSurfaceOffset(
        _ offset: CGFloat,
        animated: Bool,
        notification: Notification? = nil
    ) {
        let sanitizedOffset = max(0, offset)
        guard abs(currentAnnotationSurfaceOffset - sanitizedOffset) > 0.5 else {
            return
        }

        currentAnnotationSurfaceOffset = sanitizedOffset

        let changes = {
            let transform = CGAffineTransform(translationX: 0, y: -sanitizedOffset)
            self.imageView.transform = transform
            self.dimmingView.transform = transform
            self.draftView?.applyAnnotationSurfaceTransform(transform)
            self.markersByAnnotationID.values.forEach { $0.transform = transform }
        }

        guard animated else {
            changes()
            return
        }

        let duration = notification?.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval ?? 0.28
        let curveRawValue = notification?.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt ?? UInt(UIView.AnimationCurve.easeInOut.rawValue)
        let curveOptions = UIView.AnimationOptions(rawValue: curveRawValue << 16)

        UIView.animate(
            withDuration: duration,
            delay: 0,
            usingSpringWithDamping: notification == nil ? 0.88 : 1,
            initialSpringVelocity: 0.15,
            options: [curveOptions, .beginFromCurrentState, .allowUserInteraction],
            animations: changes
        )
    }

    private func centeredMarkerRect(in rect: CGRect, markerSize: CGFloat) -> CGRect {
        let origin = CGPoint(
            x: min(max(rect.midX - markerSize / 2, view.bounds.minX + 8), view.bounds.maxX - markerSize - 8),
            y: min(max(rect.midY - markerSize / 2, view.bounds.minY + 8), view.bounds.maxY - markerSize - 8)
        )

        return CGRect(origin: origin, size: CGSize(width: markerSize, height: markerSize))
    }

    private func centeredTapRect(at point: CGPoint) -> CGRect {
        let size = Constants.tapAnnotationSize
        let origin = CGPoint(
            x: point.x - size.width / 2,
            y: point.y - size.height / 2
        )
        return CGRect(origin: origin, size: size).intersection(view.bounds)
    }

    private func isTapAnnotationRect(_ rect: CGRect) -> Bool {
        abs(rect.width - Constants.tapAnnotationSize.width) < 1
            && abs(rect.height - Constants.tapAnnotationSize.height) < 1
    }

    private func showToast(title: String, iconName: String? = nil) {
        let toastView = ToastView(title: title, iconName: iconName, overlayTheme: overlayTheme)
        toastView.alpha = 0
        toastView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(toastView)

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
}

final class ToastView: UIView {
    init(title: String, iconName: String?, overlayTheme: OverlayTheme) {
        super.init(frame: .zero)
        configure(title: title, iconName: iconName, overlayTheme: overlayTheme)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configure(title: String, iconName: String?, overlayTheme: OverlayTheme) {
        overrideUserInterfaceStyle = overlayTheme.userInterfaceStyle
        backgroundColor = overlayTheme.toastBackground
        layer.cornerRadius = 21
        layer.masksToBounds = true

        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = 8
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)

        if let iconName {
            let imageView = UIImageView(
                image: UIImage(
                    systemName: iconName,
                    withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
                )
            )
            imageView.tintColor = overlayTheme.primaryText
            imageView.contentMode = .scaleAspectFit
            imageView.translatesAutoresizingMaskIntoConstraints = false
            stackView.addArrangedSubview(imageView)
            NSLayoutConstraint.activate([
                imageView.widthAnchor.constraint(equalToConstant: 16),
                imageView.heightAnchor.constraint(equalToConstant: 16)
            ])
        }

        let label = UILabel()
        label.text = title
        label.textColor = overlayTheme.primaryText
        label.font = .systemFont(ofSize: 14, weight: .semibold)
        label.textAlignment = .center
        stackView.addArrangedSubview(label)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            stackView.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10)
        ])
    }
}

extension AnnotationViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if gestureRecognizer is UITapGestureRecognizer,
           (touch.view is AnnotationMarkerView || touch.view?.superview is AnnotationMarkerView) {
            return false
        }

        guard let draftView, draftView.state == .commenting else {
            return true
        }

        let point = touch.location(in: markerLayerView)

        if gestureRecognizer is UITapGestureRecognizer {
            return !draftView.containsInteractivePoint(point)
        }

        if gestureRecognizer is UIPanGestureRecognizer {
            return false
        }

        return !draftView.containsInteractivePoint(point)
    }
}

final class AnnotationDraftView: UIView {
    private enum Constants {
        static let fullWidthCommentMinHeight: CGFloat = 224
        static let fullWidthCommentVerticalGap: CGFloat = 10
        static let pointIndicatorSize: CGFloat = 34
        static let outerMargin: CGFloat = 18
        static let contentPadding: CGFloat = 14
    }

    enum State {
        case drafting
        case commenting
    }

    private let textView = UITextView()
    private let doneButton = UIButton(type: .system)
    private let cancelButton = UIButton(type: .system)
    private let deleteButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let pointIndicatorView = UIView()
    private let pointIndicatorImageView = UIImageView()
    private let selectionOutlineView = UIView()
    private let selectionOutlineLayer = CAShapeLayer()
    private let dashedBorderLayer = CAShapeLayer()
    private let feedbackGenerator = UIImpactFeedbackGenerator(style: .light)
    private var minimumCommentHeight: CGFloat = 112

    private(set) var state: State = .drafting
    var annotationColor: UIColor = .systemBlue {
        didSet {
            backgroundColor = state == .drafting
                ? annotationColor.withAlphaComponent(0.14)
                : overlayTheme.annotationCardBackground
            layer.borderColor = annotationColor.cgColor
            pointIndicatorView.backgroundColor = annotationColor
            pointIndicatorImageView.tintColor = annotationColor.annotationForegroundColor
            doneButton.backgroundColor = annotationColor
            doneButton.tintColor = annotationColor.annotationForegroundColor
            selectionOutlineLayer.strokeColor = annotationColor.cgColor
            selectionOutlineLayer.fillColor = annotationColor.withAlphaComponent(0.14).cgColor
            applyBorderStyle(for: state)
        }
    }
    var overlayTheme: OverlayTheme = .light {
        didSet {
            applyTheme()
        }
    }
    var annotationRect: CGRect?
    var editingAnnotationID: UUID?
    var onSubmit: ((String) -> Void)?
    var onCancel: (() -> Void)?
    var onDelete: (() -> Void)?
    var onFrameChanged: (() -> Void)?
    var prefersFullWidthCommentLayout = false
    var keepsCommentAttachedToAnnotation = true
    var showsPointIndicator = false {
        didSet {
            updatePointIndicatorFrame()
        }
    }
    var showsSelectionOutline = false {
        didSet {
            updateSelectionOutlineFrame()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateDashedBorder()
        updatePointIndicatorFrame()
        updateSelectionOutlineFrame()
    }

    override func removeFromSuperview() {
        selectionOutlineView.removeFromSuperview()
        pointIndicatorView.removeFromSuperview()
        super.removeFromSuperview()
    }

    func containsInteractivePoint(_ point: CGPoint) -> Bool {
        frame.contains(point)
            || pointIndicatorFrameInSuperview.contains(point)
            || selectionOutlineFrameInSuperview.contains(point)
    }

    func beginCommenting(initialComment: String = "", submitTitle: String = "Add") {
        state = .commenting
        textView.text = initialComment
        doneButton.setTitle(submitTitle, for: .normal)
        titleLabel.alpha = 0
        textView.alpha = 0
        doneButton.alpha = 0
        cancelButton.alpha = 0
        deleteButton.alpha = 0
        titleLabel.isHidden = false
        textView.isHidden = false
        textView.isScrollEnabled = true
        doneButton.isHidden = false
        cancelButton.isHidden = false
        deleteButton.isHidden = editingAnnotationID == nil
        triggerHaptic()

        let availableBounds = superview?.bounds.insetBy(
            dx: Constants.outerMargin,
            dy: Constants.outerMargin
        ) ?? UIScreen.main.bounds.insetBy(dx: Constants.outerMargin, dy: Constants.outerMargin)
        let sourceRect = (annotationRect ?? frame).standardized
        let targetHeight = prefersFullWidthCommentLayout
            ? min(Constants.fullWidthCommentMinHeight, availableBounds.height)
            : min(max(sourceRect.height, 96), availableBounds.height)
        minimumCommentHeight = targetHeight
        let targetWidth = prefersFullWidthCommentLayout
            ? availableBounds.width
            : min(max(sourceRect.width, 220), availableBounds.width)

        var proposedFrame = CGRect(
            x: prefersFullWidthCommentLayout ? availableBounds.minX : sourceRect.origin.x,
            y: prefersFullWidthCommentLayout
                ? proposedFullWidthCommentY(
                    below: sourceRect,
                    height: targetHeight,
                    in: availableBounds
                )
                : sourceRect.origin.y,
            width: targetWidth,
            height: targetHeight
        )

        if targetWidth > sourceRect.width, !prefersFullWidthCommentLayout {
            proposedFrame.origin.x = sourceRect.midX - targetWidth / 2
        }

        let expandedFrame = prefersFullWidthCommentLayout
            ? horizontallyConstrained(proposedFrame, in: availableBounds)
            : clampedToVisibleBounds(proposedFrame)

        prepareExternalIndicatorsForPresentation()

        UIView.animate(
            withDuration: 0.24,
            delay: 0,
            usingSpringWithDamping: 0.9,
            initialSpringVelocity: 0.15,
            options: [.allowUserInteraction]
        ) {
            self.frame = expandedFrame
            self.layer.cornerRadius = 18
            self.backgroundColor = self.overlayTheme.annotationCardBackground
            self.applyBorderStyle(for: .commenting)
            self.applyTheme()
            self.pointIndicatorView.alpha = self.showsPointIndicator ? 1 : 0
            self.selectionOutlineView.alpha = self.showsSelectionOutline ? 1 : 0
            self.titleLabel.alpha = 1
            self.textView.alpha = 1
            self.doneButton.alpha = 1
            self.cancelButton.alpha = 1
            self.deleteButton.alpha = self.editingAnnotationID == nil ? 0 : 1
            self.layoutIfNeeded()
            self.bringCommentEditorToFront()
            self.updateHeightForText(animated: false)
        } completion: { _ in
            self.focusTextView()
        }
    }

    func collapseToward(frame targetFrame: CGRect, completion: @escaping () -> Void) {
        textView.resignFirstResponder()
        layoutIfNeeded()

        let footerSnapshot = snapshotView(afterScreenUpdates: false)
        if let footerSnapshot {
            footerSnapshot.frame = frame
            superview?.addSubview(footerSnapshot)
        }

        textView.alpha = 0
        titleLabel.alpha = 0
        doneButton.alpha = 0
        cancelButton.alpha = 0
        deleteButton.alpha = 0
        pointIndicatorView.alpha = 0
        selectionOutlineView.alpha = 0

        UIView.animate(
            withDuration: 0.1,
            delay: 0,
            options: [.beginFromCurrentState, .curveEaseOut]
        ) {
            footerSnapshot?.alpha = 0
        } completion: { _ in
            footerSnapshot?.removeFromSuperview()
        }

        UIView.animate(
            withDuration: 0.24,
            delay: 0,
            usingSpringWithDamping: 0.84,
            initialSpringVelocity: 0.3,
            options: [.curveEaseInOut]
        ) {
            self.frame = targetFrame
            self.layer.cornerRadius = targetFrame.height / 2
            self.layer.borderWidth = 0
            self.backgroundColor = self.annotationColor
            self.dashedBorderLayer.isHidden = true
        } completion: { _ in
            completion()
        }
    }

    func collapseForDismissal(completion: @escaping () -> Void) {
        textView.resignFirstResponder()
        layoutIfNeeded()

        let targetFrame = (annotationRect ?? frame).standardized
        let pointIndicatorSnapshot = dismissalSnapshot(for: pointIndicatorView)
        let selectionOutlineSnapshot = dismissalSnapshot(for: selectionOutlineView)
        pointIndicatorView.alpha = 0
        selectionOutlineView.alpha = 0

        UIView.animate(
            withDuration: 0.2,
            delay: 0,
            options: [.beginFromCurrentState, .curveEaseInOut]
        ) {
            self.frame = targetFrame
            self.alpha = 0
            self.transform = CGAffineTransform(scaleX: 0.86, y: 0.86)
            self.layer.cornerRadius = min(18, max(10, targetFrame.height / 2))
            self.textView.alpha = 0
            self.titleLabel.alpha = 0
            self.doneButton.alpha = 0
            self.cancelButton.alpha = 0
            self.deleteButton.alpha = 0
            pointIndicatorSnapshot?.alpha = 0
            pointIndicatorSnapshot?.transform = CGAffineTransform(scaleX: 0.58, y: 0.58)
            selectionOutlineSnapshot?.alpha = 0
            selectionOutlineSnapshot?.transform = CGAffineTransform(scaleX: 0.72, y: 0.72)
            self.layoutIfNeeded()
        } completion: { _ in
            pointIndicatorSnapshot?.removeFromSuperview()
            selectionOutlineSnapshot?.removeFromSuperview()
            completion()
        }
    }

    func dismissKeyboard() {
        textView.resignFirstResponder()
    }

    private func dismissalSnapshot(for view: UIView) -> UIView? {
        guard
            view.alpha > 0.01,
            let container = view.superview,
            let snapshot = view.snapshotView(afterScreenUpdates: false)
        else {
            return nil
        }

        snapshot.frame = view.convert(view.bounds, to: container)
        container.addSubview(snapshot)
        return snapshot
    }

    private func focusTextView(attempt: Int = 0) {
        guard attempt < 5 else {
            return
        }

        DispatchQueue.main.async {
            self.superview?.window?.makeKey()
            self.layoutIfNeeded()

            if self.textView.becomeFirstResponder() {
                return
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                self.focusTextView(attempt: attempt + 1)
            }
        }
    }

    private func configure() {
        backgroundColor = annotationColor.withAlphaComponent(0.14)
        layer.cornerRadius = 12
        layer.masksToBounds = false
        layer.borderColor = annotationColor.cgColor
        layer.borderWidth = 0

        dashedBorderLayer.strokeColor = annotationColor.cgColor
        dashedBorderLayer.fillColor = UIColor.clear.cgColor
        dashedBorderLayer.lineWidth = 2
        dashedBorderLayer.lineJoin = .round
        dashedBorderLayer.lineDashPattern = [7, 5]
        dashedBorderLayer.zPosition = 10
        layer.addSublayer(dashedBorderLayer)

        pointIndicatorView.alpha = 0
        pointIndicatorView.backgroundColor = annotationColor
        pointIndicatorView.layer.cornerRadius = Constants.pointIndicatorSize / 2
        pointIndicatorView.layer.shadowColor = UIColor.black.cgColor
        pointIndicatorView.layer.shadowOpacity = 0.22
        pointIndicatorView.layer.shadowRadius = 8
        pointIndicatorView.layer.shadowOffset = CGSize(width: 0, height: 3)
        pointIndicatorView.translatesAutoresizingMaskIntoConstraints = true

        pointIndicatorImageView.image = UIImage(
            systemName: "plus",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .bold)
        )
        pointIndicatorImageView.contentMode = .scaleAspectFit
        pointIndicatorImageView.translatesAutoresizingMaskIntoConstraints = false
        pointIndicatorView.addSubview(pointIndicatorImageView)

        selectionOutlineView.alpha = 0
        selectionOutlineView.isUserInteractionEnabled = false
        selectionOutlineView.backgroundColor = .clear
        selectionOutlineView.translatesAutoresizingMaskIntoConstraints = true
        selectionOutlineLayer.strokeColor = annotationColor.cgColor
        selectionOutlineLayer.fillColor = annotationColor.withAlphaComponent(0.14).cgColor
        selectionOutlineLayer.lineWidth = 2
        selectionOutlineLayer.lineJoin = .round
        selectionOutlineLayer.lineDashPattern = [7, 5]
        selectionOutlineView.layer.addSublayer(selectionOutlineLayer)

        textView.font = .preferredFont(forTextStyle: .body)
        textView.textContainerInset = UIEdgeInsets(top: 9, left: 9, bottom: 9, right: 9)
        textView.layer.cornerRadius = 10
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.isHidden = true
        textView.isScrollEnabled = true
        textView.alwaysBounceVertical = false
        textView.delegate = self
        addSubview(textView)

        titleLabel.text = "What should change?"
        titleLabel.font = .preferredFont(forTextStyle: .subheadline)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.isHidden = true
        addSubview(titleLabel)

        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.isHidden = true
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        addSubview(cancelButton)

        deleteButton.setImage(UIImage(systemName: "trash", withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)), for: .normal)
        deleteButton.translatesAutoresizingMaskIntoConstraints = false
        deleteButton.isHidden = true
        deleteButton.addTarget(self, action: #selector(deleteTapped), for: .touchUpInside)
        addSubview(deleteButton)

        doneButton.setTitle("Add", for: .normal)
        doneButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        doneButton.layer.cornerRadius = 20
        doneButton.translatesAutoresizingMaskIntoConstraints = false
        doneButton.isHidden = true
        doneButton.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)
        addSubview(doneButton)

        NSLayoutConstraint.activate([
            pointIndicatorImageView.centerXAnchor.constraint(equalTo: pointIndicatorView.centerXAnchor),
            pointIndicatorImageView.centerYAnchor.constraint(equalTo: pointIndicatorView.centerYAnchor),
            pointIndicatorImageView.widthAnchor.constraint(equalToConstant: 15),
            pointIndicatorImageView.heightAnchor.constraint(equalToConstant: 15),

            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Constants.contentPadding),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -Constants.contentPadding),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: Constants.contentPadding),

            textView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Constants.contentPadding),
            textView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Constants.contentPadding),
            textView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),
            textView.bottomAnchor.constraint(equalTo: doneButton.topAnchor, constant: -14),

            deleteButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Constants.contentPadding),
            deleteButton.centerYAnchor.constraint(equalTo: doneButton.centerYAnchor),
            deleteButton.widthAnchor.constraint(equalToConstant: 44),
            deleteButton.heightAnchor.constraint(equalToConstant: 40),

            cancelButton.trailingAnchor.constraint(equalTo: doneButton.leadingAnchor, constant: -14),
            cancelButton.centerYAnchor.constraint(equalTo: doneButton.centerYAnchor),
            cancelButton.heightAnchor.constraint(equalToConstant: 40),

            doneButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Constants.contentPadding),
            doneButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Constants.contentPadding),
            doneButton.widthAnchor.constraint(equalToConstant: 68),
            doneButton.heightAnchor.constraint(equalToConstant: 40)
        ])

        feedbackGenerator.prepare()
        applyTheme()
    }

    private func updateDashedBorder() {
        guard bounds.width > 2, bounds.height > 2 else {
            dashedBorderLayer.path = nil
            return
        }

        let inset = dashedBorderLayer.lineWidth + 1
        let borderRect = bounds.insetBy(dx: inset, dy: inset)
        guard borderRect.width > 0, borderRect.height > 0 else {
            dashedBorderLayer.path = nil
            return
        }

        dashedBorderLayer.frame = bounds
        dashedBorderLayer.path = UIBezierPath(
            roundedRect: borderRect,
            cornerRadius: max(0, layer.cornerRadius - inset)
        ).cgPath
        applyBorderStyle(for: state)
    }

    private func applyBorderStyle(for state: State) {
        switch state {
        case .drafting:
            layer.borderWidth = 0
            dashedBorderLayer.isHidden = false
            dashedBorderLayer.strokeColor = annotationColor.cgColor
            dashedBorderLayer.lineWidth = 2
            dashedBorderLayer.lineCap = .round
            dashedBorderLayer.lineJoin = .round
            dashedBorderLayer.lineDashPattern = [7, 5]
        case .commenting:
            dashedBorderLayer.isHidden = true
            layer.borderColor = annotationColor.cgColor
            layer.borderWidth = 2
        }
    }

    private func applyTheme() {
        overrideUserInterfaceStyle = overlayTheme.userInterfaceStyle
        guard state == .commenting else {
            textView.backgroundColor = overlayTheme.annotationTextBoxBackground
            textView.textColor = overlayTheme.primaryText
            titleLabel.textColor = overlayTheme.secondaryText
            cancelButton.tintColor = overlayTheme.secondaryText
            deleteButton.tintColor = overlayTheme.secondaryText
        doneButton.backgroundColor = annotationColor
        doneButton.tintColor = annotationColor.annotationForegroundColor
            return
        }

        backgroundColor = overlayTheme.annotationCardBackground
        textView.backgroundColor = overlayTheme.annotationTextBoxBackground
        textView.textColor = overlayTheme.primaryText
        titleLabel.textColor = overlayTheme.secondaryText
        cancelButton.tintColor = overlayTheme.secondaryText
        deleteButton.tintColor = overlayTheme.secondaryText
        doneButton.backgroundColor = annotationColor
        doneButton.tintColor = annotationColor.annotationForegroundColor
    }

    private var pointIndicatorFrameInSuperview: CGRect {
        guard showsPointIndicator, let annotationRect else {
            return .null
        }

        return CGRect(
            x: annotationRect.midX - Constants.pointIndicatorSize / 2,
            y: annotationRect.midY - Constants.pointIndicatorSize / 2,
            width: Constants.pointIndicatorSize,
            height: Constants.pointIndicatorSize
        )
    }

    private func updatePointIndicatorFrame() {
        guard showsPointIndicator else {
            pointIndicatorView.frame = .zero
            pointIndicatorView.removeFromSuperview()
            return
        }

        guard let superview else {
            return
        }

        if pointIndicatorView.superview !== superview {
            superview.insertSubview(pointIndicatorView, belowSubview: self)
        }

        pointIndicatorView.frame = pointIndicatorFrameInSuperview
    }

    private var selectionOutlineFrameInSuperview: CGRect {
        guard showsSelectionOutline, let annotationRect else {
            return .null
        }

        return annotationRect.standardized
    }

    private func updateSelectionOutlineFrame() {
        guard showsSelectionOutline else {
            selectionOutlineView.frame = .zero
            selectionOutlineLayer.path = nil
            selectionOutlineView.removeFromSuperview()
            return
        }

        guard let superview else {
            return
        }

        if selectionOutlineView.superview !== superview {
            superview.insertSubview(selectionOutlineView, belowSubview: self)
        }

        selectionOutlineView.frame = selectionOutlineFrameInSuperview
        selectionOutlineLayer.frame = selectionOutlineView.bounds
        let inset = selectionOutlineLayer.lineWidth + 1
        let outlineRect = selectionOutlineView.bounds.insetBy(dx: inset, dy: inset)
        selectionOutlineLayer.path = UIBezierPath(
            roundedRect: outlineRect,
            cornerRadius: 12
        ).cgPath
    }

    private func prepareExternalIndicatorsForPresentation() {
        UIView.performWithoutAnimation {
            updatePointIndicatorFrame()
            updateSelectionOutlineFrame()
            pointIndicatorView.layoutIfNeeded()
            selectionOutlineView.layoutIfNeeded()
        }
    }

    func bringCommentEditorToFront() {
        bringSubviewToFront(titleLabel)
        bringSubviewToFront(textView)
        bringSubviewToFront(deleteButton)
        bringSubviewToFront(cancelButton)
        bringSubviewToFront(doneButton)
    }

    func applyAnnotationSurfaceTransform(_ transform: CGAffineTransform) {
        self.transform = transform
        pointIndicatorView.transform = transform
        selectionOutlineView.transform = transform
    }

    @objc private func doneTapped() {
        triggerHaptic()
        onSubmit?(textView.text)
    }

    @objc private func cancelTapped() {
        triggerHaptic()
        onCancel?()
    }

    @objc private func deleteTapped() {
        triggerHaptic()
        onDelete?()
    }

    private func triggerHaptic() {
        feedbackGenerator.impactOccurred()
        feedbackGenerator.prepare()
    }

    private func updateHeightForText(animated: Bool) {
        guard state == .commenting else {
            return
        }

        let fixedChromeHeight: CGFloat = 58
        let maximumHeight = max(minimumCommentHeight, min((superview?.bounds.height ?? 640) * 0.42, 300))
        let fittingWidth = max(bounds.width - 20, 1)
        let contentHeight = textView.sizeThatFits(
            CGSize(width: fittingWidth, height: .greatestFiniteMagnitude)
        ).height + fixedChromeHeight
        let targetHeight = min(max(minimumCommentHeight, contentHeight), maximumHeight)

        guard abs(frame.height - targetHeight) > 1 else {
            scrollCaretToVisible()
            return
        }

        let changes = {
            var nextFrame = self.frame
            nextFrame.size.height = targetHeight
            self.frame = self.clampedToVisibleBounds(nextFrame)
            self.layoutIfNeeded()
        }

        if animated {
            UIView.animate(
                withDuration: 0.18,
                delay: 0,
                options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseInOut],
                animations: changes
            ) { _ in
                self.scrollCaretToVisible()
                self.onFrameChanged?()
            }
        } else {
            changes()
            scrollCaretToVisible()
            onFrameChanged?()
        }
    }

    private func scrollCaretToVisible() {
        guard state == .commenting else {
            return
        }

        DispatchQueue.main.async {
            let selectedRange = self.textView.selectedRange
            guard selectedRange.location != NSNotFound else {
                return
            }

            self.textView.layoutIfNeeded()
            self.textView.layoutManager.ensureLayout(for: self.textView.textContainer)

            if let selectedTextRange = self.textView.selectedTextRange {
                let caretRect = self.textView.caretRect(for: selectedTextRange.end)
                guard
                    caretRect.origin.x.isFinite,
                    caretRect.origin.y.isFinite,
                    caretRect.width.isFinite,
                    caretRect.height.isFinite,
                    caretRect != .zero
                else {
                    self.textView.scrollRangeToVisible(selectedRange)
                    return
                }

                let bottomPadding: CGFloat = 16
                let topPadding: CGFloat = 8
                let visibleMinY = self.textView.contentOffset.y + self.textView.adjustedContentInset.top
                let visibleMaxY = self.textView.contentOffset.y + self.textView.bounds.height - self.textView.adjustedContentInset.bottom

                var targetOffsetY = self.textView.contentOffset.y
                if caretRect.maxY + bottomPadding > visibleMaxY {
                    targetOffsetY += caretRect.maxY + bottomPadding - visibleMaxY
                } else if caretRect.minY - topPadding < visibleMinY {
                    targetOffsetY -= visibleMinY - (caretRect.minY - topPadding)
                }

                let minOffsetY = -self.textView.adjustedContentInset.top
                let maxOffsetY = max(
                    minOffsetY,
                    self.textView.contentSize.height - self.textView.bounds.height + self.textView.adjustedContentInset.bottom
                )
                targetOffsetY = min(max(targetOffsetY, minOffsetY), maxOffsetY)

                self.textView.setContentOffset(CGPoint(x: self.textView.contentOffset.x, y: targetOffsetY), animated: false)
            }
        }
    }

    private func clampedToVisibleBounds(_ proposedFrame: CGRect) -> CGRect {
        guard
            proposedFrame.width.isFinite,
            proposedFrame.height.isFinite,
            proposedFrame.origin.x.isFinite,
            proposedFrame.origin.y.isFinite,
            proposedFrame.width > 0,
            proposedFrame.height > 0
        else {
            return frame
        }

        guard let bounds = superview?.bounds.insetBy(dx: Constants.outerMargin, dy: Constants.outerMargin) else {
            return proposedFrame
        }

        var frame = proposedFrame
        frame.size.width = min(frame.width, bounds.width)
        frame.size.height = min(frame.height, bounds.height)

        if frame.maxX > bounds.maxX {
            frame.origin.x = bounds.maxX - frame.width
        }
        if frame.minX < bounds.minX {
            frame.origin.x = bounds.minX
        }
        if frame.maxY > bounds.maxY {
            frame.origin.y = bounds.maxY - frame.height
        }
        if frame.minY < bounds.minY {
            frame.origin.y = bounds.minY
        }

        return frame
    }

    private func proposedFullWidthCommentY(
        below sourceRect: CGRect,
        height targetHeight: CGFloat,
        in availableBounds: CGRect
    ) -> CGFloat {
        let attachedY = sourceRect.maxY + Constants.fullWidthCommentVerticalGap
        guard !keepsCommentAttachedToAnnotation else {
            return attachedY
        }

        return min(attachedY, availableBounds.maxY - targetHeight)
    }

    private func horizontallyConstrained(_ proposedFrame: CGRect, in bounds: CGRect) -> CGRect {
        var frame = proposedFrame
        frame.size.width = min(frame.width, bounds.width)

        if frame.maxX > bounds.maxX {
            frame.origin.x = bounds.maxX - frame.width
        }
        if frame.minX < bounds.minX {
            frame.origin.x = bounds.minX
        }

        return frame
    }
}

extension AnnotationDraftView: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        updateHeightForText(animated: false)
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
        scrollCaretToVisible()
    }
}

final class AnnotationMarkerView: UIControl {
    var annotationID: UUID?
    var markerColor: UIColor = .black {
        didSet {
            backgroundColor = markerColor
            label.textColor = markerColor.annotationForegroundColor
        }
    }
    private let label = UILabel()

    init(number: Int) {
        super.init(frame: .zero)
        configure(number: number)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configure(number: Int) {
        backgroundColor = markerColor
        layer.cornerRadius = 15
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.2
        layer.shadowRadius = 8
        layer.shadowOffset = CGSize(width: 0, height: 3)

        label.text = "\(number)"
        label.textColor = markerColor.annotationForegroundColor
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 15, weight: .bold)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor),
            label.trailingAnchor.constraint(equalTo: trailingAnchor),
            label.topAnchor.constraint(equalTo: topAnchor),
            label.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
}
#endif
