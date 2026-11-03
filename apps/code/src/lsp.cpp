#include "lsp.h"

#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QMap>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QRegularExpression>
#include <QStandardPaths>
#include <QTimer>
#include <QUrl>

namespace {

struct ServerDef {
    const char *id;
    const char *name;                       // pokazywana na pasku stanu
    QStringList exts;
    QList<QStringList> commands;            // kolejne próby: program i argumenty
    const char *package;                    // jak zainstalować (Fedora)
};

const QList<ServerDef> &definitions()
{
    static const QList<ServerDef> defs{
        {"clangd", "clangd", {"c", "h", "cpp", "cc", "cxx", "hpp", "hh", "hxx", "m", "mm"},
         {{"clangd", "--header-insertion=never"}}, "sudo dnf install clang-tools-extra"},
        {"qmlls", "qmlls", {"qml"}, {{"qmlls"}, {"/usr/lib64/qt6/bin/qmlls"}}, "sudo dnf install qt6-qtdeclarative"},
        {"python", "Python", {"py", "pyi"},
         {{"pylsp"}, {"pyright-langserver", "--stdio"}, {"basedpyright-langserver", "--stdio"}}, "sudo dnf install python3-lsp-server"},
        {"typescript", "TypeScript", {"js", "mjs", "cjs", "jsx", "ts", "mts", "cts", "tsx"},
         {{"typescript-language-server", "--stdio"}}, "npm install -g typescript-language-server typescript"},
        {"rust", "rust-analyzer", {"rs"}, {{"rust-analyzer"}}, "sudo dnf install rust-analyzer"},
        {"go", "gopls", {"go"}, {{"gopls"}}, "sudo dnf install golang-x-tools-gopls"},
        {"bash", "bash-language-server", {"sh", "bash"}, {{"bash-language-server", "start"}}, "npm install -g bash-language-server"},
    };
    return defs;
}

const ServerDef *defForPath(const QString &path)
{
    const QString ext = QFileInfo(path).suffix().toLower();
    for (const ServerDef &d : definitions())
        if (d.exts.contains(ext))
            return &d;
    return nullptr;
}

QString languageId(const QString &path)
{
    static const QHash<QString, QString> ids{
        {"c", "c"}, {"h", "cpp"}, {"cpp", "cpp"}, {"cc", "cpp"}, {"cxx", "cpp"}, {"hpp", "cpp"}, {"hh", "cpp"}, {"hxx", "cpp"},
        {"m", "objective-c"}, {"mm", "objective-cpp"}, {"qml", "qml"}, {"py", "python"}, {"pyi", "python"},
        {"js", "javascript"}, {"mjs", "javascript"}, {"cjs", "javascript"}, {"jsx", "javascriptreact"},
        {"ts", "typescript"}, {"mts", "typescript"}, {"cts", "typescript"}, {"tsx", "typescriptreact"},
        {"rs", "rust"}, {"go", "go"}, {"sh", "shellscript"}, {"bash", "shellscript"}};
    return ids.value(QFileInfo(path).suffix().toLower(), QStringLiteral("plaintext"));
}

QString uri(const QString &path)
{
    return QUrl::fromLocalFile(path).toString(QUrl::FullyEncoded);
}

QString pathFromUri(const QString &u)
{
    return QUrl(u).toLocalFile();
}

// Fragmenty (snippets) VS Code: ${1:nazwa} → nazwa, $0 / $1 → nic
QString stripSnippet(QString s)
{
    static const QRegularExpression placeholder(QStringLiteral("\\$\\{\\d+:([^}]*)\\}"));
    static const QRegularExpression tabstop(QStringLiteral("\\$\\{?\\d+\\}?"));
    s.replace(placeholder, QStringLiteral("\\1"));
    s.remove(tabstop);
    return s;
}

// Opis z „hover”: MarkupContent, MarkedString albo ich lista — jako zwykły tekst bez znaczników bloków kodu
QString hoverText(const QJsonValue &contents)
{
    QStringList parts;
    const auto add = [&](const QJsonValue &v) {
        if (v.isString())
            parts << v.toString();
        else if (v.isObject())
            parts << v.toObject().value(QStringLiteral("value")).toString();
    };
    if (contents.isArray())
        for (const QJsonValue &v : contents.toArray())
            add(v);
    else
        add(contents);
    QString text = parts.join(QStringLiteral("\n\n"));
    QStringList lines;
    for (const QString &l : text.split(QLatin1Char('\n')))
        if (!l.trimmed().startsWith(QLatin1String("```")) && l.trimmed() != QLatin1String("---"))
            lines << l;
    text = lines.join(QLatin1Char('\n')).trimmed();
    text.replace(QLatin1String("\\_"), QLatin1String("_"));
    return text.left(4000);
}

} // namespace

// ——— LspServer ———

LspServer::LspServer(const QString &id, const QString &program, const QStringList &args, const QString &root, QObject *parent)
    : QObject(parent)
    , m_id(id)
    , m_program(program)
{
    m_proc.setWorkingDirectory(root);
    m_proc.setProcessChannelMode(QProcess::SeparateChannels);
    connect(&m_proc, &QProcess::readyReadStandardOutput, this, &LspServer::readOutput);
    connect(&m_proc, &QProcess::readyReadStandardError, this, [this] { m_proc.readAllStandardError(); });
    connect(&m_proc, &QProcess::finished, this, [this] {
        m_ready = false;
        m_failed = true;
        Q_EMIT readyChanged();
        Q_EMIT stopped();
    });
    connect(&m_proc, &QProcess::errorOccurred, this, [this](QProcess::ProcessError e) {
        if (e == QProcess::FailedToStart) {
            m_failed = true;
            Q_EMIT stopped();
        }
    });
    m_proc.start(program, args);

    // Co potrafi edytor (tylko to, z czego korzysta Aster Code)
    const QJsonObject caps{
        {"textDocument", QJsonObject{
             {"synchronization", QJsonObject{{"didSave", true}, {"dynamicRegistration", false}}},
             {"completion", QJsonObject{{"completionItem", QJsonObject{{"snippetSupport", false}, {"documentationFormat", QJsonArray{"plaintext"}}}},
                                        {"contextSupport", true}}},
             {"hover", QJsonObject{{"contentFormat", QJsonArray{"markdown", "plaintext"}}}},
             {"definition", QJsonObject{{"linkSupport", true}}},
             {"publishDiagnostics", QJsonObject{{"relatedInformation", false}}}}},
        {"workspace", QJsonObject{{"configuration", true}, {"workspaceFolders", true}}},
        {"window", QJsonObject{{"workDoneProgress", false}}},
        {"general", QJsonObject{{"positionEncodings", QJsonArray{"utf-16"}}}}};
    const QJsonObject params{
        {"processId", int(QCoreApplication::applicationPid())},
        {"clientInfo", QJsonObject{{"name", "Aster Code"}, {"version", "1.0"}}},
        {"rootUri", uri(root)},
        {"rootPath", root},
        {"workspaceFolders", QJsonArray{QJsonObject{{"uri", uri(root)}, {"name", QFileInfo(root).fileName()}}}},
        {"capabilities", caps}};
    // „initialize” idzie od razu; reszta czeka w kolejce na odpowiedź
    const int id0 = ++m_seq;
    m_replies.insert(id0, [this](const QJsonValue &, const QJsonObject &error) {
        if (!error.isEmpty()) {
            m_failed = true;
            Q_EMIT stopped();
            return;
        }
        m_ready = true;
        send(QJsonObject{{"jsonrpc", "2.0"}, {"method", "initialized"}, {"params", QJsonObject{}}});
        for (const QJsonObject &m : std::as_const(m_queue))
            send(m);
        m_queue.clear();
        Q_EMIT readyChanged();
    });
    send(QJsonObject{{"jsonrpc", "2.0"}, {"id", id0}, {"method", "initialize"}, {"params", params}});
}

LspServer::~LspServer()
{
    shutdown();
}

void LspServer::shutdown()
{
    if (m_proc.state() == QProcess::NotRunning)
        return;
    if (m_ready) {
        send(QJsonObject{{"jsonrpc", "2.0"}, {"id", ++m_seq}, {"method", "shutdown"}});
        send(QJsonObject{{"jsonrpc", "2.0"}, {"method", "exit"}});
        m_proc.waitForFinished(300);
    }
    if (m_proc.state() != QProcess::NotRunning) {
        m_proc.terminate();
        if (!m_proc.waitForFinished(300))
            m_proc.kill();
    }
}

void LspServer::send(const QJsonObject &msg)
{
    if (m_proc.state() == QProcess::NotRunning && m_proc.error() == QProcess::FailedToStart)
        return;
    const QByteArray body = QJsonDocument(msg).toJson(QJsonDocument::Compact);
    m_proc.write("Content-Length: " + QByteArray::number(body.size()) + "\r\n\r\n" + body);
}

int LspServer::request(const QString &method, const QJsonObject &params, Reply reply)
{
    const int id = ++m_seq;
    m_replies.insert(id, std::move(reply));
    const QJsonObject msg{{"jsonrpc", "2.0"}, {"id", id}, {"method", method}, {"params", params}};
    if (m_ready)
        send(msg);
    else
        m_queue << msg;
    return id;
}

void LspServer::notify(const QString &method, const QJsonObject &params)
{
    const QJsonObject msg{{"jsonrpc", "2.0"}, {"method", method}, {"params", params}};
    if (m_ready)
        send(msg);
    else
        m_queue << msg;
}

void LspServer::readOutput()
{
    m_buffer += m_proc.readAllStandardOutput();
    // Ramki: nagłówki „Content-Length: N” zakończone pustą linią, potem N bajtów JSON
    for (;;) {
        const int headerEnd = int(m_buffer.indexOf("\r\n\r\n"));
        if (headerEnd < 0)
            return;
        int length = -1;
        for (const QByteArray &h : m_buffer.left(headerEnd).split('\n'))
            if (h.trimmed().toLower().startsWith("content-length:"))
                length = h.mid(h.indexOf(':') + 1).trimmed().toInt();
        if (length < 0) {
            m_buffer.remove(0, headerEnd + 4);
            continue;
        }
        if (m_buffer.size() < headerEnd + 4 + length)
            return;
        const QByteArray body = m_buffer.mid(headerEnd + 4, length);
        m_buffer.remove(0, headerEnd + 4 + length);
        const QJsonDocument doc = QJsonDocument::fromJson(body);
        if (doc.isObject())
            handle(doc.object());
    }
}

void LspServer::handle(const QJsonObject &msg)
{
    const bool hasId = msg.contains(QStringLiteral("id"));
    const QString method = msg.value(QStringLiteral("method")).toString();
    if (hasId && method.isEmpty()) {
        // Odpowiedź na nasze zapytanie
        const int id = msg.value(QStringLiteral("id")).toInt();
        if (Reply r = m_replies.take(id))
            r(msg.value(QStringLiteral("result")), msg.value(QStringLiteral("error")).toObject());
        return;
    }
    if (hasId) {
        // Zapytanie serwera: konfiguracja (puste ustawienia), rejestracja, postęp — zgoda bez treści
        QJsonValue result;
        if (method == QLatin1String("workspace/configuration")) {
            QJsonArray items;
            const int n = int(msg.value(QStringLiteral("params")).toObject().value(QStringLiteral("items")).toArray().size());
            for (int i = 0; i < n; ++i)
                items << QJsonValue();
            result = items;
        } else if (method == QLatin1String("workspace/workspaceFolders")) {
            result = QJsonArray{QJsonObject{{"uri", uri(m_proc.workingDirectory())}, {"name", QFileInfo(m_proc.workingDirectory()).fileName()}}};
        }
        send(QJsonObject{{"jsonrpc", "2.0"}, {"id", msg.value(QStringLiteral("id"))}, {"result", result}});
        return;
    }
    Q_EMIT notification(method, msg.value(QStringLiteral("params")).toObject());
}

// ——— Lsp ———

Lsp::Lsp(QObject *parent)
    : QObject(parent)
{
}

Lsp::~Lsp()
{
    for (LspServer *s : std::as_const(m_servers))
        delete s;
}

void Lsp::setRoot(const QString &root)
{
    if (root == m_root)
        return;
    for (LspServer *s : std::as_const(m_servers))
        s->deleteLater();
    m_servers.clear();
    m_docs.clear();
    m_diagnostics.clear();
    m_root = root;
    recount();
    Q_EMIT serversChanged();
}

QString Lsp::serverId(const QString &path) const
{
    const ServerDef *d = defForPath(path);
    return d ? QString::fromLatin1(d->id) : QString();
}

QVariantMap Lsp::serverFor(const QString &path) const
{
    const ServerDef *d = defForPath(path);
    if (!d)
        return {{QStringLiteral("id"), QString()}};
    bool available = false;
    for (const QStringList &c : d->commands)
        if (!QStandardPaths::findExecutable(c.first()).isEmpty() || QFileInfo(c.first()).isExecutable())
            available = true;
    const LspServer *s = m_servers.value(QString::fromLatin1(d->id));
    return {{QStringLiteral("id"), QString::fromLatin1(d->id)},
            {QStringLiteral("name"), s ? QFileInfo(s->program()).fileName() : QString::fromUtf8(d->name)},
            {QStringLiteral("available"), available},
            {QStringLiteral("running"), s && s->ready()},
            {QStringLiteral("failed"), s && s->failed()},
            {QStringLiteral("package"), QString::fromUtf8(d->package)}};
}

LspServer *Lsp::serverForPath(const QString &path)
{
    if (m_root.isEmpty())
        return nullptr;
    const ServerDef *d = defForPath(path);
    if (!d)
        return nullptr;
    const QString id = QString::fromLatin1(d->id);
    if (LspServer *s = m_servers.value(id))
        return s->failed() ? nullptr : s;
    for (const QStringList &c : d->commands) {
        QString exe = QStandardPaths::findExecutable(c.first());
        if (exe.isEmpty() && QFileInfo(c.first()).isExecutable())
            exe = c.first();
        if (exe.isEmpty())
            continue;
        auto *s = new LspServer(id, exe, c.mid(1), m_root, this);
        m_servers.insert(id, s);
        connect(s, &LspServer::notification, this, &Lsp::onNotification);
        connect(s, &LspServer::readyChanged, this, &Lsp::serversChanged);
        connect(s, &LspServer::stopped, this, [this, s] {
            // Serwer padł — jego błędy znikają (zostałyby nieaktualne); następny plik nie uruchamia go od nowa
            for (auto it = m_docs.begin(); it != m_docs.end(); ++it)
                if (it->server == s->id())
                    m_diagnostics.remove(it.key());
            recount();
            Q_EMIT serversChanged();
        });
        Q_EMIT serversChanged();
        return s;
    }
    return nullptr;
}

QJsonObject Lsp::position(const QString &path, int line, int col)
{
    return QJsonObject{{"textDocument", QJsonObject{{"uri", uri(path)}}}, {"position", QJsonObject{{"line", line}, {"character", col}}}};
}

void Lsp::sendOpen(const QString &path, Doc &doc, LspServer *s)
{
    s->notify(QStringLiteral("textDocument/didOpen"),
              QJsonObject{{"textDocument", QJsonObject{{"uri", uri(path)}, {"languageId", languageId(path)},
                                                       {"version", doc.version}, {"text", doc.text}}}});
    doc.opened = true;
}

void Lsp::open(const QString &path, const QString &text)
{
    LspServer *s = serverForPath(path);
    if (!s)
        return;
    Doc &doc = m_docs[path];
    if (doc.opened)
        return update(path, text);
    doc.server = s->id();
    doc.version = 1;
    doc.text = text;
    doc.hash = qHash(text);
    sendOpen(path, doc, s);
}

void Lsp::update(const QString &path, const QString &text)
{
    auto it = m_docs.find(path);
    if (it == m_docs.end()) {
        open(path, text);
        return;
    }
    const size_t h = qHash(text);
    if (h == it->hash && it->text.size() == text.size())
        return;
    LspServer *s = m_servers.value(it->server);
    if (!s || s->failed())
        return;
    it->hash = h;
    it->text = text;
    ++it->version;
    s->notify(QStringLiteral("textDocument/didChange"),
              QJsonObject{{"textDocument", QJsonObject{{"uri", uri(path)}, {"version", it->version}}},
                          {"contentChanges", QJsonArray{QJsonObject{{"text", text}}}}});
}

void Lsp::saved(const QString &path)
{
    auto it = m_docs.find(path);
    if (it == m_docs.end())
        return;
    if (LspServer *s = m_servers.value(it->server))
        s->notify(QStringLiteral("textDocument/didSave"), QJsonObject{{"textDocument", QJsonObject{{"uri", uri(path)}}}});
}

void Lsp::close(const QString &path)
{
    auto it = m_docs.find(path);
    if (it == m_docs.end())
        return;
    if (LspServer *s = m_servers.value(it->server); s && !s->failed())
        s->notify(QStringLiteral("textDocument/didClose"), QJsonObject{{"textDocument", QJsonObject{{"uri", uri(path)}}}});
    m_docs.erase(it);
    if (m_diagnostics.remove(path))
        recount();
}

int Lsp::complete(const QString &path, int line, int col)
{
    const int seq = ++m_seq;
    auto it = m_docs.find(path);
    LspServer *s = it == m_docs.end() ? nullptr : m_servers.value(it->server);
    if (!s || s->failed())
        return -1;
    QJsonObject params = position(path, line, col);
    params.insert(QStringLiteral("context"), QJsonObject{{"triggerKind", 1}});
    s->request(QStringLiteral("textDocument/completion"), params, [this, seq, path](const QJsonValue &result, const QJsonObject &) {
        const QJsonArray raw = result.isArray() ? result.toArray() : result.toObject().value(QStringLiteral("items")).toArray();
        struct Item { QString sort; QVariantMap map; };
        QList<Item> items;
        for (const QJsonValue &v : raw) {
            const QJsonObject o = v.toObject();
            const QString label = o.value(QStringLiteral("label")).toString().trimmed();
            QString insert = o.value(QStringLiteral("insertText")).toString();
            QVariantMap m{{QStringLiteral("label"), label},
                          {QStringLiteral("detail"), o.value(QStringLiteral("detail")).toString().simplified().left(80)},
                          {QStringLiteral("kind"), o.value(QStringLiteral("kind")).toInt()},
                          {QStringLiteral("filter"), o.value(QStringLiteral("filterText")).toString(label)}};
            // Zakres zamiany z serwera (textEdit albo insert/replace)
            const QJsonObject edit = o.value(QStringLiteral("textEdit")).toObject();
            if (!edit.isEmpty()) {
                insert = edit.value(QStringLiteral("newText")).toString();
                QJsonObject range = edit.value(QStringLiteral("range")).toObject();
                if (range.isEmpty())
                    range = edit.value(QStringLiteral("replace")).toObject();
                const QJsonObject st = range.value(QStringLiteral("start")).toObject(), en = range.value(QStringLiteral("end")).toObject();
                m.insert(QStringLiteral("startLine"), st.value(QStringLiteral("line")).toInt());
                m.insert(QStringLiteral("startCol"), st.value(QStringLiteral("character")).toInt());
                m.insert(QStringLiteral("endLine"), en.value(QStringLiteral("line")).toInt());
                m.insert(QStringLiteral("endCol"), en.value(QStringLiteral("character")).toInt());
            }
            if (insert.isEmpty())
                insert = label;
            if (o.value(QStringLiteral("insertTextFormat")).toInt() == 2)
                insert = stripSnippet(insert);
            m.insert(QStringLiteral("insert"), insert);
            items.append({o.value(QStringLiteral("sortText")).toString(label), m});
            if (items.size() >= 400)
                break;
        }
        std::stable_sort(items.begin(), items.end(), [](const Item &a, const Item &b) { return a.sort < b.sort; });
        QVariantList out;
        for (const Item &i : std::as_const(items))
            out << i.map;
        Q_EMIT completionReady(seq, path, out);
    });
    return seq;
}

int Lsp::definition(const QString &path, int line, int col)
{
    const int seq = ++m_seq;
    auto it = m_docs.find(path);
    LspServer *s = it == m_docs.end() ? nullptr : m_servers.value(it->server);
    if (!s || s->failed())
        return -1;
    s->request(QStringLiteral("textDocument/definition"), position(path, line, col), [this, seq](const QJsonValue &result, const QJsonObject &) {
        // Location, Location[] albo LocationLink[]
        QJsonObject loc = result.isArray() ? result.toArray().first().toObject() : result.toObject();
        QString target = loc.value(QStringLiteral("uri")).toString();
        QJsonObject range = loc.value(QStringLiteral("range")).toObject();
        if (target.isEmpty()) {
            target = loc.value(QStringLiteral("targetUri")).toString();
            range = loc.value(QStringLiteral("targetSelectionRange")).toObject();
        }
        if (target.isEmpty()) {
            Q_EMIT definitionMissing(seq);
            return;
        }
        const QJsonObject st = range.value(QStringLiteral("start")).toObject();
        Q_EMIT definitionReady(seq, pathFromUri(target), st.value(QStringLiteral("line")).toInt(), st.value(QStringLiteral("character")).toInt());
    });
    return seq;
}

int Lsp::hover(const QString &path, int line, int col)
{
    const int seq = ++m_seq;
    auto it = m_docs.find(path);
    LspServer *s = it == m_docs.end() ? nullptr : m_servers.value(it->server);
    if (!s || s->failed())
        return -1;
    s->request(QStringLiteral("textDocument/hover"), position(path, line, col), [this, seq, path](const QJsonValue &result, const QJsonObject &) {
        Q_EMIT hoverReady(seq, path, result.isObject() ? hoverText(result.toObject().value(QStringLiteral("contents"))) : QString());
    });
    return seq;
}

LspServer *Lsp::docServer(const QString &path) const
{
    auto it = m_docs.find(path);
    LspServer *s = it == m_docs.end() ? nullptr : m_servers.value(it->server);
    return s && !s->failed() ? s : nullptr;
}

QString Lsp::relative(const QString &path) const
{
    return m_root.isEmpty() || !path.startsWith(m_root + QLatin1Char('/')) ? path : path.mid(m_root.size() + 1);
}

// Wiersz pliku do podglądu odwołania: z otwartego dokumentu albo z dysku
QString Lsp::lineOf(const QString &path, int line, QHash<QString, QStringList> &cache) const
{
    if (!cache.contains(path)) {
        QString text;
        if (auto it = m_docs.find(path); it != m_docs.end()) {
            text = it->text;
        } else {
            QFile f(path);
            if (f.size() < 8 * 1024 * 1024 && f.open(QIODevice::ReadOnly))
                text = QString::fromUtf8(f.readAll());
        }
        cache.insert(path, text.split(QLatin1Char('\n')));
    }
    const QStringList &lines = cache[path];
    return line >= 0 && line < lines.size() ? lines.at(line) : QString();
}

namespace {

QVariantList textEdits(const QJsonArray &arr)
{
    QVariantList out;
    for (const QJsonValue &v : arr) {
        const QJsonObject e = v.toObject();
        const QJsonObject r = e.value(QStringLiteral("range")).toObject();
        const QJsonObject st = r.value(QStringLiteral("start")).toObject(), en = r.value(QStringLiteral("end")).toObject();
        out << QVariantMap{{QStringLiteral("sl"), st.value(QStringLiteral("line")).toInt()},
                           {QStringLiteral("sc"), st.value(QStringLiteral("character")).toInt()},
                           {QStringLiteral("el"), en.value(QStringLiteral("line")).toInt()},
                           {QStringLiteral("ec"), en.value(QStringLiteral("character")).toInt()},
                           {QStringLiteral("text"), e.value(QStringLiteral("newText")).toString()}};
    }
    return out;
}

} // namespace

int Lsp::rename(const QString &path, int line, int col, const QString &newName)
{
    LspServer *s = docServer(path);
    if (!s)
        return -1;
    const int seq = ++m_seq;
    QJsonObject params = position(path, line, col);
    params.insert(QStringLiteral("newName"), newName);
    s->request(QStringLiteral("textDocument/rename"), params, [this, seq](const QJsonValue &result, const QJsonObject &error) {
        if (!error.isEmpty()) {
            Q_EMIT renameReady(seq, {}, error.value(QStringLiteral("message")).toString());
            return;
        }
        // WorkspaceEdit: „changes” (uri → zmiany) albo „documentChanges” (pomijamy tworzenie i przenoszenie plików)
        QHash<QString, QVariantList> byFile;
        const QJsonObject we = result.toObject();
        const QJsonObject changes = we.value(QStringLiteral("changes")).toObject();
        for (auto it = changes.begin(); it != changes.end(); ++it)
            byFile[pathFromUri(it.key())] += textEdits(it.value().toArray());
        for (const QJsonValue &v : we.value(QStringLiteral("documentChanges")).toArray()) {
            const QJsonObject dc = v.toObject();
            if (!dc.contains(QStringLiteral("edits")))
                continue;
            byFile[pathFromUri(dc.value(QStringLiteral("textDocument")).toObject().value(QStringLiteral("uri")).toString())]
                += textEdits(dc.value(QStringLiteral("edits")).toArray());
        }
        QVariantList files;
        for (auto it = byFile.begin(); it != byFile.end(); ++it)
            files << QVariantMap{{QStringLiteral("path"), it.key()}, {QStringLiteral("edits"), it.value()}};
        Q_EMIT renameReady(seq, files, files.isEmpty() ? QStringLiteral("Tu nie ma nazwy do zmiany") : QString());
    });
    return seq;
}

int Lsp::references(const QString &path, int line, int col)
{
    LspServer *s = docServer(path);
    if (!s)
        return -1;
    const int seq = ++m_seq;
    QJsonObject params = position(path, line, col);
    params.insert(QStringLiteral("context"), QJsonObject{{"includeDeclaration", true}});
    s->request(QStringLiteral("textDocument/references"), params, [this, seq](const QJsonValue &result, const QJsonObject &) {
        QMap<QString, QVariantList> byFile;
        QHash<QString, QStringList> cache;
        int total = 0;
        for (const QJsonValue &v : result.toArray()) {
            const QJsonObject loc = v.toObject();
            const QString p = pathFromUri(loc.value(QStringLiteral("uri")).toString());
            const QJsonObject r = loc.value(QStringLiteral("range")).toObject();
            const QJsonObject st = r.value(QStringLiteral("start")).toObject(), en = r.value(QStringLiteral("end")).toObject();
            const int l = st.value(QStringLiteral("line")).toInt(), c = st.value(QStringLiteral("character")).toInt();
            const int ec = en.value(QStringLiteral("line")).toInt() == l ? en.value(QStringLiteral("character")).toInt() : c;
            byFile[p] << QVariantMap{{QStringLiteral("line"), l}, {QStringLiteral("col"), c}, {QStringLiteral("endCol"), ec},
                                     {QStringLiteral("text"), lineOf(p, l, cache)}};
            ++total;
        }
        QVariantList groups;
        for (auto it = byFile.begin(); it != byFile.end(); ++it) {
            QVariantList items = it.value();
            std::sort(items.begin(), items.end(), [](const QVariant &a, const QVariant &b) {
                return a.toMap().value(QStringLiteral("line")).toInt() < b.toMap().value(QStringLiteral("line")).toInt();
            });
            const QString rel = relative(it.key());
            const int slash = int(rel.lastIndexOf(QLatin1Char('/')));
            groups << QVariantMap{{QStringLiteral("path"), it.key()}, {QStringLiteral("name"), rel.mid(slash + 1)},
                                  {QStringLiteral("dir"), slash > 0 ? rel.left(slash) : QString()}, {QStringLiteral("items"), items}};
        }
        Q_EMIT referencesReady(seq, groups, total);
    });
    return seq;
}

int Lsp::format(const QString &path, int tabSize, bool insertSpaces)
{
    LspServer *s = docServer(path);
    if (!s)
        return -1;
    const int seq = ++m_seq;
    const QJsonObject params{{"textDocument", QJsonObject{{"uri", uri(path)}}},
                             {"options", QJsonObject{{"tabSize", tabSize}, {"insertSpaces", insertSpaces}, {"trimTrailingWhitespace", true}}}};
    s->request(QStringLiteral("textDocument/formatting"), params, [this, seq, path](const QJsonValue &result, const QJsonObject &) {
        Q_EMIT formatReady(seq, path, textEdits(result.toArray()));
    });
    return seq;
}

void Lsp::onNotification(const QString &method, const QJsonObject &params)
{
    if (method == QLatin1String("textDocument/publishDiagnostics")) {
        const QString path = pathFromUri(params.value(QStringLiteral("uri")).toString());
        QVariantList list;
        for (const QJsonValue &v : params.value(QStringLiteral("diagnostics")).toArray()) {
            const QJsonObject d = v.toObject();
            const QJsonObject r = d.value(QStringLiteral("range")).toObject();
            const QJsonObject st = r.value(QStringLiteral("start")).toObject(), en = r.value(QStringLiteral("end")).toObject();
            list << QVariantMap{{QStringLiteral("line"), st.value(QStringLiteral("line")).toInt()},
                                {QStringLiteral("col"), st.value(QStringLiteral("character")).toInt()},
                                {QStringLiteral("endLine"), en.value(QStringLiteral("line")).toInt()},
                                {QStringLiteral("endCol"), en.value(QStringLiteral("character")).toInt()},
                                {QStringLiteral("severity"), d.value(QStringLiteral("severity")).toInt(1)},
                                {QStringLiteral("message"), d.value(QStringLiteral("message")).toString()},
                                {QStringLiteral("source"), d.value(QStringLiteral("source")).toString()}};
        }
        std::stable_sort(list.begin(), list.end(), [](const QVariant &a, const QVariant &b) {
            return a.toMap().value(QStringLiteral("line")).toInt() < b.toMap().value(QStringLiteral("line")).toInt();
        });
        if (list.isEmpty())
            m_diagnostics.remove(path);
        else
            m_diagnostics.insert(path, list);
        recount();
    } else if (method == QLatin1String("window/showMessage")) {
        // Tylko błędy i ostrzeżenia serwera (informacje byłyby natrętne)
        if (params.value(QStringLiteral("type")).toInt() <= 2)
            Q_EMIT message(params.value(QStringLiteral("message")).toString().left(160));
    }
}

void Lsp::recount()
{
    int e = 0, w = 0;
    for (const QVariantList &l : std::as_const(m_diagnostics))
        for (const QVariant &v : l) {
            const int s = v.toMap().value(QStringLiteral("severity")).toInt();
            if (s == 1)
                ++e;
            else if (s == 2)
                ++w;
        }
    m_errors = e;
    m_warnings = w;
    ++m_revision;
    Q_EMIT diagnosticsChanged();
}

QVariantList Lsp::diagnostics(const QString &path) const
{
    return m_diagnostics.value(path);
}

QVariantList Lsp::problems() const
{
    QStringList paths = m_diagnostics.keys();
    std::sort(paths.begin(), paths.end());
    QVariantList out;
    for (const QString &p : std::as_const(paths)) {
        const QString rel = m_root.isEmpty() || !p.startsWith(m_root + QLatin1Char('/')) ? p : p.mid(m_root.size() + 1);
        const int slash = int(rel.lastIndexOf(QLatin1Char('/')));
        out << QVariantMap{{QStringLiteral("path"), p},
                           {QStringLiteral("name"), rel.mid(slash + 1)},
                           {QStringLiteral("dir"), slash > 0 ? rel.left(slash) : QString()},
                           {QStringLiteral("items"), m_diagnostics.value(p)}};
    }
    return out;
}
