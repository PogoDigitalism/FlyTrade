local ReplicatedStorage = game:GetService('ReplicatedStorage')
local ServerScriptService = game:GetService('ServerScriptService')
local Players = game:GetService('Players')

local PlayerDataService = require(ServerScriptService:WaitForChild('Player'):WaitForChild('Core'):WaitForChild('PlayerDataService'))
local SignalService = require(ReplicatedStorage:WaitForChild('Signals').SignalService)
local Cooldown = require(ReplicatedStorage:WaitForChild('CooldownUtils'))

local Remotes = ReplicatedStorage:WaitForChild('RemoteEvents'):WaitForChild('Trading')

local GameSpecific = require(script.GameSpecific)

local Trade = {}
Trade.__index = Trade

setmetatable(
	Trade,
	GameSpecific
)

local Types = require(ReplicatedStorage:WaitForChild('Trading'):WaitForChild('SharedTypes'))
local Constants = require(ReplicatedStorage:WaitForChild('Trading'):WaitForChild('SharedConstants'))

export type tradeStage = "init" | "ready" | "confirm" | "counting_down" | "pending" | "completed" | "cancelled"
export type offerType = {
	asset: string,
	type: Types.TradableType
}

local stage_order = {
	"init",
	"ready",
	"confirm",
	"counting_down",
	"pending", -- TODO if at this stage; cancel is not possible
	"completed",
}

local thread_calls = {
	ready = "readyCountdown",
	confirm = "confirmCountdown"
}

function Trade.Invokable(instigator: Player, buddy: Player): boolean
	local player_data = PlayerDataService.GetPlayerDataInstance(buddy)
	local trade_settings = player_data:GetTradeSettings()
	
	local is_friend = buddy:IsFriendsWith(instigator.UserId)

	if trade_settings.request == "public" then 
		return true
	elseif trade_settings.request == "friends" and is_friend then
		return true
	end
	return false
end

function Trade.getOpponent(role: Types.Role): Types.Role
	if role == "buddy" then
		return "instigator"
	else
		return "buddy"
	end
end

function Trade.new(instigator: Player)
	local self = {}
	setmetatable(self, Trade)
	-- public vars
	self.instigator = instigator
	self.instigator_data = PlayerDataService.GetPlayerDataInstance(instigator)
	
	self.buddy = nil :: Player
	self.buddy_data = nil
	
	self.locked = false
	self.cooldown = Cooldown.new(3)
	
	self.role_data = {
		["instigator"] = self.instigator_data,
		["buddy"] = {},
	}
	
	self.stage = "init" :: tradeStage
	
	self.offers = {
		["instigator"] = {},
		["buddy"] = {},
	} :: {
		instigator: {
			offerType
		},
		buddy: {
			offerType
		}
	}
	self.offers_value = {
		["instigator"] = 0,
		["buddy"] = 0,
	}

	self.stage_advancement = {
		["instigator"] = false,
		["buddy"] = false
	}

	setmetatable(
		self.stage_advancement,
		{}
	)

	self._countdown_thread = nil :: thread

	return self
end
export type cls = typeof(
	Trade.new(...)
)

function Trade.destroyClass(self: cls)
	self.cooldown.destroy(self)
	
	table.clear(
		self
	)
	setmetatable(
		self,
		nil
	)
	table.freeze(
		self
	)
end

function Trade.invokeTrade(self: cls, buddy: Player): boolean
	if self.stage ~= "init" then return false end
	
	local accepted = Remotes.InvokeTrade:InvokeClient(buddy)
	if typeof(accepted) ~= 'boolean' then return false end
	
	self.buddy = buddy
	self.buddy_data = PlayerDataService.GetPlayerDataInstance(buddy)
	if not accepted or not self.buddy_data.data_loaded then 
		self:destroyClass()
		return false
	end
	self.role_data.buddy = self.buddy_data

	self.stage =  "ready"
	
	--Remotes.InvokeAccepted:FireClient(
	--	self.instigator
	--)

	return true
end

function Trade.involvedPlayers(self: cls): (Player, Player)
	return self.instigator, self.buddy
end


function Trade.getRole(self: cls, player: Player)
	if player == self.instigator then
		return "instigator"
	else
		return "buddy"
	end
end

function Trade._ownsAssets(self: cls): boolean
	-- TODO do asset ownership check
	for role, offers in self.offers do
		local player_data = self.role_data.instigator -- TODO change (intellisense)

		for index, offer: offerType in offers do
			local owns = self.hasAsset(player_data, offer.asset, offer.type)
			if not owns then return false end
		end
	end
	return true
end

function Trade._clearAdvancement(self: cls)
	self.stage_advancement = {
		instigator = false,
		buddy = false
	}
end

function Trade._completeTrade(self: cls): boolean
	if not self:_ownsAssets() then
		Remotes.AssetOwnershipChanged:FireClient(
			self.instigator,
			true -- trade cancelled
		)
		Remotes.AssetOwnershipChanged:FireClient(
			self.buddy,
			true -- trade cancelled
		)

		return false
	end
	-- remote items first
	local offers_copy = self.offers
	for role, offers in self.offers do
		local player_data = self.role_data.instigator -- TODO change (intellisense)
		
		for index, offer: offerType in offers do
			self.removeAsset(player_data, offer.asset, offer.type)
		end
	end
	
	-- insert from other side
	-- TODO remove units and items from both sides, then insert them
	
	-- TODO add player statistics/trading history
end

function Trade._finalize(self: cls)
	-- TODO clear Trade class, cleanup etc
end


function Trade.readyCountdown(self: cls)
	self.stage = "counting_down"

	self:_clearAdvancement()
	self.stage = "confirm" 
end
function Trade.confirmCountdown(self: cls)
	self.stage = "counting_down"

	task.wait(
		Constants.COMPLETE_TRADE_TIME
	)

	self:_clearAdvancement()
	self.stage = "pending"
	
	task.wait(
		Constants.CONFIRMATION_WAIT_TIME
	)
	
	self:_completeTrade()
	self.stage = "completed"
end


function Trade.submitAdvance(self: cls, role: Types.Role): boolean
	self.stage_advancement[role] = true
	
	if self.stage_advancement.instigator and self.stage_advancement.buddy then
		if not self:_ownsAssets() then
			local opponent = self.getOpponent(role)
			Remotes.AssetOwnershipChanged:FireClient(
				self[opponent],
				false -- trade cancelled
			)

			return false 
		end
		
		self._countdown_thread = coroutine.create(
			self[thread_calls[self.stage]]
		)
		coroutine.resume(
			self._countdown_thread,
			self
		)
	end

	local opponent = self.getOpponent(role)
	Remotes.AdvanceSubmitted:FireClient(
		self[opponent]
	)
	
	return true
end
function Trade.cancelAdvance(self: cls, role: Types.Role): boolean
	self.stage_advancement[role] = false
	
	if self._countdown_thread then
		coroutine.close(
			self._countdown_thread
		)
		self._countdown_thread = nil
		
		local opponent = self.getOpponent(role)
		Remotes.AdvanceCancelled:FireClient(
			self[opponent]
		)

		return true
	end
	return false
end

function Trade.cancelTrade(self: cls): boolean
	if table.find(stage_order, self.stage) > 4 then
		return false
	end

	if self._countdown_thread then
		coroutine.close(
			self._countdown_thread
		)
		self._countdown_thread = nil
	end
	self:destroyClass()
	-- TODO CLEAN UP HERE
	
	return true
end

function Trade.addToOffer(self: cls, role: Types.Role, asset: string): boolean
	if not self.cooldown:check(self.instigator) then return false end
	self.locked = false
	
	if self.stage ~= "ready" then return false end
	if #self.offers[role] >= Constants.MAX_OFFERS then return false end
	
	-- TODO playerdata ownership checks
	
	if not self:canAdd(role, asset) then return false end
	
	local asset_type = self:findAssetType(asset)
	local asset_value = self:calcAssetValue(asset, asset_type)
	
	local offer = {
		asset = asset,
		type = asset_type
	}
	
	table.insert(
		self.offers[role],
		offer
	)
	self.offers_value[role] += asset_value
	

	local opponent = self.getOpponent(role)
	Remotes.AssetAdded:FireClient(
		self[opponent],
		offer
	)
	
	self.cooldown:apply(
		self.instigator
	)
	self.locked = true
	
	return true
end
function Trade.removefromOffer(self: cls, role: Types.Role, asset: string): boolean
	if self.stage ~= "ready" then return false end

	local asset_type = self:findAssetType(asset)
	local asset_value = self:calcAssetValue(asset, asset_type)

	for index, offer in self.offers[role] do
		if offer.asset == asset then
			table.remove(
				self.offers[role],
				index
			)
			self.offers_value[role] -= asset_value
			
			self.cooldown:apply(
				self.instigator
			)
			self.locked = true
			
			local opponent = self.getOpponent(role)
			Remotes.AssetRemoved:FireClient(
				self[opponent],
				offer
			)

			return true
		end
	end
	return false
end

return Trade
