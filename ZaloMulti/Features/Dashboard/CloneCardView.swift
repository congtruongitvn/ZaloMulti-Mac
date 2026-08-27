// CloneCardView.swift
// ZaloMulti
//
// Card hiển thị thông tin một clone account — với avatar + display_name.
// Rebuild v2.1 — @EnvironmentObject, proper state management.

import SwiftUI

struct CloneCardView: View {
    let clone: CloneAccount
    @ObservedObject var store: CloneStore = CloneStore.shared
    @State private var showDeleteConfirm = false
    @State private var showEditSheet = false
    @State private var isHovered = false
    @State private var avatarImage: NSImage?
    @State private var displayName: String?
    
    var statusColor: Color {
        switch clone.status {
        case .running:  return .green
        case .paused:   return .orange
        case .stopped:  return .secondary
        case .creating: return .blue
        }
    }
    
    var statusGradient: [Color] {
        switch clone.status {
        case .running:  return [.green, .mint]
        case .paused:   return [.orange, .yellow]
        case .stopped:  return [.gray, .secondary]
        case .creating: return [.blue, .cyan]
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header: Avatar + Info + Status
            HStack(spacing: 12) {
                // Avatar
                ZStack(alignment: .bottomTrailing) {
                    if let avatar = avatarImage {
                        Image(nsImage: avatar)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 44, height: 44)
                            .clipShape(Circle())
                    } else {
                        let gradient = Color.avatarGradient(for: clone.cloneIndex)
                        Circle()
                            .fill(LinearGradient(
                                colors: [gradient.0, gradient.1],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ))
                            .frame(width: 44, height: 44)
                            .overlay(
                                Text(String(clone.name.prefix(1)).uppercased())
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(.white)
                            )
                    }
                    
                    Circle()
                        .fill(statusColor)
                        .frame(width: 12, height: 12)
                        .overlay(
                            Circle()
                                .stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 2)
                        )
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(displayName ?? clone.name)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                    
                    HStack(spacing: 4) {
                        Image(systemName: "iphone")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(clone.phoneNumber.isEmpty ? "Chưa có SĐT" : clone.phoneNumber)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                // Status badge
                Text(clone.status.displayName)
                    .font(.system(size: 11, weight: .bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: statusGradient.map { $0.opacity(0.15) },
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    )
                    .foregroundColor(statusColor)
            }
            .padding(14)
            
            Divider()
                .padding(.horizontal, 14)
            
            // Footer: Meta + Actions
            HStack(spacing: 6) {
                if clone.status == .running, let pid = clone.processID {
                    HStack(spacing: 3) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 5, height: 5)
                        Text("PID \(pid)")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Label("clone-0\(clone.cloneIndex)", systemImage: "app.badge")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                
                Spacer()
                
                // Launch/Stop
                CardActionButton(
                    title: clone.status == .running ? "Dừng" : "Chạy",
                    icon: clone.status == .running ? "stop.fill" : "play.fill",
                    tint: clone.status == .running ? .red : .accentColor,
                    isPrimary: true
                ) {
                    if clone.status == .running {
                        store.stopClone(clone)
                    } else {
                        store.launchClone(clone)
                    }
                }
                
                // Edit
                CardActionButton(title: nil, icon: "pencil", tint: .secondary) {
                    showEditSheet = true
                }
                
                // Delete
                CardActionButton(title: nil, icon: "trash", tint: .red) {
                    showDeleteConfirm = true
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(
                    clone.status == .running
                    ? Color.green.opacity(isHovered ? 0.6 : 0.4)
                    : Color.secondary.opacity(0.15),
                    lineWidth: 1
                )
        )
        .shadow(
            color: clone.status == .running
                ? Color.green.opacity(isHovered ? 0.2 : 0)
                : Color.black.opacity(isHovered ? 0.1 : 0.03),
            radius: isHovered ? 8 : 3,
            y: isHovered ? 4 : 1
        )
        .scaleEffect(isHovered ? 1.01 : 1.0)
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .onHover { isHovered = $0 }
        .onAppear { loadAvatar() }
        .onChange(of: clone.status) { _, newStatus in
            if newStatus == .running {
                DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
                    AvatarExtractor.clearCache(cloneIndex: clone.cloneIndex)
                    loadAvatar()
                }
            }
        }
        .sheet(isPresented: $showEditSheet) {
            EditCloneView(clone: clone)
                .environmentObject(store)
        }
        .confirmationDialog(
            "Xoá Clone \"\(clone.name)\"?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Xoá", role: .destructive) { store.deleteClone(clone) }
            Button("Huỷ", role: .cancel) {}
        } message: {
            Text("Hành động này sẽ xoá toàn bộ dữ liệu của clone này và không thể hoàn tác.")
        }
    }
    
    private func loadAvatar() {
        AvatarExtractor.loadProfile(cloneIndex: clone.cloneIndex) { profile, image in
            if let image = image {
                withAnimation(.easeIn(duration: 0.3)) { avatarImage = image }
            } else {
                avatarImage = nil
            }
            if let name = profile?.displayName, !name.isEmpty {
                displayName = name
            } else {
                displayName = nil
            }
        }
    }
}

// MARK: - Card Action Button
struct CardActionButton: View {
    var title: String?
    let icon: String
    var tint: Color = .accentColor
    var isPrimary: Bool = false
    let action: () -> Void
    
    @State private var isHovered = false
    @State private var isPressed = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                if let title = title {
                    Text(title)
                        .font(.system(size: 11, weight: .semibold))
                }
            }
            .padding(.horizontal, title != nil ? 10 : 6)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(
                        isPrimary
                            ? AnyShapeStyle(tint)
                            : AnyShapeStyle(tint.opacity(isHovered ? 0.2 : 0.1))
                    )
            )
            .foregroundColor(isPrimary ? .white : tint)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(
                        isPrimary ? .clear : tint.opacity(isHovered ? 0.4 : 0.2),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(isPressed ? 0.92 : (isHovered ? 1.06 : 1.0))
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .animation(.easeOut(duration: 0.1), value: isPressed)
        .onHover { isHovered = $0 }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}
