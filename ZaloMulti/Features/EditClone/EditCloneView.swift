// EditCloneView.swift
// ZaloMulti
//
// Sheet chỉnh sửa thông tin clone.
// Rebuild v2.1 — @Environment(\.dismiss) + @EnvironmentObject.

import SwiftUI

struct EditCloneView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var store: CloneStore = CloneStore.shared
    
    let clone: CloneAccount
    
    private enum Field: Hashable {
        case name
        case phone
    }
    
    @FocusState private var focusedField: Field?
    @State private var name: String
    @State private var phoneNumber: String
    
    init(clone: CloneAccount) {
        self.clone = clone
        _name = State(initialValue: clone.name)
        _phoneNumber = State(initialValue: clone.phoneNumber)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Chỉnh sửa — \(clone.name)")
                    .font(.headline)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    GroupBox("Thông tin tài khoản") {
                        VStack(alignment: .leading, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Tên hiển thị")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                TextField("VD: Business, Shop Online...", text: $name)
                                    .textFieldStyle(.roundedBorder)
                                    .focused($focusedField, equals: .name)
                                    .id("edit_clone_name_field")
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Số điện thoại")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                TextField("0901234567", text: $phoneNumber)
                                    .textFieldStyle(.roundedBorder)
                                    .focused($focusedField, equals: .phone)
                                    .id("edit_clone_phone_field")
                            }
                        }
                        .padding(8)
                    }
                    
                    GroupBox("Chi tiết Clone") {
                        VStack(alignment: .leading, spacing: 8) {
                            InfoRow(label: "Bundle ID", value: clone.bundleID)
                            InfoRow(label: "Đường dẫn App", value: clone.appPath)
                            InfoRow(label: "Thư mục Data", value: clone.dataPath)
                            InfoRow(label: "Ngày tạo", value: clone.createdAt.formatted(date: .abbreviated, time: .shortened))
                            if let lastOpened = clone.lastOpenedAt {
                                InfoRow(label: "Mở lần cuối", value: lastOpened.formatted(date: .abbreviated, time: .shortened))
                            }
                        }
                        .padding(8)
                    }
                }
                .padding()
            }
            
            Divider()
            
            HStack {
                Spacer()
                Button("Huỷ") { dismiss() }
                Button("Lưu") { saveChanges() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return)
            }
            .padding()
        }
        .frame(width: 480, height: 420)
    }
    
    private func saveChanges() {
        var updated = clone
        updated.name = name
        updated.phoneNumber = phoneNumber
        store.updateClone(updated)
        dismiss()
    }
}

// MARK: - Info Row
struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .trailing)
            
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
            
            Spacer()
        }
    }
}
