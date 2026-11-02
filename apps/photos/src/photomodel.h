#pragma once

#include <QAbstractListModel>
#include <QDateTime>
#include <QFutureWatcher>
#include <QQmlEngine>
#include <QVector>

// Lista zdjęć: jeden folder (posortowany jak w Plikach — po nazwie, z liczbami po kolei)
// albo biblioteka (kilka folderów razem z podfolderami, najnowsze na górze). Czyta w tle.
class PhotoModel : public QAbstractListModel
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(int count READ count NOTIFY countChanged)
    Q_PROPERTY(bool loading READ loading NOTIFY loadingChanged)
    Q_PROPERTY(QString folder READ folder NOTIFY loaded)             // otwarty folder (pusty: biblioteka)

public:
    enum Roles { PathRole = Qt::UserRole + 1, NameRole, ThumbRole, UrlRole, ModifiedRole, MonthRole, AnimatedRole };
    struct Photo {
        QString path, name;
        qint64 mtime = 0;          // ms
    };

    explicit PhotoModel(QObject *parent = nullptr);
    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    int count() const { return m_items.size(); }
    bool loading() const { return m_loading; }
    QString folder() const { return m_folder; }

    Q_INVOKABLE void openFolder(const QString &dir);
    Q_INVOKABLE void openLibrary(const QStringList &roots);
    Q_INVOKABLE void reload();
    Q_INVOKABLE int indexOf(const QString &path) const;
    Q_INVOKABLE QVariantMap get(int row) const;                 // { path, name, thumb, url, animated }
    Q_INVOKABLE void removeAt(int row);
    Q_INVOKABLE void touch(int row);                            // plik zmieniony (obrót) — nowa miniatura
    Q_INVOKABLE QString monthAt(int row) const;                 // „listopad 2026”

    static bool isPhoto(const QString &fileName);
    static QString thumbUrl(const QString &path, qint64 mtime);

Q_SIGNALS:
    void countChanged();
    void loadingChanged();
    void loaded();

private:
    void start(const QString &folder, const QStringList &roots);
    QVector<Photo> m_items;
    QString m_folder;
    QStringList m_roots;
    bool m_loading = false;
    int m_generation = 0;
    QFutureWatcher<QVector<Photo>> m_watcher;
};
