# Muzyka (aster-music) — budowana z głównego CMakeLists.txt repozytorium.
# Odtwarzanie: Qt Multimedia; tagi i okładki: TagLib (pakiet taglib-devel).
find_package(PkgConfig REQUIRED)
pkg_check_modules(TAGLIB REQUIRED IMPORTED_TARGET taglib)
find_package(Qt6 REQUIRED COMPONENTS Multimedia Concurrent)

qt_add_executable(aster-music src/main.cpp)
target_include_directories(aster-music PRIVATE src)

set(MUSIC_QML
    qml/Main.qml
    qml/Playback.qml
    qml/TrackList.qml
)
foreach(f ${MUSIC_QML})
    get_filename_component(name ${f} NAME)
    set_source_files_properties(${f} PROPERTIES QT_RESOURCE_ALIAS ${name})
endforeach()

qt_add_qml_module(aster-music
    URI Aster.Music
    VERSION 1.0
    QML_FILES ${MUSIC_QML}
    SOURCES
        src/library.cpp
        src/library.h
        src/roundimage.cpp
        src/roundimage.h
        ${CMAKE_SOURCE_DIR}/common/mediasession.cpp
        ${CMAKE_SOURCE_DIR}/common/mediasession.h
)

target_link_libraries(aster-music PRIVATE
    Qt6::Gui
    Qt6::Quick
    Qt6::Qml
    Qt6::DBus
    Qt6::Multimedia
    Qt6::Concurrent
    PkgConfig::TAGLIB
    KF6::WindowSystem
    aster-uiplugin
)

install(TARGETS aster-music RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
install(FILES org.aster.music.desktop DESTINATION ${CMAKE_INSTALL_DATADIR}/applications)
