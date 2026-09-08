//
//  AppUpdateInfo.swift
//  metere
//

import Foundation

/// Represents release details retrieved from an update feed (such as GitHub Releases).
public struct AppUpdateInfo: Equatable, Codable, Sendable, Identifiable {
    public var id: String { rawTagName }

    public let version: SemanticVersion
    public let rawTagName: String
    public let releaseTitle: String
    public let releaseNotes: String
    public let publishedAt: Date
    public let htmlURL: URL
    public let downloadURL: URL?
    public let assetName: String?
    public let assetSize: Int64?
    public let isPrerelease: Bool

    public init(
        version: SemanticVersion,
        rawTagName: String,
        releaseTitle: String,
        releaseNotes: String,
        publishedAt: Date,
        htmlURL: URL,
        downloadURL: URL?,
        assetName: String?,
        assetSize: Int64?,
        isPrerelease: Bool
    ) {
        self.version = version
        self.rawTagName = rawTagName
        self.releaseTitle = releaseTitle
        self.releaseNotes = releaseNotes
        self.publishedAt = publishedAt
        self.htmlURL = htmlURL
        self.downloadURL = downloadURL
        self.assetName = assetName
        self.assetSize = assetSize
        self.isPrerelease = isPrerelease
    }

    public var formattedSize: String? {
        guard let size = assetSize, size > 0 else { return nil }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }
}

// MARK: - GitHub Release API DTOs
public struct GitHubReleasePayload: Decodable, Sendable {
    public let tagName: String
    public let name: String?
    public let body: String?
    public let htmlUrl: String
    public let publishedAt: String
    public let prerelease: Bool
    public let draft: Bool
    public let assets: [GitHubAssetPayload]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case htmlUrl = "html_url"
        case publishedAt = "published_at"
        case prerelease
        case draft
        case assets
    }

    public init(
        tagName: String,
        name: String?,
        body: String?,
        htmlUrl: String,
        publishedAt: String,
        prerelease: Bool = false,
        draft: Bool = false,
        assets: [GitHubAssetPayload] = []
    ) {
        self.tagName = tagName
        self.name = name
        self.body = body
        self.htmlUrl = htmlUrl
        self.publishedAt = publishedAt
        self.prerelease = prerelease
        self.draft = draft
        self.assets = assets
    }
}

public struct GitHubAssetPayload: Decodable, Sendable {
    public let name: String
    public let size: Int64
    public let browserDownloadUrl: String
    public let contentType: String?

    enum CodingKeys: String, CodingKey {
        case name
        case size
        case browserDownloadUrl = "browser_download_url"
        case contentType = "content_type"
    }

    public init(name: String, size: Int64, browserDownloadUrl: String, contentType: String? = nil) {
        self.name = name
        self.size = size
        self.browserDownloadUrl = browserDownloadUrl
        self.contentType = contentType
    }
}

// MARK: - Parser Extension
extension AppUpdateInfo {
    public static func parse(from gitHub: GitHubReleasePayload) -> AppUpdateInfo? {
        guard !gitHub.draft else { return nil }
        guard let semVer = SemanticVersion(gitHub.tagName) else { return nil }
        guard let html = URL(string: gitHub.htmlUrl) else { return nil }

        let isoFormatter = ISO8601DateFormatter()
        let published = isoFormatter.date(from: gitHub.publishedAt) ?? Date()

        // Choose best binary asset (.dmg preferred, then .zip, then .pkg)
        let preferredAsset = gitHub.assets.first(where: {
            $0.name.lowercased().hasSuffix(".dmg")
        }) ?? gitHub.assets.first(where: {
            $0.name.lowercased().hasSuffix(".zip")
        }) ?? gitHub.assets.first(where: {
            $0.name.lowercased().hasSuffix(".pkg")
        })

        let downloadURL = preferredAsset.flatMap { URL(string: $0.browserDownloadUrl) }

        return AppUpdateInfo(
            version: semVer,
            rawTagName: gitHub.tagName,
            releaseTitle: gitHub.name?.isEmpty == false ? gitHub.name! : "Metere \(semVer.description)",
            releaseNotes: gitHub.body ?? "No release notes provided for this version.",
            publishedAt: published,
            htmlURL: html,
            downloadURL: downloadURL,
            assetName: preferredAsset?.name,
            assetSize: preferredAsset?.size,
            isPrerelease: gitHub.prerelease
        )
    }
}
