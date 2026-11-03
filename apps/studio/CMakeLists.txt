# Studio (aster-studio) — budowane z głównego CMakeLists.txt repozytorium.
# Dźwięk: PipeWire (pipewire-devel) w wątku czasu rzeczywistego; pliki: libsndfile (WAV/FLAC/OGG/MP3);
# przepróbkowanie importu: libsamplerate.
find_package(PkgConfig REQUIRED)
pkg_check_modules(PIPEWIRE REQUIRED IMPORTED_TARGET libpipewire-0.3)
pkg_check_modules(SNDFILE REQUIRED IMPORTED_TARGET sndfile)
pkg_check_modules(SAMPLERATE REQUIRED IMPORTED_TARGET samplerate)

qt_add_executable(aster-studio src/main.cpp)
target_include_directories(aster-studio PRIVATE src)

set(STUDIO_QML
    qml/Main.qml
    qml/StartPage.qml
    qml/Timeline.qml
    qml/Mixer.qml
    qml/Sheet.qml
    qml/Pill.qml
    qml/Tip.qml
    qml/Field.qml
    qml/Segmented.qml
    qml/Inspector.qml
)
foreach(f ${STUDIO_QML})
    get_filename_component(name ${f} NAME)
    set_source_files_properties(${f} PROPERTIES QT_RESOURCE_ALIAS ${name})
endforeach()

qt_add_qml_module(aster-studio
    URI Aster.Studio
    VERSION 1.0
    QML_FILES ${STUDIO_QML}
    SOURCES
        src/audiosource.cpp
        src/audiosource.h
        src/dsp.h
        src/engine.cpp
        src/engine.h
        src/studio.cpp
        src/studio.h
        src/waveform.cpp
        src/waveform.h
)

target_link_libraries(aster-studio PRIVATE
    Qt6::Gui
    Qt6::Quick
    Qt6::Qml
    Qt6::DBus
    PkgConfig::PIPEWIRE
    PkgConfig::SNDFILE
    PkgConfig::SAMPLERATE
    KF6::WindowSystem
    aster-uiplugin
)

install(TARGETS aster-studio RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
install(FILES org.aster.studio.desktop DESTINATION ${CMAKE_INSTALL_DATADIR}/applications)
