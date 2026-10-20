import AppKit
import DiskatCore

/// Menu "Thêm" (⋯): giao diện sáng / tối, kiểm tra cập nhật, giới thiệu (tương ứng MainWindow.Extras.cs).
extension AppModel {
    // ================= Giao diện =================

    func setTheme(_ value: AppTheme) {
        theme = value
        Settings.theme = value
        applyTheme()
    }

    /// Theo hệ thống, luôn sáng hoặc luôn tối. Màu bản đồ đổi theo (TreemapView.viewDidChangeEffectiveAppearance).
    func applyTheme() {
        switch theme {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    // ================= Giới thiệu =================

    func showAbout() {
        let credits = NSMutableAttributedString(string: Loc.t("AboutText") + "\n", attributes: [
            .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor,
        ])
        credits.append(NSAttributedString(string: "diskat.cc", attributes: [
            .font: NSFont.systemFont(ofSize: 11), .link: URL(string: "https://diskat.cc")!,
        ]))
        let center = NSMutableParagraphStyle()
        center.alignment = .center
        credits.addAttribute(.paragraphStyle, value: center, range: NSRange(location: 0, length: credits.length))
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits, .applicationName: "Diskat"])
        NSApp.activate(ignoringOtherApps: true)
    }

    // ================= Cập nhật =================

    /// Gọi khi cửa sổ đã mở: kiểm tra tự động tối đa một lần mỗi ngày, chỉ khi người dùng bật.
    func maybeCheckForUpdatesOnStartup() {
        guard Settings.checkForUpdatesOnStartup else { return }
        if let last = Settings.lastUpdateCheck, Date().timeIntervalSince(last) < 20 * 3600 { return }
        Task { await checkForUpdates(userInitiated: false) }
    }

    /// userInitiated = false: lần kiểm tra tự động lúc mở app, khi đó không báo gì nếu đang ở bản mới nhất
    /// hoặc không có mạng.
    func checkForUpdates(userInitiated: Bool) async {
        guard !checkingUpdates else { return }
        checkingUpdates = true
        defer { checkingUpdates = false }
        let previous = status
        if userInitiated { setStatus { Loc.t("UpdChecking") } }

        let info: UpdateInfo?
        do {
            info = try await Updater.check()
            if userInitiated { setStatus(previous) }
        } catch {
            if userInitiated {
                setStatus(previous)
                await Dialogs.alert(Loc.f("UpdCheckFailed", error.localizedDescription), style: .warning)
            }
            return
        }
        guard let info else {
            if userInitiated { await Dialogs.alert(Loc.f("UpdUpToDate", Updater.currentVersion)) }
            return
        }

        let answer = await Dialogs.alert(Loc.t("UpdTitle"), detail: Loc.f("UpdMessage", info.version, Updater.currentVersion),
                                         buttons: [Loc.t("UpdNow"), Loc.t("UpdNotes"), Loc.t("UpdLater")])
        if answer == .alertSecondButtonReturn {
            NSWorkspace.shared.open(info.notes ?? URL(string: "https://diskat.cc/changelog")!)
            return
        }
        guard answer == .alertFirstButtonReturn else { return }

        // Máy chủ chưa công bố mã băm: mở trang tải trong trình duyệt thay vì tải mà không kiểm tra được
        guard info.sha256 != nil else {
            NSWorkspace.shared.open(info.url)
            return
        }
        busyText = Loc.f("UpdDownloading", 0.0)
        do {
            let dmg = try await Updater.download(info) { fraction in
                Task { @MainActor in
                    if AppModel.shared.busyText != nil { AppModel.shared.busyText = Loc.f("UpdDownloading", fraction * 100) }
                }
            }
            busyText = nil
            NSWorkspace.shared.open(dmg)
            await Dialogs.alert(Loc.f("UpdReady", info.version))
        } catch {
            busyText = nil
            await Dialogs.alert(Loc.f("UpdFailed", error.localizedDescription), style: .warning)
        }
    }
}
