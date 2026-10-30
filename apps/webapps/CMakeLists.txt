# Aplikacje webowe (aster-webapps) — menedżer i okno aplikacji w jednym programie.
find_package(Qt6 REQUIRED COMPONENTS WebEngineQuick Network)

qt_add_executable(aster-webapps
    src/main.cpp
    src/webapps.cpp
    src/webapps.h
    src/runtime.cpp
    src/runtime.h
)
target_include_directories(aster-webapps PRIVATE src)

set(WEBAPPS_QML
    qml/Manager.qml
    qml/WebAppWindow.qml
    qml/Catalog.js
    qml/Adapters.js
)
set_source_files_properties(qml/native.js PROPERTIES QT_RESOURCE_ALIAS native.js)
foreach(f ${WEBAPPS_QML})
    get_filename_component(name ${f} NAME)
    set_source_files_properties(${f} PROPERTIES QT_RESOURCE_ALIAS ${name})
endforeach()

qt_add_qml_module(aster-webapps
    URI Aster.WebApps
    VERSION 1.0
    QML_FILES ${WEBAPPS_QML}
    RESOURCES qml/native.js
)

target_link_libraries(aster-webapps PRIVATE
    Qt6::Gui
    Qt6::Quick
    Qt6::Qml
    Qt6::DBus
    Qt6::Network
    Qt6::WebEngineQuick
    aster-uiplugin
)

install(TARGETS aster-webapps RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
install(FILES org.aster.webapps.desktop DESTINATION ${CMAKE_INSTALL_DATADIR}/applications)
