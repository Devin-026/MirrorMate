import Foundation
import CoreGraphics

/// Screen coordinates are global AppKit points, including negative monitor origins.
public enum PopoverGeometry {
    public static func viewport(visibleFrame: CGRect, anchor: CGRect) -> CGSize {
        let width = max(1, min(484, visibleFrame.width - 32))
        // Reserve room for the popover's arrow, border, and the Dock.
        let belowAnchor = anchor.minY - visibleFrame.minY - 48
        let height = max(1, min(660, visibleFrame.height - 48, belowAnchor))
        return CGSize(width: width, height: height)
    }

    public static func clamp(_ frame: CGRect, to visibleFrame: CGRect) -> CGRect {
        let bounds = visibleFrame.insetBy(dx: 8, dy: 8)
        let size = CGSize(width: min(frame.width, max(1, bounds.width)), height: min(frame.height, max(1, bounds.height)))
        let origin = CGPoint(x: min(max(frame.minX, bounds.minX), bounds.maxX - size.width), y: min(max(frame.minY, bounds.minY), bounds.maxY - size.height))
        return CGRect(origin: origin, size: size)
    }
}
