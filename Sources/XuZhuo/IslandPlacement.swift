import Foundation

/// The anchor is the center of the panel's top edge in desktop coordinates.
/// An unplugged display or malformed preference must never strand the island.
enum IslandPlacement {
    static let collapsedSize = CGSize(width: 196, height: 44)
    static let expandedSize = CGSize(width: 480, height: 340)
    static let workflowSize = CGSize(width: 480, height: 560)

    static func centerTop(of frame: CGRect) -> CGPoint {
        CGPoint(x: frame.midX, y: frame.maxY)
    }

    static func defaultAnchor(in visibleFrame: CGRect) -> CGPoint {
        CGPoint(x: visibleFrame.midX, y: visibleFrame.maxY - 8)
    }

    static func frame(size: CGSize, anchor: CGPoint, visibleFrames: [CGRect]) -> CGRect {
        let screens = visibleFrames.filter { !$0.isNull && !$0.isInfinite && $0.width > 0 && $0.height > 0 }
        guard let first = screens.first else { return CGRect(origin: .zero, size: collapsedSize) }
        let point = anchor.x.isFinite && anchor.y.isFinite ? anchor : defaultAnchor(in: first)
        let screen = screens.first(where: { $0.contains(point) }) ?? screens.min { lhs, rhs in
            distanceSquared(point, to: lhs) < distanceSquared(point, to: rhs)
        } ?? first
        let width = min(size.width.isFinite && size.width > 0 ? size.width : collapsedSize.width, screen.width)
        let height = min(size.height.isFinite && size.height > 0 ? size.height : collapsedSize.height, screen.height)
        let x = min(max(point.x - width / 2, screen.minX), screen.maxX - width)
        let y = min(max(point.y - height, screen.minY), screen.maxY - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private static func distanceSquared(_ point: CGPoint, to rect: CGRect) -> CGFloat {
        let x = min(max(point.x, rect.minX), rect.maxX)
        let y = min(max(point.y, rect.minY), rect.maxY)
        return pow(point.x - x, 2) + pow(point.y - y, 2)
    }
}
