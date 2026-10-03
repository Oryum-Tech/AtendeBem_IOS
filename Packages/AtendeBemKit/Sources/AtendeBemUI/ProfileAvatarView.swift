import AtendeBemCore
import ImageIO
import SwiftUI

struct ProfileAvatarView: View {
    let name: String
    let mediaID: String?
    var anonymous = false
    var size: CGFloat = 44
    @Environment(AppState.self) private var app

    var body: some View {
        ProfileAvatarImage(name: name,
            mediaID: CommunityAvatarReference.mediaID(mediaID, anonymous: anonymous),
            anonymous: anonymous, size: size)
            .id("\(app.contextID)|\(anonymous)|\(mediaID ?? "")")
            // The adjacent author name already gives the identity. Never repeat
            // it as an extra focus stop for a decorative avatar.
            .accessibilityHidden(true)
    }
}

private struct ProfileAvatarImage: View {
    let name: String
    let mediaID: String?
    let anonymous: Bool
    let size: CGFloat
    @Environment(AppState.self) private var app
    @State private var thumbnail: CGImage?
    @State private var failed = false

    private var initials: String {
        let parts = name.split(whereSeparator: \.isWhitespace)
        return [parts.first, parts.count > 1 ? parts.last : nil]
            .compactMap { $0?.first.map(String.init) }.joined().uppercased()
    }

    var body: some View {
        ZStack {
            Circle().fill(Brand.accent.opacity(0.12))
            if let thumbnail {
                Image(decorative: thumbnail, scale: 1).resizable().scaledToFill()
            } else if anonymous || initials.isEmpty {
                Image(systemName: anonymous ? "person.fill.questionmark" : "person.fill")
                    .font(.system(size: size * 0.42)).foregroundStyle(Brand.accent)
            } else {
                Text(initials).font(.system(size: size * 0.34, weight: .semibold)).foregroundStyle(Brand.accent)
            }
        }
        .frame(width: size, height: size).clipShape(Circle())
        .task(id: mediaID) { await load() }
    }

    private func load() async {
        guard let mediaID, !failed, thumbnail == nil else { return }
        let context = app.contextID
        do {
            let data = try await app.api.communityImage(id: mediaID)
            try Task.checkCancellation()
            guard app.contextID == context else { return }
            guard let image = Self.decode(data) else { failed = true; return }
            thumbnail = image
        } catch is CancellationError {
        } catch {
            guard app.contextID == context else { return }
            failed = true
            await app.checkSession(after: error)
        }
    }

    private static func decode(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 16_000, height <= 16_000, width * height <= 32_000_000 else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 256] as CFDictionary)
    }
}
