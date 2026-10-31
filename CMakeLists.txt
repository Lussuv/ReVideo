cmake_minimum_required(VERSION 3.25)
project(ReVideo VERSION 3.8.1 DESCRIPTION "Video-Player und Trimmer" LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 6.5 REQUIRED COMPONENTS Core Gui Network OpenGL Quick QuickControls2 Test Widgets)
if(LINUX)
    find_package(Qt6 REQUIRED COMPONENTS DBus)
endif()
find_package(PkgConfig REQUIRED)
pkg_check_modules(MPV REQUIRED IMPORTED_TARGET mpv)

qt_standard_project_setup(REQUIRES 6.5)
if(QT_KNOWN_POLICY_QTP0004)
    qt_policy(SET QTP0004 NEW)
endif()

# Logic without QML, shared by the app and the tests.
add_library(revideo_core STATIC
    src/exportjob.cpp src/exportjob.h
    src/files.cpp src/files.h
    src/format.cpp src/format.h
    src/settings.cpp src/settings.h
    src/version.cpp src/version.h
)
target_include_directories(revideo_core PUBLIC src)
target_link_libraries(revideo_core PUBLIC Qt6::Core)
if(LINUX)
    target_link_libraries(revideo_core PUBLIC Qt6::DBus)
endif()

qt_add_executable(revideo src/main.cpp)
set_target_properties(revideo PROPERTIES WIN32_EXECUTABLE ON)
if(WIN32)
    set_target_properties(revideo PROPERTIES OUTPUT_NAME ReVideo)
    set(ICON_PATH ${CMAKE_SOURCE_DIR}/assets/icon.ico)
    configure_file(packaging/windows/revideo.rc.in revideo.rc @ONLY)
    target_sources(revideo PRIVATE ${CMAKE_CURRENT_BINARY_DIR}/revideo.rc)
endif()
target_compile_definitions(revideo PRIVATE APP_VERSION="${PROJECT_VERSION}")

set_source_files_properties(src/qml/Theme.qml PROPERTIES QT_QML_SINGLETON_TYPE TRUE)
qt_add_qml_module(revideo
    URI ReVideo
    QML_FILES
        src/qml/Main.qml
        src/qml/Theme.qml
        src/qml/Icon.qml
        src/qml/Btn.qml
        src/qml/Tip.qml
        src/qml/Sheet.qml
        src/qml/SeekSlider.qml
        src/qml/TopBar.qml
        src/qml/Controls.qml
        src/qml/TrimPanel.qml
        src/qml/Timeline.qml
        src/qml/ExportMenu.qml
        src/qml/InfoPopover.qml
        src/qml/DeleteDialog.qml
        src/qml/UpdateDialog.qml
    SOURCES
        src/mpvitem.cpp src/mpvitem.h
        src/util.cpp src/util.h
        src/exporter.cpp src/exporter.h
        src/thumbnailer.cpp src/thumbnailer.h
        src/updater.cpp src/updater.h
)
qt_add_resources(revideo assets PREFIX / FILES
    assets/icon-128.png
    assets/fonts/Inter-Regular.ttf
    assets/fonts/Inter-SemiBold.ttf
    assets/fonts/JetBrainsMono-Regular.ttf
)
target_link_libraries(revideo PRIVATE
    revideo_core Qt6::Gui Qt6::Network Qt6::OpenGL Qt6::Quick Qt6::QuickControls2 Qt6::Widgets PkgConfig::MPV)

install(TARGETS revideo RUNTIME DESTINATION bin)
if(LINUX)
    install(FILES packaging/linux/de.retrydev.ReVideo.desktop DESTINATION share/applications)
    install(FILES packaging/linux/de.retrydev.ReVideo.metainfo.xml DESTINATION share/metainfo)
    install(FILES assets/icon.png DESTINATION share/icons/hicolor/512x512/apps RENAME de.retrydev.ReVideo.png)
    install(FILES assets/icon-128.png DESTINATION share/icons/hicolor/128x128/apps RENAME de.retrydev.ReVideo.png)
endif()

enable_testing()
qt_add_executable(revideo_tests tests/tst_core.cpp)
target_link_libraries(revideo_tests PRIVATE revideo_core Qt6::Test)
add_test(NAME core COMMAND revideo_tests)
