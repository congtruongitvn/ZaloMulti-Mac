// AddCloneView.swift
// ZaloMulti
//
// Sheet thêm tài khoản clone mới — với progress bar inline.
// Rebuild v2.1 — @Environment(\.dismiss) + @EnvironmentObject.

import SwiftUI

struct AddCloneView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var store: CloneStore
    
    private enum Field: Hashable {
        case name
        case phone
    }
    
    @FocusState private var focusedField: Field?
    @State private var name = ""
    @State private var phoneNumber = ""
    @State private var isCreating = false
    @State private var createComplete = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Thêm tài khoản Clone")
                    .font(.headline)
                Spacer()
                Button(action: closeForm) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(isCreating)
            }
            .padding()
            
            Divider()
            
            // Content Form (Không dùng ScrollView để tránh lỗi auto-scroll mất focus/viewport trên macOS)
            VStack(alignment: .leading, spacing: 16) {
                GroupBox("Thông tin tài khoản") {
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Tên hiển thị")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextField("VD: Business, Shop Online...", text: $name)
                                .textFieldStyle(.roundedBorder)
                                .focused($focusedField, equals: .name)
                                .id("add_clone_name_field")
                                .onSubmit { focusedField = .phone }
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Số điện thoại")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextField("0901234567", text: $phoneNumber)
                                .textFieldStyle(.roundedBorder)
                                .focused($focusedField, equals: .phone)
                                .id("add_clone_phone_field")
                                .onSubmit {
                                    if !name.isEmpty && !isCreating && store.canAddMore {
                                        createClone()
                                    }
                                }
                        }
                        
                        // Progress bar
                        if isCreating {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text(store.engine.progressMessage)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                
                                ProgressView(value: progressValue)
                                    .progressViewStyle(.linear)
                                    .tint(.accentColor)
                                
                                Text(progressStep)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.top, 4)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                        
                        if createComplete {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("Tạo clone thành công!")
                                    .font(.caption)
                                    .foregroundColor(.green)
                                    .fontWeight(.semibold)
                            }
                            .padding(.top, 4)
                            .transition(.opacity)
                        }
                    }
                    .padding(10)
                }
            }
            .padding(16)
            
            Spacer()
            
            Divider()
            
            // Footer
            HStack {
                Spacer()
                Button("Huỷ", action: closeForm)
                    .keyboardShortcut(.escape)
                    .disabled(isCreating)
                Button(createComplete ? "Đóng" : "Tạo Clone") {
                    if createComplete {
                        closeForm()
                    } else {
                        createClone()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isCreating || !store.canAddMore)
                .keyboardShortcut(.return)
            }
            .padding()
        }
        .frame(width: 460, height: 350)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                focusedField = .name
            }
        }
    }
    
    private func closeForm() {
        store.showAddCloneSheet = false
        dismiss()
    }
    
    private var progressStep: String {
        let msg = store.engine.progressMessage
        if msg.contains("chuẩn bị") { return "Bước 1/7 — Đang chuẩn bị..." }
        if msg.contains("thư mục") { return "Bước 1/7 — Tạo thư mục dữ liệu" }
        if msg.contains("Sao chép") { return "Bước 2/7 — Sao chép ứng dụng Zalo" }
        if msg.contains("Bundle") { return "Bước 3/7 — Đổi Bundle Identifier" }
        if msg.contains("Socket") || msg.contains("asar") { return "Bước 4/7 — Vá Socket cách ly" }
        if msg.contains("wrapper") || msg.contains("launcher") { return "Bước 5/7 — Tạo launcher wrapper" }
        if msg.contains("quarantine") { return "Bước 6/7 — Xoá quarantine" }
        if msg.contains("sign") || msg.contains("Re-sign") { return "Bước 7/7 — Ký mã ứng dụng" }
        if msg.contains("Hoàn thành") { return "✅ Hoàn thành!" }
        return "Đang xử lý..."
    }
    
    private var progressValue: Double {
        let msg = store.engine.progressMessage
        if msg.contains("chuẩn bị") { return 0.05 }
        if msg.contains("thư mục") { return 1.0/7.0 }
        if msg.contains("Sao chép") { return 2.0/7.0 }
        if msg.contains("Bundle") { return 3.0/7.0 }
        if msg.contains("Socket") || msg.contains("asar") { return 4.0/7.0 }
        if msg.contains("wrapper") || msg.contains("launcher") { return 5.0/7.0 }
        if msg.contains("quarantine") { return 6.0/7.0 }
        if msg.contains("sign") || msg.contains("Re-sign") { return 6.5/7.0 }
        if msg.contains("Hoàn thành") { return 1.0 }
        return 0.02
    }
    
    private func createClone() {
        guard store.canAddMore else {
            store.errorMessage = "Đã đạt giới hạn tối đa \(CloneStore.maxClones) tài khoản."
            store.showError = true
            return
        }
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return }
        
        store.engine.progressMessage = "Đang chuẩn bị..."
        withAnimation { isCreating = true }
        
        Task {
            do {
                let nextIndex = (store.clones.map(\.cloneIndex).max() ?? 0) + 1
                let clone = try await store.engine.createClone(
                    index: nextIndex,
                    name: cleanName,
                    phone: phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                store.clones.append(clone)
                store.saveClones()
                withAnimation {
                    isCreating = false
                    createComplete = true
                }
                try? await Task.sleep(for: .seconds(1.2))
                closeForm()
            } catch {
                withAnimation { isCreating = false }
                store.errorMessage = error.localizedDescription
                store.showError = true
            }
        }
    }
}
