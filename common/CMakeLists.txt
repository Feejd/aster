# Wspólny wygląd Aster (motyw, ikony liniowe, elementy okien) — statyczny moduł QML „Aster.Ui”,
# wbudowywany w powłokę i aplikacje.
qt_add_library(aster-ui STATIC)
set_source_files_properties(Theme.qml PROPERTIES QT_QML_SINGLETON_TYPE TRUE)
qt_add_qml_module(aster-ui
    URI Aster.Ui
    VERSION 1.0
    QML_FILES
        Theme.qml
        Icon.qml
        Icons.js
        ResizeHandles.qml
        WindowButtons.qml
        WindowShadow.qml
        WindowSheen.qml
        GlassPane.qml
        ContextMenu.qml
        HoverButton.qml
        ToolBtn.qml
        AppIcon.qml
    SOURCES
        windoweffects.cpp
        windoweffects.h
        asterconfig.cpp
        asterconfig.h
)
target_include_directories(aster-ui PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})
target_link_libraries(aster-ui PRIVATE Qt6::Quick KF6::WindowSystem)
