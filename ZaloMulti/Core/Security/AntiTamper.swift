// AntiTamper.swift
// ZaloMulti
//
// Chống debug, inject, tamper — multi-layer protection.
// Rebuild v2.1 — safe init, không crash ad-hoc build, không terminate bất ngờ.

import Foundation
import Darwin
import AppKit

/// Multi-layer protection chống reverse engineering
enum AntiTamper {
    
    // MARK: - Anti-Debugger
    
    static var isDebuggerAttached: Bool {
        #if DEBUG
        return false
        #else
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0 else { return false }
        return (info.kp_proc.p_flag & P_TRACED) != 0
        #endif
    }
    
    static func denyDebuggerAttach() {
        // PT_DENY_ATTACH gây crash / thoát bất ngờ trên Apple Silicon khi macOS WindowServer
        // hoặc crash reporter hooks vào process. Giữ hàm an toàn, không gọi ptrace kernel.
    }
    
    // MARK: - Code Integrity
    
    static var isCodeSignatureValid: Bool {
        #if DEBUG
        return true
        #else
        var staticCode: SecStaticCode?
        let mainBundleURL = Bundle.main.bundleURL as CFURL
        guard SecStaticCodeCreateWithPath(mainBundleURL, [], &staticCode) == errSecSuccess,
              let code = staticCode else { return false }
        
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures)
        return SecStaticCodeCheckValidity(code, flags, nil) == errSecSuccess
        #endif
    }
    
    // MARK: - DYLD Injection Detection
    
    static var hasInjectedLibraries: Bool {
        #if DEBUG
        return false
        #else
        let suspicious = ["frida", "cycript", "substrate", "substitute", "inject",
                          "libReveal", "FLEXing", "FLEX"]
        let count = _dyld_image_count()
        for i in 0..<count {
            if let name = _dyld_get_image_name(i) {
                let path = String(cString: name).lowercased()
                for lib in suspicious {
                    if path.contains(lib.lowercased()) { return true }
                }
            }
        }
        return false
        #endif
    }
    
    // MARK: - Environment Variable Check
    
    static var hasSuspiciousEnvironment: Bool {
        #if DEBUG
        return false
        #else
        let envVars = ["DYLD_INSERT_LIBRARIES", "DYLD_FORCE_FLAT_NAMESPACE",
                       "_MSSafeMode", "SUBSTRATE_PREFIX", "DYLD_PRINT_TO_FILE"]
        for envVar in envVars {
            if getenv(envVar) != nil { return true }
        }
        return false
        #endif
    }
    
    // MARK: - Combined Security Check
    
    static func performFullCheck() -> Bool {
        #if DEBUG
        return true
        #else
        if isDebuggerAttached { return false }
        if hasInjectedLibraries { return false }
        if hasSuspiciousEnvironment { return false }
        // Bỏ kiểm tra code signature trong periodic check
        // để tránh terminate ad-hoc/dev builds
        return true
        #endif
    }
    
    /// Khởi tạo bảo vệ — GỌI TỪ onAppear, KHÔNG từ init()
    static func initialize() {
        #if !DEBUG
        // Chỉ bật khi app đã code sign đúng cách
        guard isCodeSignatureValid else {
            DiagnosticLogger.warning("SECURITY", "App chưa được code sign — anti-tamper disabled")
            return
        }
        
        denyDebuggerAttach()
        
        // Periodic check mỗi 60 giây — CHỈ check injection, KHÔNG terminate ad-hoc
        DispatchQueue.global(qos: .utility).async {
            let timer = Timer(timeInterval: 60, repeats: true) { _ in
                if isDebuggerAttached || hasInjectedLibraries || hasSuspiciousEnvironment {
                    DiagnosticLogger.error("SECURITY", "Phát hiện tampering!")
                    DispatchQueue.main.async {
                        NSApplication.shared.terminate(nil)
                    }
                }
            }
            RunLoop.current.add(timer, forMode: .default)
            RunLoop.current.run()
        }
        #endif
    }
}
