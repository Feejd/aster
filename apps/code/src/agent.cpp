#include "agent.h"
#include "projectenv.h"
#include "secretstore.h"

#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusMessage>
#include <QDBusReply>
#include <QFile>
#include <QRegularExpression>

namespace {

const QString kService = QStringLiteral("org.aster.Assistant");
const QString kPath = QStringLiteral("/org/aster/Assistant");
const QString kIface = QStringLiteral("org.aster.Assistant");
constexpr int MaxOutput = 16 * 1024;

QDBusMessage call(const QString &method, const QVariantList &args, int timeout = 8000)
{
    QDBusMessage m = QDBusMessage::createMethodCall(kService, kPath, kIface, method);
    m.setArguments(args);
    return QDBusConnection::sessionBus().call(m, QDBus::Block, timeout);
}

// ```aster-edit ścieżka … ``` i ```aster-file ścieżka … ```
const QRegularExpression &editBlock()
{
    static const QRegularExpression re(QStringLiteral("```aster-(edit|file)[ \\t]+([^\\n`]+)\\n([\\s\\S]*?)\\n?```"));
    return re;
}

} // namespace

Agent::Agent(QObject *parent)
    : QObject(parent)
{
    QDBusConnection bus = QDBusConnection::sessionBus();
    bus.connect(kService, kPath, kIface, QStringLiteral("Chunk"), this, SLOT(onChunk(QString, QString)));
    bus.connect(kService, kPath, kIface, QStringLiteral("Finished"), this, SLOT(onFinished(QString, QString, QString)));
    bus.connect(kService, kPath, kIface, QStringLiteral("Failed"), this, SLOT(onFailed(QString, QString)));
    bus.connect(kService, kPath, kIface, QStringLiteral("ActionRequested"), this, SLOT(onAction(QString, QString, QString, QString, bool)));
    bus.connect(kService, kPath, kIface, QStringLiteral("StatusChanged"), this, SLOT(onStatus()));
    refresh();
}

void Agent::refresh()
{
    // Usługa startuje na żądanie (aktywacja D-Bus) — Status() ją budzi
    const QDBusMessage r = call(QStringLiteral("Status"), {}, 4000);
    const bool ok = r.type() == QDBusMessage::ReplyMessage && !r.arguments().isEmpty();
    const QVariantMap st = ok ? qdbus_cast<QVariantMap>(r.arguments().at(0)) : QVariantMap();
    const QString badge = st.value(QStringLiteral("badge")).toString();
    const QString problem = ok ? st.value(QStringLiteral("problem")).toString()
                               : QStringLiteral("Aster Intelligence nie działa — usługa aster-assistant nie odpowiada");
    if (ok != m_available || badge != m_badge || problem != m_problem) {
        m_available = ok;
        m_badge = badge;
        m_problem = problem;
        Q_EMIT availableChanged();
    }
}

QString Agent::ask(const QString &conversation, const QString &prompt, const QString &context)
{
    const QDBusMessage r = call(QStringLiteral("Ask"), {conversation, prompt, context, QStringLiteral("code")});
    if (r.type() != QDBusMessage::ReplyMessage || r.arguments().isEmpty()) {
        refresh();
        Q_EMIT failed(conversation, r.errorMessage().isEmpty() ? QStringLiteral("Aster Intelligence nie odpowiada") : r.errorMessage());
        return {};
    }
    return r.arguments().at(0).toString();
}

void Agent::cancel(const QString &conversation)
{
    call(QStringLiteral("Cancel"), {conversation}, 3000);
    stopCommand();
}

void Agent::runCommand(const QString &conversation, const QString &action, const QString &command, const QString &cwd)
{
    stopCommand();
    auto *p = new QProcess(this);
    m_cmd = p;
    p->setWorkingDirectory(cwd);
    p->setProcessChannelMode(QProcess::MergedChannels);
    QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
    env.insert(QStringLiteral("TERM"), QStringLiteral("dumb"));
    env.insert(QStringLiteral("NO_COLOR"), QStringLiteral("1"));
    env.insert(QStringLiteral("CI"), QStringLiteral("1"));              // testy bez trybu obserwowania, bez pytań
    env.insert(QStringLiteral("GIT_TERMINAL_PROMPT"), QStringLiteral("0"));
    p->setProcessEnvironment(env);
    auto *out = new QString;
    connect(p, &QProcess::readyRead, this, [this, p, out, conversation, action] {
        const QString t = QString::fromUtf8(p->readAll()).remove(QRegularExpression(QStringLiteral("\\x1B\\[[0-9;?]*[A-Za-z]")));
        if (out->size() < MaxOutput)
            out->append(t);
        Q_EMIT commandOutput(conversation, action, t);
    });
    connect(p, &QProcess::finished, this, [this, p, out, conversation, action](int code, QProcess::ExitStatus st) {
        p->deleteLater();
        QString o = *out;
        delete out;
        if (o.size() > MaxOutput)
            o = o.left(MaxOutput / 2) + QStringLiteral("\n… (wycięte) …\n") + o.right(MaxOutput / 2);
        const int exit = st == QProcess::NormalExit ? code : 130;
        // Do modelu idzie wynik bez sekretów; w rozmowie użytkownik też widzi wersję oczyszczoną
        o = SecretStore::instance()->redact(o);
        call(QStringLiteral("ActionResult"), {conversation, action, exit, o}, 4000);
        Q_EMIT commandDone(conversation, action, exit, o);
    });
    // W kontenerze projektu albo w systemie — tak samo jak zadania
    QStringList argv = ProjectEnv::instance()->shell(command, cwd);
    if (argv.isEmpty())
        argv = {QStringLiteral("/bin/sh"), QStringLiteral("-c"), command};
    p->start(argv.first(), argv.mid(1));
    p->closeWriteChannel();
}

void Agent::decline(const QString &conversation, const QString &action)
{
    call(QStringLiteral("ActionResult"), {conversation, action, -2, QString()}, 4000);
}

void Agent::refuse(const QString &conversation, const QString &action)
{
    call(QStringLiteral("ActionResult"), {conversation, action, 126,
         QStringLiteral("Aster Code nie uruchomił tego polecenia: sięga po sekrety (.env, klucze, środowisko). Sekrety nie są dostępne dla agenta — nie próbuj ich odczytać.")}, 4000);
}

void Agent::stopCommand()
{
    if (m_cmd && m_cmd->state() != QProcess::NotRunning) {
        m_cmd->terminate();
        if (!m_cmd->waitForFinished(1000))
            m_cmd->kill();
    }
}

QVariantList Agent::parseEdits(const QString &text) const
{
    QVariantList out;
    auto it = editBlock().globalMatch(text);
    static const QRegularExpression pair(QStringLiteral("<<<<<<< *SZUKAJ[^\\n]*\\n([\\s\\S]*?)\\n?=======[^\\n]*\\n([\\s\\S]*?)\\n?>>>>>>> *ZAMIE[NŃ][^\\n]*"));
    while (it.hasNext()) {
        const QRegularExpressionMatch m = it.next();
        const QString kind = m.captured(1), path = m.captured(2).trimmed(), body = m.captured(3);
        QVariantList blocks;
        if (kind == QLatin1String("edit")) {
            auto p = pair.globalMatch(body);
            while (p.hasNext()) {
                const auto b = p.next();
                blocks << QVariantMap{{QStringLiteral("search"), b.captured(1)}, {QStringLiteral("replace"), b.captured(2)}};
            }
            if (blocks.isEmpty())
                continue;
        }
        // Kolejne bloki tego samego pliku łączą się
        bool merged = false;
        for (QVariant &v : out) {
            QVariantMap e = v.toMap();
            if (e.value(QStringLiteral("path")).toString() == path && kind == QLatin1String("edit") && e.value(QStringLiteral("kind")).toString() == kind) {
                e.insert(QStringLiteral("blocks"), e.value(QStringLiteral("blocks")).toList() + blocks);
                v = e;
                merged = true;
            }
        }
        if (!merged)
            out << QVariantMap{{QStringLiteral("path"), path}, {QStringLiteral("kind"), kind}, {QStringLiteral("blocks"), blocks},
                               {QStringLiteral("content"), kind == QLatin1String("file") ? body + QLatin1Char('\n') : QString()}};
    }
    return out;
}

QString Agent::stripEdits(const QString &text) const
{
    QString t = text;
    t.replace(editBlock(), QStringLiteral("[[zmiana:\\2]]"));
    return t;
}

QVariantMap Agent::applyBlocks(const QString &current, const QVariantList &blocks) const
{
    QString t = current;
    int n = 0;
    for (const QVariant &v : blocks) {
        ++n;
        const QVariantMap b = v.toMap();
        const QString search = b.value(QStringLiteral("search")).toString(), replace = b.value(QStringLiteral("replace")).toString();
        int at = int(t.indexOf(search));
        // Model czasem gubi wcięcie albo spacje na końcach — drugie podejście bez nich
        if (at < 0 && !search.trimmed().isEmpty()) {
            QString pattern = QRegularExpression::escape(search.trimmed());
            pattern.replace(QRegularExpression(QStringLiteral("(\\\\\\s|\\\\\\n|\\s)+")), QStringLiteral("\\s+"));
            const auto m = QRegularExpression(pattern).match(t);
            if (m.hasMatch()) {
                t.replace(m.capturedStart(), m.capturedLength(), replace.trimmed());
                continue;
            }
        }
        if (at < 0)
            return {{QStringLiteral("ok"), false},
                    {QStringLiteral("error"), QStringLiteral("Fragment %1 nie pasuje do obecnej treści pliku").arg(n)}};
        t.replace(at, search.size(), replace);
    }
    return {{QStringLiteral("ok"), true}, {QStringLiteral("text"), t}};
}

QVariantList Agent::lineDiff(const QString &before, const QString &after) const
{
    const QStringList a = before.split(QLatin1Char('\n')), b = after.split(QLatin1Char('\n'));
    // Wspólny początek i koniec, LCS dla środka (pliki kodu — tysiące wierszy, nie miliony)
    int pre = 0;
    while (pre < a.size() && pre < b.size() && a[pre] == b[pre])
        ++pre;
    int suf = 0;
    while (suf < a.size() - pre && suf < b.size() - pre && a[a.size() - 1 - suf] == b[b.size() - 1 - suf])
        ++suf;
    const int n = int(a.size()) - pre - suf, m = int(b.size()) - pre - suf;
    struct Op { QChar k; int ai, bi; };
    QList<Op> ops;
    for (int i = 0; i < pre; ++i)
        ops.append({QLatin1Char(' '), i, i});
    if (qint64(n) * m > 4'000'000) {
        for (int i = 0; i < n; ++i)
            ops.append({QLatin1Char('-'), pre + i, -1});
        for (int j = 0; j < m; ++j)
            ops.append({QLatin1Char('+'), -1, pre + j});
    } else {
        QVector<int> L((n + 1) * (m + 1), 0);
        const auto at = [&](int i, int j) -> int & { return L[i * (m + 1) + j]; };
        for (int i = n - 1; i >= 0; --i)
            for (int j = m - 1; j >= 0; --j)
                at(i, j) = a[pre + i] == b[pre + j] ? at(i + 1, j + 1) + 1 : std::max(at(i + 1, j), at(i, j + 1));
        int i = 0, j = 0;
        while (i < n || j < m) {
            if (i < n && j < m && a[pre + i] == b[pre + j]) {
                ops.append({QLatin1Char(' '), pre + i, pre + j});
                ++i;
                ++j;
            } else if (i < n && (j == m || at(i + 1, j) >= at(i, j + 1))) {
                ops.append({QLatin1Char('-'), pre + i, -1});          // usunięte przed dodanymi, jak w git diff
                ++i;
            } else {
                ops.append({QLatin1Char('+'), -1, pre + j});
                ++j;
            }
        }
    }
    for (int i = 0; i < suf; ++i)
        ops.append({QLatin1Char(' '), int(a.size()) - suf + i, int(b.size()) - suf + i});
    // Tylko zmiany z 3 wierszami kontekstu, przerwy jako „@”
    QVector<bool> keep(ops.size(), false);
    for (int k = 0; k < ops.size(); ++k)
        if (ops[k].k != QLatin1Char(' '))
            for (int d = std::max(0, k - 3); d <= std::min(int(ops.size()) - 1, k + 3); ++d)
                keep[d] = true;
    QVariantList out;
    bool gap = false;
    for (int k = 0; k < ops.size(); ++k) {
        if (!keep[k]) {
            gap = true;
            continue;
        }
        if (gap || out.isEmpty()) {
            out << QVariantMap{{QStringLiteral("kind"), QStringLiteral("@")}, {QStringLiteral("text"), QString()}};
            gap = false;
        }
        const Op &o = ops[k];
        QVariantMap row{{QStringLiteral("kind"), QString(o.k)}, {QStringLiteral("text"), o.ai >= 0 ? a[o.ai] : b[o.bi]}};
        if (o.ai >= 0)
            row.insert(QStringLiteral("old"), o.ai + 1);
        if (o.bi >= 0)
            row.insert(QStringLiteral("new"), o.bi + 1);
        out << row;
    }
    return out;
}

QString Agent::readFile(const QString &path) const
{
    QFile f(path);
    if (f.size() > 4 * 1024 * 1024 || !f.open(QIODevice::ReadOnly))
        return {};
    return QString::fromUtf8(f.readAll());
}
