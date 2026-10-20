import SwiftUI
import DiskatCore

/// Hộp xác nhận xóa. Với xóa vĩnh viễn, nút mặc định (Return) là "Hủy" để tránh bấm nhầm.
struct ConfirmSheet: View {
    let request: ConfirmRequest

    private var tint: Color { request.permanent ? Theme.danger : Theme.amber }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(tint.opacity(0.15))
                    Image(systemName: "trash")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(tint)
                }
                .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(Loc.f(request.permanent ? "ConfirmPermTitle" : "ConfirmTrashTitle", request.what))
                        .font(.system(size: 15, weight: .semibold))
                    Text(Loc.t(request.permanent ? "ConfirmPermSub" : "ConfirmTrashSub"))
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                ScrollView {
                    Text(request.path)
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 110)
                .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 0) {
                    Text(Loc.t("ConfirmSize")).foregroundStyle(.secondary)
                    Text(request.size).fontWeight(.semibold)
                    if !request.detail.isEmpty {
                        Text(request.detail).foregroundStyle(.secondary).padding(.leading, 14)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
            .padding(.top, 18)

            if let warning = request.warning {
                Notice(text: warning, color: Theme.amber, bold: false)
            }
            if request.permanent {
                Notice(text: Loc.t("ConfirmWarn"), color: Theme.danger, bold: true)
            }

            HStack(spacing: 10) {
                Spacer()
                if request.permanent {
                    Button(Loc.t("Cancel")) { request.resolve(false) }
                        .keyboardShortcut(.defaultAction)
                    Button(Loc.t("BtnDeletePerm")) { request.resolve(true) }
                        .tint(Theme.danger)
                        .buttonStyle(.bordered)
                        .foregroundStyle(Theme.danger)
                } else {
                    Button(Loc.t("Cancel")) { request.resolve(false) }
                        .keyboardShortcut(.cancelAction)
                    Button(Loc.t("BtnTrash")) { request.resolve(true) }
                        .keyboardShortcut(.defaultAction)
                        .tint(Theme.danger)
                        .buttonStyle(.borderedProminent)
                }
            }
            .controlSize(.large)
            .padding(.top, 22)

            // Esc luôn là Hủy (kể cả khi Return đã gán cho nút Hủy)
            if request.permanent {
                Button("") { request.resolve(false) }
                    .keyboardShortcut(.cancelAction)
                    .opacity(0)
                    .frame(width: 0, height: 0)
            }
        }
        .padding(24)
        .frame(width: 500)
        .onDisappear { request.resolve(false) }
    }
}

private struct Notice: View {
    let text: String
    let color: Color
    let bold: Bool

    var body: some View {
        Text(text)
            .fontWeight(bold ? .semibold : .regular)
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 8).fill(color.opacity(0.12)))
            .padding(.top, 12)
    }
}
