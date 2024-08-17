-- actual implementations are left out due to security reasons

local players = game:GetService('Players')
local rs = game:GetService('ReplicatedStorage')
local ss = game:GetService('ServerStorage')
local sss = game:GetService('ServerScriptService')
local HTTPS = game:GetService('HttpService')
local textservice = game:GetService('TextService')

local PlayerDataService = require(sss:WaitForChild('Player').Core.PlayerDataService)
local RequestLimiter = require(sss:WaitForChild('RequestLimiter'))
local SignalService = require(rs:WaitForChild('Signals').SignalService)

local Remote = rs:WaitForChild('RemoteEvents'):WaitForChild('Trading')
local TradeClass = require(script.Parent.Parent.Lib.TradeClass)

local Types = require(rs:WaitForChild('Trading'):WaitForChild('SharedTypes'))
local Constants = require(rs:WaitForChild('Trading'):WaitForChild('SharedConstants'))

local request_limiter = RequestLimiter.new(6, 2, 0, "clientinvokes trading")
request_limiter:capReachedSignal(SignalService.RemoteCalls__Capped)
request_limiter:enableKick(4)

local cancel_request_limiter = RequestLimiter.new(3, 1, 0, "clientinvokes trading")
cancel_request_limiter:capReachedSignal(SignalService.RemoteCalls__Capped)
cancel_request_limiter:enableKick(2)

local item_change_limiter = RequestLimiter.new(12, 12, 0, "clientinvokes trading")
item_change_limiter:capReachedSignal(SignalService.RemoteCalls__Capped)
item_change_limiter:enableKick(4)

local message_limiter = RequestLimiter.new(5, 2, 0, "clientinvokes trading")
message_limiter:capReachedSignal(SignalService.RemoteCalls__Capped)
message_limiter:enableKick(8)

local settings_request_limiter = RequestLimiter.new(4, 2, 0, "clientinvokes trading")
settings_request_limiter:capReachedSignal(SignalService.RemoteCalls__Capped)
settings_request_limiter:enableKick(4)

local trade_list_limiter = RequestLimiter.new(14, 5, 0, "clientinvokes trading")
trade_list_limiter:capReachedSignal(SignalService.RemoteCalls__Capped)
trade_list_limiter:enableKick(4)

local thumbnail_limiter = RequestLimiter.new(5, 2, 0, "clientinvokes trading")
thumbnail_limiter:capReachedSignal(SignalService.RemoteCalls__Capped)
thumbnail_limiter:enableKick(4)

local function isValidSettingValue(value, valid_values: {})
	return valid_values[value] ~= nil
end

function SendChat(p: Player, msg: string)
	
end
Remote.SendChat.OnServerInvoke = SendChat 


function InvokeTrade(instigator: Player, buddy_id: number)

end
Remote.InvokeTrade.OnServerInvoke = InvokeTrade 

function CancelTrade(player: Player)
	
end
Remote.CancelTrade.OnServerInvoke = CancelTrade

function AddToOffer(player: Player, asset: string)
	
end
Remote.AddToOffer.OnServerInvoke = AddToOffer 

function RemoveFromOffer(player: Player, asset: string)
	
end
Remote.RemoveFromOffer.OnServerInvoke = RemoveFromOffer

function AdvanceTrade(player: Player)

end
Remote.AdvanceTrade.OnServerInvoke = AdvanceTrade

function CancelAdvancement(player: Player)

end
Remote.CancelAdvancement.OnServerInvoke = CancelAdvancement

function GetTradeSettingsForPlayer(p: Player, buddy: Player)
	
end
Remote.GetTradeSettingsForPlayer.OnServerInvoke = GetTradeSettingsForPlayer

function GetTradeList(p: Player)

end
Remote.GetTradeList.OnServerInvoke = GetTradeList

local valid_setting_values = {
	none = true,
	public = true,
	friends = true
}
function SetTradeSettings(p: Player, trade_settings: {
	request: SettingValue,
	inventory: SettingValue
	})
	if type(trade_settings) ~= "table" then return end
	
	
end
Remote.GetTradeList.OnServerInvoke = GetTradeList


local headshot_url = "https://thumbnails.roproxy.com/v1/users/avatar-headshot?userIds=%s&size=100x100&format=Png&isCircular=false"
local thumbnail_cache: {[number]: string} = {
	
}
function GetPlayerThumbnails(p: Player, users : {number}): {[number]: string}
	
end
Remote.GetPlayerThumbnails.OnServerInvoke = GetPlayerThumbnails
