-- Main.server.lua
-- Точка входа серверной логики. Запускает по очереди все серверные модули.
-- Ничего руками менять тут не нужно - если хочешь настроить баланс игры,
-- смотри ReplicatedStorage/Modules/GameConfig.lua.

local RemotesSetup = require(script.Parent.RemotesSetup)
local remotes = RemotesSetup.Init()

local PlayerRoleService = require(script.Parent.PlayerRoleService)
local PaintService = require(script.Parent.PaintService)
local FreezeService = require(script.Parent.FreezeService)
local CatchService = require(script.Parent.CatchService)
local ScoreService = require(script.Parent.ScoreService)
local RoundManager = require(script.Parent.RoundManager)

PlayerRoleService.Init()
PaintService.Init(remotes)
FreezeService.Init(remotes, PaintService)
ScoreService.Init()
CatchService.Init(remotes, ScoreService)

RoundManager.Init(remotes, {
	PlayerRoleService = PlayerRoleService,
	PaintService = PaintService,
	FreezeService = FreezeService,
	CatchService = CatchService,
	ScoreService = ScoreService,
})

RoundManager.Start()

print("[MecchaChameleon] Сервер инициализирован, игра запущена.")
