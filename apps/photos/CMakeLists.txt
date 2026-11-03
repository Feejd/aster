# Zdjęcia (aster-photos) — budowane z głównego CMakeLists.txt repozytorium.
# Metadane zdjęć (data, aparat) i obrót JPEG bez utraty jakości: exiv2 (pakiet exiv2-devel).
# Najpierw pakiet CMake exiv2 (Flatpak buduje exiv2 sam), potem pkg-config (Fedora)
find_package(exiv2 CONFIG QUIET)
if(TARGET Exiv2::exiv2lib)
    add_library(AsterExiv2 ALIAS Exiv2::exiv2lib)
else()
    find_package(PkgConfig REQUIRED)
    pkg_check_modules(EXIV2 REQUIRED IMPORTED_TARGET exiv2)
    add_library(AsterExiv2 ALIAS PkgConfig::EXIV2)
endif()
find_package(Qt6 REQUIRED COMPONENTS Concurrent)

qt_add_executable(aster-photos src/main.cpp)
target_include_directories(aster-photos PRIVATE src)

set(PHOTOS_QML
    qml/Main.qml
    qml/Library.qml
    qml/Viewer.qml
    qml/PhotoView.qml
)
foreach(f ${PHOTOS_QML})
    get_filename_component(name ${f} NAME)
    set_source_files_properties(${f} PROPERTIES QT_RESOURCE_ALIAS ${name})
endforeach()

qt_add_qml_module(aster-photos
    URI Aster.Photos
    VERSION 1.0
    QML_FILES ${PHOTOS_QML}
    SOURCES
        src/photomodel.cpp
        src/photomodel.h
        src/photos.cpp
        src/photos.h
)

target_link_libraries(aster-photos PRIVATE
    Qt6::Gui
    Qt6::Quick
    Qt6::Qml
    Qt6::Concurrent
    AsterExiv2
    aster-uiplugin
)

install(TARGETS aster-photos RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
install(FILES org.aster.photos.desktop DESTINATION ${CMAKE_INSTALL_DATADIR}/applications)
