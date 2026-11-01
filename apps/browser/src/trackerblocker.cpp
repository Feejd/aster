#include "trackerblocker.h"

#include <QMetaObject>
#include <QUrl>

// Najczęstsze serwery reklam i śledzenia w Polsce i na świecie (domena obejmuje też poddomeny)
static const char *const trackers[] = {
    // Google
    "doubleclick.net", "googlesyndication.com", "googleadservices.com", "google-analytics.com",
    "googletagservices.com", "adservice.google.com", "pagead2.googlesyndication.com", "imasdk.googleapis.com",
    // Meta, X, LinkedIn, TikTok, Microsoft, Pinterest, Snap
    "connect.facebook.net", "pixel.facebook.com", "an.facebook.com", "ads-twitter.com", "static.ads-twitter.com",
    "analytics.twitter.com", "ads.linkedin.com", "px.ads.linkedin.com", "snap.licdn.com", "analytics.tiktok.com",
    "ads.tiktok.com", "bat.bing.com", "clarity.ms", "ct.pinterest.com", "tr.snapchat.com",
    // Sieci reklamowe
    "adnxs.com", "criteo.com", "criteo.net", "taboola.com", "outbrain.com", "amazon-adsystem.com", "adsrvr.org",
    "rubiconproject.com", "pubmatic.com", "openx.net", "casalemedia.com", "moatads.com", "adform.net",
    "smartadserver.com", "teads.tv", "bidswitch.net", "3lift.com", "sharethrough.com", "yieldmo.com",
    "media.net", "contextweb.com", "indexww.com", "adsafeprotected.com", "doubleverify.com", "quantserve.com",
    "scorecardresearch.com", "zemanta.com", "mgid.com", "revcontent.com", "adroll.com", "bluekai.com",
    "demdex.net", "everesttech.net", "rlcdn.com", "krxd.net", "exelator.com", "tapad.com", "agkn.com",
    "lijit.com", "sovrn.com", "33across.com", "gumgum.com", "undertone.com", "spotxchange.com", "springserve.com",
    "smaato.net", "inmobi.com", "adcolony.com", "unityads.unity3d.com", "applovin.com",
    // Analityka i nagrywanie sesji
    "hotjar.com", "hotjar.io", "mouseflow.com", "fullstory.com", "luckyorange.com", "crazyegg.com",
    "chartbeat.com", "chartbeat.net", "mc.yandex.ru", "top-fwz1.mail.ru", "omtrdc.net", "2o7.net",
    "segment.io", "kissmetrics.com", "mixpanel.com", "amplitude.com", "heapanalytics.com", "newrelic.com",
    "nr-data.net", "branch.io", "app-measurement.com", "adjust.com", "appsflyer.com", "kochava.com",
    // Polska
    "gemius.pl", "gemius.com", "hit.gemius.pl", "adocean.pl", "adocean-global.com",
    "dot.wp.pl", "rubiconproject.pl", "ad.onet.pl", "csr.onet.pl", "pixel.wp.pl", "adtraction.com",
    "salesmanago.pl", "salesmanago.com", "trafficstars.com", "exoclick.com",
};

TrackerBlocker::TrackerBlocker(QObject *parent)
    : QWebEngineUrlRequestInterceptor(parent)
{
    for (const char *h : trackers)
        m_hosts.insert(QString::fromLatin1(h));
}

QString TrackerBlocker::siteOf(const QString &host)
{
    const QStringList parts = host.split(QLatin1Char('.'), Qt::SkipEmptyParts);
    if (parts.size() <= 2)
        return host;
    // Drugi poziom z krótkim członem (co.uk, com.pl, gov.pl) — bierzemy trzy człony
    const QString second = parts.at(parts.size() - 2);
    const bool shortSecond = second.size() <= 3 && (second == QLatin1String("co") || second == QLatin1String("com") || second == QLatin1String("org")
                                                     || second == QLatin1String("net") || second == QLatin1String("gov") || second == QLatin1String("edu")
                                                     || second == QLatin1String("ac"));
    return parts.mid(parts.size() - (shortSecond ? 3 : 2)).join(QLatin1Char('.'));
}

bool TrackerBlocker::listed(const QString &host) const
{
    // host i każda domena nad nim: a.b.example.com → b.example.com → example.com
    QString h = host;
    while (true) {
        if (m_hosts.contains(h))
            return true;
        const int dot = h.indexOf(QLatin1Char('.'));
        if (dot < 0 || h.indexOf(QLatin1Char('.'), dot + 1) < 0)
            return false;
        h = h.mid(dot + 1);
    }
}

void TrackerBlocker::interceptRequest(QWebEngineUrlRequestInfo &info)
{
    if (!m_enabled || info.resourceType() == QWebEngineUrlRequestInfo::ResourceTypeMainFrame
        || info.navigationType() == QWebEngineUrlRequestInfo::NavigationTypeTyped)
        return;
    const QString host = info.requestUrl().host().toLower();
    const QString page = info.firstPartyUrl().host().toLower();
    if (host.isEmpty() || page.isEmpty() || siteOf(host) == siteOf(page))
        return;
    if (!listed(host))
        return;
    info.block(true);
    const QString site = siteOf(page);
    QMetaObject::invokeMethod(this, [this, site] { Q_EMIT blocked(site); }, Qt::QueuedConnection);
}
