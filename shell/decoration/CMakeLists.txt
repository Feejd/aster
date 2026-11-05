# Ramka okien Aster — wtyczka KDecoration3 dla KWin. Rysuje pasek tytułu i kolorowe przyciski programów,
# które nie mają własnego paska (programy Aster rysują go same, zob. common/WindowButtons.qml).
find_package(KDecoration3 CONFIG QUIET)
find_package(KF6CoreAddons CONFIG QUIET)
if(NOT KDecoration3_FOUND OR NOT KF6CoreAddons_FOUND)
    message(WARNING "Brak kdecoration-devel — ramka okien Aster nie zostanie zbudowana")
    return()
endif()

add_library(org.aster.decoration MODULE decoration.cpp decoration.h)
target_link_libraries(org.aster.decoration PRIVATE KDecoration3::KDecoration KF6::CoreAddons Qt6::Core Qt6::Gui)
set_target_properties(org.aster.decoration PROPERTIES PREFIX "" AUTOMOC ON)
install(TARGETS org.aster.decoration DESTINATION ${CMAKE_INSTALL_LIBDIR}/qt6/plugins/org.kde.kdecoration3)
