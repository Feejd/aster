# Aster Pixel (aster-grafika, dawniej Grafika) — budowana z głównego CMakeLists.txt repozytorium.
# Rysowanie przez QPainter (to samo na ekranie i w eksporcie), PDF przez QPdfWriter, plik projektu — ZIP (QZipWriter z Qt).
find_package(Qt6 REQUIRED COMPONENTS CorePrivate Svg Network)
find_package(KF6Prison REQUIRED)            # kody QR i kreskowe

qt_add_executable(aster-grafika src/main.cpp)
target_include_directories(aster-grafika PRIVATE src)

set(GRAFIKA_QML
    qml/Main.qml
    qml/StartPage.qml
    qml/EditorPage.qml
    qml/Stage.qml
    qml/SidePanel.qml
    qml/Inspector.qml
    qml/ColorPopup.qml
    qml/FontPopup.qml
    qml/Popover.qml
    qml/Btn.qml
    qml/Chip.qml
    qml/NumField.qml
    qml/ValueSlider.qml
    qml/ColorWell.qml
    qml/IconToggle.qml
    qml/Section.qml
        qml/CurveEditor.qml
        qml/CorrectionPanel.qml
    qml/SearchField.qml
    qml/TextBox.qml
)
foreach(f ${GRAFIKA_QML})
    get_filename_component(name ${f} NAME)
    set_source_files_properties(${f} PROPERTIES QT_RESOURCE_ALIAS ${name})
endforeach()

qt_add_qml_module(aster-grafika
    URI Aster.Grafika
    VERSION 1.0
    QML_FILES ${GRAFIKA_QML}
    SOURCES
        src/art.cpp
        src/art.h
        src/artview.cpp
        src/artview.h
        src/project.cpp
        src/project.h
        src/library.cpp
        src/library.h
        src/online.cpp
        src/online.h
        src/magic.cpp
        src/magic.h
)

# Narzędzia AI (usuwanie tła, gumka, wyodrębnianie) — ONNX Runtime; bez niego program działa, tylko bez nich
find_path(ONNXRUNTIME_INCLUDE_DIR onnxruntime_cxx_api.h PATH_SUFFIXES onnxruntime onnxruntime/core/session)
find_library(ONNXRUNTIME_LIBRARY onnxruntime)
if(ONNXRUNTIME_INCLUDE_DIR AND ONNXRUNTIME_LIBRARY)
    target_include_directories(aster-grafika PRIVATE ${ONNXRUNTIME_INCLUDE_DIR})
    target_link_libraries(aster-grafika PRIVATE ${ONNXRUNTIME_LIBRARY})
    target_compile_definitions(aster-grafika PRIVATE GRAFIKA_ONNX)
    message(STATUS "Aster Pixel: narzędzia AI z ONNX Runtime (${ONNXRUNTIME_LIBRARY})")
else()
    message(STATUS "Aster Pixel: bez ONNX Runtime — bez narzędzi AI")
endif()

# Szablony — zwykłe pliki projektu (project.json), wbudowane w program pod :/szablony
file(GLOB GRAFIKA_TEMPLATES RELATIVE ${CMAKE_CURRENT_SOURCE_DIR} CONFIGURE_DEPENDS templates/*.json)
qt_add_resources(aster-grafika "szablony"
    PREFIX "/szablony"
    BASE templates
    FILES ${GRAFIKA_TEMPLATES}
)

target_link_libraries(aster-grafika PRIVATE
    Qt6::Gui
    Qt6::CorePrivate
    Qt6::Quick
    Qt6::Qml
    Qt6::DBus
    Qt6::Svg
    Qt6::Network
    KF6::Prison
    aster-uiplugin
)

install(TARGETS aster-grafika RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
# Darmowe czcionki z Google Fonts (OFL) do szablonów — działają bez internetu
install(DIRECTORY fonts/ DESTINATION ${CMAKE_INSTALL_DATADIR}/fonts/aster-grafika)
install(FILES org.aster.grafika.desktop DESTINATION ${CMAKE_INSTALL_DATADIR}/applications)
install(FILES org.aster.grafika.xml DESTINATION ${CMAKE_INSTALL_DATADIR}/mime/packages)
