#pragma once
#include <KDecoration3/Decoration>
#include <KDecoration3/DecorationButton>
#include <QVariantAnimation>

namespace Aster {

class Decoration;

// Przycisk okna: wygląd i kolejność jak w common/WindowButtons.qml
class Button : public KDecoration3::DecorationButton
{
    Q_OBJECT
public:
    Button(KDecoration3::DecorationButtonType type, Decoration *decoration);
    void paint(QPainter *painter, const QRectF &repaintArea) override;

private:
    qreal m_hover = 0;
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
    bool isDark() const;

    QList<Button *> m_buttons;
};

} // namespace Aster
