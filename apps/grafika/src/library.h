#pragma once

#include <QObject>
#include <QQuickImageProvider>
#include <QStringList>
#include <QVariantList>
#include <QtQml/qqmlregistration.h>

// Wszystko poza otwartym projektem: szablony (wbudowane pliki JSON), projekty użytkownika
// (folder Dokumenty/Grafiki i ostatnio otwierane), czcionki systemu, zdjęcia z folderu Obrazy.
class Library : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(QVariantList templates READ templates CONSTANT)
    Q_PROPERTY(QVariantList projects READ projects NOTIFY projectsChanged)
    Q_PROPERTY(QStringList fonts READ fonts NOTIFY fontsChanged)
    Q_PROPERTY(QString projectsFolder READ projectsFolder CONSTANT)

public:
    explicit Library(QObject *parent = nullptr);

    QVariantList templates() const { return m_templates; }
    QVariantList projects() const { return m_projects; }
    QStringList fonts() const;
    QString projectsFolder() const;

    Q_INVOKABLE void refresh();
    Q_INVOKABLE void reloadFonts() { Q_EMIT fontsChanged(); }     // po pobraniu czcionki
    Q_INVOKABLE void addRecent(const QString &path);
    Q_INVOKABLE bool trash(const QString &path);
    Q_INVOKABLE QVariantList photos() const;        // ostatnie zdjęcia z folderu Obrazy
    Q_INVOKABLE void open(const QString &path) const;
    Q_INVOKABLE void showInFolder(const QString &path) const;
    Q_INVOKABLE QString toPath(const QString &url) const;

Q_SIGNALS:
    void projectsChanged();
    void fontsChanged();

private:
    QVariantList m_templates;
    QVariantList m_projects;
};

// Miniatury: image://thumb/t/<plik szablonu> — narysowany szablon, image://thumb/p/<ścieżka> — miniatura z pliku projektu
class ThumbProvider : public QQuickImageProvider
{
public:
    ThumbProvider();
    QImage requestImage(const QString &id, QSize *size, const QSize &requestedSize) override;
};
