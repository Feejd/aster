# Sklep (aster-store) — budowany z głównego CMakeLists.txt repozytorium.
find_package(Qt6 REQUIRED COMPONENTS Network)
qt_add_executable(aster-store
    src/main.cpp
    src/flatpak.cpp
    src/flatpak.h
    src/net.cpp
    src/net.h
    src/intelligence.cpp
    src/intelligence.h
)
target_include_directories(aster-store PRIVATE src)

set(STORE_QML
    qml/Main.qml
    qml/Store.qml
    qml/HomePage.qml
    qml/TaskPage.qml
    qml/SwitchPage.qml
    qml/ListPage.qml
    qml/AppPage.qml
    qml/ComparePage.qml
    qml/MinePage.qml
    qml/GetButton.qml
    qml/AppRow.qml
    qml/AppGlyph.qml
    qml/AppCard.qml
    qml/FactLine.qml
    qml/Txt.qml
    qml/Btn.qml
    qml/Chip.qml
    qml/Ui.qml
    qml/Catalog.js
    qml/Facts.js
    qml/Find.js
)
foreach(f ${STORE_QML})
    get_filename_component(name ${f} NAME)
    set_source_files_properties(${f} PROPERTIES QT_RESOURCE_ALIAS ${name})
endforeach()
set_source_files_properties(qml/Store.qml PROPERTIES QT_QML_SINGLETON_TYPE TRUE)
set_source_files_properties(qml/Ui.qml PROPERTIES QT_QML_SINGLETON_TYPE TRUE)

qt_add_qml_module(aster-store
    URI Aster.Store
    VERSION 1.0
    QML_FILES ${STORE_QML}
)

target_link_libraries(aster-store PRIVATE
    Qt6::Gui
    Qt6::Quick
    Qt6::Qml
    Qt6::Network
    Qt6::DBus
    aster-uiplugin
)

install(TARGETS aster-store RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
install(PROGRAMS tools/aster-get DESTINATION ${CMAKE_INSTALL_BINDIR})
install(FILES org.aster.store.desktop DESTINATION ${CMAKE_INSTALL_DATADIR}/applications)
