-- CatchClient.lua
-- Прячет от Hiders подсказку "Поймать" над другими Hiders (см. DECISIONS.md, п.12).
-- Сервер шлёт этот RemoteEvent только клиентам-Hiders (CatchService.StartSeekingPhase),
-- поэтому Seekers его не получают и видят подсказки как обычно. Изменение Enabled
-- здесь - чисто локальное для этого клиента и не влияет ни на сервер, ни на других игроков.

local CatchClient = {}

function CatchClient.Init(remotesFolder)
	local hideRemote = remotesFolder:WaitForChild("HideCatchPromptsFromHiders")

	hideRemote.OnClientEvent:Connect(function(prompts)
		for _, prompt in ipairs(prompts) do
			if prompt and prompt:IsA("ProximityPrompt") then
				prompt.Enabled = false
			end
		end
	end)
end

return CatchClient
