# Aster Code (aster-code) — edytor kodu, budowany z głównego CMakeLists.txt repozytorium.
# Kolorowanie składni: KSyntaxHighlighting (jak Edytor tekstu), terminal na dole: libvterm (jak Terminal).
# Wspólne pliki z Edytora i Terminala są kompilowane wprost z ich katalogów — jedno źródło, bez kopii.
find_package(KF6SyntaxHighlighting REQUIRED)
find_package(PkgConfig REQUIRED)
pkg_check_modules(VTERM REQUIRED IMPORTED_TARGET vterm)

set(EDITOR_SRC ${CMAKE_SOURCE_DIR}/apps/editor/src)
set(TERMINAL_SRC ${CMAKE_SOURCE_DIR}/apps/terminal/src)

qt_add_executable(aster-code src/main.cpp)
target_include_directories(aster-code PRIVATE src ${EDITOR_SRC} ${TERMINAL_SRC})

set(CODE_QML
    qml/Main.qml
    qml/CodePage.qml
    qml/StartPage.qml
    qml/Palette.qml
    qml/SearchView.qml
    qml/ChangesView.qml
    qml/TerminalPanel.qml
    qml/FileIcon.qml
    qml/NameBox.qml
    qml/ProblemsView.qml
    qml/CompletionPopup.qml
    qml/DiffView.qml
    qml/ReferencesView.qml
    qml/SettingsView.qml
    qml/TaskOutput.qml
    qml/DebugView.qml
)
foreach(f ${CODE_QML})
    get_filename_component(name ${f} NAME)
    set_source_files_properties(${f} PROPERTIES QT_RESOURCE_ALIAS ${name})
endforeach()

qt_add_qml_module(aster-code
    URI Aster.Code
    VERSION 1.0
    QML_FILES ${CODE_QML}
    SOURCES
        src/project.cpp
        src/project.h
        src/filetree.cpp
        src/filetree.h
        src/gutter.cpp
        src/gutter.h
        src/textops.cpp
        src/textops.h
        src/codeterminal.h
        src/lsp.cpp
        src/lsp.h
        src/searchregex.h
        src/minimap.cpp
        src/minimap.h
        src/tasks.cpp
        src/tasks.h
        src/debugger.cpp
        src/debugger.h
        ${EDITOR_SRC}/highlighter.cpp
        ${EDITOR_SRC}/highlighter.h
        ${TERMINAL_SRC}/session.cpp
        ${TERMINAL_SRC}/session.h
        ${TERMINAL_SRC}/terminalview.cpp
        ${TERMINAL_SRC}/terminalview.h
)

target_link_libraries(aster-code PRIVATE
    Qt6::Gui
    Qt6::Quick
    Qt6::Qml
    KF6::SyntaxHighlighting
    KF6::WindowSystem
    PkgConfig::VTERM
    util
    aster-uiplugin
)

install(TARGETS aster-code RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
install(FILES org.aster.code.desktop DESTINATION ${CMAKE_INSTALL_DATADIR}/applications)
