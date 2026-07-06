-- Main.client.lua
-- Точка входа клиентских скриптов. Строит весь UI и подключает обработчики.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local player = Players.LocalPlayer

local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")

local PaintClient = require(script.Parent.PaintClient)
local FreezeClient = require(script.Parent.FreezeClient)
local RoundUIClient = require(script.Parent.RoundUIClient)
local CatchClient = require(script.Parent.CatchClient)
local WhistleClient = require(script.Parent.WhistleClient)
local LobbyUIClient = require(script.Parent.LobbyUIClient)
local SpectatorClient = require(script.Parent.SpectatorClient)

-- Порядок важен: PaintClient создаёт основной ScreenGui "PaintGui" первым,
-- остальные модули добавляют свои элементы в него же (см. WaitForChild("PaintGui") внутри них).
PaintClient.Init(remotesFolder)
FreezeClient.Init(remotesFolder)
RoundUIClient.Init(remotesFolder)
CatchClient.Init(remotesFolder)
WhistleClient.Init(remotesFolder)
LobbyUIClient.Init(remotesFolder)
SpectatorClient.Init(remotesFolder)

print("[MecchaChameleon] Клиент запущен для игрока " .. player.Name)
