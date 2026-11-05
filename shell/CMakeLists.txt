# Powłoka Aster — budowana z głównego CMakeLists.txt repozytorium.

qt_add_executable(aster-shell
    src/main.cpp
    src/platform.cpp
    src/platform.h
    src/controlcenter.cpp
    src/controlcenter.h
    src/connectivity.cpp
    src/connectivity.h
    src/polkitagent.cpp
    src/polkitagent.h
    src/assistant.cpp
    src/assistant.h
    src/windows.cpp
    src/windows.h
    ../assistant/src/blocks.cpp
)

target_include_directories(aster-shell PRIVATE src)

set(ASTER_QML
    qml/Shell.qml
    qml/Island.qml
    qml/WallpaperWindow.qml
    qml/DockWindow.qml
    qml/DockItem.qml
    qml/HorizonWindow.qml
    qml/StartWindow.qml
    qml/ClockWindow.qml
    qml/ControlCenterWindow.qml
    qml/AuthWindow.qml
    qml/AssistantWindow.qml
    qml/AssistantBadge.qml
    qml/IntelligenceGlow.qml
    qml/IntelligenceOrb.qml
    qml/ShimmerText.qml
)
# Pliki leżą w qml/, ale w module mają być w jego katalogu głównym — inaczej nie widzą
# się nawzajem ani singletona Platform
foreach(f ${ASTER_QML})
    get_filename_component(name ${f} NAME)
    set_source_files_properties(${f} PROPERTIES QT_RESOURCE_ALIAS ${name})
endforeach()

qt_add_qml_module(aster-shell
    URI Aster.Shell
    VERSION 1.0
    QML_FILES ${ASTER_QML}
)

target_compile_definitions(aster-shell PRIVATE
    ASTER_INSTALL_DATADIR="${CMAKE_INSTALL_FULL_DATADIR}/aster"
)

target_include_directories(aster-shell PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/../assistant/src)
target_link_libraries(aster-shell PRIVATE
    Qt6::Gui
    Qt6::Quick
    Qt6::Qml
    Qt6::DBus
    LayerShellQt::Interface
    KF6::WindowSystem
    KF6::Service
    KF6::KIOGui
    aster-uiplugin
    AsterNotificationManager
    PolkitQt6-1::Agent
)

install(TARGETS aster-shell RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
# Ramka okien i animacje okien (KWin)
add_subdirectory(decoration)
install(DIRECTORY effects/asterokna DESTINATION ${CMAKE_INSTALL_DATADIR}/kwin/effects)
install(DIRECTORY ../data/wallpapers DESTINATION ${CMAKE_INSTALL_DATADIR}/aster)
install(DIRECTORY ../data/fonts/geist DESTINATION ${CMAKE_INSTALL_DATADIR}/fonts)
install(FILES ../session/aster.desktop DESTINATION ${CMAKE_INSTALL_DATADIR}/wayland-sessions)
install(FILES ../session/org.aster.shell.desktop DESTINATION ${CMAKE_INSTALL_DATADIR}/applications)
install(PROGRAMS ../session/startaster DESTINATION ${CMAKE_INSTALL_BINDIR})
# Ekran startowy (Plymouth) i znak Aster jako logo systemu (LOGO=aster w os-release)
install(DIRECTORY ../data/plymouth/aster DESTINATION ${CMAKE_INSTALL_DATADIR}/plymouth/themes)
# Przejście z logowania na pulpit (zamiast ekranu ładowania KDE)
install(DIRECTORY ../data/lookandfeel/org.aster.desktop DESTINATION ${CMAKE_INSTALL_DATADIR}/plasma/look-and-feel)
# Ekran blokady (pakiet powłoki Plasma, z którego kscreenlocker bierze LockScreen.qml)
install(DIRECTORY ../data/shell/org.aster.shell DESTINATION ${CMAKE_INSTALL_DATADIR}/plasma/shells)
# Ekran logowania (motyw SDDM)
install(DIRECTORY ../data/sddm/aster DESTINATION ${CMAKE_INSTALL_DATADIR}/sddm/themes)
install(FILES ../data/branding/aster.svg DESTINATION ${CMAKE_INSTALL_DATADIR}/icons/hicolor/scalable/apps)
# Kursor Aster: rysowany z SVG przy budowaniu (tools/make-cursors.py — rsvg-convert i xcursorgen)
find_program(ASTER_RSVG rsvg-convert)
find_program(ASTER_XCURSORGEN xcursorgen)
find_package(Python3 COMPONENTS Interpreter)
if(ASTER_RSVG AND ASTER_XCURSORGEN AND Python3_FOUND)
    set(ASTER_CURSORS ${CMAKE_BINARY_DIR}/cursors/Aster)
    add_custom_command(
        OUTPUT ${ASTER_CURSORS}/index.theme
        COMMAND Python3::Interpreter ${CMAKE_SOURCE_DIR}/tools/make-cursors.py ${ASTER_CURSORS}
        DEPENDS ${CMAKE_SOURCE_DIR}/tools/make-cursors.py
        COMMENT "Kursor Aster"
        VERBATIM)
    add_custom_target(aster-cursors ALL DEPENDS ${ASTER_CURSORS}/index.theme)
    install(DIRECTORY ${ASTER_CURSORS} DESTINATION ${CMAKE_INSTALL_DATADIR}/icons)
else()
    message(WARNING "Bez rsvg-convert/xcursorgen (librsvg2-tools, xcursorgen) — kursor Aster nie zostanie zbudowany")
endif()
install(FILES ../session/aster-shell.service DESTINATION ${CMAKE_INSTALL_PREFIX}/lib/systemd/user)
# Pierwszy start po instalacji: konto i ustawienia z instalatora
install(PROGRAMS ../session/aster-firstboot DESTINATION ${CMAKE_INSTALL_LIBEXECDIR})
install(FILES ../session/aster-firstboot.service DESTINATION ${CMAKE_INSTALL_PREFIX}/lib/systemd/system)
