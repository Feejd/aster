# Montaż (aster-montaz) — budowane z głównego CMakeLists.txt repozytorium.
# Silnik: MLT 7 (pakiet mlt-devel, API C++ mlt++) — ten sam, na którym stoją Kdenlive i Shotcut;
# podgląd: klatki z MLT jako tekstura w scenie QML, eksport przez FFmpeg (konsument avformat MLT),
# nagrywanie lektora z mikrofonu: Qt Multimedia (QAudioSource).
find_package(Qt6 REQUIRED COMPONENTS DBus Network Multimedia)
# Napisy z mowy: whisper.cpp (pakiet whisper-cpp-devel); bez niego program działa, tylko bez tej funkcji
find_package(whisper CONFIG QUIET)
find_package(PkgConfig REQUIRED)
pkg_check_modules(MLT REQUIRED IMPORTED_TARGET mlt++-7)

qt_add_executable(aster-montaz src/main.cpp)
target_include_directories(aster-montaz PRIVATE src)

set(MONTAZ_QML
    qml/Main.qml
    qml/Home.qml
    qml/Editor.qml
    qml/Timeline.qml
    qml/Inspector.qml
    qml/ExportSheet.qml
    qml/CaptionsSheet.qml
    qml/StickerPanel.qml
    qml/VoiceBar.qml
)
foreach(f ${MONTAZ_QML})
    get_filename_component(name ${f} NAME)
    set_source_files_properties(${f} PROPERTIES QT_RESOURCE_ALIAS ${name})
endforeach()

qt_add_qml_module(aster-montaz
    URI Aster.Montaz
    VERSION 1.0
    QML_FILES ${MONTAZ_QML}
    SOURCES
        src/project.cpp
        src/project.h
        src/engine.cpp
        src/engine.h
        src/captions.cpp
        src/captions.h
        src/stickers.cpp
        src/stickers.h
        src/voice.cpp
        src/voice.h
)

target_link_libraries(aster-montaz PRIVATE
    Qt6::Gui
    Qt6::Quick
    Qt6::Qml
    Qt6::DBus
    Qt6::Network
    Qt6::Multimedia
    PkgConfig::MLT
    aster-uiplugin
)

# Emoji do naklejek: te same dane co panel emoji Aster (polskie nazwy z CLDR)
qt_add_resources(aster-montaz montazemoji PREFIX /emoji BASE ${CMAKE_SOURCE_DIR}/apps/emoji/data FILES ${CMAKE_SOURCE_DIR}/apps/emoji/data/emoji.json)

install(TARGETS aster-montaz RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
install(FILES org.aster.montaz.desktop DESTINATION ${CMAKE_INSTALL_DATADIR}/applications)

if(whisper_FOUND)
    target_compile_definitions(aster-montaz PRIVATE HAVE_WHISPER)
    target_link_libraries(aster-montaz PRIVATE whisper)
else()
    message(STATUS "aster-montaz: brak whisper.cpp — napisy z mowy wyłączone")
endif()
