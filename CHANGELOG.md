# CHANGELOG

Журнал изменений по датам. Ведётся, чтобы можно было продолжить работу в
любой новой сессии (или с другой нейросетью) без потери контекста.

## 2026-07-05 — Дизайн-решения по итогам аудита Opus (внедрено Sonnet)

Автор ответил на оба открытых дизайн-вопроса из аудита Opus (см. запись ниже)
и попросил внести изменения. Реализовано:

**1. Подсказка "Поймать" больше не раскрывает Hiders:**
- `CatchService.lua`: убран `prompt.ObjectText = hiderPlayer.Name` (подсказка
  теперь нейтральная — только `ActionText = "Поймать"`, без имени).
- Включено `prompt.RequiresLineOfSight = true` (встроенная проверка Roblox).
- Добавлена собственная серверная проверка `hasLineOfSight` (raycast от
  `Head` искателя до `HumanoidRootPart` цели) — встроенное свойство
  `RequiresLineOfSight` само по себе только клиентское и обходится тем же
  эксплойтом `fireproximityprompt`, что и дистанция (проверено веб-поиском по
  документации и DevForum), поэтому продублировано на сервере в `TryCatch`.
- Подсказка теперь **видна только Seekers**: `CatchService.StartSeekingPhase`
  собирает все созданные `ProximityPrompt` и рассылает их персонально каждому
  Hider через новый RemoteEvent `HideCatchPromptsFromHiders`; клиент (новый
  файл `CatchClient.lua`) локально выставляет им `Enabled = false`. Seekers
  этот remote не получают и видят подсказки как раньше. Паттерн подтверждён
  через DevForum (клиентское переопределение `Enabled` не влияет на сервер и
  других игроков).

**2. Поза — только для Hiders, только в фазу Hiding:**
- `FreezeService.onRequestFreeze` теперь проверяет: игрок должен быть в
  команде Hiders и текущая фаза (`RoundManager.State`) должна быть `"Hiding"`
  — иначе запрос молча отклоняется. `FreezeService.lua` подключил
  `RoundManager` через `require` (без цикла зависимостей, т.к. `RoundManager`
  получает сервисы через `Init()`, а не `require()`).
- `FreezeClient.lua`: кнопка позы скрыта (`Visible = false`) для Seekers и
  неактивна (`Active = false`, затемнена) вне фазы `Hiding` — зеркалит
  серверное ограничение для UX, реальная защита всегда на сервере.
- Зафиксирован сознательный компромисс в `DECISIONS.md` п.13: теперь Hider не
  может переключить позу и во время `Seeking` (не только заморозиться, но и
  разморозиться) — это убирает более раннюю идею "спалиться на движении при
  разморозке" из исходного ТЗ. Если понадобится вернуть — однострочная правка
  условия фазы в `FreezeService`.

**Документация:** обновлены `ARCHITECTURE.md` (новый RemoteEvent, новая
структура `CatchService`/`FreezeService`, зависимость `FreezeService` →
`RoundManager`), `DECISIONS.md` (новые пункты 12 и 13), `TASKS.md` (два
дизайн-пункта из Раздела 0 перенесены в выполненные, добавлены сценарии
ручного тестирования для line-of-sight, видимости подсказки и гейтинга позы).

## 2026-07-05 — Аудит Opus (ревью + план следующей итерации)

Ревью первой итерации (написанной Sonnet) главным архитектором. Не переписывал
рабочий код без нужды — правил только критичные/однозначные баги, остальное
задокументировал как задачи.

**Исправленные баги (код):**
- **[КРИТ] Уязвимость поимки (`fireproximityprompt`).** `CatchService` доверял
  серверному `ProximityPrompt.Triggered` без проверки дистанции — читер мог
  ловить всех Hiders с любой точки карты. Добавлена серверная проверка
  расстояния (`seekerIsCloseEnough`) + `CATCH_MAX_DISTANCE`/
  `CATCH_DISTANCE_TOLERANCE`/`CATCH_HOLD_DURATION` в `GameConfig`. Проверено
  веб-поиском по DevForum. Исправлено ошибочное обоснование в `DECISIONS.md` п.4.
- **[ВЫС] `RoundManager.gameLoop` не был защищён от ошибок** — одна ошибка в
  фазе убивала весь игровой цикл навсегда. Тело раунда обёрнуто в `pcall` с
  аварийной уборкой и возвратом в лобби.
- **[ВЫС] Выход Hider посреди раунда** не убирал его из `foundState`, из-за чего
  `CountRemaining()` не доходил до 0 и раунд не завершался досрочно. Добавлен
  `PlayerRemoving`-обработчик в `CatchService`.
- **[СРЕД] `FreezeService`: `JumpHeight` обнулялся, но не восстанавливался** — на
  ригах `UseJumpPower=false` игрок навсегда терял прыжок. Теперь исходные
  параметры движения кешируются и восстанавливаются.

**Документация:**
- Создан `ARCHITECTURE.md` — реальная текущая архитектура: таблица всех
  RemoteEvents с параметрами, что и где хранится (состояние на игрока по
  сервисам), схема state machine раунда, известные ограничения.
- `DECISIONS.md` п.4 — исправлено неверное утверждение о "безопасности"
  ProximityPrompt.
- `TASKS.md` полностью переструктурирован: разделы "Найденные проблемы",
  "Живой тест через MCP", "Полировка MVP", "Нереализованные фичи",
  "Ручное тестирование" — каждый пункт с приоритетом и критерием готовности.
- `ROADMAP.md` — MVP отмечен как реализованный (код, не тестирован вживую),
  добавлен новый этап "Live-тестирование и полировка".

**Проверено и признано корректным (не баг):**
- Логика зарядов краски — гонки состояний нет (обработчик RemoteEvent
  однопоточный, между проверкой `charges <= 0` и `charges -= 1` нет yield).
- Серверное проигрывание анимации позы реплицируется корректно (Animator
  создан на сервере штатным персонажем).

**Оставлено как дизайн-задачи для Sonnet/авторов (не правил сам):**
- Промпт поимки раскрывает позицию Hider (плавающая кнопка с именем) — нужно
  решение, как ловить, чтобы не убивать маскировку.
- Заморозка не ограничена ролью/фазой (Seeker тоже может встать в позу).
- Магические числа скорости (16/50) вынести в конфиг.

## 2026-07-05

- Инициализирован проект-клон MECCHA CHAMELEON на Roblox/Luau.
- Создана документация: `CLAUDE.md`, `README.md`, `ROADMAP.md`, `TASKS.md`,
  `DECISIONS.md`, `CHANGELOG.md` (этот файл).
- Настроена файловая структура под Rojo: `default.project.json` + `src/`
  (ReplicatedStorage/Modules, ServerScriptService, StarterPlayer/StarterPlayerScripts).
- Реализован MVP системы покраски:
  - `ReplicatedStorage/Modules/GameConfig.lua` — общий конфиг баланса игры.
  - `ReplicatedStorage/Modules/PaletteData.lua` — набор цветов палитры.
  - `ServerScriptService/RemotesSetup.lua` — создание RemoteEvent-ов.
  - `ServerScriptService/PaintService.lua` — серверная валидация покраски,
    лимит "зарядов кисти" с перезарядкой по таймеру.
  - `StarterPlayer/StarterPlayerScripts/PaintClient.lua` +
    `UI/PaletteUIBuilder.lua` — UI палитры (сетка цветов, выбор части тела,
    кнопка пипетки), реализация пипетки через `Workspace:Raycast` от камеры,
    обработка тапа и клика мыши через один и тот же код (`UserInputService`).
- Реализован MVP системы раундов:
  - `ServerScriptService/PlayerRoleService.lua` — Teams (Hiders/Seekers/
    Spectators) и случайное распределение ролей.
  - `ServerScriptService/RoundManager.lua` — автомат фаз раунда Lobby → Hiding
    → Seeking → RoundEnd, таймеры через RemoteEvent, телепорт Seekers в
    комнату ожидания на время пряток.
  - `ServerScriptService/FreezeService.lua` +
    `StarterPlayer/StarterPlayerScripts/FreezeClient.lua` — базовая
    заморозка/поза (блокировка перемещения, запрет покраски во время позы).
  - `ServerScriptService/CatchService.lua` — обнаружение прячущихся через
    `ProximityPrompt`, серверная валидация без RemoteEvent (используется
    прямое серверное подключение к `Triggered`).
  - `ServerScriptService/ScoreService.lua` — очки за поимку и за время
    выживания, сборка итогов раунда.
  - `StarterPlayer/StarterPlayerScripts/RoundUIClient.lua` +
    `UI/HUDBuilder.lua` + `UI/ResultsUIBuilder.lua` — HUD (фаза, таймер,
    роль, счётчик найденных) и экран итогов раунда.
- `ServerScriptService/Main.server.lua` и
  `StarterPlayer/StarterPlayerScripts/Main.client.lua` — точки входа,
  связывающие все сервисы вместе.

**Статус:** MVP готов как код, не проверен вживую в Roblox Studio (сессия
без доступа к Studio/MCP). Следующий шаг — синхронизация через Rojo и
живой тест, см. `TASKS.md`.
