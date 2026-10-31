import 'package:intl/intl.dart';

const nekoBotUrl = 'https://t.me/neko_vpnbot';
const nekoUpstreamRepository = 'chen08209/FlClash';

/// GPL-3.0 section 5(a): a modified work carries a notice with the date.
const nekoModifiedOn = '2026-10-10';

/// Texts that name the fork live here, not in `arb/`: upstream rewrites its
/// translations often, and every one of those merges would conflict.
bool get _isRu => Intl.getCurrentLocale().startsWith('ru');

String get nekoUpdateTitle => _isRu ? _updateTitleRu : _updateTitleEn;

String get nekoUpdateText => _isRu ? _updateTextRu : _updateTextEn;

String get nekoOpenLink => _isRu ? 'Открыть' : 'Open';

String get nekoSosTitle => _isRu ? 'Не подключается' : 'Cannot connect';

String get nekoMultipathTitle =>
    _isRu ? 'Две сети сразу' : 'Two networks at once';

String get nekoMultipathOff => _isRu ? 'Выключено' : 'Off';

String get nekoMultipathFailover => _isRu ? 'Резерв' : 'Backup';

String get nekoMultipathDistribute =>
    _isRu ? 'Сложить скорость' : 'Combine speed';

String get nekoMultipathFooter => _isRu ? _multipathRu : _multipathEn;

const _multipathRu =
    'Wi-Fi и мобильный интернет вместе. «Резерв»: если в Wi-Fi пропал '
    'интернет, соединения сразу идут через мобильный. «Сложить скорость»: '
    'соединения раскладываются по обеим сетям. Второй телефон с другим '
    'оператором: включите на нём точку доступа и подключитесь к ней, а '
    'мобильный интернет здесь оставьте включённым. Тратит мобильный трафик '
    'и заряд.';

const _multipathEn =
    'Wi-Fi and mobile data together. Backup: when the Wi-Fi loses the '
    'internet, connections move to mobile data at once. Combine speed: '
    'connections are spread over both networks. A second phone on another '
    'carrier: turn on its hotspot, join it, and keep mobile data on here. '
    'Uses mobile data and battery.';

String get nekoSosSubtitle => _isRu ? _sosSubtitleRu : _sosSubtitleEn;

String get nekoSosIntro => _isRu ? _sosIntroRu : _sosIntroEn;

String get nekoSosSend => _isRu ? 'Отправить SOS' : 'Send SOS';

String get nekoSosReported => _isRu ? _sosReportedRu : _sosReportedEn;

String get nekoSosRepeat => _isRu ? _sosRepeatRu : _sosRepeatEn;

String get nekoSosEmergency => _isRu ? _sosEmergencyRu : _sosEmergencyEn;

String get nekoSosEmergencyHint => _isRu ? _sosHintRu : _sosHintEn;

String get nekoSosFailed => _isRu ? _sosFailedRu : _sosFailedEn;

String get nekoSosNoProfile => _isRu ? _sosNoProfileRu : _sosNoProfileEn;

String get nekoSosBot => _isRu ? 'Написать боту' : 'Message the bot';

String get nekoSosCopy => _isRu ? 'Скопировать отчёт' : 'Copy the report';

String get nekoSosCopied => _isRu ? 'Отчёт скопирован' : 'Report copied';

const _sosSubtitleRu = 'Сообщить в поддержку и узнать, что работает';

const _sosSubtitleEn = 'Tell support and see what works';

const _sosIntroRu =
    'Отправим в поддержку то, что видит приложение, и покажем, что у '
    'сервиса работает прямо сейчас.';

const _sosIntroEn =
    'We send support what the app sees and show what works on our side '
    'right now.';

const _sosReportedRu = 'Поддержка получила сообщение. Сейчас у сервиса:';

const _sosReportedEn = 'Support got your message. Right now:';

const _sosRepeatRu = 'Сообщение уже отправлено недавно. Сейчас у сервиса:';

const _sosRepeatEn = 'You sent one a few minutes ago. Right now:';

const _sosEmergencyRu = 'Добавить аварийный профиль';

const _sosEmergencyEn = 'Add the emergency profile';

const _sosHintRu = 'Серверы через CDN первыми, DNS через туннель';

const _sosHintEn = 'CDN servers first, DNS through the tunnel';

const _sosFailedRu =
    'Не удалось связаться с сервисом. Напишите боту или скопируйте отчёт и '
    'отправьте его любым способом.';

const _sosFailedEn =
    'Could not reach the service. Message the bot, or copy the report and '
    'send it any way you can.';

const _sosNoProfileRu =
    'В приложении нет подписки NekoVPN. Добавьте её кнопкой «Открыть в '
    'NekoVPN» в боте.';

const _sosNoProfileEn =
    'There is no NekoVPN subscription in the app. Add it with the «Open in '
    'NekoVPN» button in the bot.';

const _updateTitleRu = 'Нужно обновить NekoVPN';

const _updateTitleEn = 'Please update NekoVPN';

const _updateTextRu =
    'Эта версия NekoVPN устарела и может перестать подключаться. Скачайте '
    'новую и установите поверх: профили и настройки сохранятся.';

const _updateTextEn =
    'This version of NekoVPN is outdated and may stop connecting. Download '
    'the new one and install it over this one: profiles and settings stay.';

/// An upstream text about the app that names FlClash, naming NekoVPN.
String nekoBranded(String text) => text.replaceAll('FlClash', 'NekoVPN');

String get nekoBasedOnTitle => _isRu ? 'На основе FlClash' : 'Based on FlClash';

String get nekoDescription => _isRu ? _descriptionRu : _descriptionEn;

String get nekoDisclaimerDesc => _isRu ? _disclaimerDescRu : _disclaimerDescEn;

String get nekoPrivacyContent => _isRu ? _privacyRu : _privacyEn;

const _descriptionRu =
    'Клиент сервиса NekoVPN. Изменённая версия FlClash, изменения от '
    '$nekoModifiedOn. Лицензия GPL-3.0, исходный код открыт.';

const _descriptionEn =
    'The NekoVPN client. A modified version of FlClash, changed on '
    '$nekoModifiedOn. Licensed under GPL-3.0, the source code is open.';

const _disclaimerDescRu =
    'Перед использованием NekoVPN, изменённой версии FlClash (далее — '
    '«Программа»), внимательно прочитайте это заявление и убедитесь, что '
    'понимаете его полностью. Нажимая «Согласен», вы подтверждаете, что '
    'прочитали, поняли и принимаете все приведённые ниже условия. Если вы не '
    'согласны, нажмите «Выход» и прекратите использование Программы.';

const _disclaimerDescEn =
    'Before using NekoVPN, a modified version of FlClash ("the Software"), '
    'please read this statement carefully and make sure you understand all of '
    'it. Tapping "Agree" means you have read, understood, and accept every '
    'term below. If you do not agree, tap "Exit" and stop using the Software.';

const _privacyRu =
    'Программа не собирает и не отправляет адреса ваших подписок, сведения об '
    'узлах, содержимое конфигураций, посещённые сайты, записи о подключениях, '
    'содержимое трафика и журналы. Эти данные хранятся только на вашем '
    'устройстве.\n\n'
    'Программа обращается к сети только при использовании соответствующих '
    'функций: загружает указанный вами адрес подписки при обновлении профиля '
    'и обращается к GitHub при проверке обновлений.\n\n'
    'NekoVPN не содержит сервисов статистики и отчётов о сбоях. QR-коды '
    'распознаются на устройстве открытой библиотекой zxing-cpp, без '
    'сервисов Google.';

const _privacyEn =
    'The Software does not collect or upload your subscription URLs, node '
    'details, configuration content, visited websites, connection records, '
    'traffic content, or logs. This data stays on your device.\n\n'
    'The Software only reaches the network when you use a feature that needs '
    'it: fetching the subscription URL you provided when updating a profile, '
    'and contacting GitHub when checking for updates.\n\n'
    'NekoVPN includes no analytics or crash reporting service. QR codes are '
    'read on the device by the open-source zxing-cpp library, with no Google '
    'service.';

String get nekoGatewayTitle =>
    _isRu ? 'Шлюз для соседа' : 'Gateway for a neighbour';

String get nekoGatewaySubtitle => _isRu
    ? 'Раздать свой интернет или выйти через соседний телефон'
    : 'Share your network or go out through a nearby phone';

String get nekoGatewayIntro => _isRu ? _gatewayIntroRu : _gatewayIntroEn;

const _gatewayIntroRu =
    'Телефон без своего интернета может выходить через этот: по общему '
    'Wi-Fi или через точку доступа этого телефона. VPN у каждого свой, со '
    'своим ключом. Этот телефон передаёт зашифрованные соединения соседа и '
    'не видит, что внутри. Российские сайты сосед открывает через интернет '
    'этого телефона напрямую.';

const _gatewayIntroEn =
    'A phone without internet of its own can go out through this one, over '
    'a shared Wi-Fi or this phone\'s hotspot. Each phone keeps its own VPN '
    'and key. This phone carries the neighbour\'s encrypted connections and '
    'does not see inside them. The neighbour opens Russian sites directly '
    'through this phone\'s internet.';

String get nekoGatewayShareSection =>
    _isRu ? 'Этот телефон раздаёт' : 'This phone shares';

String get nekoGatewayShare =>
    _isRu ? 'Раздавать соседу' : 'Share with a neighbour';

String get nekoGatewayShareSubtitle => _isRu
    ? 'Работает, пока включён VPN. Тратит трафик и заряд этого телефона.'
    : 'Works while the VPN is on. Uses this phone\'s data and battery.';

String get nekoGatewayShareHint => _isRu
    ? 'На втором телефоне: NekoVPN → Инструменты → Шлюз для соседа → '
          'Подключиться, и наведите камеру на код.'
    : 'On the other phone: NekoVPN → Tools → Gateway for a neighbour → '
          'Connect, and point the camera at the code.';

String get nekoGatewayNoNetwork => _isRu
    ? 'Нет сети, к которой может подключиться сосед: включите точку доступа '
          'или подключитесь к Wi-Fi.'
    : 'No network a neighbour can join: turn on the hotspot or join a Wi-Fi.';

String get nekoGatewayJoinSection => _isRu
    ? 'Этот телефон выходит через соседа'
    : 'This phone goes out '
          'through a neighbour';

String get nekoGatewayScan => _isRu ? 'Подключиться' : 'Connect';

String get nekoGatewayScanSubtitle => _isRu
    ? 'Отсканируйте код на телефоне, который раздаёт'
    : 'Scan the code on the sharing phone';

String get nekoGatewayJoined => _isRu
    ? 'Весь интернет этого телефона идёт через соседа'
    : 'All of this phone\'s traffic goes through the neighbour';

String get nekoGatewayLeave => _isRu ? 'Отключиться' : 'Disconnect';

String get nekoGatewayInvalidCode =>
    _isRu ? 'Это не код шлюза NekoVPN' : 'Not a NekoVPN gateway code';
