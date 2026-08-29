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
        ZStack {
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
            
            // Custom In-Window Modal Overlay for Add Clone (100% immune to macOS sheet re-render bugs)
            if cloneStore.showAddCloneSheet {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .onTapGesture {
                        if !cloneStore.engine.isProcessing {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                cloneStore.showAddCloneSheet = false
                            }
                        }
                    }
                
                AddCloneView(isPresented: $cloneStore.showAddCloneSheet)
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
                    .zIndex(100)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: cloneStore.showAddCloneSheet)
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
        .alert("Lỗi", isPresented: $cloneStore.showError) {
            Button("OK") { cloneStore.showError = false }
        } message: {
            Text(cloneStore.errorMessage ?? "Đã xảy ra lỗi không xác định")
        }
    }
}
