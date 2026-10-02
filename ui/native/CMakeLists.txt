cmake_minimum_required(VERSION 3.21)
project(zynith-native LANGUAGES CXX)

# Zynith.Native: the in-process C++ half of the UI. Only what QML should not do itself — compositor event
# parsing, sampling, signal processing, validated config writes. Built against Qt's public API only, so it survives Qt minor updates.

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

find_package(Qt6 6.5 REQUIRED COMPONENTS Core Qml Network DBus)
find_package(PkgConfig REQUIRED)
pkg_check_modules(PIPEWIRE REQUIRED IMPORTED_TARGET libpipewire-0.3)
qt_standard_project_setup(REQUIRES 6.5)

qt_add_library(zynith_native SHARED)
qt_add_qml_module(zynith_native
    URI Zynith.Native
    VERSION 1.0
    PLUGIN_TARGET zynith_nativeplugin
    OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/qml/Zynith/Native
    SOURCES
        src/niri_state.h src/niri_state.cpp
        src/audio_spectrum.h src/audio_spectrum.cpp
        src/niri_config.h src/niri_config.cpp
        src/network_state.h src/network_state.cpp
)

target_include_directories(zynith_native PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)
target_compile_options(zynith_native PRIVATE -Wall -Wextra)
target_link_libraries(zynith_native PRIVATE Qt6::Core Qt6::Qml Qt6::Network Qt6::DBus PkgConfig::PIPEWIRE)

# backing library and plugin live side by side in the module directory
set_target_properties(zynith_native PROPERTIES LIBRARY_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/qml/Zynith/Native)
set_target_properties(zynith_nativeplugin PROPERTIES BUILD_RPATH "$ORIGIN" INSTALL_RPATH "$ORIGIN")
