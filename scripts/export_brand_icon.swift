import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Deterministic export of the repository's existing vector mark. No redesign.
final class MarkParser: NSObject, XMLParserDelegate {
    var paths: [(String, String, CGPoint)] = []
    var offset = CGPoint.zero

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes: [String: String] = [:]) {
        if elementName == "g", attributes["id"] == "wordmark" { offset = CGPoint(x: 62.37, y: 11.37) }
        if elementName == "path", let path = attributes["d"], let fill = attributes["fill"] {
            paths.append((path, fill, offset))
        }
    }
}

enum ExportError: Error { case invalidVector, unsupportedPath, cannotWrite }

func outline(_ source: String) throws -> CGPath {
    let pattern = #"[A-Za-z]|[-+]?(?:\d*\.\d+|\d+\.?\d*)(?:[eE][-+]?\d+)?"#
    let regex = try NSRegularExpression(pattern: pattern)
    let range = NSRange(source.startIndex..., in: source)
    let tokens = regex.matches(in: source, range: range).compactMap { Range($0.range, in: source).map { String(source[$0]) } }
    let path = CGMutablePath()
    var index = 0
    var command = ""
    func number() throws -> CGFloat {
        guard index < tokens.count, let value = Double(tokens[index]), value.isFinite else { throw ExportError.invalidVector }
        index += 1
        return CGFloat(value)
    }
    while index < tokens.count {
        if tokens[index].first?.isLetter == true {
            command = tokens[index]
            index += 1
        }
        switch command {
        case "M":
            let x = try number(), y = try number()
            path.move(to: CGPoint(x: x, y: y))
            command = "L"
        case "L":
            let x = try number(), y = try number()
            path.addLine(to: CGPoint(x: x, y: y))
        case "H":
            path.addLine(to: CGPoint(x: try number(), y: path.currentPoint.y))
        case "C":
            let x1 = try number(), y1 = try number(), x2 = try number(), y2 = try number(), x = try number(), y = try number()
            path.addCurve(to: CGPoint(x: x, y: y), control1: CGPoint(x: x1, y: y1), control2: CGPoint(x: x2, y: y2))
        case "Z":
            path.closeSubpath()
            command = ""
        default:
            throw ExportError.unsupportedPath
        }
    }
    return path
}

let wordmark = CommandLine.arguments.count == 4 && CommandLine.arguments[3] == "--wordmark"
guard CommandLine.arguments.count == 3 || wordmark else {
    fatalError("Usage: swift export_brand_icon.swift source.svg output.png")
}
let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
let delegate = MarkParser()
guard let parser = XMLParser(contentsOf: sourceURL) else { throw ExportError.invalidVector }
parser.shouldResolveExternalEntities = false
parser.delegate = delegate
guard parser.parse(), wordmark ? delegate.paths.count > 2 : delegate.paths.count == 2,
      let space = CGColorSpace(name: CGColorSpace.sRGB),
      let context = CGContext(data: nil, width: wordmark ? 621 : 1024, height: wordmark ? 126 : 1024, bitsPerComponent: 8,
                              bytesPerRow: 0, space: space, bitmapInfo: wordmark ? CGImageAlphaInfo.premultipliedLast.rawValue : CGImageAlphaInfo.noneSkipLast.rawValue)
else { throw ExportError.invalidVector }
if !wordmark {
context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
context.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
let scale = 674.0 / 50.5519
let top = (1024.0 - 42.0001 * scale) / 2
context.translateBy(x: 175, y: 1024 - top)
context.scaleBy(x: scale, y: -scale)
} else {
    context.translateBy(x: 0, y: 126)
    context.scaleBy(x: 3, y: -3)
}
let colorPattern = try NSRegularExpression(pattern: "#[0-9a-fA-F]{6}")
for (data, fill, offset) in delegate.paths {
    context.saveGState()
    if wordmark { context.translateBy(x: offset.x, y: offset.y) }
    guard let match = colorPattern.firstMatch(in: fill, range: NSRange(fill.startIndex..., in: fill)),
          let range = Range(match.range, in: fill),
          let color = UInt32(fill[range].dropFirst(), radix: 16) else { throw ExportError.invalidVector }
    context.setFillColor(CGColor(red: CGFloat((color >> 16) & 255) / 255,
                                 green: CGFloat((color >> 8) & 255) / 255,
                                 blue: CGFloat(color & 255) / 255, alpha: 1))
    context.addPath(try outline(data))
    context.fillPath()
    context.restoreGState()
}
guard let image = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(outputURL as CFURL, UTType.png.identifier as CFString, 1, nil)
else { throw ExportError.cannotWrite }
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else { throw ExportError.cannotWrite }
print(wordmark ? "Exported existing wordmark: 621 × 126, transparent sRGB PNG" : "Exported existing vector mark: 1024 × 1024, opaque sRGB PNG")
