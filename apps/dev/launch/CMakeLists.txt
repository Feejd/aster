# Aster Launch (aster-launch) — wdrażanie aplikacji: własny serwer przez SSH (rsync, systemd albo podman/docker, Caddy
# z HTTPS) i hostingi przez ich CLI (Netlify, Vercel, Cloudflare Pages). Okno, polecenie w terminalu i D-Bus org.aster.Launch.
# Budowany z głównego CMakeLists.txt repozytorium (albo sam: -DASTER_APPS=dev/launch).
find_package(Qt6 REQUIRED COMPONENTS Network)

qt_add_executable(aster-launch src/main.cpp src/bus.cpp src/bus.h)
target_include_directories(aster-launch PRIVATE src)

set(LAUNCH_QML
    qml/Main.qml
    qml/ProjectPage.qml
    qml/TargetPage.qml
    qml/HistoryPage.qml
    qml/LogsPage.qml
    qml/PlanSheet.qml
    qml/StartPage.qml
    qml/Field.qml
    qml/Pill.qml
    qml/Card.qml
    qml/VersionRow.qml
    qml/LaunchIcons.js
)
foreach(f ${LAUNCH_QML})
    get_filename_component(name ${f} NAME)
    set_source_files_properties(${f} PROPERTIES QT_RESOURCE_ALIAS ${name})
endforeach()

qt_add_qml_module(aster-launch
    URI Aster.Launch
    VERSION 1.0
    QML_FILES ${LAUNCH_QML}
    SOURCES
        src/engine.cpp
        src/engine.h
)

target_link_libraries(aster-launch PRIVATE
    Qt6::Gui
    Qt6::Quick
    Qt6::Qml
    Qt6::DBus
    Qt6::Network
    KF6::WindowSystem
    aster-uiplugin
)

install(TARGETS aster-launch RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
install(FILES org.aster.launch.desktop DESTINATION ${CMAKE_INSTALL_DATADIR}/applications)
# Asystent i inne programy mogą zawołać org.aster.Launch, nawet gdy okno jest zamknięte — D-Bus je uruchomi
configure_file(org.aster.Launch.service.in org.aster.Launch.service @ONLY)
install(FILES ${CMAKE_CURRENT_BINARY_DIR}/org.aster.Launch.service DESTINATION ${CMAKE_INSTALL_DATADIR}/dbus-1/services)
