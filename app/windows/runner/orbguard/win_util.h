// Shared Win32 helpers for the OrbGuard native scanner.
//
// Everything here is read-only: the scanner inspects the machine and reports,
// it never modifies system state.
#ifndef RUNNER_ORBGUARD_WIN_UTIL_H_
#define RUNNER_ORBGUARD_WIN_UTIL_H_

#include <windows.h>

#include <cstdint>
#include <optional>
#include <string>
#include <vector>

namespace orbguard {

// UTF-16 <-> UTF-8. Flutter's standard codec carries UTF-8 strings.
std::string Utf8FromWide(const std::wstring& wide);
std::wstring WideFromUtf8(const std::string& utf8);

std::wstring ToLower(std::wstring value);

// True when `haystack` contains `needle`, both compared case-insensitively.
bool ContainsNoCase(const std::wstring& haystack, const std::wstring& needle);

// Whether the current process is running elevated (the closest Windows
// analogue of the "root access" the Android scanner reports).
bool IsProcessElevated();

// ---------------------------------------------------------------------------
// Registry
// ---------------------------------------------------------------------------

struct RegistryValue {
  std::wstring name;
  std::wstring string_value;
  uint64_t qword_value = 0;
  DWORD type = REG_NONE;
};

std::vector<std::wstring> EnumRegistrySubKeys(HKEY root,
                                              const std::wstring& path,
                                              REGSAM extra_access = 0);

std::vector<RegistryValue> EnumRegistryValues(HKEY root,
                                              const std::wstring& path,
                                              REGSAM extra_access = 0);

std::optional<std::wstring> ReadRegistryString(HKEY root,
                                               const std::wstring& path,
                                               const std::wstring& value,
                                               REGSAM extra_access = 0);

// ---------------------------------------------------------------------------
// Files and signatures
// ---------------------------------------------------------------------------

// Expands %VAR% references and strips surrounding quotes / trailing arguments
// so a registry "command line" becomes a path that can be stat'ed.
std::wstring ExecutablePathFromCommandLine(const std::wstring& command);

bool FileExists(const std::wstring& path);

std::wstring KnownFolder(REFKNOWNFOLDERID id);

// Authenticode verification via WinVerifyTrust. This is the backbone of the
// scanner's heuristics: on Windows, "unsigned binary running from a user-
// writable directory" is the single strongest generic malware signal.
//
// Verification is comparatively expensive, so callers MUST bound how many
// files they check — see kMaxSignatureChecks in the scanner.
enum class SignatureStatus {
  kSigned,
  kUnsigned,
  kUnknown,  // could not be determined (file unreadable, check budget spent)
};

SignatureStatus VerifyFileSignature(const std::wstring& path);

// True when the path sits under a directory any standard user can write to
// (%TEMP%, AppData, Downloads, ProgramData, Public). Malware persists there
// precisely because it needs no elevation.
bool IsUserWritableLocation(const std::wstring& path);

// True for paths under %WINDIR% — used to spot processes that borrow a system
// binary's name while running from somewhere else entirely.
bool IsSystemLocation(const std::wstring& path);

// ISO-8601 (UTC) rendering of a FILETIME, or "" when the time is unset.
std::string Iso8601FromFileTime(const FILETIME& ft);

}  // namespace orbguard

#endif  // RUNNER_ORBGUARD_WIN_UTIL_H_
