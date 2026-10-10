# Изменения NekoVPN относительно FlClash

Этот репозиторий — изменённая версия [FlClash](https://github.com/chen08209/FlClash)
(GPL-3.0). Здесь перечислены только наши изменения, с датами (GPL-3.0, §5a).
Журнал апстрима — [CHANGELOG.md](CHANGELOG.md).

## 0.8.99-neko.1 — 2026-10-10

На основе апстрима v0.8.99 (`main` на 2026-10-10).

- **Имя, пакет, иконка.** Приложение называется NekoVPN, Android-пакет
  `com.nekovpn.client`, своя иконка (`tool/neko/icons.py` генерирует все
  размеры). Ставится рядом с FlClash и поверх него не обновляется.
- **Без Firebase.** Удалены Crashlytics и Analytics: Gradle-плагины и
  зависимости, `google-services.json`, вызовы в `GlobalState.kt`, переключатель
  «Аналитика сбоев», окно о сборе данных при запуске и раздел о Firebase в
  соглашении. Ни одна сборка NekoVPN ничего не отправляет третьим сторонам.
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
`assets/images/icon.png`, `lib/common/constant.dart`, `lib/common/protocol.dart`,
`lib/common/request.dart`, `lib/bootstrap.dart`, `lib/views/about.dart`,
`lib/views/disclaimer.dart`, `lib/views/config/general.dart`,
`test/common/protocol_test.dart`, `test/common/link_test.dart`,
`test/state_run_globals_test.dart`, `test/android_tv_launcher_icon_test.dart`,
`tool/check_coverage.dart` (порог 95% для `lib/neko`),
`pubspec.yaml`, `distribute_options.yaml`, `README.md` (README апстрима —
`README.upstream.md`).
