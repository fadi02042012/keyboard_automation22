cmake_minimum_required(VERSION 3.15)
project(runner LANGUAGES CXX)

set(BINARY_NAME "keyboard_automation")

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(SOURCES
    main.cpp
    flutter_window.cpp
    win32_window.cpp
    utils.cpp
    keyboard_input.cpp
    mouse_input.cpp
    automation_engine.cpp
    macro_recorder.cpp
    window_manager.cpp
    ui_automation.cpp
)

set(HEADERS
    flutter_window.h
    win32_window.h
    utils.h
    keyboard_input.h
    mouse_input.h
    automation_engine.h
    macro_recorder.h
    window_manager.h
    ui_automation.h
)

add_executable(${BINARY_NAME} WIN32
    ${SOURCES}
    ${HEADERS}
)

target_include_directories(${BINARY_NAME} PRIVATE
    ${CMAKE_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/flutter/ephemeral
    ${CMAKE_SOURCE_DIR}/flutter/ephemeral/cpp_client_wrapper/include
)

target_link_libraries(${BINARY_NAME} PRIVATE
    flutter_wrapper_app
    ${CMAKE_SOURCE_DIR}/flutter/ephemeral/flutter_windows.dll.lib
    dwmapi
    comctl32
    shell32
    user32
    gdi32
    psapi
    uiautomationcore
)

set_target_properties(${BINARY_NAME} PROPERTIES
    OUTPUT_NAME ${BINARY_NAME}
)