cmake_minimum_required(VERSION 3.16)
# usage: build/build-updater.sh configures this with the pinned clang22 and builds wezterm-updater.app.
# spec: INGREDIENTS.md "The Sparkle updater" -- the updater wears upstream's icon, so it needs the prepared
#       source; checked before project() so an unprepared tree fails before any compiler is probed.
set(WEZTERM_PREPARED_SOURCE "" CACHE PATH "the prepared WezTerm source (build/prepare.sh's WORK_ROOT/source)")
set(_wezterm_icon "${WEZTERM_PREPARED_SOURCE}/assets/macos/WezTerm.app/Contents/Resources/terminal.icns")
if(WEZTERM_PREPARED_SOURCE STREQUAL "" OR NOT EXISTS "${_wezterm_icon}")
  message(FATAL_ERROR
    "no prepared WezTerm source at ${WEZTERM_PREPARED_SOURCE} (no ${_wezterm_icon}): run build/prepare.sh, "
    "then build the updater with build/build-updater.sh")
endif()
project(WeztermUpdater LANGUAGES OBJC)

find_package(MavericksShipyard REQUIRED)
# spec: INGREDIENTS.md "The Sparkle updater" -- clang22 builds the updater, like the rest of this product
set(MAVERICKS_REQUIRE_APPLECLANG OFF)
include(Mavericks)
include(MavericksSparkle)

mavericks_resolve_version(WEZTERM_VERSION)

mavericks_add_updater_app(
  PRODUCT wezterm
  PRODUCT_NAME "Mavericks WezTerm"
  ICON "${_wezterm_icon}"
  VERSION "${WEZTERM_VERSION}"
  LOG_PREFIX "MavWeztermUpdater"
  CONFIRM_TITLE "Mavericks WezTerm updated"
  CONFIRM_BODY "Mavericks WezTerm in /Applications was updated."
  RELAUNCH_MARKER "/tmp/.mavericks-wezterm-updater-relaunched"
)
