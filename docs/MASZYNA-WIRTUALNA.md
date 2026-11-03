# Maszyna wirtualna do pracy nad Aster (Mac z Apple Silicon)

Kod edytujesz na Macu, a budujesz i uruchamiasz w Fedorze w VMware Fusion.
Folder `Aster` jest udostępniony maszynie, więc nic nie trzeba kopiować.

## 1. Fedora KDE w VMware Fusion

1. Pobierz **Fedora KDE Plasma Desktop** w wersji **aarch64** (ARM): https://fedoraproject.org/kde/download
2. VMware Fusion → *Plik → Nowy* → przeciągnij pobrany plik ISO.
3. System: *Linux → Fedora 64-bit Arm*.
4. Ustawienia przed startem:
   - procesory: 4, pamięć: 6 GB (Mac ma 16 GB),
   - dysk: 40 GB (zajmuje miejsce stopniowo, realnie ok. 15 GB — warto zwolnić trochę miejsca na Macu),
   - *Display → Accelerate 3D Graphics*: włączone (potrzebne do rozmycia i płynnych animacji),
   - *Sharing → Shared Folders*: dodaj folder `~/Projekty/Aster` (poza iCloud — Dokumenty synchronizowane z iCloud potrafią zablokować pliki projektu).
5. Uruchom, wybierz *Install to Hard Drive*, przejdź instalator, zrestartuj.

## 2. Przygotowanie (raz)

W Fedorze otwórz Konsolę:

```bash
sh /mnt/hgfs/Aster/tools/setup-vm.sh
```

Jeśli `/mnt/hgfs` jest puste, najpierw: `sudo mkdir -p /mnt/hgfs && sudo vmhgfs-fuse .host:/ /mnt/hgfs -o allow_other`.

## 3. Uruchamianie powłoki

```bash
sh /mnt/hgfs/Aster/tools/dev-run.sh
```

Skrypt buduje aster-shell, wyłącza pulpit KDE i uruchamia nasz. **Ctrl+C** w Konsoli przywraca zwykły pulpit.
Po każdej zmianie w kodzie: Ctrl+C i uruchom ponownie.

## 4. Pełna sesja (później)

`sudo cmake --install ~/aster-build`, wyloguj się i na ekranie logowania wybierz sesję **Aster**.
