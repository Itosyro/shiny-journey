# ARCHITECTURE

Документ описывает **реальную текущую** архитектуру проекта (как оно есть в
коде на ветке `claude/meccha-chameleon-roblox-jvepyg`), а не идеальный план.
Составлен в ходе ревью Opus (2026-07-05). Обновлять при изменении контрактов
(RemoteEvents, состояние игрока, фазы раунда).

## Общая схема

Сервер — источник истины. Клиент только отправляет "запросы" (покрасить, встать
в позу) и отрисовывает UI по событиям сервера. Вся логика раунда — на сервере.

```
КЛИЕНТ (StarterPlayerScripts)              СЕРВЕР (ServerScriptService)
------------------------------             ----------------------------
Main.client ─ инициализирует:              Main.server ─ инициализирует:
  PaintClient   ──PaintCharacter────────►    PaintService
  FreezeClient  ──RequestFreeze─────────►    FreezeService
  RoundUIClient ◄─RoundStateChanged─────     RoundManager  (главный автомат)
                ◄─RoundTimerTick───────      PlayerRoleService
                ◄─PlayerCaught────────       CatchService (ProximityPrompt)
                ◄─RoundResults───────        ScoreService
  PaintClient   ◄─BrushChargesUpdate───      PaintService
```

## RemoteEvents

Все создаются кодом при старте сервера в `ReplicatedStorage/Remotes/`
(`RemotesSetup.lua`). Направление и параметры:

| Событие | Направление | Параметры | Описание |
|---|---|---|---|
| `PaintCharacter` | клиент → сервер | `partName: string`, `color: Color3` | Запрос покрасить часть тела. Сервер валидирует часть, цвет, заряды, блокировку. |
| `RequestFreeze` | клиент → сервер | `wantsFreeze: boolean` | Запрос встать в позу / выйти из позы. |
| `RoundStateChanged` | сервер → все клиенты | `state: string`, `timeLeft: number`, `extra: table` | Смена фазы. `state` ∈ {Lobby, Hiding, Seeking, RoundEnd}. `extra` может содержать `results`, `playersNeeded`, `playersCurrent`. |
| `RoundTimerTick` | сервер → все клиенты | `remaining: number` | Тик таймера текущей фазы (раз в секунду). |
| `PlayerCaught` | сервер → все клиенты | `hiderName: string`, `seekerName: string`, `remaining: number` | Кого-то поймали + сколько осталось. |
| `RoundResults` | сервер → все клиенты | `results: table` | Итоги раунда (тот же формат, что в `RoundStateChanged` extra.results). |
| `BrushChargesUpdate` | сервер → **один** клиент | `charges: number`, `maxCharges: number` | Обновление зарядов краски конкретного игрока. |

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
| `PaintService` | `brushData[player] = { charges }` | текущие заряды краски |
| `PaintService` | `paintingBlocked[player] = bool` | запрещена ли покраска (поза / фаза поиска) |
| `FreezeService` | `frozenState[player] = bool` | стоит ли игрок в позе |
| `FreezeService` | `savedLocomotion[player] = {walkSpeed, jumpPower, jumpHeight}` | исходные параметры движения, чтобы вернуть после позы |
| `CatchService` | `foundState[player] = bool` | найден ли этот Hider (только участники текущего раунда) |
| `CatchService` | `activePrompts[player] = ProximityPrompt` | висящий на игроке промпт поимки |
| `ScoreService` | `totalScores[player] = number` | очки за всю сессию сервера |
| `ScoreService` | `roundScores[player] = number` | очки за текущий раунд |
| `ScoreService` | `roundStartTimes[player] = tick()` | когда для Hider началась фаза поиска |
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
     • Hiders: сброс зарядов, покраска разрешена      │
        │                                             │
        ▼                                             │
  [ Seeking ]  SEEKING_PHASE_DURATION сек             │
     • Seekers освобождены                            │
     • Hiders: покраска запрещена                     │
     • на Hiders повешены ProximityPrompt             │
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
- Роль/фаза не проверяются в `FreezeService` (любой может встать в позу в любой
  момент) — см. TASKS.md, раздел "Полировка MVP".
