# Edytor tekstu (aster-editor) — budowany z głównego CMakeLists.txt repozytorium.
# Kolorowanie składni: KSyntaxHighlighting (pakiet kf6-syntax-highlighting-devel) — te same definicje co w Kate.
find_package(KF6SyntaxHighlighting REQUIRED)

qt_add_executable(aster-editor src/main.cpp)
target_include_directories(aster-editor PRIVATE src)

set(EDITOR_QML
    qml/Main.qml
    qml/EditorPage.qml
)
foreach(f ${EDITOR_QML})
    get_filename_component(name ${f} NAME)
    set_source_files_properties(${f} PROPERTIES QT_RESOURCE_ALIAS ${name})
endforeach()

qt_add_qml_module(aster-editor
    URI Aster.Editor
    VERSION 1.0
    QML_FILES ${EDITOR_QML}
    SOURCES
        src/editor.cpp
        src/editor.h
        src/highlighter.cpp
        src/highlighter.h
        src/linenumbers.cpp
        src/linenumbers.h
)

target_link_libraries(aster-editor PRIVATE
    Qt6::Gui
    Qt6::Quick
    Qt6::Qml
    Qt6::DBus
    KF6::SyntaxHighlighting
    KF6::WindowSystem
    aster-uiplugin
)

install(TARGETS aster-editor RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
install(FILES org.aster.editor.desktop DESTINATION ${CMAKE_INSTALL_DATADIR}/applications)
