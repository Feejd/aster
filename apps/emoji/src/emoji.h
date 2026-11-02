#pragma once

#include <QObject>
#include <QQmlEngine>
#include <QVariantList>

class FakeInput;
class QMimeData;

// Panel emoji (Win+.): dane (polskie nazwy i słowa z CLDR), ostatnio używane, odcień skóry
// i wstawianie do aktywnego programu: schowek → Ctrl+V przez KWin → poprzednia zawartość schowka wraca.
class Emoji : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_CLASSINFO("D-Bus Interface", "org.aster.emoji")
    // [{ id, name, emoji: [{ c, n, t, s }] }] — znak, nazwa, odcienie skóry, tekst do szukania
    Q_PROPERTY(QVariantList groups READ groups CONSTANT)
    Q_PROPERTY(QStringList recent READ recent NOTIFY recentChanged)
    Q_PROPERTY(int tone READ tone WRITE setTone NOTIFY toneChanged)     // 0 — żółty, 1–5 — odcienie skóry

public:
    explicit Emoji(QObject *parent = nullptr);
    ~Emoji() override;

    QVariantList groups() const { return m_groups; }
    QStringList recent() const { return m_recent; }
    int tone() const { return m_tone; }
    void setTone(int t);

    // Bez ogonków i wielkich liter: „usmiech” znajdzie „uśmiech”
    Q_INVOKABLE QString fold(const QString &text) const;
    Q_INVOKABLE QString nameOf(const QString &emoji) const;
    // Wstaw do programu, który był aktywny przed otwarciem panelu
    Q_INVOKABLE void insert(const QString &text, bool remember);

public Q_SLOTS:
    void Toggle();                     // D-Bus: drugie Win+. — pokaż albo schowaj

Q_SIGNALS:
    void recentChanged();
    void toneChanged();
    void toggleRequested();
    void hideRequested();
    void copied(const QString &text);  // wklejanie niedostępne — zostało w schowku

private:
    QVariantList m_groups;
    QHash<QString, QString> m_names;
    QStringList m_recent;
    int m_tone = 0;
    FakeInput *m_input = nullptr;
};
