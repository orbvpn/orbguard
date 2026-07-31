#include "orbguard/win_util.h"

#include <knownfolders.h>
#include <shlobj.h>
// wintrust.h must precede softpub.h — softpub.h uses its types.
#include <wintrust.h>
#include <softpub.h>

#include <algorithm>
#include <cstdio>
#include <cstring>
#include <cwctype>
#include <iterator>

#pragma comment(lib, "wintrust.lib")
#pragma comment(lib, "shell32.lib")

namespace orbguard {
namespace {

// WinVerifyTrust is slow (it can hit the CRL cache and disk). The scanner is
// synchronous on the platform thread, so the total number of verifications per
// process lifetime is capped; past the cap we honestly report kUnknown rather
// than stalling the UI or guessing.
constexpr int kSignatureCheckBudget = 400;
int g_signature_checks_used = 0;

}  // namespace

std::string Utf8FromWide(const std::wstring& wide) {
  if (wide.empty()) return {};
  int size = ::WideCharToMultiByte(CP_UTF8, 0, wide.data(),
                                   static_cast<int>(wide.size()), nullptr, 0,
                                   nullptr, nullptr);
  if (size <= 0) return {};
  std::string out(static_cast<size_t>(size), '\0');
  ::WideCharToMultiByte(CP_UTF8, 0, wide.data(), static_cast<int>(wide.size()),
                        out.data(), size, nullptr, nullptr);
  return out;
}

std::wstring WideFromUtf8(const std::string& utf8) {
  if (utf8.empty()) return {};
  int size = ::MultiByteToWideChar(CP_UTF8, 0, utf8.data(),
                                   static_cast<int>(utf8.size()), nullptr, 0);
  if (size <= 0) return {};
  std::wstring out(static_cast<size_t>(size), L'\0');
  ::MultiByteToWideChar(CP_UTF8, 0, utf8.data(), static_cast<int>(utf8.size()),
                        out.data(), size);
  return out;
}

std::wstring ToLower(std::wstring value) {
  std::transform(value.begin(), value.end(), value.begin(),
                 [](wchar_t c) { return static_cast<wchar_t>(::towlower(c)); });
  return value;
}

bool ContainsNoCase(const std::wstring& haystack, const std::wstring& needle) {
  if (needle.empty()) return true;
  return ToLower(haystack).find(ToLower(needle)) != std::wstring::npos;
}

bool IsProcessElevated() {
  HANDLE token = nullptr;
  if (!::OpenProcessToken(::GetCurrentProcess(), TOKEN_QUERY, &token)) {
    return false;
  }
  TOKEN_ELEVATION elevation{};
  DWORD size = sizeof(elevation);
  bool elevated = false;
  if (::GetTokenInformation(token, TokenElevation, &elevation,
                            sizeof(elevation), &size)) {
    elevated = elevation.TokenIsElevated != 0;
  }
  ::CloseHandle(token);
  return elevated;
}

// ---------------------------------------------------------------------------
// Registry
// ---------------------------------------------------------------------------

std::vector<std::wstring> EnumRegistrySubKeys(HKEY root,
                                              const std::wstring& path,
                                              REGSAM extra_access) {
  std::vector<std::wstring> names;
  HKEY key = nullptr;
  if (::RegOpenKeyExW(root, path.c_str(), 0, KEY_READ | extra_access, &key) !=
      ERROR_SUCCESS) {
    return names;
  }
  wchar_t buffer[512];
  DWORD index = 0;
  for (;;) {
    DWORD length = static_cast<DWORD>(std::size(buffer));
    LONG status = ::RegEnumKeyExW(key, index++, buffer, &length, nullptr,
                                  nullptr, nullptr, nullptr);
    if (status != ERROR_SUCCESS) break;
    names.emplace_back(buffer, length);
  }
  ::RegCloseKey(key);
  return names;
}

std::vector<RegistryValue> EnumRegistryValues(HKEY root,
                                              const std::wstring& path,
                                              REGSAM extra_access) {
  std::vector<RegistryValue> values;
  HKEY key = nullptr;
  if (::RegOpenKeyExW(root, path.c_str(), 0, KEY_READ | extra_access, &key) !=
      ERROR_SUCCESS) {
    return values;
  }
  wchar_t name[512];
  std::vector<BYTE> data(4096);
  DWORD index = 0;
  for (;;) {
    DWORD name_length = static_cast<DWORD>(std::size(name));
    DWORD data_length = static_cast<DWORD>(data.size());
    DWORD type = REG_NONE;
    LONG status = ::RegEnumValueW(key, index++, name, &name_length, nullptr,
                                  &type, data.data(), &data_length);
    if (status == ERROR_MORE_DATA) {
      data.resize(data.size() * 2);
      --index;
      continue;
    }
    if (status != ERROR_SUCCESS) break;

    RegistryValue value;
    value.name.assign(name, name_length);
    value.type = type;
    if (type == REG_SZ || type == REG_EXPAND_SZ) {
      value.string_value.assign(reinterpret_cast<wchar_t*>(data.data()),
                                data_length / sizeof(wchar_t));
      while (!value.string_value.empty() && value.string_value.back() == L'\0') {
        value.string_value.pop_back();
      }
    } else if (type == REG_DWORD && data_length >= sizeof(DWORD)) {
      DWORD dword = 0;
      memcpy(&dword, data.data(), sizeof(dword));
      value.qword_value = dword;
    } else if (type == REG_QWORD && data_length >= sizeof(uint64_t)) {
      uint64_t qword = 0;
      memcpy(&qword, data.data(), sizeof(qword));
      value.qword_value = qword;
    }
    values.push_back(std::move(value));
  }
  ::RegCloseKey(key);
  return values;
}

std::optional<std::wstring> ReadRegistryString(HKEY root,
                                               const std::wstring& path,
                                               const std::wstring& value,
                                               REGSAM extra_access) {
  HKEY key = nullptr;
  if (::RegOpenKeyExW(root, path.c_str(), 0, KEY_READ | extra_access, &key) !=
      ERROR_SUCCESS) {
    return std::nullopt;
  }
  wchar_t buffer[2048];
  DWORD length = sizeof(buffer);
  DWORD type = REG_NONE;
  LONG status = ::RegQueryValueExW(key, value.c_str(), nullptr, &type,
                                   reinterpret_cast<LPBYTE>(buffer), &length);
  ::RegCloseKey(key);
  if (status != ERROR_SUCCESS || (type != REG_SZ && type != REG_EXPAND_SZ)) {
    return std::nullopt;
  }
  std::wstring result(buffer, length / sizeof(wchar_t));
  while (!result.empty() && result.back() == L'\0') result.pop_back();
  return result;
}

// ---------------------------------------------------------------------------
// Files and signatures
// ---------------------------------------------------------------------------

std::wstring ExecutablePathFromCommandLine(const std::wstring& command) {
  std::wstring value = command;
  if (value.empty()) return value;

  // Expand %ProgramFiles% and friends before anything else.
  wchar_t expanded[4096];
  DWORD written = ::ExpandEnvironmentStringsW(
      value.c_str(), expanded, static_cast<DWORD>(std::size(expanded)));
  if (written > 0 && written <= std::size(expanded)) {
    value.assign(expanded, written - 1);
  }

  // "C:\path with spaces\app.exe" --flag  ->  C:\path with spaces\app.exe
  if (!value.empty() && value.front() == L'"') {
    size_t closing = value.find(L'"', 1);
    if (closing != std::wstring::npos) return value.substr(1, closing - 1);
    return value.substr(1);
  }

  // Unquoted: cut at the first ".exe"/".dll"/".scr" boundary so arguments are
  // dropped without truncating an unquoted path that contains spaces.
  const std::wstring lower = ToLower(value);
  for (const wchar_t* ext : {L".exe", L".dll", L".scr", L".com", L".bat"}) {
    size_t pos = lower.find(ext);
    if (pos != std::wstring::npos) {
      return value.substr(0, pos + wcslen(ext));
    }
  }
  size_t space = value.find(L' ');
  return space == std::wstring::npos ? value : value.substr(0, space);
}

bool FileExists(const std::wstring& path) {
  if (path.empty()) return false;
  DWORD attributes = ::GetFileAttributesW(path.c_str());
  return attributes != INVALID_FILE_ATTRIBUTES &&
         !(attributes & FILE_ATTRIBUTE_DIRECTORY);
}

std::wstring KnownFolder(const GUID& id) {
  PWSTR raw = nullptr;
  std::wstring result;
  if (SUCCEEDED(::SHGetKnownFolderPath(id, 0, nullptr, &raw)) && raw) {
    result.assign(raw);
  }
  if (raw) ::CoTaskMemFree(raw);
  return result;
}

SignatureStatus VerifyFileSignature(const std::wstring& path) {
  if (!FileExists(path)) return SignatureStatus::kUnknown;
  if (g_signature_checks_used >= kSignatureCheckBudget) {
    return SignatureStatus::kUnknown;
  }
  ++g_signature_checks_used;

  WINTRUST_FILE_INFO file_info{};
  file_info.cbStruct = sizeof(file_info);
  file_info.pcwszFilePath = path.c_str();

  WINTRUST_DATA trust_data{};
  trust_data.cbStruct = sizeof(trust_data);
  trust_data.dwUIChoice = WTD_UI_NONE;
  trust_data.fdwRevocationChecks = WTD_REVOKE_NONE;
  trust_data.dwUnionChoice = WTD_CHOICE_FILE;
  trust_data.dwStateAction = WTD_STATEACTION_VERIFY;
  trust_data.pFile = &file_info;
  // Catalog-signed system files must count as signed, so allow the check to
  // consult catalogs rather than requiring an embedded signature.
  trust_data.dwProvFlags = WTD_CACHE_ONLY_URL_RETRIEVAL;

  GUID action = WINTRUST_ACTION_GENERIC_VERIFY_V2;
  LONG status = ::WinVerifyTrust(static_cast<HWND>(INVALID_HANDLE_VALUE),
                                 &action, &trust_data);

  trust_data.dwStateAction = WTD_STATEACTION_CLOSE;
  ::WinVerifyTrust(static_cast<HWND>(INVALID_HANDLE_VALUE), &action,
                   &trust_data);

  if (status == ERROR_SUCCESS) return SignatureStatus::kSigned;
  if (status == TRUST_E_NOSIGNATURE || status == TRUST_E_BAD_DIGEST ||
      status == TRUST_E_EXPLICIT_DISTRUST || status == CERT_E_UNTRUSTEDROOT ||
      status == CERT_E_CHAINING) {
    return SignatureStatus::kUnsigned;
  }
  return SignatureStatus::kUnknown;
}

bool IsUserWritableLocation(const std::wstring& path) {
  static const std::vector<std::wstring> kRoots = [] {
    std::vector<std::wstring> roots;
    for (const GUID& id :
         {FOLDERID_LocalAppData, FOLDERID_RoamingAppData, FOLDERID_Downloads,
          FOLDERID_ProgramData, FOLDERID_Public}) {
      std::wstring folder = KnownFolder(id);
      if (!folder.empty()) roots.push_back(ToLower(folder));
    }
    wchar_t temp[MAX_PATH];
    DWORD len = ::GetTempPathW(MAX_PATH, temp);
    if (len > 0) roots.push_back(ToLower(std::wstring(temp, len)));
    return roots;
  }();

  const std::wstring lower = ToLower(path);
  for (const std::wstring& root : kRoots) {
    if (!root.empty() && lower.rfind(root, 0) == 0) return true;
  }
  return false;
}

bool IsSystemLocation(const std::wstring& path) {
  static const std::wstring kWindows = [] {
    wchar_t dir[MAX_PATH];
    UINT len = ::GetWindowsDirectoryW(dir, MAX_PATH);
    return len > 0 ? ToLower(std::wstring(dir, len)) : std::wstring();
  }();
  if (kWindows.empty()) return false;
  return ToLower(path).rfind(kWindows, 0) == 0;
}

std::string Iso8601FromFileTime(const FILETIME& ft) {
  if (ft.dwLowDateTime == 0 && ft.dwHighDateTime == 0) return {};
  SYSTEMTIME st{};
  if (!::FileTimeToSystemTime(&ft, &st)) return {};
  char buffer[32];
  _snprintf_s(buffer, sizeof(buffer), _TRUNCATE,
              "%04d-%02d-%02dT%02d:%02d:%02dZ", st.wYear, st.wMonth, st.wDay,
              st.wHour, st.wMinute, st.wSecond);
  return buffer;
}

}  // namespace orbguard
