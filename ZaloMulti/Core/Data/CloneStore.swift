// CloneStore.swift
// ZaloMulti
//
// State management trung tâm — KHÔNG singleton.
// Được inject qua @EnvironmentObject từ App root.
//
// Rebuild v2.1 — theo kiến trúc zDesk-Pro.

import Foundation
import SwiftUI

@MainActor
final class CloneStore: ObservableObject {
    
    // MARK: - Singleton
    static let shared = CloneStore()
    
    // MARK: - Constants
    static let maxClones = 4
    
    // MARK: - Published Properties
    @Published var clones: [CloneAccount] = []
    @Published var showAddCloneSheet = false
    @Published var errorMessage: String?
    @Published var showError = false
    
    /// Kiểm tra còn slot trống không (tối đa 4 tài khoản)
    var canAddMore: Bool { clones.count < Self.maxClones }
    
    // MARK: - Dependencies
    let engine = ZaloCloneEngine()
    let processManager = ProcessManager()
    
    // MARK: - Persistence
    private let storageKey = "clone_accounts_v1"
    private var syncTimer: Timer?
    
    // MARK: - Init
    
    init() {
        DiagnosticLogger.info("STORE", "CloneStore khởi tạo...")
        loadClones()
        syncProcessStatus()
        DiagnosticLogger.info("STORE", "Đã load \(clones.count) clones từ storage")
        startSyncTimer()
    }
    
    
    // MARK: - Timer
    
    /// Timer sync trạng thái mỗi 3 giây — dùng kill(pid,0) O(1)
    private func startSyncTimer() {
        syncTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.syncRunningStatus()
            }
        }
    }
    
    // MARK: - CRUD
    
    /// Thêm clone mới
    func addClone(name: String, phone: String) {
        guard canAddMore else {
            errorMessage = "Đã đạt giới hạn tối đa \(Self.maxClones) tài khoản."
            showError = true
            DiagnosticLogger.warning("STORE", "addClone bị chặn: đã đạt giới hạn \(Self.maxClones) TK")
            return
        }
        let nextIndex = (clones.map(\.cloneIndex).max() ?? 0) + 1
        DiagnosticLogger.info("STORE", "addClone: name='\(name)', nextIndex=\(nextIndex)")
        
        Task {
            do {
                let clone = try await engine.createClone(
                    index: nextIndex,
                    name: name,
                    phone: phone
                )
                clones.append(clone)
                saveClones()
                DiagnosticLogger.success("STORE", "Clone '\(name)' đã thêm (total=\(clones.count))")
            } catch {
                errorMessage = error.localizedDescription
                showError = true
                DiagnosticLogger.error("STORE", "addClone thất bại", error: error)
            }
        }
    }
    
    /// Cập nhật thông tin clone
    func updateClone(_ updated: CloneAccount) {
        guard let index = clones.firstIndex(where: { $0.id == updated.id }) else { return }
        clones[index] = updated
        saveClones()
    }
    
    /// Xoá clone
    func deleteClone(_ clone: CloneAccount) {
        DiagnosticLogger.info("STORE", "deleteClone: '\(clone.name)'")
        
        if let pid = clone.processID, ProcessManager.isRunning(pid: pid) {
            processManager.stopClone(clone)
        }
        
        do {
            try engine.deleteClone(clone)
        } catch {
            errorMessage = "Lỗi xoá files: \(error.localizedDescription)"
            showError = true
        }
        
        clones.removeAll { $0.id == clone.id }
        saveClones()
    }
    
    // MARK: - Launch / Stop
    
    func launchClone(_ clone: CloneAccount) {
        guard let index = clones.firstIndex(where: { $0.id == clone.id }) else { return }
        
        do {
            let pid = try processManager.launchClone(clone)
            clones[index].status = .running
            clones[index].processID = pid
            clones[index].lastOpenedAt = Date()
            saveClones()
            DiagnosticLogger.success("STORE", "Clone '\(clone.name)' đang chạy — PID=\(pid)")
        } catch {
            if case CloneError.alreadyRunning = error {
                clones[index].status = .running
                saveClones()
            } else {
                errorMessage = error.localizedDescription
                showError = true
                DiagnosticLogger.error("STORE", "launchClone thất bại", error: error)
            }
        }
    }
    
    func stopClone(_ clone: CloneAccount) {
        guard let index = clones.firstIndex(where: { $0.id == clone.id }) else { return }
        processManager.stopClone(clone)
        clones[index].status = .stopped
        clones[index].processID = nil
        saveClones()
    }
    
    func stopAllClones() {
        DiagnosticLogger.info("STORE", "stopAllClones — \(clones.count) clones")
        
        for clone in clones where clone.status == .running {
            let script = "tell application id \"\(clone.bundleID)\" to quit"
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            proc.arguments = ["-e", script]
            proc.standardOutput = FileHandle.nullDevice
            proc.standardError = FileHandle.nullDevice
            try? proc.run()
        }
        
        processManager.stopAllClones()
        for i in clones.indices {
            clones[i].status = .stopped
            clones[i].processID = nil
        }
        saveClones()
    }
    
    // MARK: - Statistics
    
    var runningCount: Int { clones.filter { $0.status == .running }.count }
    var totalCount: Int { clones.count }
    
    // MARK: - Process Sync
    
    /// Đồng bộ trạng thái — dùng kill(pid,0) O(1) syscall
    private func syncRunningStatus() {
        var changed = false
        
        for i in clones.indices {
            let clone = clones[i]
            guard clone.status == .running else { continue }
            
            if let pid = clone.processID {
                if !ProcessManager.isRunning(pid: pid) {
                    clones[i].status = .stopped
                    clones[i].processID = nil
                    changed = true
                    DiagnosticLogger.info("SYNC", "'\(clone.name)' running→stopped (PID \(pid) exited)")
                }
            } else {
                clones[i].status = .stopped
                changed = true
            }
        }
        
        if changed { saveClones() }
    }
    
    // MARK: - Persistence
    
    func saveClones() {
        do {
            let data = try JSONEncoder().encode(clones)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            DiagnosticLogger.error("STORE", "saveClones FAILED", error: error)
        }
    }
    
    private func loadClones() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }
        do {
            clones = try JSONDecoder().decode([CloneAccount].self, from: data)
        } catch {
            DiagnosticLogger.error("STORE", "loadClones: decode FAILED", error: error)
        }
    }
    
    /// Startup sync — dùng kill(pid,0) + pgrep fallback cho orphan recovery
    private func syncProcessStatus() {
        DiagnosticLogger.info("STORE", "Sync process status cho \(clones.count) clones...")
        var changed = 0
        
        for i in clones.indices {
            if let pid = clones[i].processID, ProcessManager.isRunning(pid: pid) {
                clones[i].status = .running
            } else {
                let orphanAlive = ProcessManager.checkCloneRunning(
                    cloneIndex: clones[i].cloneIndex, knownPID: nil
                )
                if orphanAlive {
                    clones[i].status = .running
                    DiagnosticLogger.info("STORE", "  '\(clones[i].name)' → running (orphan recovered)")
                } else {
                    if clones[i].status == .running { changed += 1 }
                    clones[i].status = .stopped
                    clones[i].processID = nil
                }
            }
        }
        
        if changed > 0 { saveClones() }
    }
}
