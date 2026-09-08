//
//  SemanticVersion.swift
//  metere
//

import Foundation

/// A representation of a Semantic Version (semver.org) supporting major.minor.patch
/// and optional pre-release identifiers (e.g., "1.2.3", "v1.2", "2.0.0-beta.1").
public struct SemanticVersion: Comparable, LosslessStringConvertible, Codable, Sendable, Hashable {
    public let major: Int
    public let minor: Int
    public let patch: Int
    public let prerelease: String?
    public let rawString: String

    public var description: String {
        rawString
    }

    public init(major: Int, minor: Int, patch: Int = 0, prerelease: String? = nil) {
        self.major = major
        self.minor = minor
        self.patch = patch
        self.prerelease = prerelease
        if let prerelease = prerelease, !prerelease.isEmpty {
            self.rawString = "\(major).\(minor).\(patch)-\(prerelease)"
        } else {
            self.rawString = "\(major).\(minor).\(patch)"
        }
    }

    public init?(_ description: String) {
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Strip leading 'v' or 'V'
        var versionString = trimmed
        if versionString.lowercased().hasPrefix("v") {
            versionString = String(versionString.dropFirst())
        }

        // Separate pre-release tag if present (e.g. "1.2.3-beta.1" -> "1.2.3" and "beta.1")
        let parts = versionString.split(separator: "-", maxSplits: 1).map(String.init)
        let mainVersion = parts[0]
        let prereleaseTag = parts.count > 1 ? parts[1] : nil

        let components = mainVersion.split(separator: ".").compactMap { Int($0) }
        guard !components.isEmpty else { return nil }

        self.major = components[0]
        self.minor = components.count > 1 ? components[1] : 0
        self.patch = components.count > 2 ? components[2] : 0
        self.prerelease = prereleaseTag
        self.rawString = trimmed
    }

    public var isPrerelease: Bool {
        if let pre = prerelease, !pre.isEmpty {
            return true
        }
        let lower = rawString.lowercased()
        return lower.contains("beta") || lower.contains("alpha") || lower.contains("rc") || lower.contains("preview")
    }

    // MARK: - Current App Version Helper
    public static var currentAppVersion: SemanticVersion {
        if let versionStr = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
           let parsed = SemanticVersion(versionStr) {
            return parsed
        }
        return SemanticVersion(major: 1, minor: 0, patch: 0)
    }

    // MARK: - Comparable
    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        if lhs.major != rhs.major {
            return lhs.major < rhs.major
        }
        if lhs.minor != rhs.minor {
            return lhs.minor < rhs.minor
        }
        if lhs.patch != rhs.patch {
            return lhs.patch < rhs.patch
        }

        // Standard semver rule: A release with a pre-release tag is lower than the same release without one.
        // e.g. 1.0.0-rc.1 < 1.0.0
        switch (lhs.prerelease, rhs.prerelease) {
        case (.some(let lPre), .none):
            return !lPre.isEmpty
        case (.none, .some(let rPre)):
            return rPre.isEmpty
        case (.some(let lPre), .some(let rPre)):
            return lPre.localizedStandardCompare(rPre) == .orderedAscending
        case (.none, .none):
            return false
        }
    }

    // MARK: - Equatable & Hashable
    public static func == (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        lhs.major == rhs.major &&
        lhs.minor == rhs.minor &&
        lhs.patch == rhs.patch &&
        lhs.prerelease == rhs.prerelease
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(major)
        hasher.combine(minor)
        hasher.combine(patch)
        hasher.combine(prerelease)
    }
}
