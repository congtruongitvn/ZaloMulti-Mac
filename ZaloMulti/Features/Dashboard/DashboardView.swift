// DashboardView.swift
// ZaloMulti
//
// Grid 2 cột hiển thị các clone cards + nút thêm tài khoản.
// Rebuild v2.1 — @EnvironmentObject + Button thay vì onTapGesture.

import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var store: CloneStore
    
    let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]
    
    var body: some View {
        ScrollView {
            // Section header
            HStack {
                Text("TÀI KHOẢN CLONE")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.5)
                
                Spacer()
                
                Text("\(store.totalCount)/\(CloneStore.maxClones) tài khoản")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(store.canAddMore ? .accentColor : .orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background((store.canAddMore ? Color.accentColor : Color.orange).opacity(0.12))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(store.clones) { clone in
                    CloneCardView(clone: clone)
                }
                
                // Nút thêm clone — chỉ hiện khi chưa đạt giới hạn
                if store.canAddMore {
                    AddCloneCardView {
                        store.showAddCloneSheet = true
                    }
                } else {
                    MaxClonesReachedView()
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
            .animation(.spring(response: 0.3), value: store.clones.count)
        }
    }
}

// MARK: - Add Clone Card (Nút "Thêm tài khoản")
struct AddCloneCardView: View {
    @State private var isHovered = false
    var action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(isHovered ? Color.accentColor : Color(nsColor: .separatorColor).opacity(0.3))
                        .frame(width: 36, height: 36)
                    
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(isHovered ? .white : .secondary)
                }
                
                Text("Thêm tài khoản")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(isHovered ? .accentColor : .secondary)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 130)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(nsColor: .windowBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(
                                isHovered ? Color.accentColor.opacity(0.5) : Color.secondary.opacity(0.15),
                                style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                            )
                    )
            )
            .shadow(color: .black.opacity(isHovered ? 0.08 : 0.04), radius: isHovered ? 8 : 4, y: 2)
            .scaleEffect(isHovered ? 1.01 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

// MARK: - Max Clones Reached (Hiển thị khi đã đạt giới hạn 4 TK)
struct MaxClonesReachedView: View {
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.15))
                    .frame(width: 36, height: 36)
                
                Image(systemName: "lock.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.orange)
            }
            
            Text("Đã đạt giới hạn")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
            
            Text("Tối đa \(CloneStore.maxClones) tài khoản")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 130)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.6))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.orange.opacity(0.2), lineWidth: 1)
                )
        )
    }
}
