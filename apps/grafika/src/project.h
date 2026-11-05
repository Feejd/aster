#pragma once

#include "art.h"

#include <QAbstractListModel>
#include <QHash>
#include <QImage>
#include <QSize>
#include <QStringList>
#include <QtQml/qqmlregistration.h>

// Otwarty projekt: rozmiar stron i strony (tło i elementy od spodu do wierzchu). Model dla Repeatera to elementy
// bieżącej strony; pozostałe strony czekają w m_pages. Wszystkie strony mają ten sam rozmiar (karuzela, PDF).
// Plik projektu (.grafika) to ZIP: project.json, zdjęcia w images/ i miniatura thumbnail.png.
// Cofanie i ponawianie zapamiętuje całe migawki strony (JSON) — zdjęcia zostają w pamięci, dopóki projekt jest otwarty.
class Project : public QAbstractListModel, public ImageSource
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(qreal pageWidth READ pageWidth NOTIFY pageChanged)
    Q_PROPERTY(qreal pageHeight READ pageHeight NOTIFY pageChanged)
    Q_PROPERTY(QVariantMap background READ background NOTIFY backgroundChanged)
    Q_PROPERTY(QString name READ name WRITE setName NOTIFY nameChanged)
    Q_PROPERTY(QString path READ path NOTIFY pathChanged)
    Q_PROPERTY(bool modified READ modified NOTIFY modifiedChanged)
    Q_PROPERTY(bool canUndo READ canUndo NOTIFY historyChanged)
    Q_PROPERTY(bool canRedo READ canRedo NOTIFY historyChanged)
    Q_PROPERTY(int count READ count NOTIFY countChanged)
    Q_PROPERTY(QStringList images READ images NOTIFY imagesChanged)
    Q_PROPERTY(QStringList colors READ colors NOTIFY colorsChanged)
    Q_PROPERTY(int pageCount READ pageCount NOTIFY pagesChanged)
    Q_PROPERTY(int currentPage READ currentPage NOTIFY pagesChanged)
    Q_PROPERTY(QVariantMap guides READ guides NOTIFY guidesChanged)     // { x: [...], y: [...] } — prowadnice wszystkich stron
    Q_PROPERTY(QVariantMap print READ print NOTIFY pageChanged)

public:
    enum Roles { ElementRole = Qt::UserRole + 1, IdRole };

    explicit Project(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    qreal pageWidth() const { return m_width; }
    qreal pageHeight() const { return m_height; }
    QVariantMap background() const { return m_background; }
    QString name() const { return m_name; }
    void setName(const QString &name);
    QString path() const { return m_path; }
    bool modified() const { return m_modified; }
    bool canUndo() const { return !m_undo.isEmpty(); }
    bool canRedo() const { return !m_redo.isEmpty(); }
    int count() const { return m_elements.size(); }
    QStringList images() const;
    QStringList colors() const;
    int pageCount() const { return int(m_pages.size()); }
    int currentPage() const { return m_page; }
    QVariantMap guides() const { return m_guides; }
    QVariantMap print() const { return m_print; }

    QImage image(const QString &key, qreal pixels) const override;
    QImage fullImage(const QString &key) const;
    // Automatyczna poprawa: jasność, kontrast i nasycenie dobrane do zdjęcia (pola elementu do zmiany)
    Q_INVOKABLE QVariantMap autoEnhance(const QString &key) const;
    // Warstwy jak w programach do zdjęć
    Q_INVOKABLE bool usesCompositing() const;                    // bieżąca strona ma tryby mieszania albo korekcje
    Q_INVOKABLE QVariantList curveSamples(const QVariantList &points, int size) const;
    Q_INVOKABLE void addMask(const QString &id, bool hidden = false);   // maska warstwy: cała biała albo cała czarna
    // Malowanie po masce: punkty i grubość w częściach pola warstwy, soft 0..1 — miękkość pędzla
    Q_INVOKABLE void maskStroke(const QString &id, const QVariantList &points, qreal width, bool reveal, qreal soft);
    Q_INVOKABLE void invertMask(const QString &id);
    Q_INVOKABLE void gradientMask(const QString &id, qreal angle);       // wygaszanie: od pełnego widoku do zera
    void setMaskImage(const QString &id, const QImage &mask);            // gotowa maska (np. zaznaczenie AI)                  // zdjęcie w pełnej rozdzielczości (do AI)
    QString addImage(const QImage &img);                         // nowe zdjęcie w projekcie (PNG, z przezroczystością)
    QByteArray vector(const QString &key) const override;
    Q_INVOKABLE bool recolorable(const QString &key) const;     // SVG z currentColor (jednokolorowa ikona)

    // ——— Projekt ———
    Q_INVOKABLE void create(qreal width, qreal height, const QString &name, const QVariantMap &print = {});
    Q_INVOKABLE bool openTemplate(const QString &file);   // nowy projekt z szablonu (plik JSON)
    Q_INVOKABLE bool applyTemplate(const QString &file);  // zastąp zawartość strony (z cofaniem)
    Q_INVOKABLE bool open(const QString &path);
    Q_INVOKABLE bool save();                               // bez ścieżki — do Dokumenty/Grafiki
    Q_INVOKABLE void setPageSize(qreal width, qreal height, bool fit = false);   // fit — przeskaluj treść do nowej strony
    // Element powiększony k razy względem punktu (ox, oy) — rozmiar, pozycja, czcionka, grubości, cień
    Q_INVOKABLE QVariantMap scaled(const QVariantMap &el, qreal k, qreal ox, qreal oy) const;
    Q_INVOKABLE QVariantMap document() const;              // bieżąca strona (background, elements) i wszystkie (pages)

    // ——— Strony ———
    Q_INVOKABLE QVariantMap pageDocument(int page) const;   // { width, height, background, elements } do podglądu
    Q_INVOKABLE void goToPage(int page);
    Q_INVOKABLE void addPage();                             // pusta strona za bieżącą (z tym samym tłem)
    Q_INVOKABLE void duplicatePage(int page);
    Q_INVOKABLE void removePage(int page);
    Q_INVOKABLE void movePage(int from, int to);
    Q_INVOKABLE void setGuides(const QVariantMap &guides, bool commit = true);

    // Kolory całego projektu (wszystkie strony) i zamiana jednego na inny wszędzie naraz.
    // Zamiana zawsze od ostatniego zamkniętego stanu — podgląd podczas wybierania nie skleja kolorów.
    Q_INVOKABLE QStringList projectColors() const;
    Q_INVOKABLE void replaceColor(const QString &from, const QString &to, bool commit = true);

    // Moje elementy (np. logo, podpis) — zapisane poza projektem, do wstawienia w każdym projekcie
    Q_INVOKABLE bool saveElements(const QStringList &ids);
    Q_INVOKABLE QVariantList savedElements() const;              // [{ file, thumb }] od najnowszych
    Q_INVOKABLE QStringList insertSaved(const QString &file);
    Q_INVOKABLE void removeSaved(const QString &file);

    // ——— Elementy (po id, bo indeks zmienia się przy zmianie kolejności) ———
    Q_INVOKABLE QString add(const QVariantMap &element);
    Q_INVOKABLE void change(const QString &id, const QVariantMap &patch, bool commit = true);
    Q_INVOKABLE void remove(const QString &id);
    Q_INVOKABLE QString duplicate(const QString &id);
    Q_INVOKABLE void arrange(const QString &id, const QString &how);  // up | down | front | back
    Q_INVOKABLE void moveTo(const QString &id, int index);             // przeciągnięcie w panelu Warstwy
    // Kilka zaznaczonych elementów naraz — jeden krok cofania
    Q_INVOKABLE QStringList duplicateAll(const QStringList &ids);
    Q_INVOKABLE void removeAll(const QStringList &ids);
    Q_INVOKABLE QVariantMap get(const QString &id) const;
    Q_INVOKABLE int indexOf(const QString &id) const;
    Q_INVOKABLE QString idAt(int index) const;
    Q_INVOKABLE void setBackground(const QVariantMap &background, bool commit = true);
    Q_INVOKABLE qreal naturalWidth(const QVariantMap &textElement) const;

    // Zamyka zmianę (np. po przeciągnięciu) jako jeden krok cofania
    Q_INVOKABLE void commit();
    Q_INVOKABLE void undo();
    Q_INVOKABLE void redo();

    // ——— Zdjęcia, schowek, eksport ———
    Q_INVOKABLE QString importImage(const QString &fileOrUrl);   // zwraca klucz zdjęcia albo ""
    Q_INVOKABLE QSize imageSize(const QString &key) const;
    Q_INVOKABLE void copy(const QStringList &ids) const;
    Q_INVOKABLE QString clipboardText() const;                    // np. komórki skopiowane z arkusza (tabulatory)
    Q_INVOKABLE QStringList paste();                              // elementy ze schowka, zdjęcie albo tekst
    Q_INVOKABLE bool copyImage();                                 // cała strona jako obraz (do wklejenia w komunikatorze)
    // allPages — PNG/JPG: każda strona do osobnego pliku (nazwa-1, nazwa-2…); PDF ma zawsze wszystkie strony
    Q_INVOKABLE QString exportFile(const QString &format, qreal scale, const QString &target = QString(), bool allPages = false);

Q_SIGNALS:
    void pageChanged();
    void backgroundChanged();
    void nameChanged();
    void pathChanged();
    void modifiedChanged();
    void historyChanged();
    void countChanged();
    void imagesChanged();
    void colorsChanged();
    void pagesChanged();
    void guidesChanged();
    void savedElementsChanged();
    void changed();                 // każda zmiana treści (do zapisu automatycznego)
    void reset();                   // nowa zawartość (cofanie, otwarcie) — zaznaczenie mogło zniknąć
    void error(const QString &message);

private:
    struct Asset {
        QByteArray data;
        QString ext;
        QImage full;
        QImage preview;             // do 1600 px — na ekran
    };

    QByteArray snapshot() const;
    void restore(const QByteArray &json);
    void load(const QVariantMap &doc);
    QVariantList pages() const;                 // wszystkie strony, z bieżącą w aktualnym stanie
    void storePage();                           // bieżąca strona → m_pages
    void showPage(int page);                    // strona z m_pages → model
    void setModified(bool on);
    void setPath(const QString &path);
    QString addAsset(const QByteArray &data, const QString &ext);
    static bool decode(Asset &a);
    QVariantMap prepared(QVariantMap el) const;
    QString newId();
    QString insert(const QVariantMap &element);     // bez zamykania kroku cofania
    QVariantMap clipData(const QStringList &ids) const;                 // elementy z dołączonymi zdjęciami
    QStringList insertClip(const QVariantMap &clip, const std::function<QVariantMap(QVariantMap)> &place);
    QString uniquePath(const QString &dir, const QString &base, const QString &ext) const;

    qreal m_width = 1080;
    qreal m_height = 1080;
    QVariantMap m_background;
    QVariantMap m_guides;
    QVariantMap m_print;            // rozmiar do druku w mm (PDF), np. A4
    QVariantList m_elements;
    QVariantList m_pages;           // { background, elements } każdej strony (bieżąca — stan sprzed storePage)
    int m_page = 0;
    QString m_name;
    QString m_path;
    bool m_modified = false;
    QHash<QString, Asset> m_assets;
    QHash<QString, int> m_fonts;    // czcionki dołączone do otwartego pliku (nazwa pliku → id)
    QList<QByteArray> m_undo;
    QList<QByteArray> m_redo;
    QByteArray m_last;              // ostatni zamknięty stan
    int m_nextId = 1;
};
