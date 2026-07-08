# ARCHITECTURE

Документ описывает **реальную текущую** архитектуру проекта (как оно есть в
коде на ветке `claude/meccha-chameleon-roblox-jvepyg`), а не идеальный план.
Составлен в ходе ревью Opus (2026-07-05), обновлён после внедрения фиксов из
аудита (line-of-sight поимка, скрытие подсказок от Hiders, гейтинг позы),
после пересмотра механики покраски на рисование кистью + добавления свистка,
после пересмотра позы на конкретные пресеты + добавления режима Infection
(2026-07-05), после добавления лобби-UI, гибкого баланса ролей 2-24,
приватных комнат и режима зрителя, после добавления системы очков Missed
Point Ranking (обе части — 2026-07-06), и после добавления первой
процедурной карты (`MapBuilder.lua`, см. "Карта" ниже и `DECISIONS.md`,
п.23 — 2026-07-08). Обновлять при изменении контрактов (RemoteEvents,
состояние игрока, фазы раунда).

## Общая схема

Сервер — источник истины. Клиент только отправляет "запросы" (покрасить, встать
в позу) и отрисовывает UI по событиям сервера. Вся логика раунда — на сервере.

```
КЛИЕНТ (StarterPlayerScripts)              СЕРВЕР (ServerScriptService)
------------------------------             ----------------------------
Main.client ─ инициализирует:              Main.server ─ инициализирует:
  PaintClient   ──PaintStroke───────────►    PaintService ──require──► RoundManager (для проверки фазы)
  FreezeClient  ──RequestFreeze(pose)───►    FreezeService ──require──► RoundManager (для проверки фазы)
  RoundUIClient ◄─RoundStateChanged─────     RoundManager  (главный автомат, требует GameMode)
                ◄─RoundTimerTick───────      PlayerRoleService
                ◄─PlayerCaught────────       CatchService (ProximityPrompt + серверные
  CatchClient   ◄─HideCatchPromptsFromHiders  дистанция/line-of-sight проверки; OnCatch-хук
  PaintClient   ◄─InkUpdate─────────────      для перехода роли в Infection, см. DECISIONS 18)
  WhistleClient ──RequestWhistle────────►    WhistleService (Sound + RollOff, см. DECISIONS 15)
  WhistleClient ◄─WhistleCountdownUpdate      ScoreService ──require──► CatchService, LineOfSightUtil
  RoundUIClient ◄─MissedPointRankingUpdate    (Missed Point Ranking, только самому Hider'у, см. DECISIONS 22)
  LobbyUIClient ◄─RoundStateChanged─────     PrivateRoomService (TeleportService +
                ──CreatePrivateRoom───►       MemoryStoreService, см. DECISIONS 20)
                ──JoinPrivateRoom─────►
                ◄─PrivateRoomError─────
  SpectatorClient◄─SpectatorModeChanged──    SpectatorService (скрытие/анкор персонажа,
                                              см. DECISIONS 21) ──require──► RoundManager
```

`Main.server.lua` вызывает `MapBuilder.Build()` самым первым действием (до
`RemotesSetup.Init()` и остальных сервисов) - строит геометрию карты в
`Workspace` кодом, см. раздел "Карта" ниже.

## Карта

Карта строится кодом при старте сервера (`MapBuilder.lua`,
`ServerScriptService`), а не хранится как файл/ассет - см. `MAPS.md` и
`DECISIONS.md`, п.23 для полного обоснования (готовые бесплатные карты с
Marketplace/GitHub нельзя ни легально встроить в репозиторий, ни физически
вставить без доступа к Studio). Переключается константой
`GameConfig.USE_PROCEDURAL_MAP`.

Результат - `Folder` с именем `Map` в `Workspace`, содержащий:
- **Холл** (X от -60 до -18, `buildEntranceHall`, раньше называлась
  `buildLobby`) - обычная игровая зона здания с парой скамеек и 2
  маркерами `HiderSpawn`. Спавнов игроков тут больше нет - они переехали
  на лобби-платформу (см. ниже).
- **Рабочая зона** (X от -18 до 25) - под-зоны "Офис" и "Склад", разделены
  низкой (4 стада) перегородкой, ~20 предметов мебели разного цвета/размера
  (столы, стулья, шкафы, ящики), 3 маркера `HiderSpawn`.
- **Гостиная** (X от 25 до 85) - под-зоны "Гостиная" и "Переговорная", та
  же логика низкой перегородки, ~15 предметов (диваны, столы, растения,
  стулья, книжный шкаф), 3 маркера `HiderSpawn`.
- Три зоны разделены между собой **полновысотными** (12 стадов) стенами с
  проёмом 12 стадов - единственная геометрия, реально блокирующая
  `LineOfSightUtil` (поимку и Missed Point Ranking).
- **`SpectatorSpawn`** (именной Part-контракт, см. `DECISIONS.md`, п.23) -
  невидимая точка высоко над центром здания; `SpectatorService.
  hideAndImmobilize` телепортирует туда персонажа перед анкором, если Part
  найден (иначе просто анкорит на месте, как раньше).
- Крыш у комнат нет (осознанно - дешевле по производительности и даёт
  зрителю обзор сверху, см. `DECISIONS.md`, п.23).

Координаты и пропорции не откалиброваны визуально (нет доступа к Studio в
этой сессии) - см. "Известные ограничения" ниже и `TASKS.md`.

## Лобби-платформа (см. `MEGA_PLAN.md` Часть 1, `DECISIONS.md` п.25)

Геометрия платформы (MEGA_PLAN 1.1) **реализована** в `MapBuilder.
buildLobbyPlatform` (заменила `buildSeekerWaitingRoom`) - остальные
подшаги (1.2-1.6) по статусу см. `TASKS.md`, Раздел B1. Ключевой принцип
(ponytail), выдержанный в реализации: **отдельного `LobbyService` нет** -
логика лежит на существующих владельцах.

- **Геометрия (готово)** - `MapBuilder.buildLobbyPlatform`: парящий
  круглый `Part`-цилиндр (`Shape = Enum.PartType.Cylinder`, центр
  `Vector3.new(12, 120, -160)`, радиус 32) высоко над картой и в стороне
  от здания; бортик+невидимые стены по 8 сегментам периметра; в центре
  видимый диск-подсветка + невидимый маркер-объём `SeekerVolunteerZone`
  (встал = доброволец-Seeker) с `BillboardGui`; по краю 4 арки с
  маркерами `HiderGateZone` (встал = доброволец-Hider), остальная площадь
  = случайное распределение; 6 `SpawnLocation` на кольце. Маркер-контракт
  `SeekerWaitingRoom` переехал в центр платформы - строка телепорта в
  `RoundManager` не поменялась. Новый маркер-контракт `HiderSpawn`×8
  раскидан по зонам здания - `RoundManager.runHidingPhase` телепортирует
  туда Hiders случайно (`teleportPlayersToRandomOf`). Попутно исправлен
  баг `findSpawnByName` (искал в `Workspace`, а не в `Workspace.Map` -
  см. `DECISIONS.md`, п.25).
- **Выбор роли (готово)** - в `PlayerRoleService.AssignRoles`: новая
  `getRoleIntent(player)` читает позицию игрока ОДИН раз в момент
  раздачи (не следит циклом — правило производительности №1) и относит
  его к пулу volunteers/hiderWish/randomPool (по `SeekerVolunteerZone`/
  `HiderGateZone`); слоты Seeker заполняются по приоритету
  (добровольцы → случайные → желающие прятаться). Сигнатура
  `AssignRoles` не изменилась.
- **Разрешения фаз (ещё не реализовано)** - `PaintService`/`FreezeService`
  расширяют проверку фазы на `Lobby` (тренировка кисти/поз в лобби) и
  позже на `Seeking` (докраска, MEGA_PLAN 3.2/Q2). Гейтинг клиентских
  панелей (`PaintClient`/`FreezeClient`) зеркалит это.
- **Персистентность покраски (проверка, не правка)** - БЕЗ новых структур:
  мазки живут на частях персонажа. Hider на старте пряток проходит через
  существующий `ResetForNewRound` (стирается), Seeker не проходит
  (сохраняется).
- **Телепорт-эффект (ещё не реализовано)** - локальная
  `teleportWithEffect` внутри `RoundManager` (частицы `ParticleEmitter` +
  твин прозрачности + одновременный телепорт всех Seekers на новый маркер
  `SeekerSpawn`); клиентского кода ноль (сервер реплицирует эффект сам).

## Внешность персонажа (ЗАПЛАНИРОВАНО — см. `MEGA_PLAN.md` Часть 2)

- **`CharacterStyleService.lua`** (новый, ServerScriptService): на
  `CharacterAdded` красит все `BasePart` персонажа в `BASE_BODY_COLOR`
  (белый) + `SmoothPlastic`. НЕ трогает `Transparency` (чтобы не
  конфликтовать со `SpectatorService.hideAndImmobilize`).
- **`StarterPlayer.LoadCharacterAppearance = false`** — платформенное
  отключение каталожной косметики (не код-велосипед). Риг R15 (настройка
  места → README). Округлые формы через `HumanoidDescription`/бандл —
  этап 2, только на живой сессии со Studio.

Общие модули `ReplicatedStorage/Modules/`:
- `BrushGeometry.lua` — используется и клиентом (`PaintClient`, чтобы понять,
  куда мазнул игрок), и сервером (`PaintService`, чтобы честно разместить
  мазок по присланным координатам) — единая математика face/UV, без
  дублирования и риска рассинхронизации.
- `PosePresets.lua` — список из 4 пресетов позы (id/label/animationId/
  hipHeightMultiplier), используется клиентом (`PosePickerUIBuilder`, чтобы
  построить карусель кнопок) и сервером (`FreezeService`, чтобы
  провалидировать присланный `poseId` и применить анимацию/hitbox). См.
  `DECISIONS.md`, п.17.
- `GameMode.lua` — константа активного режима (`Classic`/`Infection`),
  читается сервером (`RoundManager`, чтобы решить, что делать при поимке) и
  может читаться клиентом (например, для формулировки сообщений). См.
  `DECISIONS.md`, п.18 — там же важный нюанс: это статическая настройка,
  переключаемая только правкой кода, а не в реальном времени.
- `RoleUtil.lua` — общая проверка `IsHider(player)`/`IsSeeker(player)` по
  `player.Team`, используется клиентскими скриптами (`FreezeClient`,
  `PaintClient`), чтобы клиентское зеркалирование серверных ограничений по
  роли не расходилось по разным файлам.

## RemoteEvents

Все создаются кодом при старте сервера в `ReplicatedStorage/Remotes/`
(`RemotesSetup.lua`). Направление и параметры:

| Событие | Направление | Параметры | Описание |
|---|---|---|---|
| `PaintStroke` | клиент → сервер | `points: {{partName: string, face: Enum.NormalId, u: number, v: number}}`, `color: Color3`, `brushSize: number` | Пакет точек мазка кисти, отправляется раз в ~0.15с при рисовании (не по одной точке за раз). Сервер валидирует роль/фазу/заморозку/чернила и сам создаёт `Texture`-мазки, см. `DECISIONS.md`, п.14. |
| `RequestFreeze` | клиент → сервер | `wantsFreeze: boolean`, `poseId: string?` | Запрос встать в конкретный пресет позы / выйти из позы. `poseId` обязателен и валидируется сервером (`PosePresets.ById`), когда `wantsFreeze = true`; при выключении не используется. См. `DECISIONS.md`, п.17. |
| `RoundStateChanged` | сервер → все клиенты | `state: string`, `timeLeft: number`, `extra: table` | Смена фазы. `state` ∈ {Lobby, Hiding, Seeking, RoundEnd}. `extra` может содержать `results`, `playersNeeded`, `playersCurrent`. |
| `RoundTimerTick` | сервер → все клиенты | `remaining: number` | Тик таймера текущей фазы (раз в секунду). |
| `PlayerCaught` | сервер → все клиенты | `hiderName: string`, `seekerName: string`, `remaining: number` | Кого-то поймали + сколько осталось. |
| `InkUpdate` | сервер → **один** клиент | `amount: number`, `maxAmount: number` | Обновление количества "чернил" кисти конкретного игрока (замена прежних дискретных "зарядов", см. `DECISIONS.md`, п.14). Отправляется только в фазах `Hiding`/`Lobby` (см. `AUDIT_FABLE5.md`, S9). |
| `HideCatchPromptsFromHiders` | сервер → **только Hiders**, персонально каждому | `prompts: {ProximityPrompt}` | Список всех активных промптов поимки за раунд; клиент локально ставит им `Enabled = false`, чтобы Hiders не видели, где стоят другие Hiders (см. `DECISIONS.md`, п.12). Seekers это событие не получают. |
| `RequestWhistle` | клиент → сервер | (без параметров) | Hider просит свистнуть прямо сейчас. Сервер проверяет роль/фазу/не пойман ли, сбрасывает таймер и проигрывает звук, см. `DECISIONS.md`, п.15. |
| `WhistleCountdownUpdate` | сервер → **только Hiders**, персонально каждому | `secondsLeft: number` | Сколько секунд осталось до следующего (авто- или уже сброшенного) свистка. |
| `CreatePrivateRoom` | клиент → сервер | `password: string` | Создать приватную комнату с этим паролем. Сервер валидирует длину, резервирует сервер (`TeleportService:ReserveServerAsync`), сохраняет пару пароль→код в `MemoryStoreService` и телепортирует создателя, см. `DECISIONS.md`, п.20. |
| `JoinPrivateRoom` | клиент → сервер | `password: string` | Войти в комнату по паролю. Сервер ищет код по паролю в `MemoryStoreService` и телепортирует, см. `DECISIONS.md`, п.20. |
| `PrivateRoomError` | сервер → **один** клиент | `message: string` | Не удалось создать/войти (текст причины на русском для показа в UI). |
| `SpectatorModeChanged` | сервер → **один** клиент | `isSpectating: boolean` | Включить/выключить клиентский режим зрителя (скрытый персонаж + fly-камера), см. `DECISIONS.md`, п.21. |
| `MissedPointRankingUpdate` | сервер → **только сам Hider** | `total: number` | Личный счётчик Missed Point Ranking (замечен, но не пойман). Seeker это событие никогда не получает - см. `DECISIONS.md`, п.22. |

RemoteFunctions в проекте **не используются** (всё построено на односторонних
событиях — так проще и безопаснее).

Формат одной записи в `results`:
```lua
{ name = "PlayerName", role = "Hider" | "Seeker", roundScore = 42, totalScore = 137, missedPoints = 9 }
```
`missedPoints` — сколько очков Missed Point Ranking набрал этот игрок за
раунд (0, если ни разу не был замечен незамеченным - см. `DECISIONS.md`,
п.22). Используется на экране итогов для номинации "Лучшая маскировка".

`LineOfSightUtil.lua` (`ServerScriptService`, только сервер) — общая
математика дистанции и прямого взгляда (raycast), переиспользуется и
`CatchService` (поимка), и `ScoreService` (Missed Point Ranking), чтобы не
дублировать один и тот же raycast-код в двух местах.

## Состояние на сервере (кто что хранит)

Единого объекта `PlayerData` **нет** — состояние распределено по сервисам,
каждый ключ — сам объект `Player`. Все сервисы чистят своё состояние в
`Players.PlayerRemoving`.

| Сервис | Таблица | Что хранит |
|---|---|---|
| `PaintService` | `inkData[player] = { amount }` | текущие "чернила" кисти (0..`MAX_INK`) |
| `PaintService` | `activeStamps[player] = { Texture, ... }` | очередь мазков игрока (FIFO), старые вытесняются по `MAX_ACTIVE_STAMPS_PER_PLAYER` |
| `PaintService` | `paintingBlocked[player] = bool` | запрещена ли покраска (поза / фаза поиска) |
| `FreezeService` | `frozenState[player] = bool` | стоит ли игрок в позе |
| `FreezeService` | `activePose[player] = string` | id текущего пресета позы (например `"Crouch"`), только пока `frozenState[player] == true` |
| `FreezeService` | `savedLocomotion[player] = {walkSpeed, jumpPower, jumpHeight, hipHeight}` | исходные параметры движения и "hitbox-профиля" (`HipHeight`), чтобы вернуть после позы |
| `CatchService` | `foundState[player] = bool` | найден ли этот Hider (только участники текущего раунда) |
| `CatchService` | `activePrompts[player] = ProximityPrompt` | висящий на игроке промпт поимки (`ActionText = "Поймать"`, без имени, `RequiresLineOfSight = true`) |
| `ScoreService` | `totalScores[player] = number` | очки за всю сессию сервера |
| `ScoreService` | `roundScores[player] = number` | очки за текущий раунд |
| `ScoreService` | `roundStartTimes[player] = tick()` | когда для Hider началась фаза поиска |
| `ScoreService` | `missedPointScores[player] = number` | очки Missed Point Ranking за текущий раунд (см. `DECISIONS.md`, п.22) |
| `WhistleService` | `nextWhistleAt[player] = tick()` | когда сработает следующий свисток этого Hider |
| `WhistleService` | `whistleSounds[player] = Sound` | переиспользуемый звук свистка (создаётся один раз) |
| `RoundManager` | `currentHiders`, `currentSeekers` | списки игроков по ролям в текущем раунде |
| `PlayerRoleService` | Teams | роль игрока хранится штатно в `player.Team` |
| `PrivateRoomService` | `joinAttempts[player] = {count, windowStart}` | рейт-лимит попыток создать/войти в приватную комнату |
| `PrivateRoomService` | `MemoryStoreService` SortedMap `"PrivateRoomPasswords"` | пароль (нормализованная строка) → `accessCode` зарезервированного сервера, TTL 6 часов — общее для всех серверов игры, не только для текущего процесса (см. `DECISIONS.md`, п.20) |
| `SpectatorService` | `isFullSpectator[player] = bool` | находится ли игрок в полном режиме зрителя (скрыт/обездвижен/летает) |

## State machine раунда (`RoundManager`)

Один бесконечный цикл `gameLoop` в отдельной корутине (`task.spawn`). Тело
раунда обёрнуто в `pcall` — при ошибке делается аварийная уборка и возврат в
лобби (цикл не умирает).

```
        ┌─────────────────────────────────────────────┐
        ▼                                             │
  [ Lobby ]  ждём MIN_PLAYERS, отсчёт LOBBY_COUNTDOWN │
        │  игроков хватило                            │
        ▼                                             │
  AssignRoles → currentHiders / currentSeekers        │
     • ExitSpectator для всех - те, кто зашёл посреди  │
       прошлого раунда и всё ещё летает зрителем,      │
       респавнятся и получают роль (DECISIONS 21)      │
        │                                             │
        ▼                                             │
  [ Hiding ]  HIDING_PHASE_DURATION сек               │
     • Seekers → SeekerWaitingRoom (на лобби-платформе), WalkSpeed=0│
     • Hiders → случайный HiderSpawn на карте здания   │
       (teleportPlayersToRandomOf, MEGA_PLAN 1.1.7)    │
     • Hiders: чернила и мазки прошлого раунда стёрты  │
       (PaintService.ResetForNewRound), рисование разрешено│
     • Hiders выбирают один из 4 пресетов позы (Crouch/ │
       LieDown/Lean/StandStill) - см. DECISIONS 17     │
        │                                             │
        ▼                                             │
  [ Seeking ]  SEEKING_PHASE_DURATION сек             │
     • Seekers освобождены                            │
     • Hiders: рисование запрещено, поза не переключается│
     • на Hiders повешены ProximityPrompt (видны только │
       Seekers, требуют line-of-sight - см. DECISIONS 12)│
     • у каждого Hider тикает таймер свистка - авто через │
       WHISTLE_AUTO_INTERVAL_SECONDS или вручную (DECISIONS 15)│
     • раз в MISSED_POINT_CHECK_INTERVAL_SECONDS каждый   │
       живой Hider проверяется на видимость Seekers -     │
       Missed Point Ranking очки, только самому Hider'у   │
       (ScoreService, DECISIONS 22)                       │
     • при поимке (CatchService.OnCatch): если GameMode  │
       == Infection - пойманный мгновенно снимает позу/ │
       покраску и становится Seeker "на лету" (DECISIONS 18)│
     • досрочный выход, если пойманы все (OnAllCaught -  │
       не зависит от режима, см. DECISIONS 18)          │
        │                                             │
        ▼                                             │
  [ RoundEnd ]  ROUND_END_DISPLAY_DURATION сек        │
     • снять позы, начислить очки выжившим            │
     • собрать и разослать results                    │
     • всех → Spectators (команда-"отстойник" между    │
       раундами; НЕ то же самое, что полный режим      │
       зрителя SpectatorService - см. DECISIONS 21)    │
     • игрокам в полном режиме зрителя WalkSpeed не    │
       возвращается - остаются "летающими" до ExitSpectator│
        │                                             │
        └─────────────────────────────────────────────┘
```

Переходы фаз последовательны (одна корутина), одновременных переходов быть не
может — это сознательно упрощает логику, но означает, что весь цикл зависит от
одной корутины (отсюда обёртка в `pcall`).

## Известные ограничения текущей архитектуры

- Нет единого `PlayerDataService` — при росте проекта состояние по разным
  таблицам станет труднее поддерживать. Кандидат на рефакторинг, если фич
  станет заметно больше (пока преждевременно).
- Списки `currentHiders`/`currentSeekers` фиксируются на старте раунда и не
  реагируют на вход новых игроков посреди раунда (новые становятся
  зрителями через `SpectatorService` и ждут следующего раунда — см.
  `DECISIONS.md`, п.21; раньше, до этой доработки, они просто ждали без
  какого-либо зрительского режима).
- `FreezeService` теперь проверяет роль (только Hiders) и фазу (только
  `Hiding`) перед переключением позы (см. `DECISIONS.md`, п.13) — раньше это
  было открытым ограничением, сейчас закрыто. Побочный эффект: Hider не может
  ни встать в позу, ни выйти из неё во время `Seeking` — компромисс описан в
  том же пункте `DECISIONS.md`.
- `FreezeService.lua` подключает `RoundManager.lua` через `require`, чтобы
  прочитать текущую фазу (`RoundManager.State`). Обратной связи нет —
  `RoundManager` получает остальные сервисы через `Init()`, а не `require()`,
  поэтому цикла зависимостей не возникает, но при рефакторинге `RoundManager`
  стоит об этом помнить. `PaintService.lua` подключает `RoundManager.lua` тем
  же способом и по той же причине.
- Мазки кисти (`Texture` с `OffsetStudsU/V`) размещаются через плоскую
  проекцию на ближайшую грань `BasePart`, а не honest UV-wrap по кривизне
  детали — это осознанное приближение (см. `DECISIONS.md`, п.14). Визуальную
  калибровку (насколько естественно ложатся мазки на реальных R6/R15 моделях)
  нужно провести в живом тесте Studio — см. `TASKS.md`.
- `GameConfig.BRUSH_STAMP_IMAGE_ID` и `GameConfig.WHISTLE_SOUND_ID` — заглушки
  `rbxassetid://0`, тем же паттерном, что раньше был у `POSE_ANIMATION_ID`
  (см. `DECISIONS.md`, п.10/14/15) — сейчас у каждого пресета позы свой
  `animationId`-заглушка в `PosePresets.lua`, см. следующий пункт. Игра не
  упадёт: присвоение невалидного `AssetId` свойству `Texture.Texture`/
  `Sound.SoundId` само по себе не бросает ошибку в Luau (в отличие от
  `Animator:LoadAnimation`, которую пришлось оборачивать в `pcall` — см. п.10),
  но мазки будут невидимы, а свисток — беззвучен, пока ассеты не загружены в
  Studio и ID не подставлены в `GameConfig.lua`.
- Все 4 `animationId` в `PosePresets.lua` — тоже заглушки `rbxassetid://0`,
  требуют 4 отдельные финальные анимации (см. `TASKS.md`).
- "Hitbox-профиль" поз реализован только через `Humanoid.HipHeight`
  (множитель от исходного значения), а не через реальную подмену формы
  коллизии — сознательное упрощение (см. `DECISIONS.md`, п.17), визуальный
  эффект нужно откалибровать в живом тесте, особенно для R6.
- Пресет "Lean" (прислониться) не делает raycast для поиска ближайшей стены и
  не ориентирует/не примагничивает персонажа к поверхности — чисто
  тематическая поза той же сложности, что и остальные три (см. `DECISIONS.md`,
  п.17). Настоящее физическое прилипание к стене — отдельная будущая задача.
- `GameMode.Current` — статическая константа, читаемая независимо клиентом и
  сервером через `require`. Работает, только пока значение не меняется в
  реальном времени после старта сервера. Если в будущем добавится
  лобби-настройка с переключением режима "на лету", потребуется отдельный
  `RemoteEvent`, чтобы сообщить клиентам актуальный режим — простая мутация
  `GameMode.Current` на сервере клиентам не реплицируется (см. `DECISIONS.md`,
  п.18).
- В режиме `Infection` `currentHiders`/`currentSeekers` в `RoundManager`
  мутируются в процессе раунда (`table.remove`/`table.insert` при переходе
  роли) — это осознанное отступление от прежнего инварианта "списки
  фиксируются на старте раунда" (см. пункт выше про вход новых игроков), но
  затрагивает только существующих участников раунда, не новых игроков.
- `PrivateRoomService` не может быть проверен вживую в Play-режиме Roblox
  Studio — `TeleportService` работает только в опубликованной игре (см.
  `DECISIONS.md`, п.20). Также остаётся редкая, сознательно не закрытая
  гонка: одновременное создание двух комнат с одинаковым паролем на разных
  серверах не атомарно (`GetAsync`+`SetAsync`, а не `UpdateAsync`) — см.
  `TASKS.md`.
- `SpectatorService` отличает "новый зритель" от "уже играющий respawn'ится"
  по `player.Team` (Hiders/Seekers ⇒ не трогать). Это работает, пока роль
  всегда назначается через `PlayerRoleService.AssignRoles`/
  `ConvertHiderToSeeker` до того, как персонаж может пересоздаться — если в
  будущем появится способ оказаться Hider/Seeker без назначенной команды
  (маловероятно при нынешней архитектуре), эту проверку нужно будет
  расширить.
- Числа `MISSED_POINT_MAX_DISTANCE`/`MISSED_POINT_PER_TICK`/
  `SURVIVAL_BONUS_POINTS` (см. `DECISIONS.md`, п.22) подобраны на бумаге,
  без живого плейтеста — баланс между очками за поимку/выживание и
  очками Missed Point Ranking не проверен вживую, см. `TASKS.md`, Раздел 0.8.
- Живой тест через Roblox Studio MCP (см. `TASKS.md`, Раздел 1, "Live Test
  Findings") не проведён — сессия Claude Code, в которой писался этот код,
  выполняется в изолированном облачном контейнере без доступа к
  десктопным GUI-приложениям, поэтому Roblox Studio физически не может
  быть запущен из неё, вне зависимости от наличия MCP-плагина. Всё
  тестирование в этой сессии ограничено статическим анализом кода.
- Карта (`MapBuilder.lua`, см. "Карта" выше и `DECISIONS.md`, п.23)
  собрана и не откалибрована визуально: координаты стен/проёмов/мебели
  подобраны на бумаге, без живого теста в Studio. Возможны мелкие огрехи
  геометрии (нахлёст/зазор в 0.5 стада на стыках стен и полов) - не
  критично для игры, но стоит перепроверить визуально при первом реальном
  подключении к Studio.
