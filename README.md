# MECCHA CHAMELEON Clone (Roblox)

Клон механик Steam-игры [MECCHA CHAMELEON](https://store.steampowered.com/app/4704690/MECCHA_CHAMELEON)
на движке Roblox: прятки + рисование.

## Суть игры

Игроки делятся на две команды:

- **Hiders (прячущиеся)** — стартуют полностью белыми. Их задача: покрасить
  своё тело под цвета и текстуры окружения (стены, пол, мебель), а затем
  замереть в позе, имитируя часть интерьера.
- **Seekers (искатели)** — ищут всех Hiders до конца таймера раунда.

Побеждают Seekers, если находят всех. Побеждают Hiders, если хотя бы один
остался не найден. Игра рассчитана на публичные лобби от 2 до 10 игроков.

## Как это устроено (кратко)

1. **Лобби** — ждём, пока наберётся минимум игроков, идёт обратный отсчёт.
2. **Фаза пряток (Hiding)** — Hiders красятся и занимают позу, Seekers ждут в
   отдельной комнате.
3. **Фаза поиска (Seeking)** — Seekers выпускают, они ищут Hiders до конца
   таймера или пока не найдут всех.
4. **Итоги раунда** — начисляются очки, показывается экран результатов, игра
   возвращается в лобби.

Подробное техническое описание решений — в `DECISIONS.md`. Прогресс и этапы —
в `ROADMAP.md` и `TASKS.md`.

## Структура проекта

```
CLAUDE.md            — правила работы над проектом (для ИИ-ассистента)
README.md            — этот файл
ROADMAP.md           — этапы разработки (MVP → Альфа → Бета → Полировка)
TASKS.md             — список задач To Do / In Progress / Done
CHANGELOG.md         — журнал изменений по датам
DECISIONS.md         — архитектурные решения с обоснованием
default.project.json — конфиг Rojo (описывает, куда какие файлы попадают в Roblox)

src/
├── ReplicatedStorage/
│   └── Modules/
│       ├── GameConfig.lua     — все настройки баланса игры в одном месте
│       └── PaletteData.lua    — список цветов для UI-палитры
│
├── ServerScriptService/       — вся серверная логика (ModuleScript, кроме Main)
│   ├── Main.server.lua         — точка входа сервера, запускает все сервисы
│   ├── RemotesSetup.lua        — создаёт RemoteEvent для связи клиент↔сервер
│   ├── PlayerRoleService.lua   — команды (Teams) и распределение ролей
│   ├── PaintService.lua        — проверка и применение покраски
│   ├── FreezeService.lua       — заморозка / поза
│   ├── CatchService.lua        — обнаружение (поимка) через ProximityPrompt
│   ├── ScoreService.lua        — подсчёт очков
│   └── RoundManager.lua        — главный автомат состояний раунда
│
└── StarterPlayer/
    └── StarterPlayerScripts/  — весь клиентский код (LocalScript + ModuleScript)
        ├── Main.client.lua      — точка входа клиента
        ├── PaintClient.lua      — палитра, пипетка, отправка покраски на сервер
        ├── FreezeClient.lua     — кнопка заморозки/позы
        ├── RoundUIClient.lua    — HUD (фаза, таймер, роль) и экран результатов
        └── UI/
            ├── PaletteUIBuilder.lua   — строит UI палитры цветов кодом
            ├── HUDBuilder.lua         — строит верхнюю панель HUD кодом
            └── ResultsUIBuilder.lua   — строит экран итогов раунда кодом
```

Все GUI-элементы создаются кодом (`Instance.new`) прямо в LocalScript, а не
собираются вручную в Studio — так весь интерфейс версионируется в Git вместе с
остальным кодом.

## Как перенести проект в Roblox Studio

**Вариант А — через Rojo (рекомендуется):**

1. Установи [Rojo](https://rojo.space/) — плагин для Roblox Studio (ищется в
   Toolbox как "Rojo") и command-line инструмент (по инструкции с сайта rojo.space).
2. В папке проекта выполни `rojo serve` (это делает Claude или тот, у кого
   настроен терминал).
3. В Studio открой плагин Rojo → Connect. Файлы из `src/` появятся в дереве
   игры в нужных сервисах автоматически, согласно `default.project.json`.

**Вариант Б — вручную (без Rojo):**

1. Открой каждый `.lua` файл из `src/...` и скопируй его содержимое.
2. В Studio создай Script/LocalScript/ModuleScript с таким же именем в
   соответствующем сервисе (см. таблицу ниже) и вставь код.

| Расширение файла | Тип объекта в Studio | Где создавать |
|---|---|---|
| `*.server.lua` | `Script` | ServerScriptService |
| `*.client.lua` | `LocalScript` | StarterPlayer → StarterPlayerScripts |
| `*.lua` (без суффикса) | `ModuleScript` | там же, где лежит в `src/` |

## Что нужно вручную настроить в самой карте (Workspace)

- Part с именем **`SeekerWaitingRoom`** — "комната ожидания" для Seekers на
  время фазы пряток (искателей туда телепортирует сервер).
- Реальный **Animation ID** позы вместо заглушки `rbxassetid://0` в
  `GameConfig.POSE_ANIMATION_ID` — загрузи анимацию через Studio и подставь ID.
- Локация с разнообразными цветами/текстурами для покраски (стены, мебель,
  декорации) — чем разнообразнее, тем интереснее играть в пипетку.

## Требования к количеству игроков

От 2 до 10 игроков на сервер (см. `GameConfig.MIN_PLAYERS_TO_START` и
`GameConfig.MAX_PLAYERS`). Ограничение `MAX_PLAYERS` дополнительно нужно
продублировать в настройках места (Place) в Studio через `MaxPlayers`.
