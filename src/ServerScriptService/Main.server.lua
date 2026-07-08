-- Main.server.lua
-- Точка входа серверной логики. Запускает по очереди все серверные модули.
-- Ничего руками менять тут не нужно - если хочешь настроить баланс игры,
-- смотри ReplicatedStorage/Modules/GameConfig.lua.

-- Отключаем каталожную косметику (одежда/шапки/лица) средствами платформы,
-- а не кодом-костылём - см. MEGA_PLAN.md, Часть 2. Должно выполниться ДО
-- первого спавна любого игрока, поэтому это самая первая строка файла.
game:GetService("StarterPlayer").LoadCharacterAppearance = false

local MapBuilder = require(script.Parent.MapBuilder)
MapBuilder.Build()

local RemotesSetup = require(script.Parent.RemotesSetup)
local remotes = RemotesSetup.Init()

local PlayerRoleService = require(script.Parent.PlayerRoleService)
local PaintService = require(script.Parent.PaintService)
local FreezeService = require(script.Parent.FreezeService)
local CatchService = require(script.Parent.CatchService)
local ScoreService = require(script.Parent.ScoreService)
local WhistleService = require(script.Parent.WhistleService)
local PrivateRoomService = require(script.Parent.PrivateRoomService)
local SpectatorService = require(script.Parent.SpectatorService)
local CharacterStyleService = require(script.Parent.CharacterStyleService)
local RoundManager = require(script.Parent.RoundManager)

PlayerRoleService.Init()
PaintService.Init(remotes)
FreezeService.Init(remotes, PaintService)
ScoreService.Init(remotes)
CatchService.Init(remotes, ScoreService)
WhistleService.Init(remotes, CatchService)
PrivateRoomService.Init(remotes)
SpectatorService.Init(remotes, PlayerRoleService)
CharacterStyleService.Init()

RoundManager.Init(remotes, {
	PlayerRoleService = PlayerRoleService,
	PaintService = PaintService,
	FreezeService = FreezeService,
	CatchService = CatchService,
	ScoreService = ScoreService,
	WhistleService = WhistleService,
	SpectatorService = SpectatorService,
})

RoundManager.Start()

print("[MecchaChameleon] Сервер инициализирован, игра запущена.")
