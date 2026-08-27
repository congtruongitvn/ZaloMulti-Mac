// ProcessManager.swift
// ZaloMulti

import Foundation
import Combine

@MainActor
final class ProcessManager: ObservableObject {
    @Published var runningProcesses: [UUID: Int32] = [:]
    
    init() {
        DiagnosticLogger.info("PROCESS", "ProcessManager khởi tạo")
    }
    
    @discardableResult
    func launchClone(_ clone: CloneAccount) throws -> Int32 {
        DiagnosticLogger.info("LAUNCH", "Bắt đầu launch clone '\(clone.name)' (index=\(clone.cloneIndex))")
        
        let binaryPath = "\(clone.appPath)/Contents/MacOS/Zalo"
        
        guard FileManager.default.fileExists(atPath: binaryPath) else {
            throw CloneError.zaloNotFound
        }
        
        if let existingPID = runningProcesses[clone.id], Self.isRunning(pid: existingPID) {
            throw CloneError.alreadyRunning
        }
        
        let fm = FileManager.default
        let realHome = NSHomeDirectory()
        
        let cloneZaloData = "\(clone.dataPath)/ZaloData"
        try? fm.createDirectory(atPath: cloneZaloData, withIntermediateDirectories: true)
        try? fm.createDirectory(atPath: "\(clone.dataPath)/tmp", withIntermediateDirectories: true)
        
        let defaultZaloData = "\(realHome)/Library/Application Support/ZaloData"
        let backupZaloData = "\(realHome)/Library/Application Support/ZaloData.original"
        
        if fm.fileExists(atPath: defaultZaloData) {
            let attrs = try? fm.attributesOfItem(atPath: defaultZaloData)
            let isSymlink = attrs?[.type] as? FileAttributeType == .typeSymbolicLink
            
            if !isSymlink {
                try? fm.moveItem(atPath: defaultZaloData, toPath: backupZaloData)
                if (try? fm.contentsOfDirectory(atPath: cloneZaloData))?.isEmpty ?? true {
                    try? fm.removeItem(atPath: cloneZaloData)
                    try? fm.copyItem(atPath: backupZaloData, toPath: cloneZaloData)
                }
            }
        }
        
        try? fm.removeItem(atPath: defaultZaloData)
        try fm.createSymbolicLink(atPath: defaultZaloData, withDestinationPath: cloneZaloData)
        
        let origBinaryPath = "\(clone.appPath)/Contents/MacOS/Zalo.orig"
        let actualBinary = fm.fileExists(atPath: origBinaryPath) ? origBinaryPath : binaryPath
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: actualBinary)
        process.currentDirectoryURL = URL(fileURLWithPath: clone.dataPath)
        
        // Cấu hình môi trường cách ly cho từng clone (HOME trỏ về clone.dataPath)
        var env = ProcessInfo.processInfo.environment
        env["HOME"] = clone.dataPath
        process.environment = env
        
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        
        do {
            try process.run()
            let pid = process.processIdentifier
            runningProcesses[clone.id] = pid
            
            let cloneId = clone.id
            
            process.terminationHandler = { [weak self] proc in
                Task { @MainActor in
                    self?.runningProcesses.removeValue(forKey: cloneId)
                }
            }
            
            
            return pid
        } catch {
            try? fm.removeItem(atPath: defaultZaloData)
            if fm.fileExists(atPath: backupZaloData) {
                try? fm.createSymbolicLink(atPath: defaultZaloData, withDestinationPath: backupZaloData)
            }
            throw CloneError.launchFailed(error.localizedDescription)
        }
    }
    
    func stopClone(_ clone: CloneAccount) {
        DiagnosticLogger.info("STOP", "Dừng clone '\(clone.name)' — graceful quit")
        
        let cloneId = clone.id
        let cloneIndex = clone.cloneIndex
        let appName = "ZaloClone\(clone.cloneIndex).app"
        let pid = runningProcesses[clone.id]
        
        // Step 1: Gửi Apple Event quit (graceful — cho Zalo thời gian lưu session)
        let bundleID = clone.bundleID
        let script = "tell application id \"\(bundleID)\" to quit"
        let appleScript = Process()
        appleScript.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        appleScript.arguments = ["-e", script]
        appleScript.standardOutput = FileHandle.nullDevice
        appleScript.standardError = FileHandle.nullDevice
        try? appleScript.run()
        
        // Step 2: Chờ tối đa 5 giây cho Zalo tự thoát (flush session data)
        Task {
            for i in 0..<10 {
                try? await Task.sleep(for: .milliseconds(500))
                let stillRunning: Bool
                if let p = pid {
                    stillRunning = Self.isRunning(pid: p)
                } else {
                    stillRunning = Self.checkCloneRunning(cloneIndex: cloneIndex, knownPID: nil)
                }
                if !stillRunning {
                    DiagnosticLogger.success("STOP", "Clone '\(clone.name)' tự thoát sau \(Double(i+1)*0.5)s")
                    self.runningProcesses.removeValue(forKey: cloneId)
                    return
                }
            }
            
            // Step 3: Sau 5s vẫn chạy → SIGTERM
            DiagnosticLogger.warning("STOP", "Clone '\(clone.name)' chưa thoát sau 5s → SIGTERM")
            if let p = pid, Self.isRunning(pid: p) {
                kill(p, SIGTERM)
            }
            let termProc = Process()
            termProc.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
            termProc.arguments = ["-f", appName]
            termProc.standardOutput = FileHandle.nullDevice
            termProc.standardError = FileHandle.nullDevice
            try? termProc.run()
            termProc.waitUntilExit()
            
            // Chờ thêm 3s cho SIGTERM
            try? await Task.sleep(for: .seconds(3))
            
            // Step 4: Force kill nếu vẫn còn
            if Self.checkCloneRunning(cloneIndex: cloneIndex, knownPID: nil) {
                DiagnosticLogger.warning("STOP", "Clone '\(clone.name)' vẫn chạy → SIGKILL")
                let forceKill = Process()
                forceKill.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
                forceKill.arguments = ["-9", "-f", appName]
                forceKill.standardOutput = FileHandle.nullDevice
                forceKill.standardError = FileHandle.nullDevice
                try? forceKill.run()
                forceKill.waitUntilExit()
            }
            
            self.runningProcesses.removeValue(forKey: cloneId)
        }
    }
    
    func stopAllClones() {
        DiagnosticLogger.info("STOP", "Dừng tất cả clones — graceful quit")
        
        // Step 1: Gửi quit cho tất cả clone bằng osascript
        for (id, pid) in runningProcesses {
            let script = """
            tell application "System Events"
                set procs to every process whose unix id is \(pid)
                repeat with p in procs
                    tell p to quit
                end repeat
            end tell
            """
            let appleScript = Process()
            appleScript.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            appleScript.arguments = ["-e", script]
            appleScript.standardOutput = FileHandle.nullDevice
            appleScript.standardError = FileHandle.nullDevice
            try? appleScript.run()
        }
        
        // Step 2: Chờ 5 giây cho tất cả clone tự thoát
        Task {
            try? await Task.sleep(for: .seconds(5))
            
            // Step 3: SIGTERM cho ai vẫn còn
            if Self.checkCloneRunning(cloneIndex: 0, knownPID: nil) ||
               !runningProcesses.isEmpty {
                let killProc = Process()
                killProc.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
                killProc.arguments = ["-f", "ZaloMulti/Clones/ZaloClone"]
                killProc.standardOutput = FileHandle.nullDevice
                killProc.standardError = FileHandle.nullDevice
                try? killProc.run()
                killProc.waitUntilExit()
            }
            
            // Step 4: Chờ thêm 3s rồi force kill
            try? await Task.sleep(for: .seconds(3))
            let forceKill = Process()
            forceKill.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
            forceKill.arguments = ["-9", "-f", "ZaloMulti/Clones/ZaloClone"]
            forceKill.standardOutput = FileHandle.nullDevice
            forceKill.standardError = FileHandle.nullDevice
            try? forceKill.run()
            forceKill.waitUntilExit()
            
            self.runningProcesses.removeAll()
            DiagnosticLogger.success("STOP", "Tất cả clones đã dừng")
        }
    }
    
    nonisolated static func isRunning(pid: Int32) -> Bool {
        kill(pid, 0) == 0
    }
    
    nonisolated static func checkCloneRunning(cloneIndex: Int, knownPID: Int32?) -> Bool {
        if let pid = knownPID, isRunning(pid: pid) {
            return true
        }
        
        let patterns = [
            "ZaloClone\(cloneIndex).app",
            "ZaloClone\(cloneIndex).app/Contents/MacOS/Zalo"
        ]
        
        for pattern in patterns {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
            proc.arguments = ["-f", pattern]
            
            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = FileHandle.nullDevice
            
            do {
                try proc.run()
                proc.waitUntilExit()
                
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                
                if !output.isEmpty {
                    return true
                }
            } catch {}
        }
        
        return false
    }
}
