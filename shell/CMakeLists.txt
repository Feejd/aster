cmake_minimum_required(VERSION 3.22)
project(aster-shell VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
include(GNUInstallDirs)

find_package(Qt6 6.6 REQUIRED COMPONENTS Gui Quick Qml)
find_package(LayerShellQt REQUIRED)
find_package(KF6WindowSystem REQUIRED)

qt_standard_project_setup(REQUIRES 6.6)

qt_add_executable(aster-shell
    src/main.cpp
    src/platform.cpp
    src/platform.h
)

target_include_directories(aster-shell PRIVATE src)

set(ASTER_QML
    qml/Shell.qml
    qml/Theme.qml
    qml/Island.qml
    qml/WallpaperWindow.qml
    qml/DockWindow.qml
    qml/DockItem.qml
    qml/HorizonWindow.qml
)
# Pliki leżą w qml/, ale w module mają być w jego katalogu głównym — inaczej nie widzą
# się nawzajem ani singletonów (Theme, Platform)
foreach(f ${ASTER_QML})
    get_filename_component(name ${f} NAME)
    set_source_files_properties(${f} PROPERTIES QT_RESOURCE_ALIAS ${name})
endforeach()
set_source_files_properties(qml/Theme.qml PROPERTIES QT_QML_SINGLETON_TYPE TRUE)

qt_add_qml_module(aster-shell
    URI Aster.Shell
    VERSION 1.0
    QML_FILES ${ASTER_QML}
)

target_compile_definitions(aster-shell PRIVATE
    ASTER_INSTALL_DATADIR="${CMAKE_INSTALL_FULL_DATADIR}/aster"
)

target_link_libraries(aster-shell PRIVATE
    Qt6::Gui
    Qt6::Quick
    Qt6::Qml
    LayerShellQt::Interface
    KF6::WindowSystem
)

install(TARGETS aster-shell RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
install(DIRECTORY ../data/wallpapers DESTINATION ${CMAKE_INSTALL_DATADIR}/aster)
install(FILES ../session/aster.desktop DESTINATION ${CMAKE_INSTALL_DATADIR}/wayland-sessions)
install(FILES ../session/org.aster.shell.desktop DESTINATION ${CMAKE_INSTALL_DATADIR}/applications)
install(PROGRAMS ../session/startaster DESTINATION ${CMAKE_INSTALL_BINDIR})
install(FILES ../session/aster-shell.service DESTINATION ${CMAKE_INSTALL_PREFIX}/lib/systemd/user)
