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
}