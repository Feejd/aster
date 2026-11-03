#pragma once

#include <QColor>
#include <QFont>
#include <QPointer>
#include <QQuickPaintedItem>
#include <QQuickTextDocument>
#include <QTimer>
#include <QVector>

// Margines edytora kodu: numery wierszy (na wzór LineNumbers z Edytora tekstu) i znaczniki zmian
// względem wersji z gita — dodane (zielone), zmienione (akcent), usunięte (czerwony trójkąt).
// Różnice liczone na bieżąco z treści dokumentu, więc znaczniki idą za pisaniem jak w VS Code.
class Gutter : public QQuickPaintedItem
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
    Q_PROPERTY(QColor addedColor MEMBER m_added NOTIFY changed)
    Q_PROPERTY(QColor modifiedColor MEMBER m_modified NOTIFY changed)
    Q_PROPERTY(QColor deletedColor MEMBER m_deleted NOTIFY changed)
    Q_PROPERTY(QString baseText READ baseText WRITE setBaseText NOTIFY baseChanged)                // wersja z HEAD
    Q_PROPERTY(bool hasBase READ hasBase WRITE setHasBase NOTIFY baseChanged)
    Q_PROPERTY(int lineCount READ lineCount NOTIFY changed)
    Q_PROPERTY(int changeCount READ changeCount NOTIFY marksChanged)                               // liczba zmienionych miejsc

public:
    explicit Gutter(QQuickItem *parent = nullptr);
    void paint(QPainter *painter) override;

    QQuickTextDocument *document() const { return m_document; }
    void setDocument(QQuickTextDocument *d);
    void setFirstPosition(int p) { m_firstPosition = p; update(); Q_EMIT changed(); }
    void setOffset(qreal o) { m_offset = o; update(); Q_EMIT changed(); }
    void setCurrentLine(int l) { m_currentLine = l; update(); Q_EMIT changed(); }
    void setFont(const QFont &f) { m_font = f; update(); Q_EMIT changed(); }
    void setColor(const QColor &c) { m_color = c; update(); Q_EMIT changed(); }
    void setCurrentColor(const QColor &c) { m_currentColor = c; update(); Q_EMIT changed(); }
    QString baseText() const { return m_baseText; }
    void setBaseText(const QString &t);
    bool hasBase() const { return m_hasBase; }
    void setHasBase(bool on);
    int lineCount() const;
    int changeCount() const { return m_changeCount; }

    // Następne/poprzednie zmienione miejsce od wiersza (−1, gdy brak)
    Q_INVOKABLE int nextChange(int line, bool backwards) const;

Q_SIGNALS:
    void changed();
    void baseChanged();
    void marksChanged();

private:
    void recompute();

    QPointer<QQuickTextDocument> m_document;
    int m_firstPosition = 0, m_currentLine = 0;
    qreal m_offset = 0;
    QFont m_font;
    QColor m_color, m_currentColor;
    QColor m_added = QColor(0x3F, 0xB9, 0x50), m_modified = QColor(0x4C, 0x8B, 0xF5), m_deleted = QColor(0xE5, 0x48, 0x4D);
    QString m_baseText;
    bool m_hasBase = false;
    QTimer m_diffTimer;
    QVector<quint8> m_marks;            // na wiersz: 0 bez zmian, 1 dodany, 2 zmieniony
    QVector<bool> m_deletedBefore;      // usunięte wiersze tuż przed wierszem i (rozmiar = wiersze + 1)
    int m_changeCount = 0;
};
