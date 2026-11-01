#pragma once

#include <QObject>
#include <QQmlEngine>
#include <QQuickWindow>
#include <QSettings>
#include <QVariantList>

// Wspólne dla wszystkich okien Terminala: ustawienia (czcionka, kolory, kursor, historia,
// zachowanie), schematy kolorów, otwieranie okien i drobne pomocnicze (ścieżki, powiadomienia).
class Terminal : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(QString fontFamily READ fontFamily WRITE setFontFamily NOTIFY settingsChanged)
    Q_PROPERTY(qreal fontSize READ fontSize WRITE setFontSize NOTIFY settingsChanged)
    Q_PROPERTY(qreal lineHeight READ lineHeight WRITE setLineHeight NOTIFY settingsChanged)
    Q_PROPERTY(QString scheme READ scheme WRITE setScheme NOTIFY settingsChanged)
    Q_PROPERTY(int cursorStyle READ cursorStyle WRITE setCursorStyle NOTIFY settingsChanged)
    Q_PROPERTY(bool cursorBlink READ cursorBlink WRITE setCursorBlink NOTIFY settingsChanged)
    Q_PROPERTY(int historyLines READ historyLines WRITE setHistoryLines NOTIFY settingsChanged)
    Q_PROPERTY(bool newTabHere READ newTabHere WRITE setNewTabHere NOTIFY settingsChanged)
    Q_PROPERTY(bool visualBell READ visualBell WRITE setVisualBell NOTIFY settingsChanged)
    Q_PROPERTY(bool confirmClose READ confirmClose WRITE setConfirmClose NOTIFY settingsChanged)
    Q_PROPERTY(bool copyOnSelect READ copyOnSelect WRITE setCopyOnSelect NOTIFY settingsChanged)
    Q_PROPERTY(bool notifyDone READ notifyDone WRITE setNotifyDone NOTIFY settingsChanged)
    Q_PROPERTY(QVariantList schemes READ schemes CONSTANT)
    Q_PROPERTY(QStringList fonts READ fonts CONSTANT)
    Q_PROPERTY(QString defaultFont READ defaultFont CONSTANT)
    Q_PROPERTY(QString shellName READ shellName CONSTANT)
    Q_PROPERTY(QString version READ version CONSTANT)

public:
    explicit Terminal(QQmlEngine *engine, QObject *parent = nullptr);
    static Terminal *instance() { return s_instance; }
    static Terminal *create(QQmlEngine *, QJSEngine *);

    QString fontFamily() const;
    void setFontFamily(const QString &f);
    qreal fontSize() const;
    void setFontSize(qreal s);
    qreal lineHeight() const;
    void setLineHeight(qreal h);
    QString scheme() const;
    void setScheme(const QString &s);
    int cursorStyle() const;
    void setCursorStyle(int s);
    bool cursorBlink() const;
    void setCursorBlink(bool on);
    int historyLines() const;
    void setHistoryLines(int n);
    bool newTabHere() const;
    void setNewTabHere(bool on);
    bool visualBell() const;
    void setVisualBell(bool on);
    bool confirmClose() const;
    void setConfirmClose(bool on);
    bool copyOnSelect() const;
    void setCopyOnSelect(bool on);
    bool notifyDone() const;
    void setNotifyDone(bool on);

    QVariantList schemes() const;
    QStringList fonts() const;
    QString defaultFont() const;
    QString shellName() const;
    QString version() const;

    // Kolory schematu: foreground, background, cursor (pusty — kolor akcentu), palette (16)
    Q_INVOKABLE QVariantMap colors(const QString &id, bool dark) const;
    Q_INVOKABLE QQuickWindow *openWindow(const QString &dir = QString(), const QStringList &command = QStringList());
    Q_INVOKABLE QString prettyPath(const QString &path) const;      // ~/Dokumenty/projekt
    Q_INVOKABLE QString folderName(const QString &path) const;      // projekt (albo ~)
    Q_INVOKABLE QString quotePaths(const QVariantList &urls) const;  // przeciągnięte pliki jako argumenty powłoki
    Q_INVOKABLE void notify(const QString &title, const QString &body);
    Q_INVOKABLE void resetSettings();

signals:
    void settingsChanged();

private:
    QVariant value(const char *key, const QVariant &def) const;
    void set(const char *key, const QVariant &v);

    static Terminal *s_instance;
    QQmlEngine *m_engine;
    mutable QSettings m_settings;
    QString m_defaultFont;
};
