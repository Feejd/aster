# Przeglądarka (aster-browser) — budowana z głównego CMakeLists.txt repozytorium.
find_package(Qt6 REQUIRED COMPONENTS WebEngineQuick)

qt_add_executable(aster-browser src/main.cpp)

set(BROWSER_QML
    qml/Main.qml
    qml/BrowserTab.qml
    qml/StartPage.qml
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
)

target_link_libraries(aster-browser PRIVATE
    Qt6::Gui
    Qt6::Quick
    Qt6::Qml
    Qt6::WebEngineQuick
    aster-uiplugin
)

install(TARGETS aster-browser RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
install(FILES org.aster.browser.desktop DESTINATION ${CMAKE_INSTALL_DATADIR}/applications)
