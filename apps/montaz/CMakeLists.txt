# Montaż (aster-montaz) — budowane z głównego CMakeLists.txt repozytorium.
# Silnik: MLT 7 (pakiet mlt-devel, API C++ mlt++) — ten sam, na którym stoją Kdenlive i Shotcut;
# podgląd: klatki z MLT jako tekstura w scenie QML, eksport przez FFmpeg (konsument avformat MLT).
find_package(Qt6 REQUIRED COMPONENTS DBus)
find_package(PkgConfig REQUIRED)
pkg_check_modules(MLT REQUIRED IMPORTED_TARGET mlt++-7)

qt_add_executable(aster-montaz src/main.cpp)
target_include_directories(aster-montaz PRIVATE src)

set(MONTAZ_QML
    qml/Main.qml
    qml/Home.qml
    qml/Editor.qml
    qml/Timeline.qml
    qml/Inspector.qml
    qml/ExportSheet.qml
)
foreach(f ${MONTAZ_QML})
    get_filename_component(name ${f} NAME)
    set_source_files_properties(${f} PROPERTIES QT_RESOURCE_ALIAS ${name})
endforeach()

qt_add_qml_module(aster-montaz
    URI Aster.Montaz
    VERSION 1.0
    QML_FILES ${MONTAZ_QML}
    SOURCES
        src/project.cpp
        src/project.h
        src/engine.cpp
        src/engine.h
)

target_link_libraries(aster-montaz PRIVATE
    Qt6::Gui
    Qt6::Quick
    Qt6::Qml
    Qt6::DBus
    PkgConfig::MLT
    aster-uiplugin
)

install(TARGETS aster-montaz RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
install(FILES org.aster.montaz.desktop DESTINATION ${CMAKE_INSTALL_DATADIR}/applications)
