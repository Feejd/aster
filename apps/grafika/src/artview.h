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

public:
    explicit ArtView(QQuickItem *parent = nullptr);

    QVariantMap element() const { return m_element; }
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
