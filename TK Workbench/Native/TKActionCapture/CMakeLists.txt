cmake_minimum_required(VERSION 3.21)

if(POLICY CMP0091)
  cmake_policy(SET CMP0091 NEW)
endif()

project(TKActionCapture LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

if(MSVC)
  set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
endif()

option(TK_ACTION_CAPTURE_FETCH_REAPER_SDK "Fetch the REAPER SDK when REAPER_SDK_DIR is not set" ON)

if(NOT DEFINED REAPER_SDK_DIR OR REAPER_SDK_DIR STREQUAL "")
  if(TK_ACTION_CAPTURE_FETCH_REAPER_SDK)
    include(FetchContent)
    FetchContent_Declare(
      reaper_sdk
      GIT_REPOSITORY https://github.com/justinfrankel/reaper-sdk.git
      GIT_TAG main
    )
    FetchContent_MakeAvailable(reaper_sdk)
    set(REAPER_SDK_DIR "${reaper_sdk_SOURCE_DIR}/sdk")
  else()
    message(FATAL_ERROR "Set REAPER_SDK_DIR to the REAPER SDK sdk folder")
  endif()
endif()

add_library(reaper_tk_action_capture MODULE
  src/tk_action_capture.cpp
)

target_include_directories(reaper_tk_action_capture PRIVATE
  "${REAPER_SDK_DIR}"
)

set_target_properties(reaper_tk_action_capture PROPERTIES
  PREFIX ""
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
  LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
  ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
)

foreach(config DEBUG RELEASE RELWITHDEBINFO MINSIZEREL)
  set_target_properties(reaper_tk_action_capture PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY_${config} "${CMAKE_BINARY_DIR}/bin"
    LIBRARY_OUTPUT_DIRECTORY_${config} "${CMAKE_BINARY_DIR}/bin"
    ARCHIVE_OUTPUT_DIRECTORY_${config} "${CMAKE_BINARY_DIR}/bin"
  )
endforeach()

if(WIN32)
  set_target_properties(reaper_tk_action_capture PROPERTIES
    SUFFIX ".dll"
  )
elseif(APPLE)
  set_target_properties(reaper_tk_action_capture PROPERTIES
    SUFFIX ".dylib"
  )
elseif(UNIX)
  set_target_properties(reaper_tk_action_capture PROPERTIES
    SUFFIX ".so"
  )
endif()

if(MSVC)
  target_compile_options(reaper_tk_action_capture PRIVATE /W4 /permissive-)
else()
  target_compile_options(reaper_tk_action_capture PRIVATE -Wall -Wextra -Wpedantic)
endif()