# NekoVPN — клиент (vpnautodeploy_client)

Клиент сервиса NekoVPN для Android, Windows, macOS и Linux. Это **изменённая
версия [FlClash](https://github.com/chen08209/FlClash)** (GPL-3.0) с ядром
[mihomo](https://github.com/MetaCubeX/mihomo) (MIT). FlClash — проект его
авторов; NekoVPN — независимый форк, не связанный с ними.

*NekoVPN client — a modified version of FlClash (GPL-3.0). Not affiliated with
the FlClash authors.*

**Статус (2026-10-10): тестовые сборки.** Владелец сервиса решил начать форк до
полевого теста обычного FlClash: тестеры первой сборки и есть полевой тест
(раздел 8 [docs/PLAN.md](docs/PLAN.md)).

## Чем отличается от FlClash

Подробно, с датами, — в [CHANGELOG-NEKO.md](CHANGELOG-NEKO.md).

- Своё имя (NekoVPN), иконка и идентификатор пакета: ставится рядом с FlClash,
  поверх него не обновляется.
- Без Firebase Crashlytics и Analytics. Остаётся Google ML Kit в сканере
  QR-кодов на Android (из апстрима): по условиям Google он может отправлять
  Google метрики работы сканера; замена — в плане (E36).
- Обновления проверяются в этом репозитории, а не у апстрима.
- Ссылки `nekovpn://install-config?url=…` для импорта подписки.

## Исходники и лицензия

- Лицензия — **GPL-3.0**, как у апстрима ([LICENSE](LICENSE)). Исходники каждой
  выпущенной сборки — тег в этом репозитории.
- История апстрима сохранена; его README — [README.upstream.md](README.upstream.md),
  сборка устроена так же (`dart setup.dart <платформа>`).
- Наш релизный конвейер — `.github/workflows/neko-release.yaml`; проверки
  апстрима (`build.yaml`) работают как есть.
- План клиента, контракт с сервером и задачи — [docs/PLAN.md](docs/PLAN.md).
  Серверная часть: [Annoyt/VPNautodeploy](https://github.com/Annoyt/VPNautodeploy).
