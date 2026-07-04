cmake_minimum_required(VERSION 3.21)

if(POLICY CMP0091)
  cmake_policy(SET CMP0091 NEW)
endif()

project(TKNativeHelper LANGUAGES CXX)

if(APPLE)
  enable_language(OBJCXX)
endif()

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

if(MSVC)
  set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
endif()

option(TK_NATIVE_HELPER_FETCH_REAPER_SDK "Fetch the REAPER SDK when REAPER_SDK_DIR is not set" ON)
option(TK_NATIVE_HELPER_FETCH_WDL "Fetch Cockos WDL when it is missing next to the REAPER SDK" ON)

if(NOT DEFINED REAPER_SDK_DIR OR REAPER_SDK_DIR STREQUAL "")
  if(TK_NATIVE_HELPER_FETCH_REAPER_SDK)
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

get_filename_component(REAPER_SDK_ROOT "${REAPER_SDK_DIR}" DIRECTORY)

if(NOT WIN32 AND NOT EXISTS "${REAPER_SDK_ROOT}/WDL/swell/swell.h")
  if(TK_NATIVE_HELPER_FETCH_WDL)
    include(FetchContent)
    FetchContent_Declare(
      wdl
      GIT_REPOSITORY https://github.com/justinfrankel/WDL.git
      GIT_TAG main
    )
    FetchContent_MakeAvailable(wdl)
    file(COPY "${wdl_SOURCE_DIR}/WDL/" DESTINATION "${REAPER_SDK_ROOT}/WDL")
  else()
    message(FATAL_ERROR "Cockos WDL is required next to the REAPER SDK for macOS/Linux builds")
  endif()
endif()

set(TK_NATIVE_HELPER_SOURCES
  src/tk_native_helper.cpp
)

if(APPLE)
  list(APPEND TK_NATIVE_HELPER_SOURCES src/tk_native_helper_mac.mm)
elseif(UNIX AND NOT WIN32)
  list(APPEND TK_NATIVE_HELPER_SOURCES src/tk_native_helper_x11.cpp)
endif()

add_library(reaper_tk_native_helper MODULE
  ${TK_NATIVE_HELPER_SOURCES}
)

target_include_directories(reaper_tk_native_helper PRIVATE
  "${REAPER_SDK_DIR}"
)

target_compile_definitions(reaper_tk_native_helper PRIVATE
  NOMINMAX
  WDL_NO_DEFINE_MINMAX
)

if(WIN32)
  target_link_libraries(reaper_tk_native_helper PRIVATE ole32 shell32 user32)
else()
  target_compile_definitions(reaper_tk_native_helper PRIVATE
    SWELL_PROVIDED_BY_APP
  )
  if(APPLE)
    target_link_libraries(reaper_tk_native_helper PRIVATE "-framework Cocoa")
  else()
    find_package(X11 REQUIRED)
    target_include_directories(reaper_tk_native_helper PRIVATE ${X11_INCLUDE_DIR})
    target_link_libraries(reaper_tk_native_helper PRIVATE ${X11_LIBRARIES})
  endif()
endif()

set_target_properties(reaper_tk_native_helper PROPERTIES
  PREFIX ""
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
  LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
  ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
)

foreach(config DEBUG RELEASE RELWITHDEBINFO MINSIZEREL)
  set_target_properties(reaper_tk_native_helper PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY_${config} "${CMAKE_BINARY_DIR}/bin"
    LIBRARY_OUTPUT_DIRECTORY_${config} "${CMAKE_BINARY_DIR}/bin"
    ARCHIVE_OUTPUT_DIRECTORY_${config} "${CMAKE_BINARY_DIR}/bin"
  )
endforeach()

if(WIN32)
  set_target_properties(reaper_tk_native_helper PROPERTIES
    SUFFIX ".dll"
  )
elseif(APPLE)
  set_target_properties(reaper_tk_native_helper PROPERTIES
    SUFFIX ".dylib"
  )
elseif(UNIX)
  set_target_properties(reaper_tk_native_helper PROPERTIES
    SUFFIX ".so"
  )
endif()

if(MSVC)
  target_compile_options(reaper_tk_native_helper PRIVATE /W4 /permissive-)
else()
  target_compile_options(reaper_tk_native_helper PRIVATE -Wall -Wextra -Wpedantic)
endif()
