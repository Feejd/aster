# Instalator (aster-installer) — budowany z głównego CMakeLists.txt, w obrazie nośnika instalacyjnego (image/installer).
# Sama instalacja: aster-install (bootc install to-disk); hasło szyfrowane przez libxcrypt.

qt_add_executable(aster-installer src/main.cpp)
target_include_directories(aster-installer PRIVATE src)

set(INSTALLER_QML
    qml/Main.qml
)
foreach(f ${INSTALLER_QML})
    get_filename_component(name ${f} NAME)
    set_source_files_properties(${f} PROPERTIES QT_RESOURCE_ALIAS ${name})
endforeach()

qt_add_qml_module(aster-installer
    URI Aster.Installer
    VERSION 1.0
    QML_FILES ${INSTALLER_QML}
    SOURCES
        src/installer.cpp
        src/installer.h
)

target_link_libraries(aster-installer PRIVATE
    Qt6::Gui
    Qt6::Quick
    Qt6::Qml
    Qt6::DBus
    crypt
    aster-uiplugin
)

install(TARGETS aster-installer RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
install(PROGRAMS aster-install.sh DESTINATION ${CMAKE_INSTALL_LIBEXECDIR} RENAME aster-install)
install(FILES org.aster.installer.desktop DESTINATION ${CMAKE_INSTALL_DATADIR}/applications)
