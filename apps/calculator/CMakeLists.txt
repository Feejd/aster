# Kalkulator (aster-calculator) — budowany z głównego CMakeLists.txt repozytorium.
qt_add_executable(aster-calculator src/main.cpp)
target_include_directories(aster-calculator PRIVATE src)

set_source_files_properties(qml/Main.qml PROPERTIES QT_RESOURCE_ALIAS Main.qml)
qt_add_qml_module(aster-calculator
    URI Aster.Calculator
    VERSION 1.0
    QML_FILES qml/Main.qml
    SOURCES
        src/calc.cpp
        src/calc.h
)

target_link_libraries(aster-calculator PRIVATE
    Qt6::Gui
    Qt6::Quick
    Qt6::Qml
    aster-uiplugin
)

install(TARGETS aster-calculator RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
install(FILES org.aster.calculator.desktop DESTINATION ${CMAKE_INSTALL_DATADIR}/applications)
