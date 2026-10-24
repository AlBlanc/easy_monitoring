cmake_minimum_required(VERSION 3.14)
set(PROJECT_NAME "easy_monitoring")
project(${PROJECT_NAME} LANGUAGES CXX)

set(PREBUILT_LIB "${CMAKE_CURRENT_SOURCE_DIR}/../prebuilt/linux/libeasy_monitoring.so")
set(RUST_MANIFEST "${CMAKE_CURRENT_SOURCE_DIR}/../rust/Cargo.toml")
set(RUST_BUILD_LIB "${CMAKE_CURRENT_SOURCE_DIR}/../rust/target/release/libeasy_monitoring.so")
set(BUNDLED_LIB "${CMAKE_CURRENT_BINARY_DIR}/libeasy_monitoring.so")

if(EXISTS "${PREBUILT_LIB}")
  message(STATUS "[easy_monitoring] Using precompiled Linux library: ${PREBUILT_LIB}")
  configure_file("${PREBUILT_LIB}" "${BUNDLED_LIB}" COPYONLY)
else()
  set(RELEASE_URL "https://github.com/AlBlanc/easy_monitoring/releases/latest/download/libeasy_monitoring-linux-x86_64.so")
  message(STATUS "[easy_monitoring] Precompiled binary not found locally; trying download from ${RELEASE_URL}")
  file(DOWNLOAD "${RELEASE_URL}" "${PREBUILT_LIB}" STATUS DOWNLOAD_STATUS)
  list(GET DOWNLOAD_STATUS 0 DOWNLOAD_CODE)
  if(DOWNLOAD_CODE EQUAL 0 AND EXISTS "${PREBUILT_LIB}")
    configure_file("${PREBUILT_LIB}" "${BUNDLED_LIB}" COPYONLY)
  else()
    file(REMOVE "${PREBUILT_LIB}")
    find_program(CARGO_EXECUTABLE cargo HINTS "$ENV{HOME}/.cargo/bin")
    if(NOT CARGO_EXECUTABLE)
      message(FATAL_ERROR "[easy_monitoring] Precompiled Linux binary not found and Rust 'cargo' is not installed.")
    endif()
    message(STATUS "[easy_monitoring] Compiling Rust library via Cargo...")
    execute_process(
      COMMAND "${CARGO_EXECUTABLE}" build --manifest-path "${RUST_MANIFEST}" --release
      RESULT_VARIABLE CARGO_RESULT
    )
    if(NOT CARGO_RESULT EQUAL 0)
      message(FATAL_ERROR "[easy_monitoring] Cargo build failed with code ${CARGO_RESULT}")
    endif()
    file(COPY "${RUST_BUILD_LIB}" DESTINATION "${CMAKE_CURRENT_SOURCE_DIR}/../prebuilt/linux")
    configure_file("${RUST_BUILD_LIB}" "${BUNDLED_LIB}" COPYONLY)
  endif()
endif()

set(easy_monitoring_bundled_libraries
  "${BUNDLED_LIB}"
  PARENT_SCOPE
)
