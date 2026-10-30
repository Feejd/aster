# Wspólny wygląd Aster (motyw, ikony liniowe) — statyczny moduł QML „Aster.Ui”,
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
)
