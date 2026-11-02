# Pliki (aster-files) — budowane z głównego CMakeLists.txt repozytorium.
# Spakuj / Wypakuj: libarchive (pakiet libarchive-devel).
find_package(PkgConfig REQUIRED)
pkg_check_modules(LIBARCHIVE REQUIRED IMPORTED_TARGET libarchive)
find_package(Qt6 REQUIRED COMPONENTS Concurrent DBus)
find_package(KF6Solid REQUIRED)

qt_add_executable(aster-files
    src/main.cpp
    src/foldermodel.cpp
    src/foldermodel.h
    src/fileops.cpp
    src/fileops.h
    src/archiver.cpp
    src/archiver.h
    src/drives.cpp
    src/drives.h
)
target_include_directories(aster-files PRIVATE src)

set(FILES_QML
    qml/Main.qml
    qml/FileItem.qml
    qml/SidebarPlace.qml
    qml/FileKinds.js
)
foreach(f ${FILES_QML})
    get_filename_component(name ${f} NAME)
    set_source_files_properties(${f} PROPERTIES QT_RESOURCE_ALIAS ${name})
endforeach()

qt_add_qml_module(aster-files
    URI Aster.Files
    VERSION 1.0
    QML_FILES ${FILES_QML}
)

target_link_libraries(aster-files PRIVATE
    Qt6::Widgets
    Qt6::Quick
    Qt6::Qml
    KF6::KIOCore
    KF6::KIOGui
    KF6::KIOWidgets
    KF6::WindowSystem
    Qt6::Concurrent
    Qt6::DBus
    KF6::Solid
    PkgConfig::LIBARCHIVE
    aster-uiplugin
)

install(TARGETS aster-files RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
install(FILES org.aster.files.desktop DESTINATION ${CMAKE_INSTALL_DATADIR}/applications)
