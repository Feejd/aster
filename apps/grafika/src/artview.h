#pragma once

#include <QPointer>
#include <QQuickPaintedItem>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

#include "project.h"

// Jeden element projektu (albo tło strony, gdy element.kind === "background") narysowany tym samym kodem
// co eksport. Położenie, obrót i przezroczystość ustawia QML — przeciąganie nie wymaga ponownego rysowania.
class ArtView : public QQuickPaintedItem
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(QVariantMap element READ element WRITE setElement NOTIFY elementChanged)
    Q_PROPERTY(Project *project READ project WRITE setProject NOTIFY projectChanged)
    // Zapas wokół elementu (w jednostkach strony) na cień — QML powiększa widok o tyle z każdej strony
    Q_PROPERTY(qreal bleed READ bleed NOTIFY elementChanged)

public:
    explicit ArtView(QQuickItem *parent = nullptr);

    QVariantMap element() const { return m_element; }
    qreal bleed() const;
    void setElement(const QVariantMap &element);
    Project *project() const { return m_project; }
    void setProject(Project *project);

    void paint(QPainter *painter) override;

Q_SIGNALS:
    void elementChanged();
    void projectChanged();

private:
    QVariantMap m_element;
    QPointer<Project> m_project;
};

// Podgląd całej strony projektu (pasek stron) — rysuje się na nowo po każdej zmianie
class PageView : public QQuickPaintedItem
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(Project *project READ project WRITE setProject NOTIFY projectChanged)
    Q_PROPERTY(int page READ page WRITE setPage NOTIFY pageChanged)
    Q_PROPERTY(QString hidden READ hidden WRITE setHidden NOTIFY hiddenChanged)    // element pominięty (pisanie w miejscu)

public:
    explicit PageView(QQuickItem *parent = nullptr);
    Project *project() const { return m_project; }
    void setProject(Project *project);
    int page() const { return m_page; }
    void setPage(int page);
    QString hidden() const { return m_hidden; }
    void setHidden(const QString &id);
    void paint(QPainter *painter) override;

Q_SIGNALS:
    void projectChanged();
    void pageChanged();
    void hiddenChanged();

private:
    QPointer<Project> m_project;
    int m_page = 0;
    QString m_hidden;
};
