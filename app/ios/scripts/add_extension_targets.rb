#!/usr/bin/env ruby
# frozen_string_literal: true
#
# add_extension_targets.rb
# ------------------------
# Wires TWO real iOS app-extension targets into ios/Runner.xcodeproj so they
# build, embed and ship alongside the existing OrbGuardFilter content filter:
#
#   1. OrbGuardSmsFilter   (com.apple.identitylookup.message-filter)
#      - Real anti-smishing MessageFilterExtension (ILMessageFilterExtension).
#      - Source: OrbGuardSmsFilter/MessageFilterExtension.swift
#      - Links IdentityLookup.framework.
#      - Entitlement: com.apple.developer.identitylookup.message-filter
#      - Info.plist declares ILMessageFilterExtensionNetworkURL (backend analyze
#        endpoint) so uncertain messages defer to the network.
#
#   2. OrbGuardCallDirectory (com.apple.callkitcalldirectory.extension)
#      - Real spam-call block/ID CXCallDirectoryProvider.
#      - Sources: OrbGuardCallDirectory/CallDirectoryHandler.swift and the
#        shared Shared/CallDirectoryStore.swift (read side).
#      - Links CallKit.framework.
#      - Entitlement: App Group group.com.orb.guard.shared (reads the lists the
#        host app writes).
#      Also adds to the Runner (host app) target so it can WRITE that data and
#      reload the extension:
#        - Shared/CallDirectoryStore.swift (write side, shared file reference)
#        - Runner/CallDirectoryChannelHandler.swift (com.orb.guard/call_directory)
#        - links CallKit.framework to Runner (for CXCallDirectoryManager).
#
# Both extensions are embedded into Runner via the existing "Embed App
# Extensions" copy-files phase (dstSubfolderSpec 13 / PlugIns). That phase is
# positioned BEFORE Flutter's "Thin Binary" phase: embedding after Thin Binary
# produces a "Cycle inside Runner" build error because Thin Binary processes the
# whole .app (including PlugIns). We reuse the existing correctly-positioned
# phase; if it were missing we would create one and move it before Thin Binary.
#
# HONESTY NOTE: both extensions are real, buildable and shippable, but iOS only
# ACTIVATES them after the user enables each one on a real device
#   - SMS filter:    Settings > Messages > Unknown & Spam
#   - Call directory: Settings > Phone > Call Blocking & Identification
# AND the build is signed with an Apple profile carrying the matching capability
# (identitylookup message-filter / callkit call-directory) and the App Group.
# Until then they filter/block nothing.
#
# Idempotent: each target is added only if absent, so re-runs (and partial
# states where only one target exists) are safe.
#
# Usage:  ruby ios/scripts/add_extension_targets.rb [path/to/Runner.xcodeproj]

require 'xcodeproj'

APP_BUNDLE_ID     = 'com.orb.guard'
DEPLOYMENT_TARGET = '15.0' # matches Runner's IPHONEOS_DEPLOYMENT_TARGET
SWIFT_VERSION     = '5.0'  # matches Runner's SWIFT_VERSION
DEV_TEAM          = '33T4RDL646'

project_path =
  if ARGV[0] && !ARGV[0].empty?
    File.expand_path(ARGV[0])
  else
    File.expand_path(File.join(__dir__, '..', 'Runner.xcodeproj'))
  end

project = Xcodeproj::Project.open(project_path)
runner  = project.targets.find { |t| t.name == 'Runner' }
raise "[add_extension_targets] Runner target not found in #{project_path}" unless runner

main = project.main_group

# --- helpers ---------------------------------------------------------------

def common_settings(target_name, ext_bundle_id)
  {
    'PRODUCT_BUNDLE_IDENTIFIER'      => ext_bundle_id,
    'PRODUCT_NAME'                   => '$(TARGET_NAME)',
    'INFOPLIST_FILE'                 => "#{target_name}/Info.plist",
    'CODE_SIGN_ENTITLEMENTS'         => "#{target_name}/#{target_name}.entitlements",
    'IPHONEOS_DEPLOYMENT_TARGET'     => DEPLOYMENT_TARGET,
    'SWIFT_VERSION'                  => SWIFT_VERSION,
    'TARGETED_DEVICE_FAMILY'         => '1,2',
    'SDKROOT'                        => 'iphoneos',
    'SUPPORTED_PLATFORMS'            => 'iphoneos',
    'SKIP_INSTALL'                   => 'YES',
    'APPLICATION_EXTENSION_API_ONLY' => 'YES',
    'CLANG_ENABLE_MODULES'           => 'YES',
    'CLANG_ENABLE_OBJC_ARC'          => 'YES',
    'ENABLE_BITCODE'                 => 'NO',
    'CODE_SIGN_STYLE'                => 'Automatic',
    'DEVELOPMENT_TEAM'               => DEV_TEAM,
    'CURRENT_PROJECT_VERSION'        => '1',
    'MARKETING_VERSION'              => '1.0',
    'LD_RUNPATH_SEARCH_PATHS'        => [
      '$(inherited)',
      '@executable_path/Frameworks',
      '@executable_path/../../Frameworks',
    ],
  }
end

def apply_settings!(target, target_name, ext_bundle_id)
  target.build_configurations.each do |config|
    config.build_settings.merge!(common_settings(target_name, ext_bundle_id))
    if config.name == 'Debug'
      config.build_settings['SWIFT_OPTIMIZATION_LEVEL']           = '-Onone'
      config.build_settings['SWIFT_ACTIVE_COMPILATION_CONDITIONS'] = 'DEBUG'
      config.build_settings['GCC_PREPROCESSOR_DEFINITIONS']       = ['DEBUG=1', '$(inherited)']
      config.build_settings['DEBUG_INFORMATION_FORMAT']           = 'dwarf'
      config.build_settings['ONLY_ACTIVE_ARCH']                   = 'YES'
    else
      config.build_settings['SWIFT_OPTIMIZATION_LEVEL'] = '-O'
      config.build_settings['SWIFT_COMPILATION_MODE']   = 'wholemodule'
      config.build_settings['DEBUG_INFORMATION_FORMAT'] = 'dwarf-with-dsym'
    end
  end
end

# Get-or-create a direct file reference (by path/basename) inside a group.
def ref_in(group, filename)
  group.files.find { |f| f.path == filename } || group.new_reference(filename)
end

# Link a system framework into a target's Frameworks build phase, only once.
def link_framework_once(target, framework_name)
  file_name = "#{framework_name}.framework"
  already = target.frameworks_build_phase.files.any? do |bf|
    ref = bf.file_ref
    ref && (ref.path == file_name || ref.display_name == file_name || ref.name == file_name)
  end
  target.add_system_framework(framework_name) unless already
end

# The single "Embed App Extensions" copy-files phase, positioned before Thin
# Binary (cycle-safe). Reuses an existing one; creates + repositions otherwise.
def embed_phase(project, runner)
  phase = runner.copy_files_build_phases.find { |p| p.display_name.to_s == 'Embed App Extensions' }
  return phase if phase

  phase = runner.new_copy_files_build_phase('Embed App Extensions')
  phase.symbol_dst_subfolder_spec = :plug_ins # dstSubfolderSpec = 13 (PlugIns)
  phase.dst_path = ''
  thin = runner.build_phases.find { |p| p.display_name.to_s == 'Thin Binary' }
  if thin
    runner.build_phases.delete(phase)
    runner.build_phases.insert(runner.build_phases.index(thin), phase)
  end
  phase
end

# Embed an extension's product into the embed phase, once, with code-signing.
def embed_appex(phase, ext)
  product = ext.product_reference
  already = phase.files.any? { |bf| bf.file_ref == product }
  return if already

  bf = phase.add_file_reference(product)
  bf.settings = { 'ATTRIBUTES' => %w[CodeSignOnCopy RemoveHeadersOnCopy] }
end

# Create an app-extension target (build settings, dependency, embed). Returns
# the target. Callers add sources/frameworks/file refs.
def add_extension_target(project, runner, name, ext_bundle_id)
  ext = project.new_target(:app_extension, name, :ios, DEPLOYMENT_TARGET)
  apply_settings!(ext, name, ext_bundle_id)
  runner.add_dependency(ext)
  embed_appex(embed_phase(project, runner), ext)
  ext
end

added = []

# === Target 1: OrbGuardSmsFilter =========================================
sms_name = 'OrbGuardSmsFilter'
if project.targets.any? { |t| t.name == sms_name }
  puts "[add_extension_targets] '#{sms_name}' already exists — skipping."
else
  ext = add_extension_target(project, runner, sms_name, "#{APP_BUNDLE_ID}.#{sms_name}")

  group = main[sms_name] || main.new_group(sms_name, sms_name)
  src   = ref_in(group, 'MessageFilterExtension.swift')
  ref_in(group, 'Info.plist')                          # navigator only
  ref_in(group, "#{sms_name}.entitlements")            # navigator only

  ext.add_file_references([src])
  link_framework_once(ext, 'IdentityLookup')

  added << sms_name
  puts "[add_extension_targets] Added '#{sms_name}' (#{APP_BUNDLE_ID}.#{sms_name}) " \
       '— MessageFilterExtension.swift + IdentityLookup.framework, embedded in Runner'
end

# === Target 2: OrbGuardCallDirectory =====================================
cd_name = 'OrbGuardCallDirectory'
if project.targets.any? { |t| t.name == cd_name }
  puts "[add_extension_targets] '#{cd_name}' already exists — skipping."
else
  ext = add_extension_target(project, runner, cd_name, "#{APP_BUNDLE_ID}.#{cd_name}")

  group = main[cd_name] || main.new_group(cd_name, cd_name)
  handler = ref_in(group, 'CallDirectoryHandler.swift')
  ref_in(group, 'Info.plist')                          # navigator only
  ref_in(group, "#{cd_name}.entitlements")             # navigator only

  # Shared read/write store — one file reference compiled into BOTH the
  # extension (reader) and Runner (writer).
  shared_group = main['Shared'] || main.new_group('Shared', 'Shared')
  store = ref_in(shared_group, 'CallDirectoryStore.swift')

  ext.add_file_references([handler, store])
  link_framework_once(ext, 'CallKit')

  # Runner (host app) side: the channel handler + the shared store writer, and
  # CallKit (for CXCallDirectoryManager reload/status).
  runner_group = main['Runner'] || main
  channel = ref_in(runner_group, 'CallDirectoryChannelHandler.swift')
  runner.add_file_references([channel, store])
  link_framework_once(runner, 'CallKit')

  added << cd_name
  puts "[add_extension_targets] Added '#{cd_name}' (#{APP_BUNDLE_ID}.#{cd_name}) " \
       '— CallDirectoryHandler.swift + CallDirectoryStore.swift + CallKit.framework, embedded in Runner'
  puts "[add_extension_targets]   Runner also compiles CallDirectoryStore.swift + " \
       'CallDirectoryChannelHandler.swift and links CallKit.framework'
end

if added.empty?
  puts '[add_extension_targets] Nothing to do — both targets already present.'
else
  project.save
  puts "[add_extension_targets] Saved #{project_path} (added: #{added.join(', ')})"
end
