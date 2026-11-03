#pragma once

#include <QColor>
#include <QPointer>
#include <QQuickPaintedItem>
#include <QQuickTextDocument>
#include <QTimer>

// Minimapa po prawej stronie edytora (jak w VS Code): wiersze jako cienkie paski w kolorach składni
// (formaty z KSyntaxHighlighting), prostokąt widocznej części; klik i przeciąganie przewijają.
// Przy długim pliku minimapa przesuwa się proporcjonalnie do przewijania.
class Minimap : public QQuickPaintedItem
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(QQuickTextDocument *document READ document WRITE setDocument NOTIFY changed)
    Q_PROPERTY(int firstLine MEMBER m_firstLine WRITE setFirstLine NOTIFY changed)      // pierwszy widoczny wiersz edytora
    Q_PROPERTY(int visibleLines MEMBER m_visibleLines WRITE setVisibleLines NOTIFY changed)
    Q_PROPERTY(QColor textColor MEMBER m_text NOTIFY changed)
    Q_PROPERTY(QColor sliderColor MEMBER m_slider NOTIFY changed)
    Q_PROPERTY(QVariantList marks READ marks WRITE setMarks NOTIFY changed)            // [{ line, color }] — błędy, trafienia

public:
    explicit Minimap(QQuickItem *parent = nullptr);
    void paint(QPainter *p) override;

    QQuickTextDocument *document() const { return m_document; }
    void setDocument(QQuickTextDocument *d);
    void setFirstLine(int l) { if (l != m_firstLine) { m_firstLine = l; update(); Q_EMIT changed(); } }
    void setVisibleLines(int n) { if (n != m_visibleLines) { m_visibleLines = n; update(); Q_EMIT changed(); } }
    QVariantList marks() const { return m_marks; }
    void setMarks(const QVariantList &m) { m_marks = m; update(); Q_EMIT changed(); }

    // Wiersz pod punktem minimapy (do przewijania z QML)
    Q_INVOKABLE int lineAt(qreal y) const;

Q_SIGNALS:
    void changed();

private:
    int visibleBlocks() const;
    qreal offset() const;              // ile pikseli minimapy jest nad jej górną krawędzią

    QPointer<QQuickTextDocument> m_document;
    int m_firstLine = 0, m_visibleLines = 40;
    QColor m_text = Qt::gray, m_slider = QColor(128, 128, 128, 40);
    QVariantList m_marks;
    QTimer m_repaint;
    static constexpr qreal LineH = 2.0, CharW = 1.0;
};
