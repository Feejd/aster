# Ustawienia (aster-settings) — budowane z głównego CMakeLists.txt repozytorium.
qt_add_executable(aster-settings
    src/main.cpp
    src/system.cpp
    src/system.h
)
target_include_directories(aster-settings PRIVATE src)

set(SETTINGS_QML
    qml/Main.qml
    qml/Page.qml
    qml/Section.qml
    qml/SettingRow.qml
    qml/Badge.qml
    qml/Toggle.qml
    qml/TextButton.qml
    qml/LevelSlider.qml
    qml/SignalBars.qml
    qml/WifiPage.qml
    qml/BluetoothPage.qml
    qml/SoundPage.qml
    qml/NotificationsPage.qml
    qml/GeneralPage.qml
    qml/AppearancePage.qml
    qml/WallpaperPage.qml
    qml/DesktopPage.qml
    qml/DisplayPage.qml
    qml/AccountPage.qml
)
foreach(f ${SETTINGS_QML})
    get_filename_component(name ${f} NAME)
    set_source_files_properties(${f} PROPERTIES QT_RESOURCE_ALIAS ${name})
endforeach()

qt_add_qml_module(aster-settings
    URI Aster.Settings
    VERSION 1.0
    QML_FILES ${SETTINGS_QML}
)

target_link_libraries(aster-settings PRIVATE
    Qt6::Gui
    Qt6::Quick
    Qt6::Qml
    aster-uiplugin
)

install(TARGETS aster-settings RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
install(FILES org.aster.settings.desktop DESTINATION ${CMAKE_INSTALL_DATADIR}/applications)
