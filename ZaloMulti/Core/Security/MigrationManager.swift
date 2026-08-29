// MigrationManager.swift
// ZaloMulti
//
// Quản lý migration data giữa các phiên bản.
// Tự động dọn dẹp dữ liệu nhạy cảm từ phiên bản cũ,
// chuyển đổi format lưu trữ, và đánh dấu version đã migrate.

import Foundation
import CryptoKit

/// Quản lý migration và cleanup dữ liệu giữa các phiên bản
@MainActor
final class MigrationManager {
    
    static let shared = MigrationManager()
    
    /// Version hiện tại của migration format
    private static let currentMigrationVersion = 2
    private static let migrationVersionKey = "migration_version_v1"
    
    /// Paths cần cleanup
    private static var appSupportDir: String {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return dir.appendingPathComponent("ZaloMulti").path
    }
    
    private static var logDir: String {
        "\(NSHomeDirectory())/Library/Logs/ZaloMulti"
    }
    
    private init() {}
    
    // MARK: - Public API
    
    /// Chạy migration khi app khởi động — idempotent
    func runMigrations() {
        let currentVersion = UserDefaults.standard.integer(forKey: Self.migrationVersionKey)
        
        guard currentVersion < Self.currentMigrationVersion else {
            DiagnosticLogger.debug("MIGRATE", "Đã ở version \(currentVersion), không cần migrate")
            return
        }
        
        DiagnosticLogger.info("MIGRATE", "Bắt đầu migration v\(currentVersion) → v\(Self.currentMigrationVersion)")
        
        if currentVersion < 1 {
            migrateToV1()
        }
        if currentVersion < 2 {
            migrateToV2()
        }
        
        UserDefaults.standard.set(Self.currentMigrationVersion, forKey: Self.migrationVersionKey)
        DiagnosticLogger.success("MIGRATE", "Migration hoàn tất → v\(Self.currentMigrationVersion)")
    }
    
    // MARK: - V1: Cleanup plaintext sensitive data
    
    /// V1: Xóa donate cache plaintext, sanitize logs chứa HWID
    private func migrateToV1() {
        DiagnosticLogger.info("MIGRATE", "V1: Cleanup dữ liệu plaintext...")
        
        let fm = FileManager.default
        
        // 1. Xóa plaintext donate cache (chứa HWID rõ ràng)
        let oldDonateCachePath = "\(Self.appSupportDir)/donate_status.json"
        if fm.fileExists(atPath: oldDonateCachePath) {
            secureDelete(atPath: oldDonateCachePath)
            DiagnosticLogger.info("MIGRATE", "Đã xóa donate_status.json plaintext")
        }
        
        // 2. Sanitize log files — xóa dòng chứa HWID
        sanitizeLogFiles()
        
        // 3. Xóa UserDefaults cũ nếu chứa data không mã hóa
        // (clone_accounts_v1 chứa paths nhưng không chứa secrets — giữ lại)
        
        DiagnosticLogger.success("MIGRATE", "V1: Cleanup hoàn tất")
    }
    
    // MARK: - V2: Encrypt sensitive storage
    
    /// V2: Chuyển sang encrypted donate cache format
    private func migrateToV2() {
        DiagnosticLogger.info("MIGRATE", "V2: Chuyển sang encrypted storage...")
        
        // Xóa mọi cached donate data cũ — force re-check qua API
        let fm = FileManager.default
        let oldPaths = [
            "\(Self.appSupportDir)/donate_status.json",
            "\(Self.appSupportDir)/donate_cache.json",
            "\(Self.appSupportDir)/donate_status.enc",
        ]
        
        for path in oldPaths {
            if fm.fileExists(atPath: path) {
                secureDelete(atPath: path)
            }
        }
        
        // Xóa avatar caches có thể chứa data người dùng
        cleanupAvatarCaches()
        
        DiagnosticLogger.success("MIGRATE", "V2: Encrypted storage activated")
    }
    
    // MARK: - Secure File Deletion
    
    /// Xóa file an toàn — overwrite trước khi delete
    private func secureDelete(atPath path: String) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else { return }
        
        do {
            // Overwrite nội dung bằng random bytes trước khi xóa
            if let attrs = try? fm.attributesOfItem(atPath: path),
               let size = attrs[.size] as? Int, size > 0 {
                let randomData = Data((0..<size).map { _ in UInt8.random(in: 0...255) })
                try randomData.write(to: URL(fileURLWithPath: path))
            }
            try fm.removeItem(atPath: path)
        } catch {
            // Fallback: xóa bình thường
            try? fm.removeItem(atPath: path)
        }
    }
    
    // MARK: - Log Sanitization
    
    /// Xóa dòng log chứa HWID hoặc thông tin nhạy cảm
    private func sanitizeLogFiles() {
        let fm = FileManager.default
        let logDir = Self.logDir
        
        guard fm.fileExists(atPath: logDir),
              let files = try? fm.contentsOfDirectory(atPath: logDir) else { return }
        
        // Patterns derived at runtime — không hardcode plaintext
        var sensitivePatterns = ["HWID", "hwid", "Hardware UUID", "IOPlatformUUID", "donate_check"]
        // Thêm patterns từ encrypted config
        if let w = SecureConfig.decrypt(SecureConfig._workersDev) { sensitivePatterns.append(w) }
        if let d = SecureConfig.decrypt(SecureConfig._socialDonate) { sensitivePatterns.append(d) }
        
        for file in files where file.hasSuffix(".log") || file.hasSuffix(".log.old") {
            let filePath = "\(logDir)/\(file)"
            guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else { continue }
            
            var sanitized = content
            for pattern in sensitivePatterns {
                sanitized = sanitized.components(separatedBy: "\n")
                    .map { line in
                        if line.contains(pattern) {
                            return "[REDACTED] — dòng chứa thông tin nhạy cảm đã bị xóa"
                        }
                        return line
                    }
                    .joined(separator: "\n")
            }
            
            if sanitized != content {
                try? sanitized.write(toFile: filePath, atomically: true, encoding: .utf8)
                DiagnosticLogger.info("MIGRATE", "Đã sanitize: \(file)")
            }
        }
    }
    
    // MARK: - Avatar Cache Cleanup
    
    /// Xóa avatar caches cũ
    private func cleanupAvatarCaches() {
        let fm = FileManager.default
        let dataDir = "\(Self.appSupportDir)/Data"
        
        guard fm.fileExists(atPath: dataDir),
              let cloneDirs = try? fm.contentsOfDirectory(atPath: dataDir) else { return }
        
        for dir in cloneDirs where dir.hasPrefix("clone") {
            let avatarCache = "\(dataDir)/\(dir)/avatar_cache.jpg"
            if fm.fileExists(atPath: avatarCache) {
                try? fm.removeItem(atPath: avatarCache)
            }
        }
    }
    
    // MARK: - Old Version Cleanup
    
    /// Phát hiện và dọn dẹp dữ liệu từ phiên bản cũ
    func cleanupOldVersionData() {
        let fm = FileManager.default
        
        let legacyPaths = [
            "\(Self.appSupportDir)/donate_status.json",
            "\(Self.appSupportDir)/donate_cache.json",
        ]
        
        for path in legacyPaths {
            if fm.fileExists(atPath: path) {
                secureDelete(atPath: path)
                DiagnosticLogger.info("MIGRATE", "Cleaned up legacy: \(URL(fileURLWithPath: path).lastPathComponent)")
            }
        }
        
        // Phục hồi ZaloData gốc nếu trước đó bị symlink sang clone/zDeskPro
        let home = NSHomeDirectory()
        let defaultZaloData = "\(home)/Library/Application Support/ZaloData"
        let backupZaloData = "\(home)/Library/Application Support/ZaloData.original"
        
        if fm.fileExists(atPath: defaultZaloData) {
            let attrs = try? fm.attributesOfItem(atPath: defaultZaloData)
            let isSymlink = attrs?[.type] as? FileAttributeType == .typeSymbolicLink
            if isSymlink {
                try? fm.removeItem(atPath: defaultZaloData)
                if fm.fileExists(atPath: backupZaloData) {
                    try? fm.moveItem(atPath: backupZaloData, toPath: defaultZaloData)
                    DiagnosticLogger.info("MIGRATE", "Đã phục hồi ZaloData gốc từ ZaloData.original")
                }
            }
        } else if fm.fileExists(atPath: backupZaloData) {
            try? fm.moveItem(atPath: backupZaloData, toPath: defaultZaloData)
            DiagnosticLogger.info("MIGRATE", "Đã phục hồi ZaloData gốc từ ZaloData.original")
        }
    }
}
