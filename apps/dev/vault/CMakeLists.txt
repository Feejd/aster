# Aster Vault (aster-vault) — program do baz danych: SQLite, PostgreSQL, MySQL/MariaDB.
# Bazy przez Qt SQL (sterowniki QSQLITE/QPSQL/QMYSQL — w Fedorze pakiety qt6-qtbase-postgresql i qt6-qtbase-mysql),
# hasła w portfelu przez Secret Service (D-Bus), kolorowanie SQL własne (bez KSyntaxHighlighting).
find_package(Qt6 REQUIRED COMPONENTS Sql DBus)

qt_add_executable(aster-vault src/main.cpp)
target_include_directories(aster-vault PRIVATE src)

set(VAULT_QML
    qml/Main.qml
    qml/StartPage.qml
    qml/ConnectionSheet.qml
    qml/DataGrid.qml
    qml/StructureView.qml
    qml/QueryPage.qml
    qml/ChangesSheet.qml
    qml/CompletionPopup.qml
    qml/Pill.qml
    qml/Field.qml
    qml/Sheet.qml
)
foreach(f ${VAULT_QML})
    get_filename_component(name ${f} NAME)
    set_source_files_properties(${f} PROPERTIES QT_RESOURCE_ALIAS ${name})
endforeach()

qt_add_qml_module(aster-vault
    URI Aster.Vault
    VERSION 1.0
    QML_FILES ${VAULT_QML}
    SOURCES
        src/vault.cpp
        src/vault.h
        src/gridmodel.cpp
        src/gridmodel.h
        src/dbcore.cpp
        src/dbcore.h
        src/store.cpp
        src/store.h
        src/secrets.cpp
        src/secrets.h
        src/sqlhighlighter.cpp
        src/sqlhighlighter.h
        src/agent.cpp
        src/agent.h
)

target_link_libraries(aster-vault PRIVATE
    Qt6::Gui
    Qt6::Quick
    Qt6::Qml
    Qt6::Sql
    Qt6::DBus
    KF6::WindowSystem
    aster-uiplugin
)

install(TARGETS aster-vault RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
install(FILES org.aster.vault.desktop DESTINATION ${CMAKE_INSTALL_DATADIR}/applications)
# Usługa D-Bus dla asystenta: uruchamiana na żądanie, sama się kończy
configure_file(org.aster.Vault.service.in ${CMAKE_CURRENT_BINARY_DIR}/org.aster.Vault.service @ONLY)
install(FILES ${CMAKE_CURRENT_BINARY_DIR}/org.aster.Vault.service DESTINATION ${CMAKE_INSTALL_DATADIR}/dbus-1/services)
