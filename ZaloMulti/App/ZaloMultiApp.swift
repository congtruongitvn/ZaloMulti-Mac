// ZaloMultiApp.swift
// ZaloMulti
//
// Entry point (@main) — khởi tạo app với CloneStore và window config.
// Rebuild v2.1 — @StateObject + .environmentObject() theo zDesk-Pro.

import SwiftUI

@main
struct ZaloMultiApp: App {
    @StateObject private var cloneStore = CloneStore.shared
    @State private var showUpdateSheet = false
    
    init() {
        // Logger init (lazy — không phụ thuộc SecureConfig)
        DiagnosticLogger.info("APP", "ZaloMulti — khởi động")
        DiagnosticLogger.info("APP", "Log file: \(DiagnosticLogger.logFilePath)")
        
        // Detect Zalo source
        let zaloInfo = ZaloCloneEngine().detectSourceZalo()
        DiagnosticLogger.info("APP", "Zalo Desktop: installed=\(zaloInfo.installed), version=\(zaloInfo.version ?? "N/A")")
    }
    
    var body: some Scene {
        WindowGroup("Zalỏ - macOS") {
            ContentView(cloneStore: cloneStore)
                .environmentObject(cloneStore)
                .frame(minWidth: 860, minHeight: 560)
                .onAppear {
                    // Anti-tamper — gọi ở onAppear, KHÔNG ở init()
                    AntiTamper.initialize()
                    
                    // Migration
                    MigrationManager.shared.runMigrations()
                    MigrationManager.shared.cleanupOldVersionData()
                    
                    // Notification monitor
                    _ = NotificationMonitor.shared
                    
                    // Donate check (delay)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        DonateManager.checkAndPromptDonate()
                    }
                    
                    // Auto-update check (delay)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        if SettingsManager.shared.settings.checkUpdateOnStartup {
                            InAppUpdater.shared.checkForUpdates()
                        }
                    }
                }
                .onReceive(InAppUpdater.shared.$state) { newState in
                    if case .available = newState {
                        showUpdateSheet = true
                    }
                }
                .sheet(isPresented: $showUpdateSheet) {
                    UpdateProgressView(updater: InAppUpdater.shared)
                }
        }
        .windowToolbarStyle(.unified(showsTitle: true))
        .defaultSize(width: 1060, height: 680)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Thêm Clone Mới") {
                    cloneStore.showAddCloneSheet = true
                }
                .keyboardShortcut("n", modifiers: .command)
            }
            CommandGroup(after: .appInfo) {
                Button("Kiểm tra cập nhật...") {
                    InAppUpdater.shared.checkForUpdates(showUpToDatePrompt: true)
                    showUpdateSheet = true
                }
            }
            CommandMenu("Clone") {
                Button("Dừng tất cả") {
                    cloneStore.stopAllClones()
                }
                .keyboardShortcut("q", modifiers: [.command, .shift])
            }
        }
        
        Settings {
            SettingsView()
                .environmentObject(cloneStore)
        }
    }
}
