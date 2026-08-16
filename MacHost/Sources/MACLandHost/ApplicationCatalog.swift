import AppKit
import Combine
import Foundation

struct InstalledApplication: Identifiable, Equatable, Hashable {
    let id: String
    let bundleIdentifier: String
    let name: String
    let url: URL

    init?(url: URL) {
        guard let bundle = Bundle(url: url),
              let bundleIdentifier = bundle.bundleIdentifier,
              let name = bundle.localizedInfoDictionary?["CFBundleDisplayName"] as? String
                ?? bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String else {
            return nil
        }

        id = bundleIdentifier
        self.bundleIdentifier = bundleIdentifier
        self.name = name
        self.url = url
    }
}

@MainActor
final class ApplicationCatalog: ObservableObject {
    @Published private(set) var applications: [InstalledApplication] = []

    func refresh() {
        let fileManager = FileManager.default
        let roots = [
            fileManager.urls(for: .applicationDirectory, in: .localDomainMask),
            fileManager.urls(for: .applicationDirectory, in: .systemDomainMask),
            fileManager.urls(for: .applicationDirectory, in: .userDomainMask)
        ].flatMap { $0 }

        var found: [String: InstalledApplication] = [:]
        for root in roots {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .isApplicationKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            for case let url as URL in enumerator {
                guard url.pathExtension == "app",
                      let app = InstalledApplication(url: url) else { continue }
                found[app.bundleIdentifier] = app
            }
        }

        applications = found.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    func launch(
        bundleIdentifier: String,
        activates: Bool,
        completion: @escaping @Sendable (Result<NSRunningApplication, Error>) -> Void
    ) {
        guard let application = applications.first(where: { $0.bundleIdentifier == bundleIdentifier }) else {
            completion(.failure(ApplicationCatalogError.notFound(bundleIdentifier)))
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = activates
        NSWorkspace.shared.openApplication(at: application.url, configuration: configuration) { runningApplication, error in
            if let error {
                completion(.failure(error))
            } else if let runningApplication {
                completion(.success(runningApplication))
            } else {
                completion(.failure(ApplicationCatalogError.launchFailed(bundleIdentifier)))
            }
        }
    }
}

enum ApplicationCatalogError: LocalizedError, Equatable {
    case notFound(String)
    case launchFailed(String)

    var errorDescription: String? {
        switch self {
        case let .notFound(bundleIdentifier):
            return "Application not found: \(bundleIdentifier)"
        case let .launchFailed(bundleIdentifier):
            return "Application did not return a running process: \(bundleIdentifier)"
        }
    }
}
