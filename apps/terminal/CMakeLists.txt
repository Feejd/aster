# Terminal (aster-terminal) — budowany z głównego CMakeLists.txt repozytorium.
# Emulacja terminala: libvterm (pakiet libvterm-devel), rysowanie i obsługa wejścia — własne (TerminalView).
find_package(PkgConfig REQUIRED)
pkg_check_modules(VTERM REQUIRED IMPORTED_TARGET vterm)

qt_add_executable(aster-terminal src/main.cpp)
target_include_directories(aster-terminal PRIVATE src)

set(TERMINAL_QML
    qml/Main.qml
    qml/SettingsSheet.qml
)
foreach(f ${TERMINAL_QML})
    get_filename_component(name ${f} NAME)
    set_source_files_properties(${f} PROPERTIES QT_RESOURCE_ALIAS ${name})
endforeach()

qt_add_qml_module(aster-terminal
    URI Aster.Terminal
    VERSION 1.0
    QML_FILES ${TERMINAL_QML}
    SOURCES
        src/session.cpp
        src/session.h
        src/terminalview.cpp
        src/terminalview.h
        src/terminal.cpp
        src/terminal.h
)

target_link_libraries(aster-terminal PRIVATE
    Qt6::Gui
    Qt6::Quick
    Qt6::Qml
    Qt6::DBus
    PkgConfig::VTERM
    util
    aster-uiplugin
)

install(TARGETS aster-terminal RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
install(FILES org.aster.terminal.desktop DESTINATION ${CMAKE_INSTALL_DATADIR}/applications)
# Domyślny terminal: xdg-terminal-exec (i programy, które go używają)
install(FILES xdg-terminals.list DESTINATION /etc/xdg)
