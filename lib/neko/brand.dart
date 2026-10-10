import 'package:intl/intl.dart';

const nekoBotUrl = 'https://t.me/neko_vpnbot';
const nekoUpstreamRepository = 'chen08209/FlClash';

/// GPL-3.0 section 5(a): a modified work carries a notice with the date.
const nekoModifiedOn = '2026-10-10';

/// Texts that name the fork live here, not in `arb/`: upstream rewrites its
/// translations often, and every one of those merges would conflict.
bool get _isRu => Intl.getCurrentLocale().startsWith('ru');

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
    'NekoVPN не содержит сервисов статистики и отчётов о сбоях ни на одной '
    'платформе: Firebase, который есть в Android-версии FlClash, из этой '
    'сборки удалён.';

const _privacyEn =
    'The Software does not collect or upload your subscription URLs, node '
    'details, configuration content, visited websites, connection records, '
    'traffic content, or logs. This data stays on your device.\n\n'
    'The Software only reaches the network when you use a feature that needs '
    'it: fetching the subscription URL you provided when updating a profile, '
    'and contacting GitHub when checking for updates.\n\n'
    'NekoVPN includes no analytics or crash reporting service on any '
    'platform: the Google Firebase services of the FlClash Android build are '
    'removed from this one.';
