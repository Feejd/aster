# Wideo (aster-video) — budowane z głównego CMakeLists.txt repozytorium.
# Odtwarzanie: Qt Multimedia (pakiet qt6-qtmultimedia-devel; kodeki z FFmpeg).
find_package(Qt6 REQUIRED COMPONENTS Multimedia)

qt_add_executable(aster-video src/main.cpp)
target_include_directories(aster-video PRIVATE src)

set(VIDEO_QML
    qml/Main.qml
    qml/Player.qml
    qml/SeekBar.qml
)
foreach(f ${VIDEO_QML})
    get_filename_component(name ${f} NAME)
    set_source_files_properties(${f} PROPERTIES QT_RESOURCE_ALIAS ${name})
endforeach()

qt_add_qml_module(aster-video
    URI Aster.Video
    VERSION 1.0
    QML_FILES ${VIDEO_QML}
    SOURCES
        src/video.cpp
        src/video.h
        ${CMAKE_SOURCE_DIR}/common/mediasession.cpp
        ${CMAKE_SOURCE_DIR}/common/mediasession.h
)

target_link_libraries(aster-video PRIVATE
    Qt6::Gui
    Qt6::Quick
    Qt6::Qml
    Qt6::DBus
    Qt6::Multimedia
    aster-uiplugin
)

install(TARGETS aster-video RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
install(FILES org.aster.video.desktop DESTINATION ${CMAKE_INSTALL_DATADIR}/applications)
