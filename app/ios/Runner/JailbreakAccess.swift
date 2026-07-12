// JailbreakAccess.swift
// Location: ios/Runner/JailbreakAccess.swift

import Foundation
import UIKit

/// Jailbreak Detection and Elevated Access Manager for iOS
/// Detects jailbreak and provides system access when available
class JailbreakAccess {

    private var isJailbrokenDevice = false
    private var jailbreakMethod: String = "None"

    /**
     * Check if device is jailbroken using multiple detection methods
     */
    func isJailbroken() -> Bool {
        if isJailbrokenDevice {
            return true
        }

        // Method 1: Check for common jailbreak files and apps
        if checkJailbreakFiles() {
            isJailbrokenDevice = true
            jailbreakMethod = "File Detection"
            return true
        }

        // Method 2: Try to write to system directory (should fail on non-jailbroken)
        if checkSystemWriteAccess() {
            isJailbrokenDevice = true
            jailbreakMethod = "Write Test"
            return true
        }

        // Method 3: Check if can open Cydia URL scheme
        if checkCydiaURL() {
            isJailbrokenDevice = true
            jailbreakMethod = "URL Scheme"
            return true
        }

        // Method 4: Check for suspicious dylibs
        if checkSuspiciousDylibs() {
            isJailbrokenDevice = true
            jailbreakMethod = "Dylib Detection"
            return true
        }

        // Method 5: Check symbolic links (jailbroken devices have modified symlinks)
        if checkSymbolicLinks() {
            isJailbrokenDevice = true
            jailbreakMethod = "Symlink Detection"
            return true
        }

        // Method 6: Check for fork() availability (sandboxed apps can't fork)
        if checkForkAvailability() {
            isJailbrokenDevice = true
            jailbreakMethod = "Fork Detection"
            return true
        }

        return false
    }

    /**
     * Get the method used to detect jailbreak
     */
    func getJailbreakMethod() -> String {
        return jailbreakMethod
    }

    // ============================================================================
    // DETECTION METHODS
    // ============================================================================

    /**
     * Method 1: Check for common jailbreak files and applications
     */
    private func checkJailbreakFiles() -> Bool {
        let jailbreakPaths = [
            // Jailbreak Tools
            "/Applications/Cydia.app",
            "/Applications/Sileo.app",
            "/Applications/Zebra.app",
            "/Applications/Installer.app",
            "/Applications/blackra1n.app",
            "/Applications/FakeCarrier.app",
            "/Applications/Icy.app",
            "/Applications/IntelliScreen.app",
            "/Applications/MxTube.app",
            "/Applications/RockApp.app",
            "/Applications/SBSettings.app",
            "/Applications/WinterBoard.app",

            // Jailbreak Binaries
            "/usr/sbin/sshd",
            "/usr/bin/sshd",
            "/bin/bash",
            "/bin/sh",
            "/usr/libexec/sftp-server",
            "/usr/bin/ssh",

            // Substrate/Substitute
            "/Library/MobileSubstrate/MobileSubstrate.dylib",
            "/Library/MobileSubstrate/DynamicLibraries",
            "/usr/lib/libsubstrate.dylib",
            "/usr/lib/substrate",
            "/usr/lib/TweakInject",

            // Common Jailbreak Directories
            "/private/var/lib/apt",
            "/private/var/lib/cydia",
            "/private/var/mobile/Library/SBSettings/Themes",
            "/private/var/stash",
            "/private/var/tmp/cydia.log",
            "/var/cache/apt",
            "/var/lib/apt",
            "/var/lib/cydia",
            "/etc/apt",

            // Jailbreak Files
            "/private/jailbreak.txt",
            "/.installed_unc0ver",
            "/.bootstrapped_electra",
            "/usr/share/jailbreak/injectme.plist",
            "/etc/apt/sources.list.d/electra.list",
            "/etc/apt/sources.list.d/sileo.sources",
            "/.cydia_no_stash",

            // Bootstrap
            "/var/binpack",
            "/Library/PreferenceBundles/AppList.bundle",
            "/Library/PreferenceBundles/CydiaSubstrateSettings.bundle",
        ]

        for path in jailbreakPaths {
            if FileManager.default.fileExists(atPath: path) {
                print("[Jailbreak] Detected via file: \(path)")
                return true
            }

            // Also check if file is accessible (some jailbreaks hide files)
            if canOpenFile(path: path) {
                print("[Jailbreak] Detected via access: \(path)")
                return true
            }
        }

        return false
    }

    /**
     * Method 2: Try to write to system directory
     */
    private func checkSystemWriteAccess() -> Bool {
        let testPath = "/private/jailbreak_test.txt"
        let testString = "test"

        do {
            try testString.write(toFile: testPath, atomically: true, encoding: .utf8)

            // If write succeeded, try to delete
            try FileManager.default.removeItem(atPath: testPath)

            print("[Jailbreak] Detected via write test")
            return true
        } catch {
            // Cannot write - normal for non-jailbroken device
            return false
        }
    }

    /**
     * Method 3: Check if can open Cydia URL
     */
    private func checkCydiaURL() -> Bool {
        if let url = URL(string: "cydia://package/com.example.package") {
            if UIApplication.shared.canOpenURL(url) {
                print("[Jailbreak] Detected via Cydia URL")
                return true
            }
        }

        // Check other jailbreak URL schemes
        let jailbreakSchemes = [
            "sileo://",
            "zbra://",
            "activator://",
            "undecimus://",
        ]

        for scheme in jailbreakSchemes {
            if let url = URL(string: scheme) {
                if UIApplication.shared.canOpenURL(url) {
                    print("[Jailbreak] Detected via URL scheme: \(scheme)")
                    return true
                }
            }
        }

        return false
    }

    /**
     * Method 4: Check for suspicious dylibs loaded in process
     */
    private func checkSuspiciousDylibs() -> Bool {
        let suspiciousDylibs = [
            "MobileSubstrate",
            "SubstrateLoader",
            "CydiaSubstrate",
            "SubstrateInserter",
            "SubstrateBootstrap",
            "ABypass",
            "FlyJB",
            "PreferenceLoader",
            "RocketBootstrap",
            "WeeLoader",
            "zzzzLiberty",
        ]

        for dylib in suspiciousDylibs {
            if dlopen(dylib, RTLD_NOW) != nil {
                print("[Jailbreak] Detected via dylib: \(dylib)")
                return true
            }
        }

        return false
    }

    /**
     * Method 5: Check symbolic links (jailbreak modifies /Applications)
     */
    private func checkSymbolicLinks() -> Bool {
        let fileManager = FileManager.default

        do {
            let attributes = try fileManager.attributesOfItem(atPath: "/Applications")
            if let fileType = attributes[.type] as? FileAttributeType {
                if fileType == .typeSymbolicLink {
                    print("[Jailbreak] Detected via /Applications symlink")
                    return true
                }
            }
        } catch {
            // Error reading attributes - might be jailbroken and hidden
        }

        return false
    }

    /**
     * Method 6: Check if fork() is available (sandboxed apps can't fork)
     */
    private func checkForkAvailability() -> Bool {
        let result = fork()

        if result >= 0 {
            // fork succeeded - jailbroken
            if result > 0 {
                // Parent process - kill child
                kill(result, SIGKILL)
            }
            print("[Jailbreak] Detected via fork test")
            return true
        }

        return false
    }

    /**
     * Helper: Check if file can be opened
     */
    private func canOpenFile(path: String) -> Bool {
        let file = fopen(path, "r")
        if file != nil {
            fclose(file)
            return true
        }
        return false
    }

    // ============================================================================
    // ELEVATED ACCESS METHODS
    // ============================================================================

    /**
     * Execute command with elevated privileges (requires jailbreak)
     */
    func executeCommand(_ command: String) -> String? {
        guard isJailbroken() else {
            return nil
        }

        let task = Process()
        task.launchPath = "/bin/sh"
        task.arguments = ["-c", command]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                return output
            }
        } catch {
            print("[Command] Execution failed: \(error)")
        }

        return nil
    }

    /**
     * Read file at path (uses elevated access if available)
     */
    func readFile(atPath path: String) -> String? {
        if isJailbroken() {
            // Try with elevated privileges
            return executeCommand("cat '\(path)'")
        } else {
            // Try standard read
            return try? String(contentsOfFile: path, encoding: .utf8)
        }
    }

    /**
     * Delete file at path (requires jailbreak)
     */
    func deleteFile(atPath path: String) -> Bool {
        guard isJailbroken() else {
            return false
        }

        let result = executeCommand("rm -rf '\(path)'")
        return result != nil && !result!.contains("cannot remove")
    }

    /**
     * List files in directory
     */
    func listFiles(atPath path: String) -> String? {
        if isJailbroken() {
            return executeCommand("ls -la '\(path)'")
        }

        // Try standard file manager
        do {
            let files = try FileManager.default.contentsOfDirectory(atPath: path)
            return files.joined(separator: "\n")
        } catch {
            return nil
        }
    }

    /**
     * Check if file exists
     */
    func fileExists(atPath path: String) -> Bool {
        return FileManager.default.fileExists(atPath: path)
    }

    /**
     * Get running processes (requires jailbreak)
     */
    func getProcessList() -> String? {
        guard isJailbroken() else {
            return nil
        }

        return executeCommand("ps -ef")
    }

    /**
     * Kill process by name (requires jailbreak)
     */
    func killProcess(name: String) -> Bool {
        guard isJailbroken() else {
            return false
        }

        let result = executeCommand("killall '\(name)'")
        return result != nil
    }

    /**
     * Execute SQL query on database (requires jailbreak)
     */
    func sqliteQuery(dbPath: String, query: String) -> String? {
        guard isJailbroken() else {
            return nil
        }

        return executeCommand("sqlite3 '\(dbPath)' \"\(query)\"")
    }
}
