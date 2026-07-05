# ARCHITECTURE

Документ описывает **реальную текущую** архитектуру проекта (как оно есть в
коде на ветке `claude/meccha-chameleon-roblox-jvepyg`), а не идеальный план.
Составлен в ходе ревью Opus (2026-07-05), обновлён после внедрения фиксов из
аудита (line-of-sight поимка, скрытие подсказок от Hiders, гейтинг позы) и
после пересмотра механики покраски на рисование кистью + добавления свистка
(оба — 2026-07-05). Обновлять при изменении контрактов (RemoteEvents,
состояние игрока, фазы раунда).

## Общая схема

Сервер — источник истины. Клиент только отправляет "запросы" (покрасить, встать
в позу) и отрисовывает UI по событиям сервера. Вся логика раунда — на сервере.

```
КЛИЕНТ (StarterPlayerScripts)              СЕРВЕР (ServerScriptService)
------------------------------             ----------------------------
Main.client ─ инициализирует:              Main.server ─ инициализирует:
  PaintClient   ──PaintStroke───────────►    PaintService ──require──► RoundManager (для проверки фазы)
  FreezeClient  ──RequestFreeze─────────►    FreezeService ──require──► RoundManager (для проверки фазы)
  RoundUIClient ◄─RoundStateChanged─────     RoundManager  (главный автомат)
                ◄─RoundTimerTick───────      PlayerRoleService
                ◄─PlayerCaught────────       CatchService (ProximityPrompt + серверные
  CatchClient   ◄─HideCatchPromptsFromHiders  дистанция/line-of-sight проверки)
  PaintClient   ◄─InkUpdate─────────────      PaintService (мазки-Texture, см. DECISIONS 14)
  WhistleClient ──RequestWhistle────────►    WhistleService (Sound + RollOff, см. DECISIONS 15)
  WhistleClient ◄─WhistleCountdownUpdate      ScoreService
```

Общий модуль `ReplicatedStorage/Modules/BrushGeometry.lua` используется и
клиентом (`PaintClient`, чтобы понять, куда мазнул игрок), и сервером
(`PaintService`, чтобы честно разместить мазок по присланным координатам) —
единая математика face/UV, без дублирования и риска рассинхронизации.

## RemoteEvents

Все создаются кодом при старте сервера в `ReplicatedStorage/Remotes/`
(`RemotesSetup.lua`). Направление и параметры:

| Событие | Направление | Параметры | Описание |
|---|---|---|---|
| `PaintStroke` | клиент → сервер | `points: {{partName: string, face: Enum.NormalId, u: number, v: number}}`, `color: Color3`, `brushSize: number` | Пакет точек мазка кисти, отправляется раз в ~0.15с при рисовании (не по одной точке за раз). Сервер валидирует роль/фазу/заморозку/чернила и сам создаёт `Texture`-мазки, см. `DECISIONS.md`, п.14. |
| `RequestFreeze` | клиент → сервер | `wantsFreeze: boolean` | Запрос встать в позу / выйти из позы. |
| `RoundStateChanged` | сервер → все клиенты | `state: string`, `timeLeft: number`, `extra: table` | Смена фазы. `state` ∈ {Lobby, Hiding, Seeking, RoundEnd}. `extra` может содержать `results`, `playersNeeded`, `playersCurrent`. |
| `RoundTimerTick` | сервер → все клиенты | `remaining: number` | Тик таймера текущей фазы (раз в секунду). |
| `PlayerCaught` | сервер → все клиенты | `hiderName: string`, `seekerName: string`, `remaining: number` | Кого-то поймали + сколько осталось. |
| `RoundResults` | сервер → все клиенты | `results: table` | Итоги раунда (тот же формат, что в `RoundStateChanged` extra.results). |
| `InkUpdate` | сервер → **один** клиент | `amount: number`, `maxAmount: number` | Обновление количества "чернил" кисти конкретного игрока (замена прежних дискретных "зарядов", см. `DECISIONS.md`, п.14). |
| `HideCatchPromptsFromHiders` | сервер → **только Hiders**, персонально каждому | `prompts: {ProximityPrompt}` | Список всех активных промптов поимки за раунд; клиент локально ставит им `Enabled = false`, чтобы Hiders не видели, где стоят другие Hiders (см. `DECISIONS.md`, п.12). Seekers это событие не получают. |
| `RequestWhistle` | клиент → сервер | (без параметров) | Hider просит свистнуть прямо сейчас. Сервер проверяет роль/фазу/не пойман ли, сбрасывает таймер и проигрывает звук, см. `DECISIONS.md`, п.15. |
| `WhistleCountdownUpdate` | сервер → **только Hiders**, персонально каждому | `secondsLeft: number` | Сколько секунд осталось до следующего (авто- или уже сброшенного) свистка. |

RemoteFunctions в проекте **не используются** (всё построено на односторонних
событиях — так проще и безопаснее).

Формат одной записи в `results`:
```lua
{ name = "PlayerName", role = "Hider" | "Seeker", roundScore = 42, totalScore = 137 }
```

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
| `FreezeService` | `savedLocomotion[player] = {walkSpeed, jumpPower, jumpHeight}` | исходные параметры движения, чтобы вернуть после позы |
| `CatchService` | `foundState[player] = bool` | найден ли этот Hider (только участники текущего раунда) |
| `CatchService` | `activePrompts[player] = ProximityPrompt` | висящий на игроке промпт поимки (`ActionText = "Поймать"`, без имени, `RequiresLineOfSight = true`) |
| `ScoreService` | `totalScores[player] = number` | очки за всю сессию сервера |
| `ScoreService` | `roundScores[player] = number` | очки за текущий раунд |
| `ScoreService` | `roundStartTimes[player] = tick()` | когда для Hider началась фаза поиска |
| `WhistleService` | `nextWhistleAt[player] = tick()` | когда сработает следующий свисток этого Hider |
| `WhistleService` | `whistleSounds[player] = Sound` | переиспользуемый звук свистка (создаётся один раз) |
| `RoundManager` | `currentHiders`, `currentSeekers` | списки игроков по ролям в текущем раунде |
| `PlayerRoleService` | Teams | роль игрока хранится штатно в `player.Team` |

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
        │                                             │
        ▼                                             │
  [ Hiding ]  HIDING_PHASE_DURATION сек               │
     • Seekers → SeekerWaitingRoom, WalkSpeed=0       │
     • Hiders: чернила и мазки прошлого раунда стёрты  │
       (PaintService.ResetForNewRound), рисование разрешено│
        │                                             │
        ▼                                             │
  [ Seeking ]  SEEKING_PHASE_DURATION сек             │
     • Seekers освобождены                            │
     • Hiders: рисование запрещено, поза не переключается│
     • на Hiders повешены ProximityPrompt (видны только │
       Seekers, требуют line-of-sight - см. DECISIONS 12)│
     • у каждого Hider тикает таймер свистка - авто через │
       WHISTLE_AUTO_INTERVAL_SECONDS или вручную (DECISIONS 15)│
     • досрочный выход, если пойманы все (OnAllCaught)│
        │                                             │
        ▼                                             │
  [ RoundEnd ]  ROUND_END_DISPLAY_DURATION сек        │
     • снять позы, начислить очки выжившим            │
     • собрать и разослать results                    │
     • всех → Spectators                              │
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
  реагируют на вход новых игроков посреди раунда (новые ждут следующего). Это
  ожидаемое поведение MVP.
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
  `rbxassetid://0`, как и `POSE_ANIMATION_ID` (см. `DECISIONS.md`, п.10/14/15).
  Игра не упадёт: присвоение невалидного `AssetId` свойству `Texture.Texture`/
  `Sound.SoundId` само по себе не бросает ошибку в Luau (в отличие от
  `Animator:LoadAnimation`, которую пришлось оборачивать в `pcall` — см. п.10),
  но мазки будут невидимы, а свисток — беззвучен, пока ассеты не загружены в
  Studio и ID не подставлены в `GameConfig.lua`.
