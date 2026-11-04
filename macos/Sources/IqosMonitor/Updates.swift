// Atualizações automáticas a partir das releases do GitHub (como no Windows).
//
// Cada release traz IqosMonitor-macOS.zip e IqosMonitor-macOS.zip.sha256. A app
// descarrega o .zip, confirma o SHA-256, descompacta-o, troca o próprio
// IqosMonitor.app pelo novo e volta a abrir-se.

import AppKit
import CryptoKit
import Foundation

struct Release {
    var version: String
    var notes: String
    var pageURL: URL
    var zipURL: URL
    var sha256URL: URL?
}

enum UpdateError: LocalizedError {
    case checksum, missingApp, notInstalled

    var errorDescription: String? {
        switch self {
        case .checksum: return "O SHA-256 não confere; a atualização foi descartada."
        case .missingApp: return "O ficheiro descarregado não tem a app."
        case .notInstalled: return "A app não está numa pasta onde se possa substituir (copie-a para Aplicações)."
        }
    }
}

enum Updates {
    static let repo = "diogoardsilva/iqos-monitor"
    static let assetName = "IqosMonitor-macOS.zip"

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    static func parse(_ v: String) -> [Int] {
        v.trimmingCharacters(in: CharacterSet(charactersIn: "vV ")).split(separator: ".").map {
            Int($0.filter(\.isNumber)) ?? 0
        }
    }

    static func isNewer(_ remote: String, than local: String = currentVersion) -> Bool {
        let a = parse(remote), b = parse(local)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    private static func request(_ url: URL) -> URLRequest {
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("IqosMonitor-mac/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        return req
    }

    /// Devolve a release mais recente se for mais nova e tiver a versão para Mac.
    static func latest() async throws -> Release? {
        let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!
        let (data, _) = try await URLSession.shared.data(for: request(url))
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let page = (json["html_url"] as? String).flatMap(URL.init(string:)),
              json["draft"] as? Bool != true, json["prerelease"] as? Bool != true
        else { return nil }
        var assets: [String: URL] = [:]
        for a in json["assets"] as? [[String: Any]] ?? [] {
            if let name = a["name"] as? String,
               let link = (a["browser_download_url"] as? String).flatMap(URL.init(string:)) {
                assets[name] = link
            }
        }
        guard let zip = assets[assetName], isNewer(tag) else { return nil }
        return Release(version: tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV")),
                       notes: json["body"] as? String ?? "", pageURL: page, zipURL: zip,
                       sha256URL: assets[assetName + ".sha256"])
    }

    /// Só a app instalada (um .app numa pasta onde o utilizador pode escrever) se substitui.
    static var canSelfUpdate: Bool {
        let app = Bundle.main.bundleURL
        return app.pathExtension == "app"
            && FileManager.default.isWritableFile(atPath: app.deletingLastPathComponent().path)
    }

    /// Descarrega, confirma o SHA-256, troca a app e volta a abri-la. Não devolve se correr bem.
    static func install(_ rel: Release) async throws {
        guard canSelfUpdate else { throw UpdateError.notInstalled }
        let (zipFile, _) = try await URLSession.shared.download(for: request(rel.zipURL))
        let data = try Data(contentsOf: zipFile)
        if let shaURL = rel.sha256URL {
            let (shaData, _) = try await URLSession.shared.data(for: request(shaURL))
            let expected = String(decoding: shaData, as: UTF8.self)
                .split(whereSeparator: \.isWhitespace).first.map { $0.lowercased() } ?? ""
            let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard actual == expected else { throw UpdateError.checksum }
        } else if data.count < 200_000 {
            throw UpdateError.checksum
        }

        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("IqosMonitor-update-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        try run("/usr/bin/ditto", ["-x", "-k", zipFile.path, work.path])
        guard let newApp = try FileManager.default.contentsOfDirectory(at: work, includingPropertiesForKeys: nil)
            .first(where: { $0.pathExtension == "app" }) else { throw UpdateError.missingApp }
        // Descarregado pela própria app: não fica em quarentena, mas por via das dúvidas.
        try? run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", newApp.path])

        let current = Bundle.main.bundleURL
        _ = try FileManager.default.replaceItemAt(current, withItemAt: newApp)

        // Abre a versão nova depois de esta sair.
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\" --args --updated", current.path]
        try p.run()
        await MainActor.run { NSApp.terminate(nil) }
    }

    private static func run(_ tool: String, _ args: [String]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        try p.run()
        p.waitUntilExit()
        if p.terminationStatus != 0 { throw UpdateError.missingApp }
    }
}
