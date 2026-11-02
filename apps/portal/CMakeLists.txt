# Okna systemowe Aster dla xdg-desktop-portal (aster-portal) — budowane z głównego CMakeLists.txt.
qt_add_executable(aster-portal src/main.cpp)
target_include_directories(aster-portal PRIVATE src)

set(PORTAL_QML qml/FileDialog.qml)
foreach(f ${PORTAL_QML})
    get_filename_component(name ${f} NAME)
    set_source_files_properties(${f} PROPERTIES QT_RESOURCE_ALIAS ${name})
endforeach()

qt_add_qml_module(aster-portal
    URI Aster.Portal
    VERSION 1.0
    QML_FILES ${PORTAL_QML}
    SOURCES
        src/filechooser.cpp
        src/filechooser.h
)

target_link_libraries(aster-portal PRIVATE
    Qt6::Gui
    Qt6::Quick
    Qt6::Qml
    Qt6::DBus
    aster-uiplugin
)

install(TARGETS aster-portal RUNTIME DESTINATION ${CMAKE_INSTALL_LIBEXECDIR})
# Portal: kto obsługuje które okna; aster-portals.conf działa w sesji z XDG_CURRENT_DESKTOP=Aster:KDE
install(FILES aster.portal DESTINATION ${CMAKE_INSTALL_DATADIR}/xdg-desktop-portal/portals)
install(FILES aster-portals.conf DESTINATION ${CMAKE_INSTALL_DATADIR}/xdg-desktop-portal)
configure_file(org.freedesktop.impl.portal.desktop.aster.service.in org.freedesktop.impl.portal.desktop.aster.service @ONLY)
install(FILES ${CMAKE_CURRENT_BINARY_DIR}/org.freedesktop.impl.portal.desktop.aster.service DESTINATION ${CMAKE_INSTALL_DATADIR}/dbus-1/services)
