# Przeglądarka (aster-browser) — budowana z głównego CMakeLists.txt repozytorium.
find_package(Qt6 REQUIRED COMPONENTS WebEngineQuick WebEngineCore DBus)

qt_add_executable(aster-browser src/main.cpp)
target_include_directories(aster-browser PRIVATE src)

set(BROWSER_QML
    qml/Main.qml
    qml/BrowserTab.qml
    qml/StartPage.qml
    qml/HistoryPage.qml
    qml/DownloadsPage.qml
    qml/SettingsPage.qml
    qml/DownloadRow.qml
    qml/PageHeader.qml
    qml/PageSearch.qml
    qml/PillButton.qml
    qml/Urls.js
)
foreach(f ${BROWSER_QML})
    get_filename_component(name ${f} NAME)
    set_source_files_properties(${f} PROPERTIES QT_RESOURCE_ALIAS ${name})
endforeach()

qt_add_qml_module(aster-browser
    URI Aster.Browser
    VERSION 1.0
    QML_FILES ${BROWSER_QML}
    SOURCES
        src/browser.cpp
        src/browser.h
        src/downloaditem.cpp
        src/downloaditem.h
        src/trackerblocker.cpp
        src/trackerblocker.h
)

target_link_libraries(aster-browser PRIVATE
    Qt6::Gui
    Qt6::Quick
    Qt6::Qml
    Qt6::DBus
    Qt6::WebEngineQuick
    Qt6::WebEngineCore
    aster-uiplugin
)

install(TARGETS aster-browser RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
install(FILES org.aster.browser.desktop DESTINATION ${CMAKE_INSTALL_DATADIR}/applications)
# Domyślna przeglądarka systemu (pliki w /etc/xdg czytają KDE i xdg-open)
install(FILES mimeapps.list DESTINATION /etc/xdg)
