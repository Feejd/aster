#pragma once

#include <QObject>
#include <QQmlEngine>
#include <QVariantList>

// Podgląd PDF: ostatnie dokumenty (z zapamiętaną stroną), szczegóły pliku, drukowanie, „Pokaż w folderze”.
class Pdf : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(QVariantList recent READ recent NOTIFY recentChanged)     // [{ path, name, folder, when, page }]

public:
    explicit Pdf(QObject *parent = nullptr);

    QVariantList recent() const;
    Q_INVOKABLE void remember(const QString &path, int page);
    Q_INVOKABLE int lastPage(const QString &path) const;
    Q_INVOKABLE void forget(const QString &path);
    Q_INVOKABLE QVariantMap fileInfo(const QString &path) const;         // { name, folder, size, modified }
    Q_INVOKABLE QString toPath(const QString &pathOrUrl) const;
    Q_INVOKABLE void showInFolder(const QString &path) const;
    Q_INVOKABLE bool print(const QString &path, const QString &password = {});
    Q_INVOKABLE QString date(const QDateTime &dt) const;

Q_SIGNALS:
    void recentChanged();
    void message(const QString &text);
};
