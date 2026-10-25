# Изменения NekoVPN относительно FlClash

Этот репозиторий — изменённая версия [FlClash](https://github.com/chen08209/FlClash)
(GPL-3.0). Здесь перечислены только наши изменения, с датами (GPL-3.0, §5a).
Журнал апстрима — [CHANGELOG.md](CHANGELOG.md).

Пункты каждой версии — это «Что нового» для пользователей: их показывают
окно обновления в приложении, страница релиза и сообщение бота при
публикации. Пишем их понятным языком; технические подробности — в
подразделе «Для разработчиков», он в «Что нового» не попадает.

## 0.9.2-neko.1 — 2026-10-25

На основе апстрима FlClash v0.9.2.

- **Свежий FlClash и новое ядро.** Внутри ядро mihomo 1.19.33 и всё, что
  вышло в FlClash 0.9.0–0.9.2. Открытие приложения больше не перезапускает
  работающий VPN.
- **Новый интерфейс.** Обновлённая главная, группы серверов карточками,
  более контрастная тёмная тема.
- **Ярлыки на значке.** Долгое нажатие на иконку NekoVPN включает или
  выключает VPN, не открывая приложение.
- **QR-код профиля.** Профиль можно показать QR-кодом и добавить на другом
  устройстве.
- **Подписка в одно касание.** У ключа в боте появилась кнопка «📲 Открыть в
  NekoVPN»: приложение откроется и предложит добавить подписку.
- **Подписка обновляется чаще.** Приложение обновляет профиль так часто,
  как просит сервер: у NekoVPN — каждые 6 часов, а не раз в сутки. Новые
  серверы и обходы блокировок доходят до вас в тот же день.
- **Обновления находятся надёжнее.** Даже когда GitHub ограничивает запросы
  с вашего адреса (так бывает в мобильных сетях), приложение узнает о новой
  версии.

### Для разработчиков

Слит апстрим v0.9.2 (`docs/PLAN.md`, раздел 7). Апстрим теперь собирает
Android-ядро через gomobile (Go 1.27 вместо JNI на C++) и встраивает в ядро
набор CA-сертификатов, закреплённый по хэшу. `neko-release.yaml` больше не
держит своих версий Flutter, Go и NDK: их и набор сертификатов читает из
`build.yaml` апстрима, шаг загрузки сертификатов — дословная копия
апстримного, кэши в сборке релиза выключены, как у апстрима. Релиз не
соберётся, пока у FlClash есть релиз новее нашей базы
(`tool/neko/upstream_base.sh`), а `neko-upstream-watch.yaml` раз в сутки
заводит issue о новом релизе апстрима. `test/neko/release_workflow_test.dart`
падает, если в сборке релиза апстрима появился, пропал или переименован шаг.
Проверка обновлений сохраняет семантику апстрима (ошибка, а не «обновлений
нет», когда GitHub не ответил) и при исчерпанной квоте API читает ленту
`releases.atom` — только записи, названные как наш релиз. Тексты апстрима,
где приложение называет себя FlClash, показываются через `nekoBranded`;
`test/neko/brand_test.dart` найдёт новые. Цвета ярлыков и фона иконки — наши.
Заголовок подписки `profile-update-interval` (часы) задаёт интервал
автообновления профиля при каждой загрузке (`lib/neko/profile_update.dart`,
от часа до недели; без заголовка интервал профиля не меняется).

### Изменённые файлы апстрима

`lib/common/request.dart` (наш канал обновлений поверх новой проверки
апстрима), `lib/models/profile.dart` (интервал из заголовка подписки),
`lib/pages/error.dart`, `lib/views/profiles/add.dart`,
`lib/views/profiles/profiles.dart` (тексты с именем NekoVPN),
`lib/views/about.dart`, `lib/views/disclaimer.dart` (наши тексты перенесены
в переписанные апстримом экраны),
`android/app/src/main/res/values/colors.xml`,
`android/app/src/main/res/values/ic_launcher_background.xml`, `pubspec.yaml`.

## 0.8.99-neko.2 — 2026-10-15

На основе апстрима v0.8.99, как и предыдущая.

- **Обновления только от NekoVPN.** Приложение больше не смотрит на релизы
  FlClash: новые версии приходят только от нас.
- **Новые версии приложение предложит само.** Проверка обновлений при
  запуске и кнопка «Проверить обновления» в «О программе» теперь видят и
  тестовые сборки.
- **Понятное окно обновления.** В нём виден список изменений, а «Скачать»
  открывает именно эту версию.

### Для разработчиков

Проверка обновлений унаследована от FlClash и читала `/releases/latest`,
который пропускает пре-релизы, а все наши тестовые сборки выходят ими.
Теперь `lib/neko/update.dart` читает список релизов этого репозитория и
берёт только теги `v…-neko.N`; сборки с `APP_ENV=pre` видят пре-релизы,
стабильные — нет, черновики не видны никому. «Скачать» открывает найденный
релиз (`nekoReleasePageUrl`). Текст окна — пункты версии из этого журнала:
`tool/neko/release_notes.dart` кладёт их между маркерами, которые читает
окно, а `neko-release.yaml` не соберёт релиз без раздела в журнале.
`test/neko/upstream_isolation_test.dart` падает, если после слияния с
апстримом задачи публикации FlClash (релиз, сайт, Telegram, Homebrew,
F-Droid) смогут запуститься в этом репозитории.

### Изменённые файлы апстрима

`lib/common/request.dart` (проверка обновлений через `lib/neko/update.dart`),
`lib/providers/action.dart`, `lib/providers/actions/common.dart` (кнопка
«Скачать»), `pubspec.yaml`.

## 0.8.99-neko.1 — 2026-10-10

На основе апстрима v0.8.99 (`main` на 2026-10-10).

- **Имя, пакет, иконка.** Приложение называется NekoVPN, Android-пакет
  `com.nekovpn.client`, своя иконка (`tool/neko/icons.py` генерирует все
  размеры). Ставится рядом с FlClash и поверх него не обновляется.
- **Без Firebase.** Удалены Crashlytics и Analytics: Gradle-плагины и
  зависимости, `google-services.json`, вызовы в `GlobalState.kt`, переключатель
  «Аналитика сбоев», окно о сборе данных при запуске и раздел о Firebase в
  соглашении. Остаётся Google ML Kit в сканере QR-кодов (`mobile_scanner` из
  апстрима): он тянет служебные части Firebase и по условиям Google может
  отправлять Google метрики работы сканера; об этом сказано в соглашении,
  замена — задача E36 в `docs/PLAN.md`.
- **Обновления — из этого репозитория.** Проверка обновлений смотрит релизы
  `Annoyt/vpnautodeploy_client`; версии вида `0.8.99-neko.N` сравнивает
  `lib/neko/version.dart`.
- **Ссылки.** Схема `nekovpn://install-config?url=…` вместо `flclash://`
  (`clash://` и `clashmeta://` остаются); на Linux обработчик называется
  `nekovpn-url-handler.desktop`.
- **«О программе» и соглашение.** Пометка «изменённая версия FlClash» с датой,
  ссылки на исходники форка и на FlClash, Telegram ведёт в бота сервиса.
  Тексты форка — в `lib/neko/brand.dart`, переводы апстрима не тронуты.
- **Сборка.** `.github/workflows/neko-release.yaml`: подписанные APK для
  Android (arm64-v8a, armeabi-v7a, x86_64) из тега `v*-neko.*` в черновик
  релиза. Сборки для Windows, macOS и Linux — следующим шагом: их служба-
  помощник, каналы ядра и TUN-адаптер ещё называются как у FlClash и
  конфликтовали бы с ним на одном компьютере.

### Изменённые файлы апстрима

`android/app/build.gradle.kts`, `android/common/build.gradle.kts`,
`android/settings.gradle.kts`, `android/app/google-services.json` (удалён),
`android/common/src/main/java/com/follow/clash/common/GlobalState.kt`,
`android/common/src/main/res/values/strings.xml`,
`android/app/src/main/AndroidManifest.xml`,
`android/app/src/debug/AndroidManifest.xml`, иконки в `android/app/src/main/res`,
`android/service/src/main/res/drawable/ic_service.xml` и `ic.xml` (значок в строке
состояния и плитка), заголовок уведомления и имя профиля по умолчанию
(`NotificationModule.kt`, `NotificationParams.kt`, `State.kt`, их тесты
`SharedStateTest.kt` и `ServiceConfigTest.kt`),
`assets/images/icon.png`, `lib/common/constant.dart`, `lib/common/protocol.dart`,
`lib/common/request.dart`, `lib/bootstrap.dart`, `lib/views/about.dart`,
`lib/views/disclaimer.dart`, `lib/views/config/general.dart`,
`test/common/protocol_test.dart`, `test/common/link_test.dart`,
`test/state_run_globals_test.dart`, `test/android_tv_launcher_icon_test.dart`,
`tool/check_coverage.dart` (порог 95% для `lib/neko`),
`pubspec.yaml`, `distribute_options.yaml`, `README.md` (README апстрима —
`README.upstream.md`).
