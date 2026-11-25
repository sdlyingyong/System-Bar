import Foundation

@main
struct CleanerTests {
    static var pass = 0
    static var fail = 0

    static func check(_ name: String, _ cond: Bool) {
        if cond { pass += 1; print("PASS: \(name)") }
        else { fail += 1; print("FAIL: \(name)") }
    }

    static func main() {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent("cleaner-test-\(UUID().uuidString)")
        let trash = base.appendingPathComponent(".Trash")
        let caches = base.appendingPathComponent("Caches")
        try! fm.createDirectory(at: trash.appendingPathComponent("sub"), withIntermediateDirectories: true)
        try! fm.createDirectory(at: caches, withIntermediateDirectories: true)
        let f1 = trash.appendingPathComponent("big.bin")
        let f2 = trash.appendingPathComponent("sub/child.bin")
        let f3 = caches.appendingPathComponent("cache.dat")
        try! Data(repeating: 0, count: 1024).write(to: f1)
        try! Data(repeating: 0, count: 2048).write(to: f2)
        try! Data(repeating: 0, count: 512).write(to: f3)

        // folderSize 递归统计（APFS 按块分配，≥ 逻辑字节即可）
        let trashSized = Cleaner.folderSize(trash)
        let cacheSized = Cleaner.folderSize(caches)
        check("trash 大小>=3072 (got \(trashSized))", trashSized >= 3072)
        check("caches 大小>=512 (got \(cacheSized))", cacheSized >= 512)

        // reclaimable 为两目录合计
        check("reclaimable=两目录之和", Cleaner.reclaimableBytes(trash: trash, caches: caches) == trashSized + cacheSized)

        // 空目录 → 0
        let empty = base.appendingPathComponent("empty")
        try! fm.createDirectory(at: empty, withIntermediateDirectories: true)
        check("空目录 0", Cleaner.folderSize(empty) == 0)

        // run 清空两目录（目录本身保留），释放 = 清理前合计
        let before = trashSized + cacheSized
        let freed = Cleaner.run(trash: trash, caches: caches)
        check("run 释放=\(before) (got \(freed))", freed == before)
        check("废纸篓已清空", (try! fm.contentsOfDirectory(at: trash, includingPropertiesForKeys: nil)).isEmpty)
        check("缓存已清空", (try! fm.contentsOfDirectory(at: caches, includingPropertiesForKeys: nil)).isEmpty)
        check("目录仍存在", fm.fileExists(atPath: trash.path) && fm.fileExists(atPath: caches.path))

        // 再次清理 → 0
        check("再次清理释放 0", Cleaner.run(trash: trash, caches: caches) == 0)

        // —— 分类规则（全部在临时目录里，不碰真实 home）——
        let home = base.appendingPathComponent("home")
        let catCache = CleanCategory(id: "test-cache", name: "缓存", paths: ["Library/Caches/Test"], risk: .low, note: "")
        let catManual = CleanCategory(id: "test-manual", name: "模型", paths: ["Models"], risk: .manual, note: "")
        let catMedium = CleanCategory(id: "test-medium", name: "开发", paths: ["Dev/cache"], risk: .medium, note: "")
        let target = home.appendingPathComponent("Library/Caches/Test")
        let manualDir = home.appendingPathComponent("Models")
        let devDir = home.appendingPathComponent("Dev/cache")
        try! fm.createDirectory(at: target, withIntermediateDirectories: true)
        try! fm.createDirectory(at: manualDir, withIntermediateDirectories: true)
        try! fm.createDirectory(at: devDir, withIntermediateDirectories: true)
        try! Data(repeating: 7, count: 4096).write(to: target.appendingPathComponent("a.dat"))

        check("low 默认勾选", catCache.defaultSelected)
        check("medium 默认不勾", !catMedium.defaultSelected)
        check("manual 不可清理", !catManual.isActionable && !catManual.defaultSelected)
        check("urls 只返回存在的目录",
              CleanRules.urls(for: catCache, home: home).map(\.standardizedFileURL.path)
                == [target.standardizedFileURL.path])

        // Git 保护：祖先含 .git 的目录必须被排除
        try! fm.createDirectory(at: home.appendingPathComponent("Repo/.git"), withIntermediateDirectories: true)
        try! fm.createDirectory(at: home.appendingPathComponent("Repo/node_modules"), withIntermediateDirectories: true)
        check("Git 仓库内目录受保护", CleanRules.isGitProtected(home.appendingPathComponent("Repo/node_modules")))
        check("普通缓存不受保护", !CleanRules.isGitProtected(target))
        let gitCat = CleanCategory(id: "git", name: "产物", paths: ["Repo/node_modules"], risk: .medium, note: "")
        check("resolvedItems 排除 Git 保护目录", !CleanRules.resolvedItems(for: [gitCat], home: home).contains(target))
        check("resolvedItems 排除 manual 分类",
              !CleanRules.resolvedItems(for: [catManual], home: home).contains(manualDir))

        // 一键清理：缓存项移入废纸篓，目录保留
        let beforeCat = Cleaner.folderSize(target)
        let result = Cleaner.clean(categories: [catCache], home: home, trash: trash)
        check("一键清理释放 >0 (got \(result.freedBytes))", result.freedBytes > 0)
        check("一键清理移走 1 项 (got \(result.removedItems))", result.removedItems == 1)
        check("清理后源目录变空", Cleaner.folderSize(target) == 0)
        check("源目录仍存在", fm.fileExists(atPath: target.path))
        check("释放量等于清理前大小", result.freedBytes == beforeCat)

        // 真实 catalog 的自检（只看规则完备性，不执行）
        check("catalog 含废纸篓", CleanRules.catalog.contains { $0.id == "trash" })
        check("catalog 含 AI 缓存", CleanRules.catalog.contains { $0.id == "aicache" })
        check("catalog 含开发缓存", CleanRules.catalog.contains { $0.id == "devcache" })
        check("catalog 含手动管理", CleanRules.catalog.contains { $0.id == "manual" })
        check("manual 分类路径不出现在可清理项",
              CleanRules.resolvedItems(for: CleanRules.catalog.filter { $0.risk == .manual }, home: home).isEmpty)

        // 父子去重：同时选 Library/Caches 与其子目录时只保留父目录
        let sub = target.appendingPathComponent("sub")
        try! fm.createDirectory(at: sub, withIntermediateDirectories: true)
        let parentCat = CleanCategory(id: "parent", name: "父", paths: ["Library/Caches"], risk: .low, note: "")
        let resolved = CleanRules.resolvedItems(for: [catCache, parentCat], home: home)
        let rootCaches = home.appendingPathComponent("Library/Caches").standardizedFileURL.path
        check("父子去重只留父目录", resolved.count == 1 && resolved.first?.standardizedFileURL.path == rootCaches)

        try? fm.removeItem(at: base)
        print("\nRESULT: \(pass) passed, \(fail) failed")
        exit(fail == 0 ? 0 : 1)
    }
}