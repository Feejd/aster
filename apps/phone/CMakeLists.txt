# Telefon (aster-phone) — budowane z głównego CMakeLists.txt repozytorium.
# Rozmawia przez D-Bus z usługą KDE Connect (kdeconnectd); bez dodatkowych bibliotek.

qt_add_executable(aster-phone src/main.cpp)
target_include_directories(aster-phone PRIVATE src)

set(PHONE_QML
    qml/Main.qml
)
foreach(f ${PHONE_QML})
    get_filename_component(name ${f} NAME)
    set_source_files_properties(${f} PROPERTIES QT_RESOURCE_ALIAS ${name})
endforeach()

qt_add_qml_module(aster-phone
    URI Aster.Phone
    VERSION 1.0
    QML_FILES ${PHONE_QML}
    SOURCES
        src/phone.cpp
        src/phone.h
)

target_link_libraries(aster-phone PRIVATE
    Qt6::Gui
    Qt6::Quick
    Qt6::Qml
    Qt6::DBus
    aster-uiplugin
)

install(TARGETS aster-phone RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
install(FILES org.aster.phone.desktop DESTINATION ${CMAKE_INSTALL_DATADIR}/applications)
