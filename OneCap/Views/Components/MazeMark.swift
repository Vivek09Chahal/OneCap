import SwiftUI

/// An eight-by-eight branching maze with a single route from the upper-left
/// entrance to the lower-right exit. Collinear walls share continuous strokes.
/// The sidebar and all app-icon assets use this same vector geometry.
struct MazeMark: Shape {
    private static let gridSize: CGFloat = 8
    private static let walls: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
        (1, 0, 8, 0),
        (2, 1, 3, 1),
        (5, 1, 6, 1),
        (1, 2, 2, 2),
        (3, 2, 5, 2),
        (0, 3, 1, 3),
        (3, 3, 5, 3),
        (2, 4, 4, 4),
        (1, 5, 2, 5),
        (3, 5, 5, 5),
        (6, 5, 7, 5),
        (2, 6, 4, 6),
        (6, 6, 8, 6),
        (1, 7, 2, 7),
        (3, 7, 6, 7),
        (0, 8, 7, 8),
        (0, 0, 0, 8),
        (1, 0, 1, 2),
        (1, 3, 1, 4),
        (1, 5, 1, 7),
        (2, 2, 2, 5),
        (2, 6, 2, 7),
        (3, 1, 3, 3),
        (3, 7, 3, 8),
        (4, 0, 4, 1),
        (5, 1, 5, 2),
        (5, 3, 5, 7),
        (6, 1, 6, 5),
        (7, 0, 7, 4),
        (7, 6, 7, 7),
        (8, 0, 8, 8),
    ]

    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height) * 0.84
        let origin = CGPoint(x: rect.midX - side / 2, y: rect.midY - side / 2)
        let unit = side / Self.gridSize
        return Path { path in
            for (x1, y1, x2, y2) in Self.walls {
                path.move(to: CGPoint(x: origin.x + x1 * unit, y: origin.y + y1 * unit))
                path.addLine(to: CGPoint(x: origin.x + x2 * unit, y: origin.y + y2 * unit))
            }
        }
    }
}
