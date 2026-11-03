#pragma once

#include <QImage>
#include <QObject>
#include <QPointer>
#include <QTransform>
#include <QVariantList>
#include <QtQml/qqmlregistration.h>
#include <functional>
#include <memory>

class Project;
class QNetworkAccessManager;
struct MagicModels;

// Narzędzia AI na zdjęciach — małe modele działające na komputerze (bez internetu, po jednorazowym pobraniu):
// - usuwanie tła (ISNet, Apache 2.0, 178 MB),
// - zaznaczanie obiektu kliknięciem (MobileSAM, Apache 2.0, 44 MB),
// - magiczna gumka — usunięcie zaznaczonego i uzupełnienie tła (MI-GAN, MIT, 28 MB).
// Zaznaczenie (maska w pikselach zdjęcia) powstaje z pędzla, lassa albo kliknięcia w obiekt; potem: usuń, wyodrębnij
// jako nowy element albo przenieś (wyodrębnij i usuń z tła). Obliczenia w tle, wynik jako nowe zdjęcie w projekcie
// (cofanie przywraca poprzednie). Modele w ~/.local/share/aster-grafika/models.
class Magic : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(bool available READ available CONSTANT)                 // program zbudowany z ONNX Runtime
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
    Q_PROPERTY(QString status READ status NOTIFY busyChanged)
    Q_PROPERTY(qreal progress READ progress NOTIFY progressChanged)     // pobieranie modelu 0…1, −1 — bez pobierania
    Q_PROPERTY(QString maskUrl READ maskUrl NOTIFY maskChanged)         // podgląd zaznaczenia w ramce elementu
    Q_PROPERTY(bool hasMask READ hasMask NOTIFY maskChanged)
    Q_PROPERTY(QString element READ element NOTIFY maskChanged)         // zdjęcie w trybie narzędzi AI

public:
    explicit Magic(QObject *parent = nullptr);
    ~Magic() override;

    bool available() const;
    bool busy() const { return !m_status.isEmpty(); }
    QString status() const { return m_status; }
    qreal progress() const { return m_progress; }
    QString maskUrl() const { return m_maskUrl; }
    bool hasMask() const { return m_hasMask; }
    QString element() const { return m_id; }

    // Ile MB trzeba pobrać przed pierwszym użyciem: background | object | erase
    Q_INVOKABLE int downloadMB(const QString &feature) const;

    Q_INVOKABLE void removeBackground(Project *project, const QString &id);

    Q_INVOKABLE void begin(Project *project, const QString &id);
    Q_INVOKABLE void end();
    // Współrzędne w ramce elementu (piksele elementu, bez obrotu); width — grubość pędzla
    Q_INVOKABLE void addStroke(const QVariantList &points, qreal width, bool lasso, bool subtract = false);
    Q_INVOKABLE void addObject(qreal x, qreal y, bool subtract = false);
    Q_INVOKABLE void clearMask();
    Q_INVOKABLE void undoMask();
    Q_INVOKABLE void apply(const QString &action);      // erase | extract | move

Q_SIGNALS:
    void busyChanged();
    void progressChanged();
    void maskChanged();
    void finished(const QString &message, const QStringList &ids);
    void failed(const QString &message);

private:
    void run(const QString &status, const QStringList &models, std::function<std::function<void()>()> work);
    void ensureModels(const QStringList &models, std::function<void()> then);
    void setStatus(const QString &status);
    void setMask(const QImage &mask, bool remember = true);
    void publishMask();
    bool loadElement();

    QNetworkAccessManager *m_net;
    std::shared_ptr<MagicModels> m_models;
    QString m_status;
    qreal m_progress = -1;

    QPointer<Project> m_project;
    QString m_id;
    QString m_src;
    QVariantMap m_el;
    QImage m_img;                   // zdjęcie elementu w pełnej rozdzielczości
    QImage m_mask;                  // zaznaczenie: Alpha8, rozmiar zdjęcia
    QList<QImage> m_history;        // poprzednie zaznaczenia (Ctrl+Z w trybie AI)
    QTransform m_toFrame;           // piksele zdjęcia → ramka elementu
    bool m_hasMask = false;
    QString m_maskUrl;
    int m_maskSerial = 0;
};
