#include "plugin.h"


namespace Plug {

QList<Info> scanFile(const QString &path)
{
    return path.endsWith(QLatin1String(".clap")) ? Clap::scanFile(path) : Vst3::scanFile(path);
}

std::unique_ptr<Plugin> loadLocal(const Info &info, double rate, int maxBlock, QString *error)
{
    return info.format == QLatin1String("clap") ? Clap::load(info, rate, maxBlock, error) : Vst3::load(info, rate, maxBlock, error);
}

}
