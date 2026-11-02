#pragma once

#include <QColor>
#include <QFont>
#include <QPointer>
#include <QQuickPaintedItem>
#include <QQuickTextDocument>

// Numery wierszy obok TextEdit: rysuje tylko widoczne wiersze (blok tekstu = wiersz; zawinięty wiersz
// ma jeden numer), bieżący — wyraźniej.
class LineNumbers : public QQuickPaintedItem
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(QQuickTextDocument *document READ document WRITE setDocument NOTIFY changed)
    Q_PROPERTY(int firstPosition MEMBER m_firstPosition WRITE setFirstPosition NOTIFY changed)   // pozycja tekstu na górze widoku
    Q_PROPERTY(qreal offset MEMBER m_offset WRITE setOffset NOTIFY changed)                        // contentY − górny margines
    Q_PROPERTY(int currentLine MEMBER m_currentLine WRITE setCurrentLine NOTIFY changed)          // od 0
    Q_PROPERTY(QFont font MEMBER m_font WRITE setFont NOTIFY changed)
    Q_PROPERTY(QColor color MEMBER m_color WRITE setColor NOTIFY changed)
    Q_PROPERTY(QColor currentColor MEMBER m_currentColor WRITE setCurrentColor NOTIFY changed)
    Q_PROPERTY(int lineCount READ lineCount NOTIFY changed)

public:
    explicit LineNumbers(QQuickItem *parent = nullptr);
    void paint(QPainter *painter) override;

    QQuickTextDocument *document() const { return m_document; }
    void setDocument(QQuickTextDocument *d);
    void setFirstPosition(int p) { m_firstPosition = p; update(); Q_EMIT changed(); }
    void setOffset(qreal o) { m_offset = o; update(); Q_EMIT changed(); }
    void setCurrentLine(int l) { m_currentLine = l; update(); Q_EMIT changed(); }
    void setFont(const QFont &f) { m_font = f; update(); Q_EMIT changed(); }
    void setColor(const QColor &c) { m_color = c; update(); Q_EMIT changed(); }
    void setCurrentColor(const QColor &c) { m_currentColor = c; update(); Q_EMIT changed(); }
    int lineCount() const;

Q_SIGNALS:
    void changed();

private:
    QPointer<QQuickTextDocument> m_document;
    int m_firstPosition = 0, m_currentLine = 0;
    qreal m_offset = 0;
    QFont m_font;
    QColor m_color, m_currentColor;
};
