#!/usr/bin/env ruby
# frozen_string_literal: true
#
# add_filter_target.rb
# ---------------------
# Wires the OrbGuardFilter content-filter Network Extension into
# ios/Runner.xcodeproj so it actually builds, embeds and ships.
#
# What it adds:
#   * an app-extension target `OrbGuardFilter`
#     (com.apple.product-type.app-extension, bundle id com.orb.guard.OrbGuardFilter)
#   * Sources: OrbGuardFilter/FilterDataProvider.swift, Shared/SharedDataManager.swift,
#     Shared/BlocklistCache.swift and Runner/API/Models/ThreatIndicator.swift
#     (the last one defines SeverityLevel + ThreatIndicator, which the two Shared
#     classes reference — without it the extension does not compile).
#   * OrbGuardFilter/Info.plist as INFOPLIST_FILE and
#     OrbGuardFilter/OrbGuardFilter.entitlements as CODE_SIGN_ENTITLEMENTS.
#   * NetworkExtension.framework linkage.
#   * the extension as a Runner dependency, embedded via an "Embed App Extensions"
#     copy-files phase (dstSubfolderSpec 13 / PlugIns).
#   * the same shared writer classes (SharedDataManager/BlocklistCache/
#     ThreatIndicator) + ContentFilterChannelHandler.swift to the Runner target,
#     so the app can populate the App Group blocklist DB the extension reads.
#
# HONESTY NOTE: NEFilterDataProvider is only ACTIVATED by iOS on MDM-supervised
# (enterprise-managed) devices. This makes the extension real, buildable and
# shippable; it does not make it run on an un-managed consumer iPhone.
#
# Idempotent: if the OrbGuardFilter target already exists the script makes no
# changes and exits 0, so re-runs are safe.
#
# Usage:  ruby ios/scripts/add_filter_target.rb [path/to/Runner.xcodeproj]

require 'xcodeproj'

TARGET_NAME       = 'OrbGuardFilter'
APP_BUNDLE_ID     = 'com.orb.guard'
EXT_BUNDLE_ID     = "#{APP_BUNDLE_ID}.#{TARGET_NAME}"
DEPLOYMENT_TARGET = '15.0'  # matches Runner's IPHONEOS_DEPLOYMENT_TARGET
SWIFT_VERSION     = '5.0'   # matches Runner's SWIFT_VERSION
DEV_TEAM          = '33T4RDL646'

project_path =
  if ARGV[0] && !ARGV[0].empty?
    File.expand_path(ARGV[0])
  else
    File.expand_path(File.join(__dir__, '..', 'Runner.xcodeproj'))
  end

project = Xcodeproj::Project.open(project_path)

if project.targets.any? { |t| t.name == TARGET_NAME }
  puts "[add_filter_target] Target '#{TARGET_NAME}' already exists in #{project_path} — nothing to do."
  exit 0
end

runner = project.targets.find { |t| t.name == 'Runner' }
raise "[add_filter_target] Runner target not found in #{project_path}" unless runner

# --- create the app-extension target --------------------------------------
ext = project.new_target(:app_extension, TARGET_NAME, :ios, DEPLOYMENT_TARGET)

common_settings = {
  'PRODUCT_BUNDLE_IDENTIFIER' => EXT_BUNDLE_ID,
  'PRODUCT_NAME'              => '$(TARGET_NAME)',
  'INFOPLIST_FILE'            => 'OrbGuardFilter/Info.plist',
  'CODE_SIGN_ENTITLEMENTS'    => 'OrbGuardFilter/OrbGuardFilter.entitlements',
  'IPHONEOS_DEPLOYMENT_TARGET' => DEPLOYMENT_TARGET,
  'SWIFT_VERSION'             => SWIFT_VERSION,
  'TARGETED_DEVICE_FAMILY'    => '1,2',
  'SDKROOT'                   => 'iphoneos',
  'SUPPORTED_PLATFORMS'       => 'iphoneos',
  'SKIP_INSTALL'              => 'YES',
  'APPLICATION_EXTENSION_API_ONLY' => 'YES',
  'CLANG_ENABLE_MODULES'      => 'YES',
  'CLANG_ENABLE_OBJC_ARC'     => 'YES',
  'ENABLE_BITCODE'            => 'NO',
  'CODE_SIGN_STYLE'           => 'Automatic',
  'DEVELOPMENT_TEAM'          => DEV_TEAM,
  'CURRENT_PROJECT_VERSION'   => '1',
  'MARKETING_VERSION'         => '1.0',
  'LD_RUNPATH_SEARCH_PATHS'   => [
    '$(inherited)',
    '@executable_path/Frameworks',
    '@executable_path/../../Frameworks',
  ],
}

ext.build_configurations.each do |config|
  config.build_settings.merge!(common_settings)
  if config.name == 'Debug'
    config.build_settings['SWIFT_OPTIMIZATION_LEVEL']          = '-Onone'
    config.build_settings['SWIFT_ACTIVE_COMPILATION_CONDITIONS'] = 'DEBUG'
    config.build_settings['GCC_PREPROCESSOR_DEFINITIONS']      = ['DEBUG=1', '$(inherited)']
    config.build_settings['DEBUG_INFORMATION_FORMAT']          = 'dwarf'
    config.build_settings['ONLY_ACTIVE_ARCH']                  = 'YES'
  else
    config.build_settings['SWIFT_OPTIMIZATION_LEVEL'] = '-O'
    config.build_settings['SWIFT_COMPILATION_MODE']   = 'wholemodule'
    config.build_settings['DEBUG_INFORMATION_FORMAT'] = 'dwarf-with-dsym'
  end
end

# --- file references / groups ---------------------------------------------
main = project.main_group

filter_group = main['OrbGuardFilter'] || main.new_group('OrbGuardFilter', 'OrbGuardFilter')
shared_group = main['Shared']         || main.new_group('Shared', 'Shared')
runner_group = main['Runner']         || main

fdp_ref  = filter_group.new_reference('FilterDataProvider.swift')
_info_ref = filter_group.new_reference('Info.plist')                  # navigator only
_ent_ref  = filter_group.new_reference('OrbGuardFilter.entitlements') # navigator only

sdm_ref = shared_group.new_reference('SharedDataManager.swift')
blc_ref = shared_group.new_reference('BlocklistCache.swift')

api_group    = runner_group['API']    || runner_group.new_group('API', 'API')
models_group = api_group['Models']    || api_group.new_group('Models', 'Models')
ti_ref       = models_group.new_reference('ThreatIndicator.swift')

cf_ref = runner_group.new_reference('ContentFilterChannelHandler.swift')

# --- sources --------------------------------------------------------------
# Extension: the filter + shared support classes + the model types they need.
ext.add_file_references([fdp_ref, sdm_ref, blc_ref, ti_ref])

# App (Runner): the same shared writer classes so it can populate the App Group
# blocklist DB, plus the content_filter channel handler.
runner.add_file_references([sdm_ref, blc_ref, ti_ref, cf_ref])

# --- frameworks -----------------------------------------------------------
ext.add_system_framework('NetworkExtension')

# --- dependency + embed ---------------------------------------------------
runner.add_dependency(ext)

embed = runner.new_copy_files_build_phase('Embed App Extensions')
embed.symbol_dst_subfolder_spec = :plug_ins # dstSubfolderSpec = 13 (PlugIns)
embed.dst_path = ''
build_file = embed.add_file_reference(ext.product_reference)
build_file.settings = { 'ATTRIBUTES' => %w[CodeSignOnCopy RemoveHeadersOnCopy] }

project.save

puts "[add_filter_target] Added app-extension '#{TARGET_NAME}' (#{EXT_BUNDLE_ID})"
puts "[add_filter_target]   sources: FilterDataProvider, SharedDataManager, BlocklistCache, ThreatIndicator"
puts "[add_filter_target]   linked NetworkExtension.framework; embedded in Runner PlugIns"
puts "[add_filter_target]   Runner also compiles SharedDataManager/BlocklistCache/ThreatIndicator + ContentFilterChannelHandler"
puts "[add_filter_target] Saved #{project_path}"
