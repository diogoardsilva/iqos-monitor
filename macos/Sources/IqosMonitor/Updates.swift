// Procura versões novas nas releases do GitHub.
// No Mac não há troca automática do executável (como no Windows): a app avisa
// e abre a página da release para descarregar IqosMonitor-macOS.zip.

import Foundation

struct Release {
    var version: String
    var pageURL: URL
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

    /// Devolve a release mais recente se for mais nova e tiver a versão para Mac.
    static func latest() async throws -> Release? {
        var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("IqosMonitor-mac/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let page = (json["html_url"] as? String).flatMap(URL.init(string:)),
              json["draft"] as? Bool != true, json["prerelease"] as? Bool != true
        else { return nil }
        let assets = (json["assets"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
        guard assets.contains(assetName), isNewer(tag) else { return nil }
        return Release(version: tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV")), pageURL: page)
    }
}
