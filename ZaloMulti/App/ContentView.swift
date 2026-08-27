// ContentView.swift
// ZaloMulti
//
// Layout tổng thể: Main Content (trái) + Sidebar (phải)
// Rebuild v2.1 — @EnvironmentObject pattern.

import SwiftUI

struct ContentView: View {
    @ObservedObject var cloneStore: CloneStore
    @State private var showSidebar = true
    
    var body: some View {
        HStack(spacing: 0) {
            // LEFT: Main Dashboard
            VStack(spacing: 0) {
                NotificationBarView()
                DashboardView()
            }
            .frame(maxWidth: .infinity)
            
            if showSidebar {
                Rectangle()
                    .fill(Color(nsColor: .separatorColor))
                    .frame(width: 1)
                
                SidebarView()
                    .frame(width: 240)
                    .transition(.move(edge: .trailing))
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showSidebar.toggle()
                    }
                } label: {
                    Image(systemName: "sidebar.right")
                }
                .help("Ẩn/Hiện thanh bên")
            }
        }
        .sheet(isPresented: $cloneStore.showAddCloneSheet) {
            AddCloneView()
                .environmentObject(cloneStore)
        }
        .alert("Lỗi", isPresented: $cloneStore.showError) {
            Button("OK") { cloneStore.showError = false }
        } message: {
            Text(cloneStore.errorMessage ?? "Đã xảy ra lỗi không xác định")
        }
    }
}
