// SidebarView.swift
// ZaloMulti
//
// Sidebar bên phải — buttons, social links, stats.
// Rebuild v2.1 — @EnvironmentObject pattern.

import SwiftUI

struct SidebarView: View {
    @ObservedObject var store: CloneStore = CloneStore.shared
    
    var body: some View {
        VStack(spacing: 0) {
            // Thông báo riêng tư
            PrivateNotificationListView()
            
            Divider()
            
            // Đóng tất cả Clone
            Button(action: { store.stopAllClones() }) {
                Label("Đóng tất cả Clone", systemImage: "xmark.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .controlSize(.large)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            
            Divider()
            
            // Footer Stats
            SidebarFooterView()
                .padding()
            
            Divider()
            
            // Social Icons
            SocialLinksView()
                .padding(.vertical, 10)
        }
        .background(.ultraThinMaterial)
    }
}

// MARK: - Social Links
struct SocialLinksView: View {
    private struct SocialItem {
        let name: String
        let urlAccessor: () -> String
        let imageName: String
        let systemIcon: String?
        let iconColor: Color?
        let bgColor: Color?
    }
    
    private let items: [SocialItem] = [
        SocialItem(name: "Messenger", urlAccessor: { SecureConfig.socialMessenger },
                   imageName: "logo-messenger", systemIcon: nil, iconColor: nil, bgColor: nil),
        SocialItem(name: "Telegram", urlAccessor: { SecureConfig.socialTelegram },
                   imageName: "", systemIcon: "paperplane.fill", iconColor: .white, bgColor: Color(hex: "#26A5E4")),
        SocialItem(name: "Zalo", urlAccessor: { SecureConfig.socialZalo },
                   imageName: "logo-zalo", systemIcon: nil, iconColor: nil, bgColor: nil),
        SocialItem(name: "Ủng hộ tác giả", urlAccessor: { SecureConfig.socialDonate },
                   imageName: "logo-donate", systemIcon: nil, iconColor: nil, bgColor: nil)
    ]
    
    var body: some View {
        HStack(spacing: 12) {
            ForEach(items.indices, id: \.self) { index in
                let item = items[index]
                if let url = URL(string: item.urlAccessor()) {
                    Link(destination: url) {
                        if let systemIcon = item.systemIcon {
                            Image(systemName: systemIcon)
                                .font(.system(size: 13))
                                .foregroundColor(item.iconColor ?? .white)
                                .frame(width: 28, height: 28)
                                .background(item.bgColor ?? .clear)
                                .clipShape(RoundedRectangle(cornerRadius: 7))
                        } else {
                            Image(item.imageName)
                                .renderingMode(.original)
                                .resizable()
                                .interpolation(.high)
                                .antialiased(true)
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 28, height: 28)
                                .clipShape(RoundedRectangle(cornerRadius: 7))
                        }
                    }
                    .buttonStyle(.plain)
                    .help(item.name)
                }
            }
        }
    }
}

// MARK: - Footer Stats
struct SidebarFooterView: View {
    @ObservedObject var store: CloneStore = CloneStore.shared
    
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 5) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)
                Text("Phiên bản v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.1")")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }
            
            HStack(spacing: 0) {
                VStack {
                    Text("\(store.runningCount)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.accentColor)
                        .contentTransition(.numericText())
                    Text("đang mở")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                
                Divider().frame(height: 30)
                
                VStack {
                    Text("\(store.totalCount)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .contentTransition(.numericText())
                    Text("tổng clone")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
            
            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.secondary.opacity(0.2))
                        .frame(height: 4)
                    
                    RoundedRectangle(cornerRadius: 2)
                        .fill(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .frame(
                            width: store.totalCount == 0 ? 0 :
                                geo.size.width * CGFloat(store.runningCount) / CGFloat(max(store.totalCount, 1)),
                            height: 4
                        )
                        .animation(.spring(), value: store.runningCount)
                }
            }
            .frame(height: 4)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .windowBackgroundColor))
                .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
        )
    }
}
