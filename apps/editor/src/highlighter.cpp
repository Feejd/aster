#include "highlighter.h"

#include <KSyntaxHighlighting/Definition>
#include <KSyntaxHighlighting/Repository>
#include <KSyntaxHighlighting/SyntaxHighlighter>
#include <KSyntaxHighlighting/Theme>
#include <QFileInfo>
#include <QRegularExpression>
#include <QTextDocument>

namespace {

KSyntaxHighlighting::Repository &repository()
{
    static KSyntaxHighlighting::Repository repo;
    return repo;
}

} // namespace

Highlighter::Highlighter(QObject *parent)
    : QObject(parent)
{
}

Highlighter::~Highlighter() = default;

void Highlighter::setDocument(QQuickTextDocument *d)
{
    if (d == m_document)
        return;
    m_document = d;
    delete m_highlighter;
    m_highlighter = nullptr;
    Q_EMIT changed();
    update();
}

void Highlighter::setFileName(const QString &f)
{
    if (f == m_fileName)
        return;
    m_fileName = f;
    Q_EMIT changed();
    update();
}

void Highlighter::setFirstLine(const QString &l)
{
    // Tylko „#!…” ma znaczenie (skrypt bez rozszerzenia) — inne zmiany pierwszej linii nie przeliczają kolorów
    const QString shebang = l.startsWith(QLatin1String("#!")) ? l.left(80) : QString();
    if (shebang == m_firstLine)
        return;
    m_firstLine = shebang;
    Q_EMIT changed();
    update();
}

void Highlighter::setDark(bool d)
{
    if (d == m_dark)
        return;
    m_dark = d;
    Q_EMIT changed();
    update();
}

void Highlighter::update()
{
    if (!m_document || !m_document->textDocument())
        return;
    auto &repo = repository();
    KSyntaxHighlighting::Definition def = repo.definitionForFileName(QFileInfo(m_fileName).fileName());
    if (!def.isValid() && !m_firstLine.isEmpty()) {
        // #!/usr/bin/env python3 → Python, #!/bin/bash → Bash
        QString prog = m_firstLine.mid(2).trimmed().section(QLatin1Char(' '), 0, 0).section(QLatin1Char('/'), -1);
        if (prog == QLatin1String("env"))
            prog = m_firstLine.mid(2).trimmed().section(QLatin1Char(' '), 1, 1);
        prog.remove(QRegularExpression(QStringLiteral("[0-9.]+$")));
        static const QHash<QString, QString> names{{QStringLiteral("sh"), QStringLiteral("Bash")}, {QStringLiteral("bash"), QStringLiteral("Bash")},
                                                   {QStringLiteral("zsh"), QStringLiteral("Zsh")}, {QStringLiteral("python"), QStringLiteral("Python")},
                                                   {QStringLiteral("perl"), QStringLiteral("Perl")}, {QStringLiteral("node"), QStringLiteral("JavaScript")},
                                                   {QStringLiteral("ruby"), QStringLiteral("Ruby")}, {QStringLiteral("fish"), QStringLiteral("Fish")}};
        if (names.contains(prog))
            def = repo.definitionForName(names.value(prog));
    }
    const QString lang = def.isValid() ? def.translatedName() : QStringLiteral("Zwykły tekst");
    if (lang != m_language) {
        m_language = lang;
        Q_EMIT languageChanged();
    }
    if (!def.isValid()) {
        delete m_highlighter;
        m_highlighter = nullptr;
        return;
    }
    if (!m_highlighter)
        m_highlighter = new KSyntaxHighlighting::SyntaxHighlighter(m_document->textDocument());
    m_highlighter->setTheme(repo.defaultTheme(m_dark ? KSyntaxHighlighting::Repository::DarkTheme : KSyntaxHighlighting::Repository::LightTheme));
    m_highlighter->setDefinition(def);
    m_highlighter->rehighlight();
}
