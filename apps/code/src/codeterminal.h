#pragma once

#include "terminalview.h"

#include <QKeyEvent>

// Terminal z Terminala Aster (TerminalView) w dolnym panelu. Jak w VS Code kilka skrótów
// zostaje oknu edytora, a nie powłoce: Ctrl+` (panel), Ctrl+P (szybkie otwieranie), Ctrl+J, Ctrl+B.
class CodeTerminal : public TerminalView
{
    Q_OBJECT
    QML_ELEMENT

public:
    explicit CodeTerminal(QQuickItem *parent = nullptr)
        : TerminalView(parent)
    {
    }

protected:
    bool event(QEvent *e) override
    {
        if (e->type() == QEvent::ShortcutOverride) {
            auto *k = static_cast<QKeyEvent *>(e);
            const Qt::KeyboardModifiers m = k->modifiers() & ~Qt::KeypadModifier;
            const int key = k->key();
            if (m == Qt::ControlModifier && (key == Qt::Key_QuoteLeft || key == Qt::Key_P || key == Qt::Key_J || key == Qt::Key_B))
                return QQuickPaintedItem::event(e);          // nie przyjmujemy — skrót okna zadziała
        }
        return TerminalView::event(e);
    }
};
