#include "orbguard/scanner.h"

// winsock2.h MUST come before windows.h, otherwise windows.h pulls in the
// winsock 1.1 declarations and every socket symbol collides.
#include <winsock2.h>
#include <ws2tcpip.h>
// Then windows.h and the rest.
#include <windows.h>

#include <iphlpapi.h>
#include <knownfolders.h>
#include <shlobj.h>
#include <tlhelp32.h>
#include <wincrypt.h>

#include <cstdint>
#include <cstring>
#include <iterator>
#include <map>
#include <set>
#include <string>
#include <vector>

#include "orbguard/win_util.h"

#pragma comment(lib, "iphlpapi.lib")
#pragma comment(lib, "crypt32.lib")
#pragma comment(lib, "ws2_32.lib")

namespace orbguard {

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;

namespace {

// Bounds so a scan stage stays responsive: it runs on the platform thread.
constexpr size_t kMaxProcesses = 800;
constexpr size_t kMaxConnections = 600;
constexpr size_t kMaxApps = 600;
constexpr size_t kMaxCertificates = 400;

EncodableValue Str(const std::wstring& value) {
  return EncodableValue(Utf8FromWide(value));
}

EncodableMap MakeThreat(const std::string& id,
                        const std::wstring& name,
                        const std::wstring& description,
                        const char* severity,
                        const std::string& type,
                        const std::wstring& path,
                        EncodableMap metadata = {}) {
  return EncodableMap{
      {EncodableValue("id"), EncodableValue(id)},
      {EncodableValue("name"), Str(name)},
      {EncodableValue("description"), Str(description)},
      {EncodableValue("severity"), EncodableValue(severity)},
      {EncodableValue("type"), EncodableValue(type)},
      {EncodableValue("path"), Str(path)},
      // Nothing here needs elevation: every check is a read the user's own
      // token already permits.
      {EncodableValue("requiresRoot"), EncodableValue(false)},
      {EncodableValue("metadata"), EncodableValue(std::move(metadata))},
  };
}

EncodableValue Wrap(const char* key, EncodableList items) {
  return EncodableValue(
      EncodableMap{{EncodableValue(key), EncodableValue(std::move(items))}});
}

// ---------------------------------------------------------------------------
// Process inventory (shared by several stages)
// ---------------------------------------------------------------------------

struct ProcessInfo {
  DWORD pid = 0;
  std::wstring name;
  std::wstring path;
};

std::wstring PathForPid(DWORD pid) {
  HANDLE handle = ::OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
  if (!handle) return {};
  wchar_t buffer[MAX_PATH * 2];
  DWORD size = static_cast<DWORD>(std::size(buffer));
  std::wstring path;
  if (::QueryFullProcessImageNameW(handle, 0, buffer, &size)) {
    path.assign(buffer, size);
  }
  ::CloseHandle(handle);
  return path;
}

std::vector<ProcessInfo>& ProcessCache() {
  static std::vector<ProcessInfo> cache;
  return cache;
}

// Snapshot once per scan and share it across stages. The cache is invalidated
// by BeginScan(); if it were process-lifetime, a second scan would report the
// processes that were running during the first one.
const std::vector<ProcessInfo>& Processes() {
  std::vector<ProcessInfo>& cached = ProcessCache();
  if (!cached.empty()) return cached;
  {
    std::vector<ProcessInfo>& list = cached;
    HANDLE snapshot = ::CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (snapshot == INVALID_HANDLE_VALUE) return cached;
    PROCESSENTRY32W entry{};
    entry.dwSize = sizeof(entry);
    if (::Process32FirstW(snapshot, &entry)) {
      do {
        if (list.size() >= kMaxProcesses) break;
        ProcessInfo info;
        info.pid = entry.th32ProcessID;
        info.name = entry.szExeFile;
        info.path = PathForPid(entry.th32ProcessID);
        list.push_back(std::move(info));
      } while (::Process32NextW(snapshot, &entry));
    }
    ::CloseHandle(snapshot);
  }
  return cached;
}

// Windows ships these under %WINDIR%. A process using one of these names from
// anywhere else is a long-standing masquerading trick.
bool IsProtectedSystemName(const std::wstring& name) {
  static const std::set<std::wstring> kNames = {
      L"svchost.exe", L"csrss.exe",   L"lsass.exe",    L"services.exe",
      L"winlogon.exe", L"smss.exe",   L"explorer.exe", L"taskhostw.exe",
      L"dwm.exe",      L"spoolsv.exe", L"conhost.exe",  L"wininit.exe"};
  return kNames.count(ToLower(name)) > 0;
}

}  // namespace

// ---------------------------------------------------------------------------
// Stage: running processes
// ---------------------------------------------------------------------------

EncodableValue ScanProcesses() {
  EncodableList threats;
  for (const ProcessInfo& process : Processes()) {
    if (process.path.empty()) continue;

    // 1. A protected system name running from outside %WINDIR%.
    if (IsProtectedSystemName(process.name) && !IsSystemLocation(process.path)) {
      threats.push_back(EncodableValue(MakeThreat(
          "win-masquerade-" + std::to_string(process.pid), process.name,
          L"A process is using the name of a Windows system component but is "
          L"running from outside the Windows directory. Malware does this to "
          L"blend in with legitimate system activity.",
          kSeverityCritical, "process", process.path,
          EncodableMap{{EncodableValue("pid"),
                        EncodableValue(static_cast<int64_t>(process.pid))},
                       {EncodableValue("processName"), Str(process.name)}})));
      continue;
    }

    // 2. Unsigned executable running from a user-writable directory. This is
    //    the single strongest generic signal available on Windows.
    if (IsUserWritableLocation(process.path) &&
        VerifyFileSignature(process.path) == SignatureStatus::kUnsigned) {
      threats.push_back(EncodableValue(MakeThreat(
          "win-unsigned-proc-" + std::to_string(process.pid), process.name,
          L"An unsigned program is running from a folder that does not require "
          L"administrator rights to write to. Legitimate software is normally "
          L"signed and installed under Program Files.",
          kSeverityHigh, "process", process.path,
          EncodableMap{{EncodableValue("pid"),
                        EncodableValue(static_cast<int64_t>(process.pid))},
                       {EncodableValue("processName"), Str(process.name)},
                       {EncodableValue("signed"), EncodableValue(false)}})));
    }
  }
  return Wrap("threats", std::move(threats));
}

// ---------------------------------------------------------------------------
// Stage: network connections
// ---------------------------------------------------------------------------

EncodableValue ScanNetwork() {
  EncodableList threats;

  std::map<DWORD, const ProcessInfo*> by_pid;
  for (const ProcessInfo& process : Processes()) by_pid[process.pid] = &process;

  ULONG size = 0;
  if (::GetExtendedTcpTable(nullptr, &size, FALSE, AF_INET,
                            TCP_TABLE_OWNER_PID_ALL, 0) != ERROR_INSUFFICIENT_BUFFER) {
    return Wrap("threats", std::move(threats));
  }
  std::vector<BYTE> buffer(size);
  if (::GetExtendedTcpTable(buffer.data(), &size, FALSE, AF_INET,
                            TCP_TABLE_OWNER_PID_ALL, 0) != NO_ERROR) {
    return Wrap("threats", std::move(threats));
  }

  auto* table = reinterpret_cast<MIB_TCPTABLE_OWNER_PID*>(buffer.data());
  std::set<DWORD> reported;
  const DWORD rows = table->dwNumEntries;
  for (DWORD i = 0; i < rows && i < kMaxConnections; ++i) {
    const MIB_TCPROW_OWNER_PID& row = table->table[i];
    auto it = by_pid.find(row.dwOwningPid);
    if (it == by_pid.end() || it->second->path.empty()) continue;
    const ProcessInfo& process = *it->second;

    // Only unsigned binaries in user-writable locations are interesting here;
    // reporting every connection would be noise, not security.
    if (!IsUserWritableLocation(process.path)) continue;
    if (VerifyFileSignature(process.path) != SignatureStatus::kUnsigned) continue;
    if (!reported.insert(row.dwOwningPid).second) continue;

    in_addr remote{};
    remote.S_un.S_addr = row.dwRemoteAddr;
    char remote_text[INET_ADDRSTRLEN] = {0};
    ::inet_ntop(AF_INET, &remote, remote_text, sizeof(remote_text));
    const bool listening = row.dwState == MIB_TCP_STATE_LISTEN;

    threats.push_back(EncodableValue(MakeThreat(
        "win-net-" + std::to_string(row.dwOwningPid), process.name,
        listening ? L"An unsigned program is listening for incoming network "
                    L"connections. Remote-access tools do this to let someone "
                    L"else reach this computer."
                  : L"An unsigned program running from a user-writable folder "
                    L"is sending data over the network.",
        listening ? kSeverityCritical : kSeverityHigh, "network", process.path,
        EncodableMap{
            {EncodableValue("pid"),
             EncodableValue(static_cast<int64_t>(row.dwOwningPid))},
            {EncodableValue("processName"), Str(process.name)},
            {EncodableValue("remoteAddress"), EncodableValue(remote_text)},
            {EncodableValue("remotePort"),
             EncodableValue(static_cast<int64_t>(
                 ::ntohs(static_cast<u_short>(row.dwRemotePort))))},
            {EncodableValue("listening"), EncodableValue(listening)}})));
  }
  return Wrap("threats", std::move(threats));
}

// ---------------------------------------------------------------------------
// Stage: file system / persistence
// ---------------------------------------------------------------------------

EncodableValue ScanFileSystem() {
  EncodableList threats;

  struct RunKey {
    HKEY root;
    const wchar_t* path;
    const wchar_t* label;
  };
  static const RunKey kRunKeys[] = {
      {HKEY_CURRENT_USER,
       L"SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Run", L"user startup"},
      {HKEY_CURRENT_USER,
       L"SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\RunOnce",
       L"user run-once"},
      {HKEY_LOCAL_MACHINE,
       L"SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Run", L"system startup"},
      {HKEY_LOCAL_MACHINE,
       L"SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\RunOnce",
       L"system run-once"},
  };

  int index = 0;
  for (const RunKey& key : kRunKeys) {
    for (const RegistryValue& value : EnumRegistryValues(key.root, key.path)) {
      if (value.string_value.empty()) continue;
      const std::wstring path =
          ExecutablePathFromCommandLine(value.string_value);
      if (!FileExists(path)) continue;
      if (VerifyFileSignature(path) != SignatureStatus::kUnsigned) continue;

      threats.push_back(EncodableValue(MakeThreat(
          "win-autostart-" + std::to_string(index++), value.name,
          std::wstring(L"An unsigned program is set to start automatically "
                       L"with Windows (") +
              key.label +
              L"). Monitoring tools rely on this to restart after every "
              L"reboot.",
          kSeverityHigh, "persistence", path,
          EncodableMap{{EncodableValue("entryName"), Str(value.name)},
                       {EncodableValue("command"), Str(value.string_value)},
                       {EncodableValue("location"), Str(key.label)}})));
    }
  }

  // Startup folders (per-user and all-users).
  for (const GUID& id : {FOLDERID_Startup, FOLDERID_CommonStartup}) {
    const std::wstring folder = KnownFolder(id);
    if (folder.empty()) continue;
    WIN32_FIND_DATAW find{};
    HANDLE handle = ::FindFirstFileW((folder + L"\\*").c_str(), &find);
    if (handle == INVALID_HANDLE_VALUE) continue;
    do {
      if (find.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) continue;
      const std::wstring full = folder + L"\\" + find.cFileName;
      const std::wstring lower = ToLower(find.cFileName);
      if (lower.find(L".exe") == std::wstring::npos &&
          lower.find(L".bat") == std::wstring::npos &&
          lower.find(L".vbs") == std::wstring::npos &&
          lower.find(L".ps1") == std::wstring::npos) {
        continue;
      }
      if (VerifyFileSignature(full) == SignatureStatus::kSigned) continue;
      threats.push_back(EncodableValue(MakeThreat(
          "win-startup-" + std::to_string(index++), find.cFileName,
          L"An unsigned item in the Windows Startup folder runs every time you "
          L"sign in.",
          kSeverityMedium, "persistence", full,
          EncodableMap{{EncodableValue("fileName"), Str(find.cFileName)}})));
    } while (::FindNextFileW(handle, &find));
    ::FindClose(handle);
  }

  return Wrap("threats", std::move(threats));
}

// ---------------------------------------------------------------------------
// Stage: "databases" — on Windows, the consent records that reveal which apps
// have actually used the camera, microphone and location.
// ---------------------------------------------------------------------------

namespace {

constexpr const wchar_t* kConsentStoreBase =
    L"SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\CapabilityAccessManager\\"
    L"ConsentStore\\";

// Microsoft's own publisher hash — first-party components legitimately hold
// these capabilities, so they must not be reported as findings.
bool IsMicrosoftPackage(const std::wstring& package) {
  return ContainsNoCase(package, L"_8wekyb3d8bbwe") ||
         ContainsNoCase(package, L"Microsoft.");
}

// A NonPackaged consent key encodes the exe path with '#' for '\'.
std::wstring DecodeNonPackagedKey(const std::wstring& key) {
  std::wstring path = key;
  for (wchar_t& c : path) {
    if (c == L'#') c = L'\\';
  }
  return path;
}

struct ConsentEntry {
  std::wstring identity;   // package family name, or a decoded exe path
  std::wstring display;    // friendly-ish label
  bool allowed = false;
  uint64_t last_used_start = 0;
  uint64_t last_used_stop = 0;
};

std::vector<ConsentEntry> ReadConsentStore(const wchar_t* capability) {
  std::vector<ConsentEntry> entries;
  const std::wstring base = std::wstring(kConsentStoreBase) + capability;

  auto read_entry = [&](HKEY root, const std::wstring& key_path,
                        const std::wstring& identity) {
    ConsentEntry entry;
    entry.identity = identity;
    entry.display = identity;
    auto value = ReadRegistryString(root, key_path, L"Value");
    entry.allowed = value.has_value() && ToLower(*value) == L"allow";
    for (const RegistryValue& rv : EnumRegistryValues(root, key_path)) {
      if (rv.name == L"LastUsedTimeStart") entry.last_used_start = rv.qword_value;
      if (rv.name == L"LastUsedTimeStop") entry.last_used_stop = rv.qword_value;
    }
    entries.push_back(std::move(entry));
  };

  for (HKEY root : {HKEY_CURRENT_USER, HKEY_LOCAL_MACHINE}) {
    for (const std::wstring& sub : EnumRegistrySubKeys(root, base)) {
      const std::wstring key_path = base + L"\\" + sub;
      if (sub == L"NonPackaged") {
        for (const std::wstring& exe : EnumRegistrySubKeys(root, key_path)) {
          read_entry(root, key_path + L"\\" + exe, DecodeNonPackagedKey(exe));
        }
      } else {
        read_entry(root, key_path, sub);
      }
    }
  }
  return entries;
}

}  // namespace

EncodableValue ScanDatabases() {
  EncodableList threats;
  int index = 0;

  struct Capability {
    const wchar_t* key;
    const wchar_t* label;
    const char* severity;
  };
  static const Capability kWatched[] = {
      {L"webcam", L"camera", kSeverityCritical},
      {L"microphone", L"microphone", kSeverityCritical},
      {L"location", L"location", kSeverityHigh},
  };

  for (const Capability& capability : kWatched) {
    for (const ConsentEntry& entry : ReadConsentStore(capability.key)) {
      if (!entry.allowed) continue;
      if (IsMicrosoftPackage(entry.identity)) continue;
      // Only report things that actually USED the capability.
      if (entry.last_used_start == 0) continue;

      // An access that started and never stopped was still running when the
      // record was written — i.e. it is using the device right now.
      const bool in_use = entry.last_used_stop < entry.last_used_start;
      const std::wstring path =
          entry.identity.find(L'\\') != std::wstring::npos ? entry.identity
                                                           : std::wstring();

      threats.push_back(EncodableValue(MakeThreat(
          "win-consent-" + std::to_string(index++), entry.display,
          std::wstring(L"This app has used your ") + capability.label +
              (in_use ? L" and appears to be using it right now."
                      : L". Check that you recognise it and expect it to have "
                        L"this access."),
          in_use ? kSeverityCritical : capability.severity, "privacy", path,
          EncodableMap{
              {EncodableValue("capability"), Str(capability.label)},
              {EncodableValue("identity"), Str(entry.identity)},
              {EncodableValue("inUse"), EncodableValue(in_use)}})));
    }
  }
  return Wrap("threats", std::move(threats));
}

// ---------------------------------------------------------------------------
// Stage: memory — unsigned modules loaded into other processes (injection)
// ---------------------------------------------------------------------------

EncodableValue ScanMemory() {
  EncodableList threats;
  int index = 0;

  // Browsers and shells are the usual injection targets for info-stealers.
  static const std::set<std::wstring> kTargets = {
      L"explorer.exe", L"chrome.exe", L"msedge.exe",
      L"firefox.exe",  L"brave.exe",  L"opera.exe"};

  for (const ProcessInfo& process : Processes()) {
    if (kTargets.count(ToLower(process.name)) == 0) continue;

    HANDLE snapshot =
        ::CreateToolhelp32Snapshot(TH32CS_SNAPMODULE, process.pid);
    if (snapshot == INVALID_HANDLE_VALUE) continue;
    MODULEENTRY32W module{};
    module.dwSize = sizeof(module);
    if (::Module32FirstW(snapshot, &module)) {
      do {
        const std::wstring path = module.szExePath;
        if (path.empty() || !IsUserWritableLocation(path)) continue;
        if (VerifyFileSignature(path) != SignatureStatus::kUnsigned) continue;

        threats.push_back(EncodableValue(MakeThreat(
            "win-inject-" + std::to_string(index++), module.szModule,
            std::wstring(L"An unsigned component is loaded inside ") +
                process.name +
                L". Info-stealers load code into browsers this way to read "
                L"what you type and see.",
            kSeverityCritical, "memory", path,
            EncodableMap{
                {EncodableValue("hostProcess"), Str(process.name)},
                {EncodableValue("pid"),
                 EncodableValue(static_cast<int64_t>(process.pid))},
                {EncodableValue("module"), Str(module.szModule)}})));
      } while (::Module32NextW(snapshot, &module));
    }
    ::CloseHandle(snapshot);
  }
  return Wrap("threats", std::move(threats));
}

// ---------------------------------------------------------------------------
// Detection-module inputs
// ---------------------------------------------------------------------------

EncodableValue GetInstalledCertificates() {
  EncodableList certificates;

  struct StoreSpec {
    DWORD flags;
    bool user_installed;
  };
  // Certificates the USER (or something running as them) added to the trusted
  // roots are the MITM signal; machine roots are the Microsoft baseline.
  static const StoreSpec kStores[] = {
      {CERT_SYSTEM_STORE_CURRENT_USER, true},
      {CERT_SYSTEM_STORE_LOCAL_MACHINE, false},
  };

  for (const StoreSpec& spec : kStores) {
    HCERTSTORE store = ::CertOpenStore(CERT_STORE_PROV_SYSTEM_W,
                                       0, NULL,
                                       spec.flags | CERT_STORE_READONLY_FLAG,
                                       L"ROOT");
    if (!store) continue;

    PCCERT_CONTEXT context = nullptr;
    while ((context = ::CertEnumCertificatesInStore(store, context)) !=
           nullptr) {
      if (certificates.size() >= kMaxCertificates) break;

      wchar_t subject[512] = {0};
      wchar_t issuer[512] = {0};
      ::CertGetNameStringW(context, CERT_NAME_SIMPLE_DISPLAY_TYPE, 0, nullptr,
                           subject, static_cast<DWORD>(std::size(subject)));
      ::CertGetNameStringW(context, CERT_NAME_SIMPLE_DISPLAY_TYPE,
                           CERT_NAME_ISSUER_FLAG, nullptr, issuer,
                           static_cast<DWORD>(std::size(issuer)));

      const bool self_signed = ::CertCompareCertificateName(
          X509_ASN_ENCODING, &context->pCertInfo->Subject,
          &context->pCertInfo->Issuer) != FALSE;

      FILETIME now{};
      ::GetSystemTimeAsFileTime(&now);
      const bool expired =
          ::CompareFileTime(&now, &context->pCertInfo->NotAfter) > 0;

      std::wstring serial;
      {
        const CRYPT_INTEGER_BLOB& blob = context->pCertInfo->SerialNumber;
        wchar_t byte_text[4];
        for (DWORD i = blob.cbData; i > 0; --i) {
          swprintf_s(byte_text, L"%02X", blob.pbData[i - 1]);
          serial += byte_text;
        }
      }

      certificates.push_back(EncodableValue(EncodableMap{
          {EncodableValue("subject"), Str(subject)},
          {EncodableValue("issuer"), Str(issuer)},
          {EncodableValue("serial"), Str(serial)},
          {EncodableValue("validFrom"),
           EncodableValue(Iso8601FromFileTime(context->pCertInfo->NotBefore))},
          {EncodableValue("validTo"),
           EncodableValue(Iso8601FromFileTime(context->pCertInfo->NotAfter))},
          {EncodableValue("isSelfSigned"), EncodableValue(self_signed)},
          {EncodableValue("isExpired"), EncodableValue(expired)},
          {EncodableValue("isUserInstalled"),
           EncodableValue(spec.user_installed)},
          {EncodableValue("isActive"), EncodableValue(!expired)},
          {EncodableValue("path"),
           EncodableValue(spec.user_installed ? "CurrentUser\\ROOT"
                                              : "LocalMachine\\ROOT")},
      }));
    }
    ::CertCloseStore(store, 0);
  }
  return Wrap("certificates", std::move(certificates));
}

EncodableValue GetInstalledApps() {
  // Build capability -> identities, then attach them to each installed app as
  // Android-style permission names so the shared Dart combo rules apply.
  struct CapabilityMap {
    const wchar_t* key;
    const char* permission;
  };
  static const CapabilityMap kCapabilities[] = {
      {L"webcam", "CAMERA"},
      {L"microphone", "RECORD_AUDIO"},
      {L"location", "ACCESS_FINE_LOCATION"},
      {L"contacts", "READ_CONTACTS"},
      {L"chat", "READ_SMS"},
      {L"phoneCallHistory", "READ_CALL_LOG"},
      {L"email", "GET_ACCOUNTS"},
  };

  std::map<std::wstring, std::set<std::string>> granted;
  for (const CapabilityMap& capability : kCapabilities) {
    for (const ConsentEntry& entry : ReadConsentStore(capability.key)) {
      if (!entry.allowed) continue;
      granted[ToLower(entry.identity)].insert(capability.permission);
      // A capability used while the app was not in the foreground is the
      // background-location signal the Dart rules look for.
      if (std::string(capability.permission) == "ACCESS_FINE_LOCATION" &&
          entry.last_used_start != 0) {
        granted[ToLower(entry.identity)].insert("ACCESS_BACKGROUND_LOCATION");
      }
    }
  }

  EncodableList apps;
  struct UninstallRoot {
    HKEY root;
    REGSAM access;
  };
  static const UninstallRoot kRoots[] = {
      {HKEY_LOCAL_MACHINE, KEY_WOW64_64KEY},
      {HKEY_LOCAL_MACHINE, KEY_WOW64_32KEY},
      {HKEY_CURRENT_USER, 0},
  };
  static const std::wstring kUninstall =
      L"SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall";

  std::set<std::wstring> seen;
  for (const UninstallRoot& root : kRoots) {
    for (const std::wstring& sub :
         EnumRegistrySubKeys(root.root, kUninstall, root.access)) {
      if (apps.size() >= kMaxApps) break;
      const std::wstring key_path = kUninstall + L"\\" + sub;
      auto display =
          ReadRegistryString(root.root, key_path, L"DisplayName", root.access);
      if (!display || display->empty()) continue;
      if (!seen.insert(ToLower(*display)).second) continue;

      auto install_location = ReadRegistryString(root.root, key_path,
                                                 L"InstallLocation", root.access);
      auto install_date =
          ReadRegistryString(root.root, key_path, L"InstallDate", root.access);

      // Match consent records by executable path or by display name.
      EncodableList permissions;
      const std::wstring needle = ToLower(*display);
      std::set<std::string> merged;
      for (const auto& [identity, values] : granted) {
        if (identity.find(needle) != std::wstring::npos ||
            (install_location && !install_location->empty() &&
             identity.find(ToLower(*install_location)) != std::wstring::npos)) {
          merged.insert(values.begin(), values.end());
        }
      }
      // Any Windows desktop program can open a socket without declaring
      // anything, so network access is universal here rather than a capability.
      merged.insert("INTERNET");
      for (const std::string& permission : merged) {
        permissions.push_back(EncodableValue(permission));
      }

      apps.push_back(EncodableValue(EncodableMap{
          {EncodableValue("packageName"), Str(sub)},
          {EncodableValue("appName"), Str(*display)},
          {EncodableValue("installDate"),
           EncodableValue(install_date ? Utf8FromWide(*install_date)
                                       : std::string())},
          {EncodableValue("permissions"), EncodableValue(permissions)},
      }));
    }
  }
  return Wrap("apps", std::move(apps));
}

EncodableValue GetAccessibilityServices() {
  EncodableList services;

  // Registered assistive technologies. Screen readers legitimately live here,
  // but so does anything that wants to read every window's contents.
  static const std::wstring kAts =
      L"SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Accessibility\\ATs";
  for (const std::wstring& sub : EnumRegistrySubKeys(HKEY_LOCAL_MACHINE, kAts)) {
    const std::wstring key_path = kAts + L"\\" + sub;
    auto description =
        ReadRegistryString(HKEY_LOCAL_MACHINE, key_path, L"Description");
    auto exe = ReadRegistryString(HKEY_LOCAL_MACHINE, key_path, L"ATExe");

    services.push_back(EncodableValue(EncodableMap{
        {EncodableValue("packageName"), Str(exe ? *exe : sub)},
        {EncodableValue("appName"),
         Str(description ? *description : sub)},
        // Anything registered as an AT can observe window content by design.
        {EncodableValue("canRetrieveWindowContent"), EncodableValue(true)},
        {EncodableValue("capabilities"),
         EncodableValue(EncodableList{
             EncodableValue("canRetrieveWindowContent"),
             EncodableValue("canPerformGestures")})},
        {EncodableValue("enabledDate"), EncodableValue(std::string())},
    }));
  }
  return Wrap("services", std::move(services));
}

EncodableValue GetInstalledKeyboards() {
  EncodableList keyboards;

  // Text Services Framework input processors — the Windows analogue of an
  // Android IME, and the only place a third party can sit in the keystroke path.
  static const std::wstring kTip = L"SOFTWARE\\Microsoft\\CTF\\TIP";
  auto preload =
      ReadRegistryString(HKEY_CURRENT_USER, L"Keyboard Layout\\Preload", L"1");

  for (const std::wstring& clsid :
       EnumRegistrySubKeys(HKEY_LOCAL_MACHINE, kTip)) {
    const std::wstring class_key = L"CLSID\\" + clsid;
    auto name = ReadRegistryString(HKEY_CLASSES_ROOT, class_key, L"");
    auto server = ReadRegistryString(HKEY_CLASSES_ROOT,
                                     class_key + L"\\InProcServer32", L"");
    const std::wstring module = server ? ExecutablePathFromCommandLine(*server)
                                       : std::wstring();

    // A signed in-box IME is expected; an unsigned one in a user-writable
    // folder is a keylogger candidate.
    const bool trusted =
        module.empty() ||
        VerifyFileSignature(module) == SignatureStatus::kSigned;

    EncodableList permissions;
    permissions.push_back(EncodableValue("READ_KEYSTROKES"));

    keyboards.push_back(EncodableValue(EncodableMap{
        {EncodableValue("packageName"), Str(module.empty() ? clsid : module)},
        {EncodableValue("appName"), Str(name ? *name : clsid)},
        {EncodableValue("isEnabled"), EncodableValue(true)},
        {EncodableValue("isDefault"), EncodableValue(false)},
        {EncodableValue("isTrusted"), EncodableValue(trusted)},
        {EncodableValue("permissions"), EncodableValue(permissions)},
    }));
  }
  return Wrap("keyboards", std::move(keyboards));
}

EncodableValue GetLocationAccessHistory(int hours) {
  EncodableList accesses;

  // FILETIME ticks (100ns) for the requested window.
  FILETIME now{};
  ::GetSystemTimeAsFileTime(&now);
  ULARGE_INTEGER now_ticks{};
  now_ticks.LowPart = now.dwLowDateTime;
  now_ticks.HighPart = now.dwHighDateTime;
  const uint64_t window =
      static_cast<uint64_t>(hours > 0 ? hours : 24) * 3600ULL * 10000000ULL;
  const uint64_t cutoff =
      now_ticks.QuadPart > window ? now_ticks.QuadPart - window : 0;

  for (const ConsentEntry& entry : ReadConsentStore(L"location")) {
    if (!entry.allowed || entry.last_used_start == 0) continue;
    if (entry.last_used_start < cutoff) continue;

    // Still-open access (no stop after the last start) means it was reading
    // location without a visible session — the background-tracking signal.
    const bool background = entry.last_used_stop < entry.last_used_start;

    FILETIME start{};
    start.dwLowDateTime = static_cast<DWORD>(entry.last_used_start & 0xFFFFFFFF);
    start.dwHighDateTime = static_cast<DWORD>(entry.last_used_start >> 32);

    accesses.push_back(EncodableValue(EncodableMap{
        {EncodableValue("packageName"), Str(entry.identity)},
        {EncodableValue("appName"), Str(entry.display)},
        {EncodableValue("isBackground"), EncodableValue(background)},
        {EncodableValue("timestamp"),
         EncodableValue(Iso8601FromFileTime(start))},
    }));
  }
  return Wrap("accesses", std::move(accesses));
}

void BeginScan() {
  ProcessCache().clear();
  ResetSignatureBudget();
}

EncodableValue CheckElevatedAccess() {
  const bool elevated = IsProcessElevated();
  return EncodableValue(EncodableMap{
      {EncodableValue("hasRoot"), EncodableValue(elevated)},
      {EncodableValue("method"),
       EncodableValue(elevated ? "Administrator" : "Standard")},
  });
}

}  // namespace orbguard
