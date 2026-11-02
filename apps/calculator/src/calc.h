#pragma once

#include <QObject>
#include <QQmlEngine>
#include <QVariantList>

// Kalkulator: liczenie wyrażeń w zapisie z ekranu („12,5 × (3 + 4)²”), z kolejnością działań,
// procentami jak w Windows (200 + 10% = 220), funkcjami naukowymi; wynik w polskim zapisie
// (przecinek, odstępy co trzy cyfry). Liczy na long double i pokazuje 15 cyfr — 0,1 + 0,2 = 0,3.
class Calc : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(QVariantList history READ history NOTIFY historyChanged)      // [{ expr, result }] — najnowsze pierwsze

public:
    explicit Calc(QObject *parent = nullptr);

    // { ok, value, text, error }
    Q_INVOKABLE QVariantMap evaluate(const QString &expression, bool degrees) const;
    Q_INVOKABLE QString format(double value) const;
    Q_INVOKABLE QString group(const QString &number) const;      // odstępy w liczbie wpisywanej („12345,6” → „12 345,6”)
    Q_INVOKABLE QString fromClipboard() const;                    // wklejony tekst zamieniony na zapis kalkulatora
    Q_INVOKABLE void toClipboard(const QString &text) const;

    QVariantList history() const { return m_history; }
    Q_INVOKABLE void addHistory(const QString &expr, const QString &result);
    Q_INVOKABLE void clearHistory();

Q_SIGNALS:
    void historyChanged();

private:
    QString formatReal(long double value) const;
    QVariantList m_history;
};
