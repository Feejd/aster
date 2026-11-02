#pragma once

#include <QObject>
#include <QPointer>
#include <QQmlEngine>
#include <QQuickTextDocument>

namespace KSyntaxHighlighting {
class SyntaxHighlighter;
}

// Kolorowanie składni (KSyntaxHighlighting, to samo co w Kate) dla TextEdit w QML.
// Język — z nazwy pliku albo pierwszej linii (#!/bin/bash); motyw jasny/ciemny jak system.
class Highlighter : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(QQuickTextDocument *document READ document WRITE setDocument NOTIFY changed)
    Q_PROPERTY(QString fileName READ fileName WRITE setFileName NOTIFY changed)
    Q_PROPERTY(QString firstLine READ firstLine WRITE setFirstLine NOTIFY changed)
    Q_PROPERTY(bool dark READ dark WRITE setDark NOTIFY changed)
    Q_PROPERTY(QString language READ language NOTIFY languageChanged)        // „Python”, „Zwykły tekst”

public:
    explicit Highlighter(QObject *parent = nullptr);
    ~Highlighter() override;

    QQuickTextDocument *document() const { return m_document; }
    void setDocument(QQuickTextDocument *d);
    QString fileName() const { return m_fileName; }
    void setFileName(const QString &f);
    QString firstLine() const { return m_firstLine; }
    void setFirstLine(const QString &l);
    bool dark() const { return m_dark; }
    void setDark(bool d);
    QString language() const { return m_language; }

Q_SIGNALS:
    void changed();
    void languageChanged();

private:
    void update();
    QPointer<QQuickTextDocument> m_document;
    KSyntaxHighlighting::SyntaxHighlighter *m_highlighter = nullptr;
    QString m_fileName, m_firstLine, m_language;
    bool m_dark = false;
};
