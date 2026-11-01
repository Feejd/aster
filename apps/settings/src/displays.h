#pragma once

#include <QObject>
#include <QQmlEngine>
#include <QTimer>
#include <QVariantList>

// Monitory (kscreen-doctor — ten sam mechanizm co w KDE): rozdzielczość, odświeżanie, skalowanie,
// obrót, monitor główny, włączanie i układ kilku ekranów; jasność (PowerDevil, org.kde.ScreenBrightness).
// Monitor: { name, label, enabled, primary, scale, rotation, x, y, width, height, modeId, refresh, modes:[{id,width,height,refresh}] }
class Displays : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(QVariantList outputs MEMBER m_outputs NOTIFY changed)
    Q_PROPERTY(bool busy MEMBER m_busy NOTIFY changed)
    Q_PROPERTY(bool brightnessAvailable MEMBER m_brightnessAvailable NOTIFY brightnessChanged)
    Q_PROPERTY(double brightness MEMBER m_brightness NOTIFY brightnessChanged)

public:
    explicit Displays(QObject *parent = nullptr);

    Q_INVOKABLE void refresh();
    Q_INVOKABLE void setMode(const QString &output, const QString &modeId);
    Q_INVOKABLE void setScale(const QString &output, double scale);
    Q_INVOKABLE void setRotation(const QString &output, const QString &rotation);   // normal | left | inverted | right
    Q_INVOKABLE void setEnabled(const QString &output, bool on);
    Q_INVOKABLE void setPrimary(const QString &output);
    Q_INVOKABLE void setPosition(const QString &output, int x, int y);
    Q_INVOKABLE void setBrightness(double value);

Q_SIGNALS:
    void changed();
    void brightnessChanged();
    void message(const QString &text);

private:
    void apply(const QStringList &args);
    void readBrightness();

    bool m_preview = false;
    bool m_busy = false;
    QVariantList m_outputs;
    bool m_brightnessAvailable = false;
    double m_brightness = 1;
    QString m_display;
    int m_maxBrightness = 0;
    QTimer m_brightnessDelay;
};
