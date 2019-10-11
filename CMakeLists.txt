project (mavlink)

if (NOT DEFINED MAVLINK_SOURCE_DIR)
    set(MAVLINK_SOURCE_DIR ${CMAKE_SOURCE_DIR})
endif ()

# settings
cmake_minimum_required (VERSION 2.8.2)
set(PROJECT_VERSION_MAJOR "1")
set(PROJECT_VERSION_MINOR "0")
set(PROJECT_VERSION_PATCH "9")
set(PROJECT_VERSION "${PROJECT_VERSION_MAJOR}.${PROJECT_VERSION_MINOR}.${PROJECT_VERSION_PATCH}")
set(PROJECT_CONTACT_EMAIL http://groups.google.com/group/mavlink)
set(PROJECT_CONTACT_VENDOR mavlink)
set(LIBRARY_VERSION ${PROJECT_VERSION})
set(LIBRARY_SOVERSION "0.0.0")

# third party 
# none required

# options
option(WITH_TESTS "Build test programs." OFF)
option(WITH_BUILD_DEPS "Build dependencies." OFF) # no deps currently to build
option(WITH_BUILD_STATIC "Build preferring static linking." ON)

# variables
set(ROOT_THREAD TRUE CACHE INTERNAL "Is this the top level of the recursion?")

# modules
list(APPEND CMAKE_MODULE_PATH ${MAVLINK_SOURCE_DIR}/cmake ${MAVLINK_SOURCE_DIR}/cmake/arkcmake)
include(DefineCMakeDefaults)
include(CheckIncludeFiles)
include(CheckFunctionExists)
include(CheckSymbolExists)
include(CheckLibraryExists)
#include(CheckTypeSize)
#include(CheckPrototypeExists)
#include(CheckCXXSourceCompiles)
#include(CheckCSourceCompiles)
include(ExternalProjectWithFilename)
include(CMakePackageConfigHelpers)

if (UNIX)
    include(GNUInstallDirs)
    set(LIB_INSTALL_DIR "lib${LIB_SUFFIX}" CACHE PATH "Installation path for libraries")
endif ()


# spawn new cmake to build deps
if (WITH_BUILD_DEPS AND ROOT_THREAD)
    execute_process(COMMAND ${CMAKE_COMMAND} "${MAVLINK_SOURCE_DIR}"
        "-DCMAKE_TOOLCHAIN_FILE=${CMAKE_TOOLCHAIN_FILE}"
        "-DCMAKE_INSTALL_PREFIX=${CMAKE_INSTALL_PREFIX}"
        "-DWITH_BUILD_DEPS=${WITH_BUILD_DEPS}"
        "-DWITH_BUILD_STATIC=${WITH_BUILD_STATIC}"
        "-DWITH_TESTS=${WITH_TESTS}"
        "-DROOT_THREAD=FALSE"
        RESULT_VARIABLE ERROR)
    if (ERROR)
        message(FATAL_ERROR "error, recursing loop returned error code: ${ERROR}")
    endif()
    message("** Making dependencies")
    execute_process(COMMAND ${CMAKE_MAKE_PROGRAM} "-j4" "-f${CMAKE_BINARY_DIR}/Makefile")
    message("** Configuring ${PROJECT_NAME}")
endif()

# external projects find path
if(NOT EP_BASE_DIR)
    set(EP_BASE_DIR "${CMAKE_BINARY_DIR}/CMakeExternals")
endif()
set_property(DIRECTORY PROPERTY EP_BASE ${EP_BASE_DIR})
set(EP_INSTALL_DIR "${EP_BASE_DIR}/Install")
list(APPEND CMAKE_FIND_ROOT_PATH ${EP_BASE_DIR})

# prefer static packages if building static library
message("** Finding libraries")
if (WITH_BUILD_STATIC)
    # prefer static libs
    if(WIN32)
        set(CMAKE_FIND_LIBRARY_SUFFIXES .lib .a ${CMAKE_FIND_LIBRARY_SUFFIXES})
    else()
        set(CMAKE_FIND_LIBRARY_SUFFIXES .a ${CMAKE_FIND_LIBRARY_SUFFIXES})
    endif()
endif()

# find libraries with cmake modules
find_package(PythonInterp)

# enable languages
if (WITH_TESTS)
    enable_language(C)
    enable_language(CXX)
    include(DefineCompilerFlags)
endif()

# build dependencies
if (WITH_BUILD_DEPS AND (NOT ROOT_THREAD) )
    message("** Configuring dependencies")

    # add external projects

    # none required currently

    set(CMAKE_DEFAULT_ARGS
        -DEP_BASE_DIR=${EP_BASE_DIR}
        -DCMAKE_TOOLCHAIN_FILE=${CMAKE_TOOLCHAIN_FILE}
        -DCMAKE_INSTALL_PREFIX=${CMAKE_INSTALL_PREFIX}
        )

    # terminate non root cmake thread
    return()
endif()

# configure
#check_include_files(string.h HAVE_STRING_H)
#check_function_exists(memcopy HAVE_MEMCOPY)
#check_symbol_exists(LC_MESSAGES "locale.h" HAVE_LC_MESSAGES) 
#check_library_exists(pthread  attachNode "" HAVE_PTHREAD)

# config files
configure_file(config.h.in config.h)
install(FILES ${CMAKE_BINARY_DIR}/config.h DESTINATION include/${PROJECT_NAME} COMPONENT Dev)

# mavlink generation
set(mavgen_path ${CMAKE_SOURCE_DIR}/pymavlink/tools/mavgen.py)
set(common_xml_path ${CMAKE_SOURCE_DIR}/message_definitions/v1.0/common.xml)
macro(generateMavlink_v10 definitions)
    foreach(definitionAbsPath ${definitions})
        get_filename_component(definition ${definitionAbsPath} NAME_WE)
        message(STATUS "processing v1.0: ${definitionAbsPath}")
        add_custom_command(
            OUTPUT include/v1.0/${definition}/${definition}.h
            COMMAND /usr/bin/env PYTHONPATH="${CMAKE_SOURCE_DIR}:$ENV{PYTHONPATH}"
                ${PYTHON_EXECUTABLE} ${mavgen_path} --lang=C --wire-protocol=1.0
                --output=include/v1.0 ${definitionAbsPath}
            DEPENDS ${definitionAbsPath} ${common_xml_path} ${mavgen_path}
            )
        add_custom_target(${definition}.xml-v1.0
            ALL DEPENDS include/v1.0/${definition}/${definition}.h
            )
    endforeach()
endmacro()
macro(generateMavlink_v20 definitions)
    foreach(definitionAbsPath ${definitions})
        get_filename_component(definition ${definitionAbsPath} NAME_WE)
        message(STATUS "processing v2.0: ${definitionAbsPath}")

        # mavgen C++ also do C gen
        add_custom_command(
            OUTPUT ${definition}-v2.0-cxx-stamp
            #OUTPUT include/v2.0/${definition}/${definition}.hpp
            COMMAND /usr/bin/env PYTHONPATH="${CMAKE_SOURCE_DIR}:$ENV{PYTHONPATH}"
                ${PYTHON_EXECUTABLE} ${mavgen_path} --lang=C++11 --wire-protocol=2.0
                --output=include/v2.0 ${definitionAbsPath}
            COMMAND touch ${definition}-v2.0-cxx-stamp
            DEPENDS ${definitionAbsPath} ${common_xml_path} ${mavgen_path}
            )
        add_custom_target(${definition}.xml-v2.0
            ALL DEPENDS
                ${definition}-v2.0-cxx-stamp
                #include/v2.0/${definition}/${definition}.hpp
            )
    endforeach()

    # XXX NOTE: that is workaround v2.0 mavgen bug:
    #           when it generate other dialect than common.xml
    #           resulting common.h/.hpp does not have extended enums like MAV_CMD
    #
    #           So we use stamp file to force run of mavgen and add all other xml to common.xml dependencies.
    foreach(definitionAbsPath ${definitions})
        get_filename_component(definition ${definitionAbsPath} NAME_WE)
        add_dependencies(common.xml-v2.0 ${definition}.xml-v2.0)
    endforeach()
endmacro()

# build v1.0
file(GLOB V10DEFINITIONS ${CMAKE_SOURCE_DIR}/message_definitions/v1.0/*.xml)

# do not generate testing dialects
foreach(definition minimal test python_array_test)
    list(REMOVE_ITEM V10DEFINITIONS "${CMAKE_SOURCE_DIR}/message_definitions/v1.0/${definition}.xml")
endforeach()
list(SORT V10DEFINITIONS)

generateMavlink_v10("${V10DEFINITIONS}")

# build v2.0 if it is supported. for now it uses same definitions as v1.0
if(EXISTS "${CMAKE_SOURCE_DIR}/pymavlink/generator/C/include_v2.0")
    set(V20DEFINITIONS "${V10DEFINITIONS}")
    generateMavlink_v20("${V20DEFINITIONS}")
endif()

# testing
if (BUILD_TEST)
    if (UNIX) 
        include_directories(${CMAKE_BINARY_DIR}/include/v1.0/common)
        # TODO fix udp example
        #add_executable(mavlink_udp examples/linux/mavlink_udp.c)
    endif()
endif()

# install files
install(DIRECTORY ${CMAKE_BINARY_DIR}/include/ DESTINATION include/${PROJECT_NAME} COMPONENT Dev FILES_MATCHING PATTERN "*.h*")
install(DIRECTORY ${CMAKE_BINARY_DIR}/src/ DESTINATION share/${PROJECT_NAME} COMPONENT Dev FILES_MATCHING PATTERN "*.c*")
install(DIRECTORY ${MAVLINK_SOURCE_DIR}/share/${PROJECT_NAME} DESTINATION share COMPONENT Dev FILES_MATCHING PATTERN "*.c*")
if (UNIX)
    install(DIRECTORY ${MAVLINK_SOURCE_DIR}/pymavlink DESTINATION ${CMAKE_INSTALL_LIBDIR}/python${PYTHON_VERSION_MAJOR}.${PYTHON_VERSION_MINOR}/site-packages COMPONENT Dev)
else ()
    install(DIRECTORY ${MAVLINK_SOURCE_DIR}/pymavlink DESTINATION "share/pyshared" COMPONENT Dev)
endif ()

configure_file(pc.in ${PROJECT_NAME}.pc)
install(FILES
    ${PROJECT_BINARY_DIR}/${PROJECT_NAME}.pc
    DESTINATION lib${LIB_SUFFIX}/pkgconfig COMPONENT Dev
    )

set(PKG_NAME ${PROJECT_NAME})
set(PKG2_NAME "${PROJECT_NAME}2")
set(PKG_VERSION ${PROJECT_VERSION})
set(PKG_DESC "MAVLink micro air vehicle marshalling / communication library")
set(PKG_LIBRARIES )
set(PKG_DEPENDS )
set(PKG_MAVLINK_DEFINITIONS "${V10DEFINITIONS}")
set(PKG2_MAVLINK_DEFINITIONS "${V20DEFINITIONS}")
foreach(def ${V10DEFINITIONS})
    get_filename_component(dialect "${def}" NAME_WE)
    list(APPEND PKG_MAVLINK_DIALECTS ${dialect})
endforeach()
foreach(def ${V20DEFINITIONS})
    get_filename_component(dialect "${def}" NAME_WE)
    list(APPEND PKG2_MAVLINK_DIALECTS ${dialect})
endforeach()

set(cmake_package_name ${PROJECT_NAME})
set(targets_export_name ${cmake_package_name}Targets CACHE INTERNAL "")
set(generated_dir "${CMAKE_CURRENT_BINARY_DIR}/generated" CACHE INTERNAL "")
set(cmake_files_install_dir "${CMAKE_INSTALL_LIBDIR}/cmake/${cmake_package_name}")
set(version_file "${generated_dir}/${cmake_package_name}ConfigVersion.cmake")
write_basic_package_version_file(${version_file} VERSION ${PROJECT_VERSION} COMPATIBILITY AnyNewerVersion)
set(config_file "${generated_dir}/${cmake_package_name}Config.cmake")
configure_package_config_file("cmake/${PROJECT_NAME}-config.cmake.in"
    "${config_file}" INSTALL_DESTINATION ${cmake_files_install_dir})
install(FILES ${version_file} ${config_file}
    DESTINATION ${cmake_files_install_dir})

### packaging

# apple bundle icon
if (APPLE)
    # set how it shows up in Info.plist
    set(MACOSX_BUNDLE_ICON_FILE mavlink.icns)
    # set where in the bundle to put the icns file
    set_source_files_properties(cmake/mavlink.icns PROPERTIES MACOSX_PACKAGE_LOCATION Resources)
    # include the icns file in the target
    #list(APPEND MAVLINKGUI_SRCS cmake/mavlink.icns)
endif()

# set NSIS image
if (WIN32)
    set(CPACK_PACKAGE_ICON "${MAVLINK_SOURCE_DIR}/cmake/mavlink.bmp")
endif()

# add file extensions and set resource files
configure_file("COPYING" "COPYING.txt" COPYONLY)
configure_file("README.md" "README.md" COPYONLY)
set(CPACK_RESOURCE_FILE_LICENSE "${MAVLINK_SOURCE_DIR}/COPYING")
set(CPACK_RESOURCE_FILE_README "${MAVLINK_SOURCE_DIR}/README.md")
set(CPACK_PACKAGE_DESCRIPTION_FILE "${CPACK_RESOURCE_FILE_README}")
set(CPACK_RESOURCE_FILE_WELCOME "${MAVLINK_SOURCE_DIR}/cmake/WELCOME.txt")
set(CPACK_PACKAGE_DESCRIPTION_SUMMARY "mavlink message marshalling library")
set(CPACK_PACKAGE_VENDOR ${PROJECT_CONTACT_VENDOR})
set(CPACK_PACKAGE_CONTACT "${PROJECT_CONTACT_EMAIL}")
set(CPACK_PACKAGE_VERSION ${PROJECT_VERSION})
set(CPACK_SET_DESTDIR TRUE)
set(CPACK_PACKAGE_FILE_NAME "${PROJECT_NAME}-${PROJECT_VERSION}")
set(CPACK_COMPONENTS_GROUPING "ALL_COMPONENTS_IN_ONE")
include(CPack)


# vim:sw=4:ts=4:expandtab
