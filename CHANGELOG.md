# CHANGELOG

Журнал изменений по датам. Ведётся, чтобы можно было продолжить работу в
любой новой сессии (или с другой нейросетью) без потери контекста.

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
