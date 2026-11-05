# Aster Pulse (aster-pulse) — testowanie API: zapytania HTTP, kolekcje w plikach JSON, środowiska ze zmiennymi
# (tajne w portfelu systemu), historia, import/eksport cURL. Polecenia `aster-pulse run|send|list|curl` i usługa
# D-Bus org.aster.pulse (interfejs org.aster.Pulse) zwracają wynik jako JSON — dla agenta Asystenta i skryptów.
find_package(Qt6 REQUIRED COMPONENTS Network)

qt_add_executable(aster-pulse src/main.cpp)
target_include_directories(aster-pulse PRIVATE src)

set(PULSE_QML
    qml/Main.qml
    qml/RequestPane.qml
    qml/ResponsePane.qml
    qml/KeyValueEditor.qml
    qml/CodeArea.qml
    qml/Sidebar.qml
    qml/EnvironmentsDialog.qml
    qml/TabBar.qml
    qml/Pill.qml
    qml/Field.qml
)
foreach(f ${PULSE_QML})
    get_filename_component(name ${f} NAME)
    set_source_files_properties(${f} PROPERTIES QT_RESOURCE_ALIAS ${name})
endforeach()

qt_add_qml_module(aster-pulse
    URI Aster.Pulse
    VERSION 1.0
    QML_FILES ${PULSE_QML}
    SOURCES
        src/agent.cpp src/agent.h
        src/curl.cpp src/curl.h
        src/highlighter.cpp src/highlighter.h
        src/jsontree.cpp src/jsontree.h
        src/pulse.cpp src/pulse.h
        src/runner.cpp src/runner.h
        src/secrets.cpp src/secrets.h
        src/workspace.cpp src/workspace.h
)

target_link_libraries(aster-pulse PRIVATE
    Qt6::Gui
    Qt6::Quick
    Qt6::Qml
    Qt6::DBus
    Qt6::Network
    KF6::WindowSystem
    aster-uiplugin
)

install(TARGETS aster-pulse RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
install(FILES org.aster.pulse.desktop DESTINATION ${CMAKE_INSTALL_DATADIR}/applications)
# Usługa dla agenta: pierwsze wywołanie org.aster.pulse uruchamia `aster-pulse --dbus` (bez okna)
configure_file(org.aster.pulse.service.in ${CMAKE_CURRENT_BINARY_DIR}/org.aster.pulse.service @ONLY)
install(FILES ${CMAKE_CURRENT_BINARY_DIR}/org.aster.pulse.service DESTINATION ${CMAKE_INSTALL_DATADIR}/dbus-1/services)
