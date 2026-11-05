#pragma once
#include <KDecoration3/Decoration>
#include <KDecoration3/DecorationButton>
#include <QVariantAnimation>

namespace Aster {

class Decoration;

// Kropka okna: wygląd i kolejność jak w common/WindowButtons.qml
class Button : public KDecoration3::DecorationButton
{
    Q_OBJECT
public:
    Button(KDecoration3::DecorationButtonType type, Decoration *decoration);
    void paint(QPainter *painter, const QRectF &repaintArea) override;
    // Znaki na kropkach pojawiają się po najechaniu na całą grupę
    void setGroupHovered(qreal progress);

private:
    qreal m_hover = 0;
    qreal m_group = 0;
    QVariantAnimation m_hoverAnim;
};

class Decoration : public KDecoration3::Decoration
{
    Q_OBJECT
public:
    explicit Decoration(QObject *parent, const QVariantList &args);
    void paint(QPainter *painter, const QRectF &repaintArea) override;
    bool init() override;

private:
    void updateLayout();
    void updateShadow();
    void updateGroupHover();
    bool isDark() const;

    QList<Button *> m_buttons;
    QVariantAnimation m_groupAnim;
    qreal m_group = 0;
};

} // namespace Aster
