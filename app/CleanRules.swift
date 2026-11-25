import Foundation

/// 清理风险等级：
/// - low：可重建的缓存与日志，默认勾选，移动到废纸篓
/// - medium：重建成本高（需重新下载/编译），默认不勾，需用户主动选
/// - manual：模型/容器等大头，只显示占用，永不清理
enum CleanRisk: String {
    case low, medium, manual
}

/// 一个可清理分类。paths 为相对 home 的目录路径（支持 `~` 省略）。
struct CleanCategory: Identifiable, Equatable {
    let id: String
    let name: String
    let paths: [String]
    let risk: CleanRisk
    let note: String

    var defaultSelected: Bool { risk == .low }
    var isActionable: Bool { risk != .manual }
}

/// 分类规则与路径解析（纯逻辑，可单测；测试时注入临时 home 避免碰真实目录）。
enum CleanRules {
    /// 目录内容可被安全清理的分类。刻意不包含「应用数据 / 配置 / 模型 / 数据库」。
    static let catalog: [CleanCategory] = [
        CleanCategory(id: "trash", name: "废纸篓", paths: [".Trash"], risk: .low,
                      note: "永久删除，不进废纸篓"),
        CleanCategory(id: "browser", name: "浏览器缓存", paths: [
            "Library/Caches/com.apple.Safari",
            "Library/Caches/Google/Chrome",
            "Library/Caches/com.google.Chrome",
            "Library/Caches/org.chromium.Chromium",
            "Library/Caches/com.microsoft.edgemac",
            "Library/Caches/Tabbit",
        ], risk: .low, note: "仅缓存，不动历史记录与 Cookie"),
        CleanCategory(id: "applog", name: "应用日志", paths: [
            "Library/Logs",
            "Library/Application Support/CrashReporter",
        ], risk: .low, note: "旧日志与崩溃报告"),
        CleanCategory(id: "appcache", name: "全部应用缓存", paths: [
            "Library/Caches",
        ], risk: .medium, note: "范围过大且可能含活跃缓存，默认不选"),
        CleanCategory(id: "aicache", name: "AI 工具缓存", paths: [
            ".claude/cache",
            ".codex/cache",
            "Library/Caches/com.openai",
            "Library/Caches/com.anthropic",
        ], risk: .low, note: "只扫 cache 子目录，不碰会话与配置"),
        CleanCategory(id: "devcache", name: "开发缓存", paths: [
            ".npm/_cacache",
            ".cache/pnpm",
            ".cargo/registry/cache",
            ".gradle/caches",
            ".cache/go-build",
            "Library/Caches/Homebrew",
            "Library/Developer/Xcode/DerivedData",
            "Library/Developer/Xcode/iOS DeviceSupport",
        ], risk: .medium, note: "可重建但需重新下载/编译"),
        CleanCategory(id: "manual", name: "手动管理", paths: [
            ".ollama/models",
            ".cache/huggingface",
            "Library/Application Support/lmstudio",
            "Library/Containers/com.docker.docker",
        ], risk: .manual, note: "模型与容器，只显示占用，绝不自动清理"),
    ]

    /// 将分类里的相对路径解析为绝对 URL（只返回实际存在的目录）。
    static func urls(for category: CleanCategory, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        category.paths.compactMap { rel in
            let url = home.appendingPathComponent(rel, isDirectory: true)
            var isDir: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue ? url : nil
        }
    }

    /// 是否受 Git 保护：目标本身或其任意祖先含 `.git`，则跳过（避免删掉仓库内的构建产物）。
    static func isGitProtected(_ url: URL, fileManager: FileManager = .default) -> Bool {
        var current = url
        for _ in 0..<12 {
            let marker = current.appendingPathComponent(".git")
            if fileManager.fileExists(atPath: marker.path) { return true }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path { break }
            current = parent
        }
        return false
    }

    /// 从多个分类聚合出实际待清理项，去重（同一路径可能被多个分类覆盖）。
    static func resolvedItems(for categories: [CleanCategory],
                              home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        var candidates: [URL] = []
        var seen = Set<String>()
        for c in categories where c.isActionable {
            for url in urls(for: c, home: home) where !isGitProtected(url) {
                let p = url.standardizedFileURL.path
                if seen.insert(p).inserted { candidates.append(url) }
            }
        }
        // 父目录已入选时移除其子目录，避免重复统计与重复清理
        return candidates.filter { url in
            let path = url.standardizedFileURL.path + "/"
            return !candidates.contains { other in
                other.standardizedFileURL.path != url.standardizedFileURL.path
                    && path.hasPrefix(other.standardizedFileURL.path + "/")
            }
        }
    }
}
