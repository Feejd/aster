#pragma once

#include <QObject>
#include <QPointer>
#include <QQmlEngine>
#include <QQuickTextDocument>
#include <QSet>
#include <QSyntaxHighlighter>

// Kolorowanie SQL w edytorze zapytań: słowa kluczowe, funkcje, napisy, liczby, komentarze
// (także wielowierszowe /* */) i nazwy tabel z otwartej bazy. Bez KSyntaxHighlighting — lżej.
class SqlRules : public QSyntaxHighlighter
{
public:
    explicit SqlRules(QTextDocument *doc);
    void highlightBlock(const QString &text) override;
    bool dark = false;
    QSet<QString> tables;
};

class SqlHighlighter : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(QQuickTextDocument *document READ document WRITE setDocument NOTIFY changed)
    Q_PROPERTY(bool dark READ dark WRITE setDark NOTIFY changed)
    Q_PROPERTY(QStringList tables READ tables WRITE setTables NOTIFY changed)
public:
    QQuickTextDocument *document() const { return m_doc; }
    void setDocument(QQuickTextDocument *d);
    bool dark() const { return m_dark; }
    void setDark(bool d);
    QStringList tables() const { return m_tables; }
    void setTables(const QStringList &t);
Q_SIGNALS:
    void changed();
private:
    void apply();
    QPointer<QQuickTextDocument> m_doc;
    SqlRules *m_rules = nullptr;
    bool m_dark = false;
    QStringList m_tables;
};
