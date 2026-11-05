#include "providers.h"

#include <QHostAddress>
#include <QUrl>

QVariantMap Provider::toMap() const
{
    return {{QStringLiteral("id"), id},
            {QStringLiteral("name"), name},
            {QStringLiteral("kind"), kind == Anthropic ? QStringLiteral("anthropic") : QStringLiteral("openai")},
            {QStringLiteral("baseUrl"), baseUrl},
            {QStringLiteral("defaultModel"), defaultModel},
            {QStringLiteral("models"), models},
            {QStringLiteral("region"), region},
            {QStringLiteral("needsKey"), needsKey},
            {QStringLiteral("editableUrl"), editableUrl},
            {QStringLiteral("keyUrl"), keyUrl}};
}

const QList<Provider> &Catalog::all()
{
    static const QList<Provider> list{
        // Na tym komputerze: llama.cpp (llama-server) albo Ollama — nic nie wychodzi z komputera
        {QStringLiteral("lokalny"), QStringLiteral("Model lokalny (llama.cpp)"), Provider::OpenAI,
         QStringLiteral("http://127.0.0.1:8080/v1"), QStringLiteral("lokalny"), {}, QString(), false, true, QString()},
        {QStringLiteral("ollama"), QStringLiteral("Ollama"), Provider::OpenAI,
         QStringLiteral("http://127.0.0.1:11434/v1"), QStringLiteral("qwen3:4b"),
         {QStringLiteral("qwen3:4b"), QStringLiteral("llama3.2:3b"), QStringLiteral("gemma3:4b")}, QString(), false, true, QString()},
        // Chmura
        {QStringLiteral("mistral"), QStringLiteral("Mistral"), Provider::OpenAI,
         QStringLiteral("https://api.mistral.ai/v1"), QStringLiteral("mistral-small-latest"),
         {QStringLiteral("mistral-small-latest"), QStringLiteral("mistral-medium-latest"), QStringLiteral("mistral-large-latest")},
         QStringLiteral("UE (Francja)"), true, false, QStringLiteral("https://console.mistral.ai/api-keys")},
        {QStringLiteral("deepseek"), QStringLiteral("DeepSeek"), Provider::OpenAI,
         QStringLiteral("https://api.deepseek.com/v1"), QStringLiteral("deepseek-chat"),
         {QStringLiteral("deepseek-chat"), QStringLiteral("deepseek-reasoner")},
         QStringLiteral("Chiny"), true, false, QStringLiteral("https://platform.deepseek.com/api_keys")},
        {QStringLiteral("openai"), QStringLiteral("OpenAI"), Provider::OpenAI,
         QStringLiteral("https://api.openai.com/v1"), QStringLiteral("gpt-5-mini"),
         {QStringLiteral("gpt-5-mini"), QStringLiteral("gpt-5"), QStringLiteral("gpt-4.1-mini")},
         QStringLiteral("USA"), true, false, QStringLiteral("https://platform.openai.com/api-keys")},
        {QStringLiteral("anthropic"), QStringLiteral("Claude (Anthropic)"), Provider::Anthropic,
         QStringLiteral("https://api.anthropic.com/v1"), QStringLiteral("claude-haiku-5-5"),
         {QStringLiteral("claude-haiku-5-5"), QStringLiteral("claude-sonnet-5-5"), QStringLiteral("claude-opus-5-5")},
         QStringLiteral("USA"), true, false, QStringLiteral("https://console.anthropic.com/settings/keys")},
        {QStringLiteral("gemini"), QStringLiteral("Gemini (Google)"), Provider::OpenAI,
         QStringLiteral("https://generativelanguage.googleapis.com/v1beta/openai"), QStringLiteral("gemini-2.5-flash"),
         {QStringLiteral("gemini-2.5-flash"), QStringLiteral("gemini-2.5-pro")},
         QStringLiteral("USA"), true, false, QStringLiteral("https://aistudio.google.com/apikey")},
        {QStringLiteral("openrouter"), QStringLiteral("OpenRouter"), Provider::OpenAI,
         QStringLiteral("https://openrouter.ai/api/v1"), QStringLiteral("openrouter/auto"),
         {QStringLiteral("openrouter/auto")},
         QStringLiteral("USA (dalej — serwery wybranego modelu)"), true, false, QStringLiteral("https://openrouter.ai/keys")},
    };
    return list;
}

Provider Catalog::find(const QString &id)
{
    for (const Provider &p : all())
        if (p.id == id)
            return p;
    return {};
}

bool Catalog::isLoopback(const QString &url)
{
    const QString host = QUrl(url).host();
    if (host.compare(QLatin1String("localhost"), Qt::CaseInsensitive) == 0 || host.endsWith(QLatin1String(".localhost")))
        return true;
    const QHostAddress a(host);
    return !a.isNull() && a.isLoopback();
}
