# Kamera (aster-camera) — budowane z głównego CMakeLists.txt repozytorium.
# Obraz z kamery, zdjęcia i nagrywanie: Qt Multimedia (pakiet qt6-qtmultimedia-devel).
find_package(Qt6 REQUIRED COMPONENTS Multimedia)

qt_add_executable(aster-camera src/main.cpp)
target_include_directories(aster-camera PRIVATE src)

set(CAMERA_QML
    qml/Main.qml
)
foreach(f ${CAMERA_QML})
    get_filename_component(name ${f} NAME)
    set_source_files_properties(${f} PROPERTIES QT_RESOURCE_ALIAS ${name})
endforeach()

qt_add_qml_module(aster-camera
    URI Aster.Camera
    VERSION 1.0
    QML_FILES ${CAMERA_QML}
    DEPENDENCIES QtMultimedia
    SOURCES
        src/roll.cpp
        src/roll.h
)

target_link_libraries(aster-camera PRIVATE
    Qt6::Gui
    Qt6::Quick
    Qt6::Qml
    Qt6::DBus
    Qt6::Multimedia
    aster-uiplugin
)

install(TARGETS aster-camera RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
install(FILES org.aster.camera.desktop DESTINATION ${CMAKE_INSTALL_DATADIR}/applications)
