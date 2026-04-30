import AppKit

enum Tool: String, CaseIterable, Identifiable {
    case select, rect, arrow, text, highlight, blur, crop
    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .select:    return "cursorarrow"
        case .rect:      return "rectangle"
        case .arrow:     return "arrow.up.right"
        case .text:      return "textformat"
        case .highlight: return "highlighter"
        case .blur:      return "drop"
        case .crop:      return "crop"
        }
    }

    var label: String {
        switch self {
        case .select:    return "Select"
        case .rect:      return "Rectangle"
        case .arrow:     return "Arrow"
        case .text:      return "Text"
        case .highlight: return "Highlight"
        case .blur:      return "Blur"
        case .crop:      return "Crop"
        }
    }
}

struct AnnotationStyle: Equatable {
    var color: NSColor = .systemRed
    var strokeWidth: CGFloat = 4
    var fontSize: CGFloat = 24
}

enum Annotation: Identifiable {
    case rect(id: UUID, frame: CGRect, style: AnnotationStyle)
    case arrow(id: UUID, from: CGPoint, to: CGPoint, style: AnnotationStyle)
    case text(id: UUID, origin: CGPoint, string: String, style: AnnotationStyle)
    case highlight(id: UUID, frame: CGRect, style: AnnotationStyle)
    case blur(id: UUID, frame: CGRect, radius: CGFloat)

    var id: UUID {
        switch self {
        case .rect(let id, _, _),
             .arrow(let id, _, _, _),
             .text(let id, _, _, _),
             .highlight(let id, _, _),
             .blur(let id, _, _):
            return id
        }
    }

    var boundingBox: CGRect {
        switch self {
        case .rect(_, let frame, _),
             .highlight(_, let frame, _),
             .blur(_, let frame, _):
            return frame
        case .arrow(_, let from, let to, _):
            return CGRect(x: min(from.x, to.x),
                          y: min(from.y, to.y),
                          width: abs(to.x - from.x),
                          height: abs(to.y - from.y))
        case .text(_, let origin, _, _):
            return CGRect(x: origin.x, y: origin.y, width: 200, height: 40)
        }
    }
}
