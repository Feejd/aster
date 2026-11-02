# Menedżer zadań (aster-tasks) — budowany z głównego CMakeLists.txt repozytorium.
# Procesy i wydajność czyta prosto z /proc i /sys; programy rozpoznaje przez KService.
qt_add_executable(aster-tasks src/main.cpp src/instance.h)
target_include_directories(aster-tasks PRIVATE src)

set(TASKS_QML
    qml/Main.qml
    qml/ProcessesPage.qml
    qml/PerformancePage.qml
    qml/Graph.qml
)
foreach(f ${TASKS_QML})
    get_filename_component(name ${f} NAME)
    set_source_files_properties(${f} PROPERTIES QT_RESOURCE_ALIAS ${name})
endforeach()

qt_add_qml_module(aster-tasks
    URI Aster.Tasks
    VERSION 1.0
    QML_FILES ${TASKS_QML}
    SOURCES
        src/monitor.cpp
        src/monitor.h
        src/processmodel.cpp
        src/processmodel.h
)

target_link_libraries(aster-tasks PRIVATE
    Qt6::Gui
    Qt6::Quick
    Qt6::Qml
    Qt6::DBus
    KF6::Service
    KF6::CoreAddons
    KF6::WindowSystem
    aster-uiplugin
)

install(TARGETS aster-tasks RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
install(FILES org.aster.tasks.desktop DESTINATION ${CMAKE_INSTALL_DATADIR}/applications)
# Ctrl+Shift+Esc z każdego miejsca (KGlobalAccel czyta skróty programów z share/kglobalaccel)
install(FILES org.aster.tasks.desktop DESTINATION ${CMAKE_INSTALL_DATADIR}/kglobalaccel)
