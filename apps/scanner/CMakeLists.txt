# Skaner (aster-scanner) — budowane z głównego CMakeLists.txt repozytorium.
# Skanowanie przez SANE (pakiet sane-backends-devel), zapis PDF przez QPdfWriter (Qt Gui).
find_package(PkgConfig REQUIRED)
pkg_check_modules(SANE REQUIRED IMPORTED_TARGET sane-backends)

qt_add_executable(aster-scanner src/main.cpp)
target_include_directories(aster-scanner PRIVATE src)

set(SCANNER_QML
    qml/Main.qml
)
foreach(f ${SCANNER_QML})
    get_filename_component(name ${f} NAME)
    set_source_files_properties(${f} PROPERTIES QT_RESOURCE_ALIAS ${name})
endforeach()

qt_add_qml_module(aster-scanner
    URI Aster.Scanner
    VERSION 1.0
    QML_FILES ${SCANNER_QML}
    SOURCES
        src/scanner.cpp
        src/scanner.h
)

target_link_libraries(aster-scanner PRIVATE
    Qt6::Gui
    Qt6::Quick
    Qt6::Qml
    Qt6::DBus
    PkgConfig::SANE
    aster-uiplugin
)

install(TARGETS aster-scanner RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
install(FILES org.aster.scanner.desktop DESTINATION ${CMAKE_INSTALL_DATADIR}/applications)
