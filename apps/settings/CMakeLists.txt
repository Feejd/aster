# Ustawienia (aster-settings) — budowane z głównego CMakeLists.txt repozytorium.
find_package(KF6Config REQUIRED)
find_package(Qt6 REQUIRED COMPONENTS Concurrent)

qt_add_executable(aster-settings
    src/main.cpp
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
    qml/PowerPage.qml
    qml/MousePage.qml
    qml/KeyboardPage.qml
    qml/ShortcutsPage.qml
    qml/PrintersPage.qml
    qml/DatetimePage.qml
    qml/LanguagePage.qml
    qml/AppsPage.qml
    qml/AccessibilityPage.qml
    qml/PrivacyPage.qml
    qml/AssistantPage.qml
    qml/StoragePage.qml
    qml/UpdatesPage.qml
    qml/Dropdown.qml
    qml/Sheet.qml
    qml/Field.qml
    qml/Segmented.qml
)
foreach(f ${SETTINGS_QML})
    get_filename_component(name ${f} NAME)
    set_source_files_properties(${f} PROPERTIES QT_RESOURCE_ALIAS ${name})
endforeach()

qt_add_qml_module(aster-settings
    URI Aster.Settings
    VERSION 1.0
    QML_FILES ${SETTINGS_QML}
    SOURCES
        src/util.h
        src/system.cpp src/system.h
        src/conf.cpp src/conf.h
        src/displays.cpp src/displays.h
        src/power.cpp src/power.h
        src/inputs.cpp src/inputs.h
        src/accounts.cpp src/accounts.h
        src/datetime.cpp src/datetime.h
        src/apps.cpp src/apps.h
        src/shortcuts.cpp src/shortcuts.h
        src/printers.cpp src/printers.h
        src/storage.cpp src/storage.h
        src/updates.cpp src/updates.h
        src/assistant.cpp src/assistant.h
)

target_link_libraries(aster-settings PRIVATE
    Qt6::Gui
    Qt6::Quick
    Qt6::Qml
    Qt6::DBus
    Qt6::Concurrent
    KF6::ConfigCore
    KF6::Service
    crypt
    aster-uiplugin
)

install(TARGETS aster-settings RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
install(FILES org.aster.settings.desktop DESTINATION ${CMAKE_INSTALL_DATADIR}/applications)
