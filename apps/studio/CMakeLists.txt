# Studio (aster-studio) — budowane z głównego CMakeLists.txt repozytorium.
# Dźwięk: PipeWire (pipewire-devel) w wątku czasu rzeczywistego; pliki: libsndfile (WAV/FLAC/OGG/MP3);
# przepróbkowanie importu: libsamplerate; klawiatury MIDI: sekwencer ALSA (alsa-lib-devel);
# udostępnianie: okładka w tagach MP3 (taglib-devel), paczka projektu (libarchive-devel).
find_package(PkgConfig REQUIRED)
pkg_check_modules(PIPEWIRE REQUIRED IMPORTED_TARGET libpipewire-0.3)
pkg_check_modules(SNDFILE REQUIRED IMPORTED_TARGET sndfile)
pkg_check_modules(SAMPLERATE REQUIRED IMPORTED_TARGET samplerate)
pkg_check_modules(ALSA REQUIRED IMPORTED_TARGET alsa)
pkg_check_modules(TAGLIB REQUIRED IMPORTED_TARGET taglib)
pkg_check_modules(LIBARCHIVE REQUIRED IMPORTED_TARGET libarchive)

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
    qml/Lyrics.qml
    qml/LyricText.qml
    qml/Prompter.qml
    qml/PatternEditor.qml
    qml/PianoRoll.qml
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
        src/analysis.cpp src/analysis.h src/lyrics.cpp src/lyrics.h src/denoise.cpp src/denoise.h src/fft.h
        src/audiosource.cpp
        src/audiosource.h
        src/dsp.h
        src/midiinput.cpp
        src/share.cpp
        src/share.h
        src/midiinput.h
        src/tune.h
        src/synthvoice.h
        src/beatsynth.cpp
        src/beatsynth.h
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
    PkgConfig::ALSA
    PkgConfig::TAGLIB
    PkgConfig::LIBARCHIVE
    KF6::WindowSystem
    aster-uiplugin
)

install(TARGETS aster-studio RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
install(FILES org.aster.studio.desktop DESTINATION ${CMAKE_INSTALL_DATADIR}/applications)
