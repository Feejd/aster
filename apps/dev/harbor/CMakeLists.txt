# Aster Harbor (aster-harbor) — kontenery podmana, toolboxy, projekty compose i obrazy.
# Rozmawia z podmanem przez CLI z `--format json` (w Flatpaku przez flatpak-spawn --host).
# Dla agenta asystenta: `aster-harbor list|logs|start|stop` i D-Bus org.aster.Harbor (start na żądanie).
qt_add_executable(aster-harbor src/main.cpp src/instance.h)
target_include_directories(aster-harbor PRIVATE src)

set(HARBOR_QML
    qml/Main.qml
    qml/EnvironmentsPage.qml
    qml/ComposePage.qml
    qml/ImagesPage.qml
    qml/LogsPanel.qml
    qml/NewEnvSheet.qml
    qml/Sheet.qml
    qml/Pill.qml
    qml/StateDot.qml
    qml/ActionButton.qml
)
foreach(f ${HARBOR_QML})
    get_filename_component(name ${f} NAME)
    set_source_files_properties(${f} PROPERTIES QT_RESOURCE_ALIAS ${name})
endforeach()

qt_add_qml_module(aster-harbor
    URI Aster.Harbor
    VERSION 1.0
    QML_FILES ${HARBOR_QML}
    SOURCES
        src/harbor.cpp
        src/harbor.h
        src/linemodel.h
        src/podman.cpp
        src/podman.h
        src/agent.cpp
        src/agent.h
)

target_link_libraries(aster-harbor PRIVATE
    Qt6::Gui
    Qt6::Quick
    Qt6::Qml
    Qt6::DBus
    KF6::WindowSystem
    aster-uiplugin
)

install(TARGETS aster-harbor RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
install(FILES org.aster.harbor.desktop DESTINATION ${CMAKE_INSTALL_DATADIR}/applications)
install(FILES org.aster.harbor.svg DESTINATION ${CMAKE_INSTALL_DATADIR}/icons/hicolor/scalable/apps)
configure_file(org.aster.Harbor.service.in ${CMAKE_CURRENT_BINARY_DIR}/org.aster.Harbor.service @ONLY)
install(FILES ${CMAKE_CURRENT_BINARY_DIR}/org.aster.Harbor.service DESTINATION ${CMAKE_INSTALL_DATADIR}/dbus-1/services)
