if(NOT CTEST_SOURCE_DIRECTORY)
   get_filename_component(CTEST_SOURCE_DIRECTORY "${CMAKE_CURRENT_LIST_FILE}" PATH)
endif()

set(dashboard_model "$ENV{dashboard_model}")
if(NOT dashboard_model)
   set(dashboard_model "Experimental")
endif()
set(target_architecture "$ENV{target_architecture}")
set(skip_tests "$ENV{skip_tests}")

set(build_type "$ENV{build_type}")
if(NOT build_type)
   set(build_type "Release")
endif()

# better make sure we get english output (this is vital for the implicit_type_conversion_failures tests)
set(ENV{LANG} "en_US")

find_program(UNAME uname)
if(UNAME)
   execute_process(COMMAND ${UNAME} -s OUTPUT_VARIABLE arch OUTPUT_STRIP_TRAILING_WHITESPACE)
   string(TOLOWER "${arch}" arch)
   execute_process(COMMAND ${UNAME} -m OUTPUT_VARIABLE chip OUTPUT_STRIP_TRAILING_WHITESPACE)
   string(TOLOWER "${chip}" chip)
else()
   find_program(CMD cmd)
   if(CMD)
      execute_process(COMMAND cmd /D /Q /C ver OUTPUT_VARIABLE arch OUTPUT_STRIP_TRAILING_WHITESPACE)
      string(REGEX REPLACE "^.*Windows[^0-9]*([.0-9]+).*$" "Windows \\1" arch "${arch}")
   else()
      string(TOLOWER "$ENV{TARGET_PLATFORM}" arch)
      if(arch)
         if("$ENV{WindowsSDKVersionOverride}")
            set(arch "${arch} SDK $ENV{WindowsSDKVersionOverride}")
         endif()
      else()
         string(TOLOWER "${CMAKE_SYSTEM_NAME}" arch)
      endif()
   endif()
   execute_process(COMMAND
      reg query "HKLM\\HARDWARE\\DESCRIPTION\\System\\CentralProcessor\\0" /v Identifier
      OUTPUT_STRIP_TRAILING_WHITESPACE OUTPUT_VARIABLE processorId)
   if("${processorId}" MATCHES "AMD64")
      set(chip "x86_64")
   elseif("${processorId}" MATCHES "x86")
      set(chip "x86")
   else()
      set(chip "unknown")
   endif()
endif()

if("${arch}" MATCHES "[Ww]indows" OR "${arch}" MATCHES "win7")
   find_program(CL cl)
   execute_process(COMMAND ${CL} /nologo -EP "${CTEST_SOURCE_DIRECTORY}/cmake/msvc_version.c" OUTPUT_STRIP_TRAILING_WHITESPACE OUTPUT_VARIABLE COMPILER_VERSION)
   string(STRIP "${COMPILER_VERSION}" COMPILER_VERSION)
   if("${CL}" MATCHES "amd64")
      set(COMPILER_VERSION "${COMPILER_VERSION} x86 64bit")
   elseif("${CL}" MATCHES "ia64")
      set(COMPILER_VERSION "${COMPILER_VERSION} Itanium")
   else()
      set(COMPILER_VERSION "${COMPILER_VERSION} x86 32bit")
   endif()
   set(number_of_processors "$ENV{NUMBER_OF_PROCESSORS}")
   if(NOT number_of_processors)
      execute_process(COMMAND
         reg query "HKLM\\HARDWARE\\DESCRIPTION\\System\\CentralProcessor"
         OUTPUT_STRIP_TRAILING_WHITESPACE OUTPUT_VARIABLE number_of_processors)
      string(REGEX REPLACE "[^0-9]+" "," number_of_processors "${number_of_processors}")
      string(REGEX REPLACE "^.*," "" number_of_processors "${number_of_processors}")
      math(EXPR number_of_processors "1 + ${number_of_processors}")
   endif()
elseif(arch MATCHES "mingw")
   find_program(CL cl)
   find_program(GXX "g++")
   if("$ENV{CXX}" MATCHES "g\\+\\+")
      set(GXX "$ENV{CXX}")
   endif()
   if(GXX)
      execute_process(COMMAND "${GXX}" --version OUTPUT_VARIABLE COMPILER_VERSION ERROR_VARIABLE COMPILER_VERSION OUTPUT_STRIP_TRAILING_WHITESPACE)
      string(REPLACE "\n" ";" COMPILER_VERSION "${COMPILER_VERSION}")
      list(GET COMPILER_VERSION 0 COMPILER_VERSION)
   elseif(CL)
      execute_process(COMMAND ${CL} /nologo -EP "${CTEST_SOURCE_DIRECTORY}/cmake/msvc_version.c" OUTPUT_STRIP_TRAILING_WHITESPACE OUTPUT_VARIABLE COMPILER_VERSION)
      string(STRIP "${COMPILER_VERSION}" COMPILER_VERSION)
   else()
      message(FATAL_ERROR "unknown compiler")
   endif()
   execute_process(COMMAND reg query "HKLM\\HARDWARE\\DESCRIPTION\\System\\CentralProcessor" COMMAND grep -c CentralProcessor OUTPUT_STRIP_TRAILING_WHITESPACE OUTPUT_VARIABLE number_of_processors)
else()
   set(_cxx "$ENV{CXX}")
   if(NOT _cxx)
      find_program(GXX "g++")
      if(GXX)
         set(_cxx "${GXX}")
      else()
         set(_cxx "c++")
      endif()
   endif()
   execute_process(COMMAND ${_cxx} --version OUTPUT_VARIABLE COMPILER_VERSION_COMPLETE ERROR_VARIABLE COMPILER_VERSION_COMPLETE OUTPUT_STRIP_TRAILING_WHITESPACE)
   string(REPLACE "\n" ";" COMPILER_VERSION "${COMPILER_VERSION_COMPLETE}")
   list(GET COMPILER_VERSION 0 COMPILER_VERSION)
   string(REPLACE "Open64 Compiler Suite: Version" "Open64" COMPILER_VERSION "${COMPILER_VERSION}")
   if(arch STREQUAL "darwin")
      execute_process(COMMAND sysctl -n hw.ncpu OUTPUT_STRIP_TRAILING_WHITESPACE OUTPUT_VARIABLE number_of_processors)
   else()
      execute_process(COMMAND grep -c processor /proc/cpuinfo OUTPUT_STRIP_TRAILING_WHITESPACE OUTPUT_VARIABLE number_of_processors)
   endif()
endif()

file(READ "${CTEST_SOURCE_DIRECTORY}/.git/HEAD" git_branch)
string(STRIP "${git_branch}" git_branch)
# -> ref: refs/heads/master
string(REGEX REPLACE "^.*/" "" git_branch "${git_branch}")
# -> master

if(arch STREQUAL "linux")
   execute_process(COMMAND lsb_release -d COMMAND cut -f2 OUTPUT_STRIP_TRAILING_WHITESPACE OUTPUT_VARIABLE lsbRelease)
   set(CTEST_BUILD_NAME "${lsbRelease}")
else()
   set(CTEST_BUILD_NAME "${arch}")
endif()
string(STRIP "${CTEST_BUILD_NAME} ${chip} ${COMPILER_VERSION} $ENV{CXXFLAGS}" CTEST_BUILD_NAME)
set(CTEST_BUILD_NAME "${CTEST_BUILD_NAME} ${build_type}")
if(target_architecture)
   set(CTEST_BUILD_NAME "${CTEST_BUILD_NAME} ${target_architecture}")
else()
   execute_process(COMMAND cmake -Darch=${arch} -P ${CTEST_SOURCE_DIRECTORY}/print_target_architecture.cmake OUTPUT_STRIP_TRAILING_WHITESPACE OUTPUT_VARIABLE auto_target_arch ERROR_VARIABLE auto_target_arch)
   set(CTEST_BUILD_NAME "${CTEST_BUILD_NAME} ${auto_target_arch}")
endif()
string(REPLACE "/" "_" CTEST_BUILD_NAME "${git_branch}: ${CTEST_BUILD_NAME}")
string(REPLACE "+" "x" CTEST_BUILD_NAME "${CTEST_BUILD_NAME}") # CDash fails to escape '+' correctly in URIs
string(REGEX REPLACE "[][ ():]" "_" CTEST_BINARY_DIRECTORY "${CTEST_BUILD_NAME}")
set(CTEST_BINARY_DIRECTORY "${CTEST_SOURCE_DIRECTORY}/build-${dashboard_model}-${CTEST_BINARY_DIRECTORY}")
file(MAKE_DIRECTORY "${CTEST_BINARY_DIRECTORY}")

execute_process(COMMAND hostname -s RESULT_VARIABLE ok OUTPUT_VARIABLE CTEST_SITE ERROR_QUIET OUTPUT_STRIP_TRAILING_WHITESPACE)
if(NOT ok EQUAL 0)
   execute_process(COMMAND hostname OUTPUT_VARIABLE CTEST_SITE ERROR_QUIET OUTPUT_STRIP_TRAILING_WHITESPACE)
endif()

Set(CTEST_START_WITH_EMPTY_BINARY_DIRECTORY_ONCE TRUE)

set(CTEST_NOTES_FILES "${CTEST_SOURCE_DIRECTORY}/.git/HEAD" "${CTEST_SOURCE_DIRECTORY}/.git/refs/heads/${git_branch}")

set(compiler)
if(COMPILER_VERSION MATCHES "clang")
   set(compiler "clang")
elseif(COMPILER_VERSION MATCHES "MSVC")
   set(compiler "MSVC")
elseif(COMPILER_VERSION MATCHES "ICC")
   set(compiler "ICC")
elseif(COMPILER_VERSION MATCHES "Open64")
   set(compiler "Open64")
elseif(COMPILER_VERSION MATCHES "g\\+\\+" OR COMPILER_VERSION_COMPLETE MATCHES "Free Software Foundation, Inc.")
   if(WIN32)
      set(compiler "mingw")
   else()
      set(compiler "GCC")
   endif()
endif()
if(COMPILER_VERSION MATCHES "\\((experimental|prerelease)\\)" OR COMPILER_VERSION_COMPLETE MATCHES "clang.git")
   set(compiler "experimental")
endif()

include(${CTEST_SOURCE_DIRECTORY}/CTestConfig.cmake)
ctest_read_custom_files(${CTEST_SOURCE_DIRECTORY})
set(CTEST_USE_LAUNCHERS 0) # launchers once lead to much improved error/warning
                           # message logging. Nowadays they lead to no warning/
                           # error messages on the dashboard at all.
if(WIN32)
   set(MAKE_ARGS "-k")
else()
   set(MAKE_ARGS "-j${number_of_processors} -k")
endif()

message("********************************")
#message("src:        ${CTEST_SOURCE_DIRECTORY}")
#message("obj:        ${CTEST_BINARY_DIRECTORY}")
message("build name: ${CTEST_BUILD_NAME}")
message("site:       ${CTEST_SITE}")
message("model:      ${dashboard_model}")
message("********************************")

if(WIN32)
   if("${compiler}" STREQUAL "MSVC")
      find_program(JOM jom)
      if(JOM)
	 set(CTEST_CMAKE_GENERATOR "NMake Makefiles JOM")
	 set(CMAKE_MAKE_PROGRAM "jom")
      else()
	 set(CTEST_CMAKE_GENERATOR "NMake Makefiles")
	 set(CMAKE_MAKE_PROGRAM "nmake")
	 set(MAKE_ARGS "-I")
      endif()
   elseif("${compiler}" STREQUAL "mingw")
      set(CTEST_CMAKE_GENERATOR "MSYS Makefiles")
      set(CMAKE_MAKE_PROGRAM "make")
   else()
      message(FATAL_ERROR "unknown cmake generator required (compiler: ${compiler})")
   endif()
else()
   set(CTEST_CMAKE_GENERATOR "Unix Makefiles")
   set(CMAKE_MAKE_PROGRAM "make")
endif()

set(configure_options "-DCTEST_USE_LAUNCHERS=${CTEST_USE_LAUNCHERS};-DCMAKE_BUILD_TYPE=${build_type};-DBUILD_EXAMPLES=TRUE;-DTEST_OPERATOR_FAILURES=TRUE")
if(target_architecture)
   set(configure_options "${configure_options};-DTARGET_ARCHITECTURE=${target_architecture}")
endif()

macro(go)
   set_property(GLOBAL PROPERTY SubProject "master: ${compiler}")
   set_property(GLOBAL PROPERTY Label other)
   CTEST_START (${dashboard_model})
   set(res 0)
   if(NOT ${dashboard_model} STREQUAL "Experimental")
      CTEST_UPDATE (SOURCE "${CTEST_SOURCE_DIRECTORY}" RETURN_VALUE res)
      if(res GREATER 0)
         ctest_submit(PARTS Update)
      endif()
   endif()
   if(NOT ${dashboard_model} STREQUAL "Continuous" OR res GREATER 0)
      if("${COMPILER_VERSION}" MATCHES "(g\\+\\+|GCC|Open64).*4\\.[0123456]\\.")
         file(WRITE "${CTEST_BINARY_DIRECTORY}/abort_reason" "Compiler too old for C++11: ${COMPILER_VERSION}")
         list(APPEND CTEST_NOTES_FILES "${CTEST_BINARY_DIRECTORY}/abort_reason")
         ctest_submit(PARTS Notes)
         set(res 1)
      else()
         CTEST_CONFIGURE (BUILD "${CTEST_BINARY_DIRECTORY}"
            OPTIONS "${configure_options}"
            APPEND
            RETURN_VALUE res)
         ctest_submit(PARTS Notes Configure)
      endif()
      if(res EQUAL 0)
         foreach(label other Scalar SSE AVX AVX2 MIC)
            set_property(GLOBAL PROPERTY Label ${label})
            set(CTEST_BUILD_TARGET "${label}")
            set(CTEST_BUILD_COMMAND "${CMAKE_MAKE_PROGRAM} ${MAKE_ARGS} ${CTEST_BUILD_TARGET}")
            ctest_build(
               BUILD "${CTEST_BINARY_DIRECTORY}"
               APPEND
               RETURN_VALUE res)
            ctest_submit(PARTS Build)
            if(res EQUAL 0 AND NOT skip_tests)
               ctest_test(
                  BUILD "${CTEST_BINARY_DIRECTORY}"
                  APPEND
                  RETURN_VALUE res
                  PARALLEL_LEVEL ${number_of_processors}
                  INCLUDE_LABEL "${label}")
               ctest_submit(PARTS Test)
            endif()
         endforeach()
      endif()
   endif()
endmacro()

if(${dashboard_model} STREQUAL "Continuous")
   while(${CTEST_ELAPSED_TIME} LESS 64800)
      set(START_TIME ${CTEST_ELAPSED_TIME})
      go()
      ctest_sleep(${START_TIME} 1200 ${CTEST_ELAPSED_TIME})
   endwhile()
else()
   CTEST_EMPTY_BINARY_DIRECTORY(${CTEST_BINARY_DIRECTORY})
   go()
endif()
