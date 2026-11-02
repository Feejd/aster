# Panel emoji (aster-emoji, Win+.) — budowany z głównego CMakeLists.txt repozytorium.
# Wklejanie do aktywnego programu: protokół KWin fake-input (pakiet plasma-wayland-protocols-devel),
# schowek bez aktywnego okna: KSystemClipboard (kf6-kguiaddons-devel).
enable_language(C)                                      # kod protokołu z wayland-scanner jest w C
find_package(ECM REQUIRED NO_MODULE)
list(APPEND CMAKE_MODULE_PATH ${ECM_MODULE_PATH})
find_package(QtWaylandScanner REQUIRED)                 # ecm_add_qtwayland_client_protocol
find_package(Qt6 REQUIRED COMPONENTS WaylandClient WaylandClientPrivate)
find_package(Wayland REQUIRED COMPONENTS Client)
find_package(PlasmaWaylandProtocols REQUIRED)
find_package(KF6GuiAddons REQUIRED)

set(EMOJI_WAYLAND)
ecm_add_qtwayland_client_protocol(EMOJI_WAYLAND PROTOCOL ${PLASMA_WAYLAND_PROTOCOLS_DIR}/fake-input.xml BASENAME fake-input)
qt_add_executable(aster-emoji src/main.cpp ${EMOJI_WAYLAND})
target_include_directories(aster-emoji PRIVATE src ${CMAKE_CURRENT_BINARY_DIR})

set(EMOJI_QML qml/Main.qml qml/Lists.qml)
set_source_files_properties(qml/Lists.qml PROPERTIES QT_QML_SINGLETON_TYPE TRUE)
foreach(f ${EMOJI_QML})
    get_filename_component(name ${f} NAME)
    set_source_files_properties(${f} PROPERTIES QT_RESOURCE_ALIAS ${name})
endforeach()

qt_add_qml_module(aster-emoji
    URI Aster.Emoji
    VERSION 1.0
    QML_FILES ${EMOJI_QML}
    SOURCES
        src/emoji.cpp
        src/emoji.h
        src/fakeinput.cpp
        src/fakeinput.h
)
# Dane: data/emoji.json (tools/make-emoji-data.py — z Unicode i polskiego CLDR)
qt_add_resources(aster-emoji emojidata PREFIX /emoji BASE data FILES data/emoji.json)

target_link_libraries(aster-emoji PRIVATE
    Qt6::Gui
    Qt6::Quick
    Qt6::Qml
    Qt6::DBus
    Qt6::WaylandClient
    Qt6::WaylandClientPrivate
    Wayland::Client
    LayerShellQt::Interface
    KF6::GuiAddons
    aster-uiplugin
)

install(TARGETS aster-emoji RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
install(FILES org.aster.emoji.desktop DESTINATION ${CMAKE_INSTALL_DATADIR}/applications)
# Skrót Win+. (KGlobalAccel czyta skróty programów z share/kglobalaccel)
install(FILES org.aster.emoji.desktop DESTINATION ${CMAKE_INSTALL_DATADIR}/kglobalaccel)
# Wybierak emoji KDE zajmuje Win+. — wersja z innym skrótem, przed /usr/share w kolejności katalogów
install(FILES org.kde.plasma.emojier.desktop DESTINATION /usr/local/share/kglobalaccel)
