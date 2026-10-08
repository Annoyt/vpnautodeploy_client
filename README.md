# vpnautodeploy_client

Клиент NekoVPN: планируемый форк [FlClash](https://github.com/chen08209/FlClash)
(ядро [mihomo](https://github.com/MetaCubeX/mihomo)) с удалёнными настройками,
кнопкой SOS и режимом шлюза для соседей.

*NekoVPN client — a planned fork of FlClash (mihomo core) with signed remote
settings, an SOS button and a LAN gateway mode. Plan first; code when the
field test says so.*

**Статус (2026-10-08): планирование.** Кода здесь пока нет. Форк появится,
только если полевой тест обычного FlClash из российских сетей покажет, что без
правок ядра не обойтись, или понадобятся резервные адреса и телеметрия с кнопки
(см. [docs/PLAN.md](docs/PLAN.md), раздел «Критерий запуска»).

- Серверная часть (бот, подписка, каскад): [Annoyt/VPNautodeploy](https://github.com/Annoyt/VPNautodeploy),
  раздел E плана `docs/IMPROVEMENT_PLAN.md`.
- Апстрим: [chen08209/FlClash](https://github.com/chen08209/FlClash) (GPL-3.0),
  ядро — форк mihomo (MIT).
- Лицензия этого репозитория: **GPL-3.0** — как у апстрима. Исходники всех
  выпущенных сборок будут здесь, с пометкой об изменениях.

Почему отдельный клиент, что берём от FlClash как есть, контракт с сервером,
объём форка, сборка и раздача, лицензионные обязательства, задачи и оценки —
в [docs/PLAN.md](docs/PLAN.md).
