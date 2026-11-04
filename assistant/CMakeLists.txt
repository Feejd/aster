# Aster Intelligence: usługa sesji (aster-assistant, D-Bus org.aster.Assistant) i polecenie `aster` (skrót `ai`).
# Bez QML i bez GUI — sama sieć i D-Bus, żeby usługa była lekka (startuje na żądanie, kończy się po bezczynności).
find_package(Qt6 REQUIRED COMPONENTS Core Network DBus)

qt_add_executable(aster-assistant
    src/main.cpp
    src/service.cpp src/service.h
    src/providers.cpp src/providers.h
    src/secrets.cpp src/secrets.h
    src/localmodels.cpp src/localmodels.h
)
target_link_libraries(aster-assistant PRIVATE Qt6::Core Qt6::Network Qt6::DBus)

qt_add_executable(aster-cli cli/aster.cpp)
set_target_properties(aster-cli PROPERTIES OUTPUT_NAME aster)
target_link_libraries(aster-cli PRIVATE Qt6::Core Qt6::DBus)

install(TARGETS aster-assistant RUNTIME DESTINATION ${CMAKE_INSTALL_LIBEXECDIR})
install(TARGETS aster-cli RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
# `ai` — krótszy skrót tego samego polecenia
install(CODE "execute_process(COMMAND ${CMAKE_COMMAND} -E create_symlink aster \$ENV{DESTDIR}${CMAKE_INSTALL_FULL_BINDIR}/ai)")

# Uruchamianie na żądanie: pierwsze wywołanie D-Bus (wyspa, panel, terminal, Ustawienia) startuje usługę
configure_file(org.aster.Assistant.service.in ${CMAKE_CURRENT_BINARY_DIR}/org.aster.Assistant.service @ONLY)
configure_file(aster-assistant.service.in ${CMAKE_CURRENT_BINARY_DIR}/aster-assistant.service @ONLY)
install(FILES ${CMAKE_CURRENT_BINARY_DIR}/org.aster.Assistant.service DESTINATION ${CMAKE_INSTALL_DATADIR}/dbus-1/services)
install(FILES ${CMAKE_CURRENT_BINARY_DIR}/aster-assistant.service DESTINATION ${CMAKE_INSTALL_PREFIX}/lib/systemd/user)
# Model lokalny (llama-server z pakietu llama-cpp) — włączany przez usługę dopiero przy pytaniu, bez [Install]
install(FILES aster-llama.service DESTINATION ${CMAKE_INSTALL_PREFIX}/lib/systemd/user)
