include(cmake/SystemLink.cmake)
include(cmake/LibFuzzer.cmake)
include(CMakeDependentOption)
include(CheckCXXCompilerFlag)


macro(atmos_supports_sanitizers)
  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND NOT WIN32)
    set(SUPPORTS_UBSAN ON)
  else()
    set(SUPPORTS_UBSAN OFF)
  endif()

  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND WIN32)
    set(SUPPORTS_ASAN OFF)
  else()
    set(SUPPORTS_ASAN ON)
  endif()
endmacro()

macro(atmos_setup_options)
  option(atmos_ENABLE_HARDENING "Enable hardening" ON)
  option(atmos_ENABLE_COVERAGE "Enable coverage reporting" OFF)
  cmake_dependent_option(
    atmos_ENABLE_GLOBAL_HARDENING
    "Attempt to push hardening options to built dependencies"
    ON
    atmos_ENABLE_HARDENING
    OFF)

  atmos_supports_sanitizers()

  if(NOT PROJECT_IS_TOP_LEVEL OR atmos_PACKAGING_MAINTAINER_MODE)
    option(atmos_ENABLE_IPO "Enable IPO/LTO" OFF)
    option(atmos_WARNINGS_AS_ERRORS "Treat Warnings As Errors" OFF)
    option(atmos_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(atmos_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" OFF)
    option(atmos_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(atmos_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" OFF)
    option(atmos_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(atmos_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(atmos_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(atmos_ENABLE_CLANG_TIDY "Enable clang-tidy" OFF)
    option(atmos_ENABLE_CPPCHECK "Enable cpp-check analysis" OFF)
    option(atmos_ENABLE_PCH "Enable precompiled headers" OFF)
    option(atmos_ENABLE_CACHE "Enable ccache" OFF)
  else()
    option(atmos_ENABLE_IPO "Enable IPO/LTO" ON)
    option(atmos_WARNINGS_AS_ERRORS "Treat Warnings As Errors" ON)
    option(atmos_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(atmos_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" ${SUPPORTS_ASAN})
    option(atmos_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(atmos_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" ${SUPPORTS_UBSAN})
    option(atmos_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(atmos_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(atmos_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(atmos_ENABLE_CLANG_TIDY "Enable clang-tidy" ON)
    option(atmos_ENABLE_CPPCHECK "Enable cpp-check analysis" ON)
    option(atmos_ENABLE_PCH "Enable precompiled headers" OFF)
    option(atmos_ENABLE_CACHE "Enable ccache" ON)
  endif()

  if(NOT PROJECT_IS_TOP_LEVEL)
    mark_as_advanced(
      atmos_ENABLE_IPO
      atmos_WARNINGS_AS_ERRORS
      atmos_ENABLE_USER_LINKER
      atmos_ENABLE_SANITIZER_ADDRESS
      atmos_ENABLE_SANITIZER_LEAK
      atmos_ENABLE_SANITIZER_UNDEFINED
      atmos_ENABLE_SANITIZER_THREAD
      atmos_ENABLE_SANITIZER_MEMORY
      atmos_ENABLE_UNITY_BUILD
      atmos_ENABLE_CLANG_TIDY
      atmos_ENABLE_CPPCHECK
      atmos_ENABLE_COVERAGE
      atmos_ENABLE_PCH
      atmos_ENABLE_CACHE)
  endif()

  atmos_check_libfuzzer_support(LIBFUZZER_SUPPORTED)
  if(LIBFUZZER_SUPPORTED AND (atmos_ENABLE_SANITIZER_ADDRESS OR atmos_ENABLE_SANITIZER_THREAD OR atmos_ENABLE_SANITIZER_UNDEFINED))
    set(DEFAULT_FUZZER ON)
  else()
    set(DEFAULT_FUZZER OFF)
  endif()

  option(atmos_BUILD_FUZZ_TESTS "Enable fuzz testing executable" ${DEFAULT_FUZZER})

endmacro()

macro(atmos_global_options)
  if(atmos_ENABLE_IPO)
    include(cmake/InterproceduralOptimization.cmake)
    atmos_enable_ipo()
  endif()

  atmos_supports_sanitizers()

  if(atmos_ENABLE_HARDENING AND atmos_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR atmos_ENABLE_SANITIZER_UNDEFINED
       OR atmos_ENABLE_SANITIZER_ADDRESS
       OR atmos_ENABLE_SANITIZER_THREAD
       OR atmos_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    message("${atmos_ENABLE_HARDENING} ${ENABLE_UBSAN_MINIMAL_RUNTIME} ${atmos_ENABLE_SANITIZER_UNDEFINED}")
    atmos_enable_hardening(atmos_options ON ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()
endmacro()

macro(atmos_local_options)
  if(PROJECT_IS_TOP_LEVEL)
    include(cmake/StandardProjectSettings.cmake)
  endif()

  add_library(atmos_warnings INTERFACE)
  add_library(atmos_options INTERFACE)

  include(cmake/CompilerWarnings.cmake)
  atmos_set_project_warnings(
    atmos_warnings
    ${atmos_WARNINGS_AS_ERRORS}
    ""
    ""
    ""
    "")

  if(atmos_ENABLE_USER_LINKER)
    include(cmake/Linker.cmake)
    configure_linker(atmos_options)
  endif()

  include(cmake/Sanitizers.cmake)
  atmos_enable_sanitizers(
    atmos_options
    ${atmos_ENABLE_SANITIZER_ADDRESS}
    ${atmos_ENABLE_SANITIZER_LEAK}
    ${atmos_ENABLE_SANITIZER_UNDEFINED}
    ${atmos_ENABLE_SANITIZER_THREAD}
    ${atmos_ENABLE_SANITIZER_MEMORY})

  set_target_properties(atmos_options PROPERTIES UNITY_BUILD ${atmos_ENABLE_UNITY_BUILD})

  if(atmos_ENABLE_PCH)
    target_precompile_headers(
      atmos_options
      INTERFACE
      <vector>
      <string>
      <utility>)
  endif()

  if(atmos_ENABLE_CACHE)
    include(cmake/Cache.cmake)
    atmos_enable_cache()
  endif()

  include(cmake/StaticAnalyzers.cmake)
  if(atmos_ENABLE_CLANG_TIDY)
    atmos_enable_clang_tidy(atmos_options ${atmos_WARNINGS_AS_ERRORS})
  endif()

  if(atmos_ENABLE_CPPCHECK)
    atmos_enable_cppcheck(${atmos_WARNINGS_AS_ERRORS} "" # override cppcheck options
    )
  endif()

  if(atmos_ENABLE_COVERAGE)
    include(cmake/Tests.cmake)
    atmos_enable_coverage(atmos_options)
  endif()

  if(atmos_WARNINGS_AS_ERRORS)
    check_cxx_compiler_flag("-Wl,--fatal-warnings" LINKER_FATAL_WARNINGS)
    if(LINKER_FATAL_WARNINGS)
      # This is not working consistently, so disabling for now
      # target_link_options(atmos_options INTERFACE -Wl,--fatal-warnings)
    endif()
  endif()

  if(atmos_ENABLE_HARDENING AND NOT atmos_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR atmos_ENABLE_SANITIZER_UNDEFINED
       OR atmos_ENABLE_SANITIZER_ADDRESS
       OR atmos_ENABLE_SANITIZER_THREAD
       OR atmos_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    atmos_enable_hardening(atmos_options OFF ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()

endmacro()
