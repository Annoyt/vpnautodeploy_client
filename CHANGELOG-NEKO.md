# Изменения NekoVPN относительно FlClash

Этот репозиторий — изменённая версия [FlClash](https://github.com/chen08209/FlClash)
(GPL-3.0). Здесь перечислены только наши изменения, с датами (GPL-3.0, §5a).
Журнал апстрима — [CHANGELOG.md](CHANGELOG.md).

## 0.8.99-neko.2 — 2026-10-15

На основе апстрима v0.8.99, как и предыдущая.

- **Обновления только от NekoVPN.** Приложение смотрит список релизов этого
  репозитория и берёт только теги вида v…-neko.N: релиз FlClash или любой
  другой тег не предлагается никогда.
- **Тестовые сборки получают тестовые обновления.** Раньше проверка, взятая у
  FlClash, смотрела только «последний стабильный релиз» и наши пре-релизы не
  видела; будущие стабильные сборки увидят только стабильные релизы.
- **«Скачать» ведёт на найденный релиз**, а не на страницу «последнего»
  релиза, которой у пре-релизов нет.
- **В окне обновления — наши изменения**: список берётся из этого журнала.
- **Публикация FlClash в нашем репозитории под замком**: тест падает, если
  после слияния с апстримом его задачи релиза или сайта смогут запуститься
  здесь.

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
