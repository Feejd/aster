# Podgląd PDF (aster-pdf) — budowany z głównego CMakeLists.txt repozytorium.
# Strony, tekst, linki i szukanie: QtPdf (pakiet qt6-qtpdf-devel, część QtWebEngine); drukowanie: Qt PrintSupport.
find_package(Qt6 REQUIRED COMPONENTS Pdf PdfQuick PrintSupport Widgets)

qt_add_executable(aster-pdf src/main.cpp)
target_include_directories(aster-pdf PRIVATE src)

set(PDF_QML
    qml/Main.qml
    qml/PageView.qml
)
foreach(f ${PDF_QML})
    get_filename_component(name ${f} NAME)
    set_source_files_properties(${f} PROPERTIES QT_RESOURCE_ALIAS ${name})
endforeach()

qt_add_qml_module(aster-pdf
    URI Aster.Pdf
    VERSION 1.0
    QML_FILES ${PDF_QML}
    SOURCES
        src/pdf.cpp
        src/pdf.h
)

target_link_libraries(aster-pdf PRIVATE
    Qt6::Gui
    Qt6::Quick
    Qt6::Qml
    Qt6::Widgets
    Qt6::PrintSupport
    Qt6::Pdf
    Qt6::PdfQuick
    aster-uiplugin
)

install(TARGETS aster-pdf RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
install(FILES org.aster.pdf.desktop DESTINATION ${CMAKE_INSTALL_DATADIR}/applications)
