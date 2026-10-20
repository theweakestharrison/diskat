import Darwin

/// Một mục trả về từ getattrlistbulk. Tên chỉ được chuyển thành String khi cần
/// (không cấp phát chuỗi cho từng file nhỏ).
struct RawEntry {
    let namePointer: UnsafePointer<CChar>
    let type: UInt32
    /// Mount point hoặc điểm kích hoạt automount: không đi vào.
    let isMountPoint: Bool
    /// Dung lượng thực chiếm trên đĩa (mọi fork). File iCloud chưa tải về có giá trị 0.
    let allocatedSize: Int64
    let linkCount: UInt32
    let fileID: UInt64
    let modified: Double

    var isDirectory: Bool { type == VDIR.rawValue }
    var isRegularFile: Bool { type == VREG.rawValue }
    var name: String { String(cString: namePointer) }
}

/// Liệt kê thư mục bằng getattrlistbulk: một lời gọi hệ thống trả về tên, loại, dung lượng, thời gian
/// của hàng trăm mục cùng lúc (không cần stat từng file). Mỗi luồng dùng một DirLister riêng.
final class DirLister {
    private static let bufferSize = 256 * 1024
    private let buffer = UnsafeMutableRawPointer.allocate(byteCount: DirLister.bufferSize, alignment: 16)

    deinit { buffer.deallocate() }

    private static let common = attrgroup_t(ATTR_CMN_RETURNED_ATTRS) | attrgroup_t(ATTR_CMN_NAME)
        | attrgroup_t(ATTR_CMN_ERROR) | attrgroup_t(ATTR_CMN_OBJTYPE) | attrgroup_t(ATTR_CMN_MODTIME)
        | attrgroup_t(ATTR_CMN_FILEID)
    private static let dirAttrs = attrgroup_t(ATTR_DIR_MOUNTSTATUS)
    private static let fileAttrs = attrgroup_t(ATTR_FILE_LINKCOUNT) | attrgroup_t(ATTR_FILE_ALLOCSIZE)
    private static let mountMask = UInt32(DIR_MNTSTATUS_MNTPOINT) | UInt32(DIR_MNTSTATUS_TRIGGER)

    /// Gọi `body` cho từng mục trong thư mục. Trả về 0 nếu đọc trọn vẹn, ngược lại errno
    /// (các mục đã đọc được trước lỗi vẫn được trả về).
    @discardableResult
    func list(_ path: String, _ body: (RawEntry) -> Void) -> Int32 {
        // O_NOFOLLOW: thư mục bị thay bằng symlink giữa chừng sẽ không bị đi theo
        let fd = open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        if fd < 0 { return errno }
        defer { close(fd) }

        var attrs = attrlist()
        attrs.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        attrs.commonattr = Self.common
        attrs.dirattr = Self.dirAttrs
        attrs.fileattr = Self.fileAttrs

        while true {
            let count = getattrlistbulk(fd, &attrs, buffer, Self.bufferSize, 0)
            if count < 0 { return errno }
            if count == 0 { return 0 }

            var entry = buffer
            for _ in 0..<count {
                let length = Int(entry.loadUnaligned(as: UInt32.self))
                defer { entry += length }

                // Thứ tự trong bộ đệm: độ dài, các thuộc tính trả về, lỗi, rồi các thuộc tính theo thứ tự bit
                var field = entry + 4
                let returned = field.loadUnaligned(as: attribute_set_t.self)
                field += MemoryLayout<attribute_set_t>.size

                if returned.commonattr & attrgroup_t(ATTR_CMN_ERROR) != 0 {
                    let err = field.loadUnaligned(as: UInt32.self)
                    field += 4
                    if err != 0 { continue }
                }

                guard returned.commonattr & attrgroup_t(ATTR_CMN_NAME) != 0 else { continue }
                let nameRef = field.loadUnaligned(as: attrreference_t.self)
                let namePointer = UnsafePointer((field + Int(nameRef.attr_dataoffset)).assumingMemoryBound(to: CChar.self))
                field += MemoryLayout<attrreference_t>.size

                var type: UInt32 = 0
                if returned.commonattr & attrgroup_t(ATTR_CMN_OBJTYPE) != 0 {
                    type = field.loadUnaligned(as: UInt32.self)
                    field += 4
                }

                var modified = 0.0
                if returned.commonattr & attrgroup_t(ATTR_CMN_MODTIME) != 0 {
                    let sec = field.loadUnaligned(as: Int.self)
                    let nsec = field.loadUnaligned(fromByteOffset: 8, as: Int.self)
                    modified = Double(sec) + Double(nsec) / 1_000_000_000
                    field += MemoryLayout<timespec>.size
                }

                var fileID: UInt64 = 0
                if returned.commonattr & attrgroup_t(ATTR_CMN_FILEID) != 0 {
                    fileID = field.loadUnaligned(as: UInt64.self)
                    field += 8
                }

                var isMount = false
                if returned.dirattr & attrgroup_t(ATTR_DIR_MOUNTSTATUS) != 0 {
                    isMount = field.loadUnaligned(as: UInt32.self) & Self.mountMask != 0
                    field += 4
                }

                var links: UInt32 = 1
                if returned.fileattr & attrgroup_t(ATTR_FILE_LINKCOUNT) != 0 {
                    links = field.loadUnaligned(as: UInt32.self)
                    field += 4
                }

                var allocated: Int64 = 0
                if returned.fileattr & attrgroup_t(ATTR_FILE_ALLOCSIZE) != 0 {
                    allocated = field.loadUnaligned(as: Int64.self)
                    field += 8
                }

                body(RawEntry(namePointer: namePointer, type: type, isMountPoint: isMount,
                              allocatedSize: allocated, linkCount: links, fileID: fileID, modified: modified))
            }
        }
    }
}
