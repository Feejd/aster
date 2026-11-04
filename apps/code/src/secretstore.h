#pragma once

#include <QHash>
#include <QObject>
#include <QQmlEngine>
#include <QStringList>
#include <QVariantMap>

// Sekrety projektu (zmienne .env, klucze API) w portfelu systemu przez Secret Service (w Aster: KWallet,
// ksecretd) — jeden wpis na projekt, nic w plikach. Trafiają do zadań, serwerów i debugera przy
// uruchomieniu (plik tylko dla właściciela w /run/user, kasowany zaraz po wczytaniu przez powłokę)
// i nigdy do modelu: redact() wycina ich wartości, a pliki .env nie są dołączane do kontekstu agenta.
class SecretStore : public QObject
{
    Q_OBJECT
    QML_NAMED_ELEMENT(Secrets)
    QML_SINGLETON
    Q_PROPERTY(QString root READ root WRITE setRoot NOTIFY changed)
    Q_PROPERTY(QStringList names READ names NOTIFY changed)
    Q_PROPERTY(QString error READ error NOTIFY changed)

public:
    static SecretStore *instance();
    static SecretStore *create(QQmlEngine *, QJSEngine *);

    QString root() const { return m_root; }
    void setRoot(const QString &r);
    QStringList names() const;
    QString error() const;

    Q_INVOKABLE bool set(const QString &name, const QString &value);
    Q_INVOKABLE bool remove(const QString &name);
    Q_INVOKABLE QString reveal(const QString &name) const;          // wartość do pokazania na żądanie
    Q_INVOKABLE QVariantMap env() const;
    Q_INVOKABLE QString redact(const QString &text) const;
    Q_INVOKABLE QVariantList envFiles() const;                      // pliki .env w projekcie: [{ name, path, count }]
    Q_INVOKABLE int importEnv(const QString &path, bool clearFile); // liczba zmiennych, −1 — błąd portfela
    Q_INVOKABLE void reload() { m_loaded = false; Q_EMIT changed(); }
    static bool isSecretFile(const QString &path);
    Q_INVOKABLE bool secretFile(const QString &path) const { return isSecretFile(path); }
    static QVariantMap parseEnv(const QString &path);
    // Wspólne dla wszystkich projektów (np. token GitHuba) — osobny wpis w portfelu
    static QString globalGet(const QString &name);
    static bool globalSet(const QString &name, const QString &value);
    // Plik „export NAZWA='wartość'” dla powłoki (pusty — brak sekretów)
    QString writeEnvFile(const QVariantMap &extra = QVariantMap()) const;

Q_SIGNALS:
    void changed();

private:
    explicit SecretStore(QObject *parent = nullptr);
    void load() const;
    bool save();

    QString m_root;
    mutable QHash<QString, QString> m_vars;
    mutable bool m_loaded = false;
    mutable QString m_error;
    mutable int m_fileSeq = 0;
};
