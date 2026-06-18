# ============================================================================
#  File:    CMakeLists.txt
#  Purpose: App-level build script for the biometric chest-strap firmware.
#  Author:  Daan
#  Date:    2026-06-14
#
#  Description:
#    Standard nRF Connect SDK / Zephyr application CMake. Finds the Zephyr
#    package, registers the firmware sources, and exposes src/ as an include
#    root so modules use folder-qualified includes (e.g. "sensors/heatflux.h").
#    The board (DK or custom) is selected on the west command line, not here.
# ============================================================================

cmake_minimum_required(VERSION 3.20.0)

# BOARD_ROOT lets west find the custom board definition under boards/ in-tree.
list(APPEND BOARD_ROOT ${CMAKE_CURRENT_SOURCE_DIR})

find_package(Zephyr REQUIRED HINTS $ENV{ZEPHYR_BASE})
project(biometric_wearable LANGUAGES C)

# src/ as an include root so folder-qualified includes ("app/app_config.h",
# "sensors/heatflux.h", "util/log_cfg.h") resolve. The per-module subdirs are
# also added so a header can include a sibling module's header by bare name
# (e.g. temp_tmp117.h -> "app_data.h").
target_include_directories(app PRIVATE
	src
	src/app
	src/sensors
	src/radio
	src/hmi
	src/util
)

# ---- Firmware sources --------------------------------------------------------
target_sources(app PRIVATE
	src/main.c

	src/app/app_state.c

	src/sensors/temp_tmp117.c
	src/sensors/heatflux.c
	src/sensors/eda_gsr.c

	src/radio/ble_service.c
	src/radio/ant_profile.c

	src/hmi/buttons.c
	src/hmi/leds.c
	src/hmi/status_led.c

	src/util/battery.c
)
