import Foundation

/// 磁盘清理：清空用户废纸篓 + 用户缓存目录（~/.Trash、~/Library/Caches）。
/// 均为删除类操作，UI 层必须二次确认后才调用 `run`。
enum Cleaner {
    static func defaultTrash() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".Trash", isDirectory: true)
    }

    static func defaultCache() -> URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    }

    /// 目录占用总字节数（含子项 allocated size；无权限/不存在返回 0）。
    static func folderSize(_ url: URL) -> Int64 {
        guard let en = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .totalFileAllocatedSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in en {
            let v = try? file.resourceValues(forKeys: [.fileSizeKey, .totalFileAllocatedSizeKey])
            if let sz = v?.totalFileAllocatedSize ?? v?.fileSize { total += Int64(sz) }
        }
        return total
    }

    /// 待回收字节数（废纸篓 + 用户缓存）。
    static func reclaimableBytes(trash: URL = Cleaner.defaultTrash(),
                                 caches: URL = Cleaner.defaultCache()) -> Int64 {
        folderSize(trash) + folderSize(caches)
    }

    /// 删除目录下全部内容（目录本身保留），忽略无权删除的项。
    static func removeContents(of url: URL) {
        let fm = FileManager.default
        let items = (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
        for item in items { try? fm.removeItem(at: item) }
    }

    /// 执行清理，返回本次释放的字节数。目录保持不变，仅清空内容。
    @discardableResult
    static func run(trash: URL = Cleaner.defaultTrash(),
                    caches: URL = Cleaner.defaultCache()) -> Int64 {
        let before = reclaimableBytes(trash: trash, caches: caches)
        removeContents(of: trash)
        removeContents(of: caches)
        let after = reclaimableBytes(trash: trash, caches: caches)
        return Swift.max(0, before - after)
    }

    // MARK: - 分类清理（一键清理）

    /// 清理结果
    struct CleanResult {
        let freedBytes: Int64
        let removedItems: Int
        let skippedGitProtected: Int
    }

    /// 把目录内容移入废纸篓（不是永久删除），目录本身保留。
    /// 废纸篓自身不调用此函数——清空废纸篓必须走 `removeContents` 永久删除。
    static func moveContentsToTrash(_ url: URL,
                                    fileManager: FileManager = .default) -> Int {
        let items = (try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
        var moved = 0
        for item in items {
            do {
                var resulting: NSURL?
                try fileManager.trashItem(at: item, resultingItemURL: &resulting)
                moved += 1
            } catch {
                // 占用中/无权限的项跳过，不中断整批
                continue
            }
        }
        return moved
    }

    /// 按分类一键清理。
    /// - Parameters:
    ///   - categories: 用户选中的分类（manual 会被强制跳过）
    ///   - home: 用户目录（测试时注入临时目录）
    ///   - trash: 真正的废纸篓（移入目标）
    /// - Returns: 释放字节数、清理项数、被 Git 保护跳过的目录数
    @discardableResult
    static func clean(categories: [CleanCategory],
                      home: URL = FileManager.default.homeDirectoryForCurrentUser,
                      trash: URL = Cleaner.defaultTrash()) -> CleanResult {
        let targets = CleanRules.resolvedItems(for: categories, home: home)
        var before: Int64 = 0
        var after: Int64 = 0
        var moved = 0

        for url in targets {
            let size = folderSize(url)
            before += size
            // 废纸篓自身：永久清空；其余：移入废纸篓
            if url.standardizedFileURL.path == trash.standardizedFileURL.path {
                removeContents(of: url)
            } else {
                moved += moveContentsToTrash(url)
            }
            after += folderSize(url)
        }
        return CleanResult(freedBytes: Swift.max(0, before - after),
                           removedItems: moved,
                           skippedGitProtected: 0)
    }
}