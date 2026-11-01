import 'dart:convert';

/// The app chooser on GitHub Pages: a static copy of the bot's /app page
/// (bot AGENTS.md section 45), without the user's subscription. A visitor
/// gets the subscription from the bot; this page is where to find the apps
/// when the bot's own domain does not open.

const nekoSiteBot = 'https://t.me/neko_vpnbot';
const nekoSiteReleases =
    'https://github.com/Annoyt/vpnautodeploy_client/releases';
const nekoSiteSource = 'https://github.com/Annoyt/vpnautodeploy_client';
const _hiddify = 'https://hiddify.com/';
const _flclash = 'https://chen08209.github.io/FlClash/#download';
const _karing = 'https://karing.app/';

/// The APK builds a release carries; the first is what nearly every phone
/// takes.
const nekoSiteAbis = ['arm64-v8a', 'armeabi-v7a', 'x86_64'];

final _nekoTag = RegExp(r'^v\d+\.\d+\.\d+-neko\.\d+$');

typedef NekoSiteRelease = ({
  String tag,
  Map<String, ({String url, int size})> apks,
});

/// The newest published NekoVPN release with an APK for the common ABI,
/// from GitHub's release list (newest first): drafts and other tags are
/// skipped, pre-releases taken (every NekoVPN build is one so far).
NekoSiteRelease? nekoSiteLatest(Object? releases) {
  if (releases is! List) return null;
  for (final release in releases) {
    if (release is! Map || release['draft'] == true) continue;
    final tag = release['tag_name'];
    if (tag is! String || !_nekoTag.hasMatch(tag)) continue;
    final apks = <String, ({String url, int size})>{};
    for (final asset in (release['assets'] as List?) ?? const []) {
      if (asset is! Map) continue;
      final name = asset['name'];
      final url = asset['browser_download_url'];
      if (name is! String || url is! String) continue;
      for (final abi in nekoSiteAbis) {
        if (name.endsWith('-android-$abi.apk')) {
          final size = asset['size'];
          apks[abi] = (url: url, size: size is int ? size : 0);
        }
      }
    }
    if (apks.containsKey(nekoSiteAbis.first)) return (tag: tag, apks: apks);
  }
  return null;
}

/// Opens the visitor's own platform; without a script the Android section
/// is open.
const nekoSiteScript =
    '(function(){var u=navigator.userAgent;'
    'var id=/Android/.test(u)?"android":/iPhone|iPad|iPod/.test(u)?"ios":'
    '"desktop";var all=document.querySelectorAll("details[id]");'
    'for(var i=0;i<all.length;i++){all[i].open=all[i].id===id;}})();';

String nekoSitePage(NekoSiteRelease? release) {
  // & < > " like the bot's html.escape; the default mode also turns every
  // slash of a link into &#47;.
  const e = HtmlEscape(HtmlEscapeMode.attribute);
  String button(String href, String text) =>
      '<a class="btn" href="${e.convert(href)}">${e.convert(text)}</a>';
  String app(
    String name,
    String about,
    String download, {
    String label = 'Скачать',
    bool recommended = false,
    String extra = '',
  }) {
    final badge = recommended ? ' <span class="rec">рекомендуем</span>' : '';
    return '<div class="app"><h3>${e.convert(name)}$badge</h3>'
        '<p>${e.convert(about)}</p>'
        '<div class="row">${button(download, label)}</div>$extra</div>';
  }

  String neko;
  if (release == null) {
    neko = app(
      'NekoVPN',
      _nekoAbout,
      nekoSiteReleases,
      label: 'Скачать NekoVPN',
      recommended: true,
    );
  } else {
    final common = release.apks[nekoSiteAbis.first]!;
    final version = release.tag.substring(1);
    final megabytes = (common.size / 1048576).round();
    final others = [
      for (final abi in nekoSiteAbis.skip(1))
        if (release.apks[abi] case final apk?)
          '<a href="${e.convert(apk.url)}">${e.convert(abi)}</a>',
    ];
    neko = app(
      'NekoVPN',
      _nekoAbout,
      common.url,
      label: 'Скачать NekoVPN',
      recommended: true,
      extra:
          '<p class="small">Версия ${e.convert(version)} · $megabytes МБ</p>'
          '<p class="small">${e.convert(_steps)}</p>'
          '${others.isEmpty ? '' : '<p class="small">Не устанавливается? Другие сборки: ${others.join(' · ')}</p>'}',
    );
  }

  String section(String id, String title, List<String> apps) =>
      '<details id="$id"${id == 'android' ? ' open' : ''}>'
      '<summary>${e.convert(title)}</summary>${apps.join()}</details>';

  final body = [
    '<h1>🐱 NekoVPN</h1>',
    '<p class="lead">Выберите приложение. Подписка одна, подходит ко всем.</p>',
    section('android', 'Android', [
      neko,
      app('Hiddify', _hiddifyAbout, _hiddify),
      app('FlClash', _flclashAbout, _flclash),
    ]),
    section('ios', 'iPhone и iPad', [app('Karing', _karingAbout, _karing)]),
    section('desktop', 'Компьютер: Windows, macOS, Linux', [
      app('FlClash', _flclashPcAbout, _flclash, recommended: true),
      app('Hiddify', _hiddifyAbout, _hiddify),
    ]),
    _botHint,
    _demoLine,
    _footer,
  ].join('\n');
  return '''<!doctype html>
<html lang="ru">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>NekoVPN — приложения</title>
<style>
body{font-family:system-ui,sans-serif;margin:0;background:#fafafa;color:#222}
main{max-width:480px;margin:0 auto;padding:28px 16px}
h1{font-size:28px;margin:8px 0 8px;text-align:center}
.lead{text-align:center;font-size:16px;color:#444}
details{background:#fff;border-radius:14px;margin:14px 0;padding:4px 14px;
box-shadow:0 1px 3px rgba(0,0,0,.08)}
summary{font-size:18px;font-weight:600;padding:12px 0;cursor:pointer}
.app{border-top:1px solid #eee;padding:12px 0}
.app h3{margin:0 0 4px;font-size:17px}
.app p{margin:4px 0 8px;font-size:15px;color:#444}
.rec{font-size:12px;font-weight:600;color:#fff;background:#f57c1f;border-radius:8px;
padding:2px 8px;vertical-align:middle}
.row{display:flex;gap:8px;flex-wrap:wrap}
.btn{display:inline-block;padding:11px 16px;border-radius:12px;background:#f57c1f;
color:#fff;font-weight:600;text-decoration:none;font-size:15px}
.small{font-size:14px;color:#555}
.foot{margin-top:24px;text-align:center}
</style>
</head>
<body>
<main>
$body
</main>
<script>$nekoSiteScript</script>
</body>
</html>
''';
}

/// Mirrors the bot's texts (bot/services/neko_client.py, _CHOOSER_TEXTS).
const _nekoAbout =
    'Наше приложение: в демо 10 ГБ в месяц вместо 5, карточка трафика, '
    'шлюз для соседа, кнопка «Не подключается».';
const _steps =
    'Откройте скачанный файл. Android спросит, можно ли браузеру '
    'устанавливать приложения, — разрешите.';
const _hiddifyAbout =
    'Проще всего: обычное приложение. Наши правила маршрутизации не '
    'применяет.';
const _flclashAbout =
    'Применяет наши правила полностью: звонки, YouTube через VPN, российские '
    'сайты напрямую. С официального сайта, в Google Play его нет.';
const _flclashPcAbout =
    'Рекомендуем для компьютера: применяет наши правила полностью.';
const _karingAbout =
    'Для iPhone и iPad, из App Store. NekoVPN для iPhone пока нет.';
const _botHint =
    '<p class="small">Подписку возьмите в боте '
    '<a href="$nekoSiteBot">@neko_vpnbot</a>: команда /sub. Там же кнопка, '
    'которая добавляет её в приложение одним касанием.</p>';
const _demoLine =
    '<p class="small">Демо в NekoVPN — 10 ГБ в месяц, в других приложениях — '
    '5 ГБ.</p>';
const _footer =
    '<p class="small foot">NekoVPN — изменённая версия FlClash (GPL-3.0). '
    '<a href="$nekoSiteSource">Исходники</a></p>';

/// The page for a release list as GitHub's API returns it.
String nekoSitePageFromJson(String releasesJson) {
  return nekoSitePage(nekoSiteLatest(jsonDecode(releasesJson)));
}
