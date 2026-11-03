#pragma once

#include <QAtomicInt>
#include <QImage>
#include <QMutex>
#include <QObject>
#include <QQmlEngine>
#include <QQuickImageProvider>
#include <QRectF>
#include <QThreadPool>
#include <QVariantList>

// Skaner (zamiast Skanlite), przez SANE: lista skanerów (USB i sieciowe przez sane-airscan), podgląd z kadrowaniem,
// skanowanie z płyty albo podajnika (wiele stron naraz), strony do obrócenia i ułożenia, zapis do PDF albo JPG/PNG.
// Wszystkie wywołania SANE idą po kolei w jednym wątku w tle.
class Scanner : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(QVariantList devices READ devices NOTIFY devicesChanged)       // [{ name, label }]
    Q_PROPERTY(bool searching READ searching NOTIFY devicesChanged)
    Q_PROPERTY(QString device READ device NOTIFY optionsChanged)
    Q_PROPERTY(QVariantList sources READ sources NOTIFY optionsChanged)       // [{ value, label, feeder }]
    Q_PROPERTY(QVariantList modes READ modes NOTIFY optionsChanged)           // [{ value, label }]
    Q_PROPERTY(QVariantList resolutions READ resolutions NOTIFY optionsChanged) // [150, 300, …]
    Q_PROPERTY(QSizeF area READ area NOTIFY optionsChanged)                   // obszar skanowania (mm)
    Q_PROPERTY(bool busy READ busy NOTIFY stateChanged)
    Q_PROPERTY(QString task READ task NOTIFY stateChanged)                    // „Skanowanie strony 2…”
    Q_PROPERTY(qreal progress READ progress NOTIFY progressChanged)
    Q_PROPERTY(QString preview READ preview NOTIFY previewChanged)            // adres obrazka podglądu
    Q_PROPERTY(QVariantList pages READ pages NOTIFY pagesChanged)             // [{ url, width, height }]

public:
    explicit Scanner(QObject *parent = nullptr);
    ~Scanner() override;

    QVariantList devices() const { return m_devices; }
    bool searching() const { return m_searching; }
    QString device() const { return m_device; }
    QVariantList sources() const { return m_sources; }
    QVariantList modes() const { return m_modes; }
    QVariantList resolutions() const { return m_resolutions; }
    QSizeF area() const { return m_area; }
    bool busy() const { return !m_task.isEmpty(); }
    QString task() const { return m_task; }
    qreal progress() const { return m_progress; }
    QString preview() const { return m_previewUrl; }
    QVariantList pages() const;

    Q_INVOKABLE void refresh();
    Q_INVOKABLE void select(const QString &name);
    Q_INVOKABLE void previewScan(const QString &source, const QString &mode);
    // crop: znormalizowany prostokąt (0..1) z podglądu; pusty = cały obszar
    Q_INVOKABLE void scan(const QString &source, const QString &mode, int dpi, const QRectF &crop);
    Q_INVOKABLE void cancel();
    Q_INVOKABLE void removePage(int index);
    Q_INVOKABLE void movePage(int from, int to);
    Q_INVOKABLE void rotatePage(int index);
    Q_INVOKABLE void clear();
    Q_INVOKABLE void save(const QString &format);         // pdf | jpg | png
    Q_INVOKABLE void showInFolder(const QString &path) const;
    Q_INVOKABLE void open(const QString &path) const;

    QImage image(const QString &id) const;                // dla dostawcy obrazków

    static Scanner *s_instance;

Q_SIGNALS:
    void devicesChanged();
    void optionsChanged();
    void stateChanged();
    void progressChanged();
    void previewChanged();
    void pagesChanged();
    void error(const QString &message);
    void saved(const QString &path, int count);           // ścieżka pierwszego pliku, liczba plików

private:
    struct Page { int id; QImage image; int dpi; };
    void run(const QString &task, std::function<void()> job);
    void finish();
    void setProgress(qreal p);
    QString folder(bool documents) const;

    QThreadPool m_pool;                                   // jeden wątek: SANE po kolei
    void *m_handle = nullptr;                             // SANE_Handle (tylko w wątku SANE)
    QAtomicInt m_cancel;
    QVariantList m_devices, m_sources, m_modes, m_resolutions;
    bool m_searching = false;
    QString m_device, m_task, m_previewUrl;
    QSizeF m_area;
    qreal m_progress = 0;
    QImage m_previewImage;
    int m_previewCount = 0;
    QList<Page> m_pages;
    int m_nextId = 1;
    mutable QMutex m_imagesLock;
};

class ScanImageProvider : public QQuickImageProvider
{
public:
    ScanImageProvider() : QQuickImageProvider(QQuickImageProvider::Image) {}
    QImage requestImage(const QString &id, QSize *size, const QSize &requestedSize) override;
};
