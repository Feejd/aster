# Sklep (aster-store) — budowany z głównego CMakeLists.txt repozytorium.
qt_add_executable(aster-store
    src/main.cpp
    src/flatpak.cpp
    src/flatpak.h
)
target_include_directories(aster-store PRIVATE src)

set(STORE_QML
    qml/Main.qml
    qml/AppPage.qml
    qml/GetButton.qml
    qml/AppRow.qml
    qml/Curated.js
)
foreach(f ${STORE_QML})
    get_filename_component(name ${f} NAME)
    set_source_files_properties(${f} PROPERTIES QT_RESOURCE_ALIAS ${name})
endforeach()

qt_add_qml_module(aster-store
    URI Aster.Store
    VERSION 1.0
    QML_FILES ${STORE_QML}
)

target_link_libraries(aster-store PRIVATE
    Qt6::Gui
    Qt6::Quick
    Qt6::Qml
    aster-uiplugin
)

install(TARGETS aster-store RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
install(FILES org.aster.store.desktop DESTINATION ${CMAKE_INSTALL_DATADIR}/applications)
