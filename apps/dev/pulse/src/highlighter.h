#pragma once

#include <QPointer>
#include <QQmlEngine>
#include <QQuickTextDocument>
#include <QSyntaxHighlighter>

// Kolory JSON (klucze, napisy, liczby, true/false/null) i {{zmiennych}} w polach tekstowych QML.
// Użycie: SyntaxColors { document: edit.textDocument; dark: Theme.dark; json: true }
class SyntaxColors : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(QQuickTextDocument *document READ document WRITE setDocument NOTIFY changed)
    Q_PROPERTY(bool dark READ dark WRITE setDark NOTIFY changed)
    Q_PROPERTY(bool json READ json WRITE setJson NOTIFY changed)
    Q_PROPERTY(QColor accent READ accent WRITE setAccent NOTIFY changed)
    // Znane zmienne środowiska — pozostałe {{…}} na czerwono (puste: wszystkie w kolorze akcentu)
    Q_PROPERTY(QStringList known READ known WRITE setKnown NOTIFY changed)
public:
    explicit SyntaxColors(QObject *parent = nullptr);
    QQuickTextDocument *document() const { return m_doc; }
    void setDocument(QQuickTextDocument *d);
    bool dark() const { return m_dark; }
    void setDark(bool d);
    bool json() const { return m_json; }
    void setJson(bool j);
    QColor accent() const { return m_accent; }
    void setAccent(const QColor &c);
    QStringList known() const { return m_known; }
    void setKnown(const QStringList &k);

Q_SIGNALS:
    void changed();

private:
    class Impl;
    QPointer<QQuickTextDocument> m_doc;
    Impl *m_impl = nullptr;
    bool m_dark = false;
    bool m_json = true;
    QColor m_accent = QColor(0x34, 0x56, 0xE8);
    QStringList m_known;
};
