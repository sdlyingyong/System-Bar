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

        try? fm.removeItem(at: base)
        print("\nRESULT: \(pass) passed, \(fail) failed")
        exit(fail == 0 ? 0 : 1)
    }
}