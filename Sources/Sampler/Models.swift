#if DEBUG && os(iOS)
import UIKit

struct CapturedScreen {
    let screenshot: UIImage
    let bounds: CGRect
    let scale: CGFloat
    let appName: String
    let deviceName: String
    let systemVersion: String
    let capturedAt: Date
    let accessibilityElements: [AccessibilityElementSnapshot]
}

struct AccessibilityElementSnapshot: Codable {
    let identifier: String?
    let label: String?
    let value: String?
    let traits: [String]
    let frame: RectSnapshot

    var displayName: String {
        if let label, !label.isEmpty {
            return label
        }
        if let identifier, !identifier.isEmpty {
            return identifier
        }
        return "Element"
    }
}

struct Annotation: Codable {
    let id: UUID
    let number: Int
    let rect: RectSnapshot
    var comment: String
    var matchedElements: [AccessibilityElementSnapshot]
    var borderColorHex: String
}

struct RectSnapshot: Codable {
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat

    init(_ rect: CGRect) {
        x = rect.origin.x
        y = rect.origin.y
        width = rect.size.width
        height = rect.size.height
    }

    var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }

    func normalized(in bounds: CGRect) -> RectSnapshot {
        guard bounds.width > 0, bounds.height > 0 else {
            return RectSnapshot(.zero)
        }

        return RectSnapshot(
            CGRect(
                x: x / bounds.width,
                y: y / bounds.height,
                width: width / bounds.width,
                height: height / bounds.height
            )
        )
    }
}

enum SamplerError: LocalizedError {
    case noActiveWindowScene
    case screenCaptureFailed
    case exportFailed

    var errorDescription: String? {
        switch self {
        case .noActiveWindowScene:
            return "No active iOS window scene was found."
        case .screenCaptureFailed:
            return "The current app screen could not be captured."
        case .exportFailed:
            return "The annotation export could not be created."
        }
    }
}

enum CopyFormat {
    case annotatedScreenshot
    case markdown

    var toggled: CopyFormat {
        switch self {
        case .annotatedScreenshot:
            return .markdown
        case .markdown:
            return .annotatedScreenshot
        }
    }

    var displayTitle: String {
        switch self {
        case .annotatedScreenshot:
            return "Screenshot"
        case .markdown:
            return "Markdown"
        }
    }
}

enum OverlayTheme {
    case light
    case dark

    var toggled: OverlayTheme {
        switch self {
        case .light:
            return .dark
        case .dark:
            return .light
        }
    }

    var userInterfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }

    var widgetBackground: UIColor {
        switch self {
        case .light:
            return .white
        case .dark:
            return .black
        }
    }

    var primaryText: UIColor {
        switch self {
        case .light:
            return .black
        case .dark:
            return .white
        }
    }

    var secondaryText: UIColor {
        switch self {
        case .light:
            return UIColor.black.withAlphaComponent(0.58)
        case .dark:
            return UIColor.white.withAlphaComponent(0.62)
        }
    }

    var mutedText: UIColor {
        switch self {
        case .light:
            return UIColor.black.withAlphaComponent(0.42)
        case .dark:
            return UIColor.white.withAlphaComponent(0.42)
        }
    }

    var elevatedControlBackground: UIColor {
        switch self {
        case .light:
            return UIColor.black.withAlphaComponent(0.07)
        case .dark:
            return UIColor.white.withAlphaComponent(0.14)
        }
    }

    var divider: UIColor {
        switch self {
        case .light:
            return UIColor.black.withAlphaComponent(0.07)
        case .dark:
            return UIColor.white.withAlphaComponent(0.08)
        }
    }

    var annotationCardBackground: UIColor {
        switch self {
        case .light:
            return .white
        case .dark:
            return .black
        }
    }

    var annotationTextBoxBackground: UIColor {
        switch self {
        case .light:
            return .secondarySystemBackground
        case .dark:
            return UIColor(white: 0.14, alpha: 1)
        }
    }

    var actionButtonBackground: UIColor {
        switch self {
        case .light:
            return .black
        case .dark:
            return .white
        }
    }

    var actionButtonForeground: UIColor {
        switch self {
        case .light:
            return .white
        case .dark:
            return .black
        }
    }

    var toastBackground: UIColor {
        switch self {
        case .light:
            return UIColor.white.withAlphaComponent(0.94)
        case .dark:
            return UIColor(white: 0.08, alpha: 0.94)
        }
    }

    var shadowColor: CGColor {
        UIColor.black.cgColor
    }
}

extension UIColor {
    convenience init?(hexString: String) {
        let trimmed = hexString.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard trimmed.count == 6, let value = Int(trimmed, radix: 16) else {
            return nil
        }

        self.init(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }

    var hexString: String {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        guard getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return "#007AFF"
        }

        return String(
            format: "#%02X%02X%02X",
            Int(round(red * 255)),
            Int(round(green * 255)),
            Int(round(blue * 255))
        )
    }

    var annotationForegroundColor: UIColor {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        guard getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return .white
        }

        return red > 0.85 && green > 0.65 && blue < 0.35 ? .black : .white
    }
}
#endif
