#if DEBUG && os(iOS)
import UIKit

enum ExportBuilder {
    @MainActor
    static func copyAgentContext(capture: CapturedScreen, annotations: [Annotation], format: CopyFormat) {
        switch format {
        case .annotatedScreenshot:
            let annotatedImage = makeAnnotatedScreenshot(capture: capture, annotations: annotations)
            UIPasteboard.general.image = annotatedImage
        case .markdown:
            UIPasteboard.general.string = makeMarkdown(
                capture: capture,
                annotations: annotations,
                includeSnippetLinks: false
            )
        }
    }

    @MainActor
    static func buildZip(capture: CapturedScreen, annotations: [Annotation]) throws -> URL {
        let fileManager = FileManager.default
        let baseURL = fileManager.temporaryDirectory
            .appendingPathComponent("Sampler-\(UUID().uuidString)", isDirectory: true)
        let snippetsURL = baseURL.appendingPathComponent("snippets", isDirectory: true)

        try fileManager.createDirectory(at: snippetsURL, withIntermediateDirectories: true)

        try write(
            text: makeMarkdown(capture: capture, annotations: annotations, includeSnippetLinks: true),
            to: baseURL.appendingPathComponent("report.md")
        )
        try writeJSON(
            capture: capture,
            annotations: annotations,
            to: baseURL.appendingPathComponent("annotations.json")
        )
        try writePNG(capture.screenshot, to: baseURL.appendingPathComponent("screenshot.png"))
        try writePNG(
            makeAnnotatedScreenshot(capture: capture, annotations: annotations),
            to: baseURL.appendingPathComponent("annotated.png")
        )

        for annotation in annotations {
            if let snippet = cropSnippet(for: annotation, capture: capture) {
                try writePNG(snippet, to: snippetsURL.appendingPathComponent("box-\(annotation.number).png"))
            }
        }

        return try zipDirectory(baseURL)
    }

    @MainActor
    static func makeAgentSyncPayload(sessionID: String, capture: CapturedScreen, annotations: [Annotation]) throws -> Data {
        let annotatedImage = makeAnnotatedScreenshot(capture: capture, annotations: annotations)
        guard
            let screenshotData = capture.screenshot.pngData(),
            let annotatedData = annotatedImage.pngData()
        else {
            throw SamplerError.exportFailed
        }

        let payload = AgentSyncPayload(
            sessionId: sessionID,
            source: AgentSyncSource(
                appName: capture.appName,
                deviceName: capture.deviceName,
                systemVersion: capture.systemVersion
            ),
            capture: makeExportPayload(capture: capture, annotations: annotations),
            annotations: makeExportAnnotations(capture: capture, annotations: annotations),
            markdown: makeMarkdown(capture: capture, annotations: annotations, includeSnippetLinks: false),
            screenshotPngBase64: screenshotData.base64EncodedString(),
            annotatedPngBase64: annotatedData.base64EncodedString(),
            createdAt: capture.capturedAt
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(payload)
    }

    private static func makeMarkdown(
        capture: CapturedScreen,
        annotations: [Annotation],
        includeSnippetLinks: Bool
    ) -> String {
        var lines: [String] = []
        lines.append("# UI Feedback - \(capture.appName)")
        lines.append("")
        lines.append("- Device: \(capture.deviceName)")
        lines.append("- iOS: \(capture.systemVersion)")
        lines.append("- Screen: \(Int(capture.bounds.width))x\(Int(capture.bounds.height)) pt @\(format(capture.scale))x")
        lines.append("- Captured: \(ISO8601DateFormatter().string(from: capture.capturedAt))")
        lines.append("")
        lines.append("Use the numbered markers in the annotated screenshot to match each comment to the UI.")
        lines.append("")

        for annotation in annotations {
            let rect = annotation.rect
            let normalized = rect.normalized(in: capture.bounds)
            lines.append("## Annotation \(annotation.number)")
            lines.append("")
            lines.append("Comment: \(annotation.comment)")
            lines.append("")
            lines.append("- Rect (points): x=\(format(rect.x)), y=\(format(rect.y)), w=\(format(rect.width)), h=\(format(rect.height))")
            lines.append("- Rect (normalized): x=\(format(normalized.x)), y=\(format(normalized.y)), w=\(format(normalized.width)), h=\(format(normalized.height))")

            if annotation.matchedElements.isEmpty {
                lines.append("- Elements under box: none captured")
            } else {
                lines.append("- Elements under box:")
                for element in annotation.matchedElements.prefix(8) {
                    lines.append("  - \(describe(element))")
                }
            }

            if includeSnippetLinks {
                lines.append("- Snippet: snippets/box-\(annotation.number).png")
            } else {
                lines.append("- Screenshot marker: \(annotation.number)")
            }

            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    private static func describe(_ element: AccessibilityElementSnapshot) -> String {
        var parts: [String] = []
        if let label = element.label, !label.isEmpty {
            parts.append("label \"\(label)\"")
        }
        if let identifier = element.identifier, !identifier.isEmpty {
            parts.append("identifier \"\(identifier)\"")
        }
        if let value = element.value, !value.isEmpty {
            parts.append("value \"\(value)\"")
        }
        if !element.traits.isEmpty {
            parts.append("traits \(element.traits.joined(separator: ", "))")
        }

        let frame = element.frame
        parts.append("frame x=\(format(frame.x)), y=\(format(frame.y)), w=\(format(frame.width)), h=\(format(frame.height))")
        return parts.joined(separator: "; ")
    }

    private static func makeAnnotatedScreenshot(capture: CapturedScreen, annotations: [Annotation]) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = capture.scale
        format.opaque = false

        let notesHeight = notesPanelHeight(width: capture.bounds.width, annotations: annotations)
        let outputSize = CGSize(width: capture.bounds.width, height: capture.bounds.height + notesHeight)
        let renderer = UIGraphicsImageRenderer(size: outputSize, format: format)
        return renderer.image { context in
            capture.screenshot.draw(in: capture.bounds)

            for annotation in annotations {
                let rect = annotation.rect.cgRect
                let borderColor = UIColor(hexString: annotation.borderColorHex) ?? .systemBlue
                borderColor.withAlphaComponent(0.14).setFill()
                UIBezierPath(roundedRect: rect, cornerRadius: 12).fill()

                borderColor.setStroke()
                let path = UIBezierPath(roundedRect: rect, cornerRadius: 12)
                path.lineWidth = 2
                path.setLineDash([7, 5], count: 2, phase: 0)
                path.stroke()

                let markerSize: CGFloat = 30
                let markerRect = centeredMarkerRect(in: rect, markerSize: markerSize, bounds: capture.bounds)
                UIColor.black.setFill()
                UIBezierPath(ovalIn: markerRect).fill()

                let number = "\(annotation.number)" as NSString
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 15, weight: .bold),
                    .foregroundColor: UIColor.white
                ]
                let numberSize = number.size(withAttributes: attributes)
                number.draw(
                    at: CGPoint(
                        x: markerRect.midX - numberSize.width / 2,
                        y: markerRect.midY - numberSize.height / 2
                    ),
                    withAttributes: attributes
                )
            }

            drawNotesPanel(
                in: CGRect(x: 0, y: capture.bounds.maxY, width: capture.bounds.width, height: notesHeight),
                annotations: annotations
            )
            context.cgContext.setBlendMode(.normal)
        }
    }

    private static func notesPanelHeight(width: CGFloat, annotations: [Annotation]) -> CGFloat {
        guard !annotations.isEmpty else {
            return 0
        }

        let panelWidth = width - 24
        let textWidth = panelWidth - 66
        let titleHeight: CGFloat = 24
        let topPadding: CGFloat = 12
        let titleTop: CGFloat = 14
        let rowsStartOffset: CGFloat = 48
        let rowSpacing: CGFloat = 10
        let bottomPadding: CGFloat = 36
        let rowHeights = annotations.map { annotation in
            noteText(for: annotation).boundingRect(
                with: CGSize(width: textWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: UIFont.systemFont(ofSize: 14, weight: .medium)],
                context: nil
            ).height
        }

        let rowsHeight = rowHeights.reduce(CGFloat.zero) { partialResult, textHeight in
            partialResult + max(24, ceil(textHeight)) + rowSpacing
        }

        return ceil(topPadding + titleTop + titleHeight + rowsStartOffset - titleTop - titleHeight + rowsHeight + bottomPadding)
    }

    private static func drawNotesPanel(in rect: CGRect, annotations: [Annotation]) {
        guard !annotations.isEmpty else {
            return
        }

        UIColor.systemGroupedBackground.setFill()
        UIRectFill(rect)

        let panelRect = rect.insetBy(dx: 12, dy: 12)
        UIColor.white.setFill()
        UIBezierPath(roundedRect: panelRect, cornerRadius: 22).fill()

        let title = "Annotation Notes" as NSString
        title.draw(
            at: CGPoint(x: panelRect.minX + 16, y: panelRect.minY + 14),
            withAttributes: [
                .font: UIFont.systemFont(ofSize: 16, weight: .bold),
                .foregroundColor: UIColor.black
            ]
        )

        var y = panelRect.minY + 48
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 14, weight: .medium),
            .foregroundColor: UIColor.black
        ]

        for annotation in annotations {
            let badgeSize: CGFloat = 24
            let badgeRect = CGRect(x: panelRect.minX + 16, y: y, width: badgeSize, height: badgeSize)
            UIColor.black.setFill()
            UIBezierPath(ovalIn: badgeRect).fill()

            let number = "\(annotation.number)" as NSString
            let numberAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12, weight: .bold),
                .foregroundColor: UIColor.white
            ]
            let numberSize = number.size(withAttributes: numberAttributes)
            number.draw(
                at: CGPoint(x: badgeRect.midX - numberSize.width / 2, y: badgeRect.midY - numberSize.height / 2),
                withAttributes: numberAttributes
            )

            let text = noteText(for: annotation) as NSString
            let textRect = CGRect(
                x: badgeRect.maxX + 10,
                y: y + 2,
                width: panelRect.width - 66,
                height: .greatestFiniteMagnitude
            )
            let textSize = text.boundingRect(
                with: textRect.size,
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: textAttributes,
                context: nil
            ).size
            text.draw(
                with: CGRect(origin: textRect.origin, size: textSize),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: textAttributes,
                context: nil
            )

            y += max(badgeSize, ceil(textSize.height)) + 10
        }
    }

    private static func noteText(for annotation: Annotation) -> String {
        annotation.comment.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func cropSnippet(for annotation: Annotation, capture: CapturedScreen) -> UIImage? {
        guard let cgImage = capture.screenshot.cgImage else {
            return nil
        }

        let padding: CGFloat = 12
        let paddedRect = annotation.rect.cgRect
            .insetBy(dx: -padding, dy: -padding)
            .intersection(capture.bounds)
        let scaledRect = CGRect(
            x: paddedRect.origin.x * capture.scale,
            y: paddedRect.origin.y * capture.scale,
            width: paddedRect.width * capture.scale,
            height: paddedRect.height * capture.scale
        ).integral

        guard let croppedImage = cgImage.cropping(to: scaledRect) else {
            return nil
        }

        return UIImage(cgImage: croppedImage, scale: capture.scale, orientation: capture.screenshot.imageOrientation)
    }

    private static func write(text: String, to url: URL) throws {
        try text.data(using: .utf8)?.write(to: url, options: .atomic)
    }

    private static func centeredMarkerRect(in rect: CGRect, markerSize: CGFloat, bounds: CGRect) -> CGRect {
        let origin = CGPoint(
            x: min(max(rect.midX - markerSize / 2, bounds.minX + 8), bounds.maxX - markerSize - 8),
            y: min(max(rect.midY - markerSize / 2, bounds.minY + 8), bounds.maxY - markerSize - 8)
        )

        return CGRect(origin: origin, size: CGSize(width: markerSize, height: markerSize))
    }

    private static func writePNG(_ image: UIImage, to url: URL) throws {
        guard let data = image.pngData() else {
            throw SamplerError.exportFailed
        }

        try data.write(to: url, options: .atomic)
    }

    private static func writeJSON(capture: CapturedScreen, annotations: [Annotation], to url: URL) throws {
        let payload = makeExportPayload(capture: capture, annotations: annotations)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(payload).write(to: url, options: .atomic)
    }

    private static func makeExportPayload(capture: CapturedScreen, annotations: [Annotation]) -> ExportPayload {
        ExportPayload(
            appName: capture.appName,
            deviceName: capture.deviceName,
            systemVersion: capture.systemVersion,
            screenBounds: RectSnapshot(capture.bounds),
            scale: capture.scale,
            capturedAt: capture.capturedAt,
            annotations: makeExportAnnotations(capture: capture, annotations: annotations)
        )
    }

    private static func makeExportAnnotations(capture: CapturedScreen, annotations: [Annotation]) -> [ExportAnnotation] {
        annotations.map {
            ExportAnnotation(
                id: $0.id,
                number: $0.number,
                comment: $0.comment,
                rect: $0.rect,
                normalizedRect: $0.rect.normalized(in: capture.bounds),
                matchedElements: $0.matchedElements
            )
        }
    }

    private static func zipDirectory(_ directoryURL: URL) throws -> URL {
        let destinationURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(directoryURL.lastPathComponent)
            .appendingPathExtension("zip")
        try? FileManager.default.removeItem(at: destinationURL)

        var coordinationError: NSError?
        var copyError: Error?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(
            readingItemAt: directoryURL,
            options: .forUploading,
            error: &coordinationError
        ) { zippedURL in
            do {
                try FileManager.default.copyItem(at: zippedURL, to: destinationURL)
            } catch {
                copyError = error
            }
        }

        if let coordinationError {
            throw coordinationError
        }
        if let copyError {
            throw copyError
        }

        return destinationURL
    }

    private static func format(_ value: CGFloat) -> String {
        String(format: "%.2f", value)
    }
}

private struct ExportPayload: Codable {
    let appName: String
    let deviceName: String
    let systemVersion: String
    let screenBounds: RectSnapshot
    let scale: CGFloat
    let capturedAt: Date
    let annotations: [ExportAnnotation]
}

private struct ExportAnnotation: Codable {
    let id: UUID
    let number: Int
    let comment: String
    let rect: RectSnapshot
    let normalizedRect: RectSnapshot
    let matchedElements: [AccessibilityElementSnapshot]
}

private struct AgentSyncPayload: Codable {
    let sessionId: String
    let source: AgentSyncSource
    let capture: ExportPayload
    let annotations: [ExportAnnotation]
    let markdown: String
    let screenshotPngBase64: String
    let annotatedPngBase64: String
    let createdAt: Date
}

private struct AgentSyncSource: Codable {
    let appName: String
    let deviceName: String
    let systemVersion: String
}
#endif
