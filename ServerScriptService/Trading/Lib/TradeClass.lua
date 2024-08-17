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

export type tradeStage = "init" | "ready" | "ready_counting_down" | "confirm" | "confirm_counting_down" | "pending" | "completed" | "cancelled"
export type offerType = {
	asset: string,
	type: Types.TradableType
}

local stage_order = {
	"init",
	"ready",
	"ready_counting_down",
	"confirm",
	"confirm_counting_down",
	"pending",
	"completed",
}
local advance_cancel_resets = {
	"ready",
	"confirm"
}

local thread_calls = {
	ready = "readyCountdown",
	confirm = "confirmCountdown"
}

Trade.active_trades = {
	
}
function Trade.unregisterTrade(ID: number)
	for i, trade in Trade.active_trades do
		if trade.ID == ID then
			table.remove(
				Trade.active_trades,
				i
			)
			break
		end
	end
end

function Trade.unregisterPlayerTrades(player: Player, exception_ID: number?)
	for i, trade in Trade.active_trades do
		local p1, p2 = trade:involvedPlayers()
		if not (exception_ID and trade.ID == exception_ID) and (p1 == player or p2 == player) then
			trade:destroyClass()
		end
	end
end

Trade.ID = 0

function Trade.GetTradesOverview()
	warn("-----------------")
	local count = 0
	for _, trade in Trade.active_trades do
		count += 1
		print(trade.ID, "|", trade.stage, "|" ,trade:involvedPlayers())
	end
	warn("-----------------")
end

function Trade.GetTrades(player: Player)
	local trades = {}
	for _, trade in Trade.active_trades do
		local p1, p2 = trade:involvedPlayers()
		if p1 == player or p2 == player then
			table.insert(
				trades,
				trade
			)
		end
	end
	
	return trades
end

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
	Trade.ID += 1
	
	local self = {}
	setmetatable(self, Trade)
	-- public vars
	self.ID = Trade.ID
	
	self.instigator = instigator
	self.instigator_data = PlayerDataService.GetPlayerDataInstance(instigator)
	
	self.buddy = nil :: Player
	self.buddy_data = nil
	
	self.in_progress = false
	self.locked = false
	self.closed = false

	self.cooldown = Cooldown.new(
		3,
		function()
			self.locked = false
		end
	)
	
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

	table.insert(
		Trade.active_trades,
		self
	)
	return self
end
export type cls = typeof(
	Trade.new(...)
)

function Trade.destroyClass(self: cls)
	Trade.unregisterTrade(self.ID)
	
	self.in_progress = false
	self.closed = true
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
	
	local accepted = Remotes.InvokeTrade:InvokeClient(buddy, self.instigator.UserId)
	if typeof(accepted) ~= 'boolean' then return false, 500 end

	local buddy_trades = Trade.GetTrades(buddy)
	for _, trade in buddy_trades do
		if trade.in_progress then
			return false, 410
		end
	end
	local instigator_trades = Trade.GetTrades(self.instigator)
	for _, trade in instigator_trades do
		if trade.in_progress then
			return false, 410
		end
	end

	if self.closed then
		Remotes.TradeCancelled:FireClient(buddy)
		return false, 500
	end

	Trade.unregisterPlayerTrades(
		buddy,
		self.ID
	)
	Trade.unregisterPlayerTrades(
		self.instigator,
		self.ID
	)
	
	self.buddy = buddy
	self.buddy_data = PlayerDataService.GetPlayerDataInstance(buddy)
	if not accepted or not self.buddy_data.data_loaded then 
		self:destroyClass()
		return false, 411
	end
	self.role_data.buddy = self.buddy_data
	
	self.in_progress = true
	self.stage =  "ready"
	
	--Remotes.InvokeAccepted:FireClient(
	--	self.instigator
	--)

	return true, 200
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

function Trade._clearOffers(self: cls)
	table.clear(
		self.offers.buddy
	)
	table.clear(
		self.offers.instigator
	)
	self.offers_value.buddy = 0
	self.offers_value.instigator = 0
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

		self.stage = "cancelled"
		self:destroyClass()

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
	for role, offers in self.offers do
		local player_data = self.role_data.instigator -- TODO change (intellisense)

		local opponent = self.getOpponent(role)
		for index, offer: offerType in self.offers[opponent] do
			self.addAsset(player_data, offer.asset, offer.type)
		end
	end	
	
	self.in_progress = false
	self.stage = "completed"
	-- TODO remove units and items from both sides, then insert them
	
	-- TODO add player statistics/trading history
	Remotes.TradeConfirmed:FireClient(
		self.instigator
	)
	Remotes.TradeConfirmed:FireClient(
		self.buddy
	)
	
end

function Trade._finalize(self: cls)
	-- TODO clear Trade class, cleanup etc
end


function Trade.readyCountdown(self: cls)
	self.stage = "ready_counting_down"

	self:_clearAdvancement()
	self.stage = "confirm" 
end
function Trade.confirmCountdown(self: cls)
	self.stage = "confirm_counting_down"

	task.wait(
		Constants.COMPLETE_TRADE_TIME
	)
	self.stage = "pending"

	task.wait(
		Constants.CONFIRMATION_WAIT_TIME
	)
	self:_clearAdvancement()
	
	self:_completeTrade()
end


function Trade.submitAdvance(self: cls, role: Types.Role): boolean
	if table.find(stage_order, self.stage) > 5 and not self.stage_advancement[role] then
		return false
	end

	if not self.cooldown:check(self.instigator) then return false end
	self.locked = false

	self.stage_advancement[role] = true

	local opponent = self.getOpponent(role)
	Remotes.AdvanceSubmitted:FireClient(
		self[opponent]
	)
	
	if self.stage_advancement.instigator and self.stage_advancement.buddy then
		if not self:_ownsAssets() then
			local opponent = self.getOpponent(role)
			--Remotes.AssetOwnershipChanged:FireClient(
			--	self[opponent],
			--	false -- trade cancelled
			--)
			Remotes.AssetOwnershipChanged:FireClient(
				self.instigator,
				false -- trade cancelled
			)
			Remotes.AssetOwnershipChanged:FireClient(
				self.buddy,
				false -- trade cancelled
			)
			
			self:_clearOffers()
			self:_clearAdvancement()

			print(self)
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

	print(self)
	return true
end

function Trade.cancelAdvance(self: cls, role: Types.Role): boolean
	if table.find(stage_order, self.stage) > 5 and self.stage_advancement[role] then
		return false
	end
	
	self.stage_advancement[role] = false

	local opponent = self.getOpponent(role)

	local advance_cleared = false
	if self._countdown_thread then
		advance_cleared = true
		self:_clearAdvancement()

		coroutine.close(
			self._countdown_thread
		)
		self._countdown_thread = nil
		

		local stage_spot = table.find(
			stage_order,
			self.stage
		)

		local chosen_reset_stage
		for i, reset_stage in advance_cancel_resets do
			local reset_spot = table.find(
				stage_order,
				reset_stage
			)
			if i == #advance_cancel_resets then
				chosen_reset_stage = reset_stage
				break
			end

			local next_reset = advance_cancel_resets[i+1]
			if table.find(stage_order, next_reset) > stage_spot then
				chosen_reset_stage = reset_stage
				break
			end
		end
		self.stage = chosen_reset_stage
	end
	
	Remotes.AdvanceCancelled:FireClient(
		self[opponent],
		advance_cleared
	)
	print(self)
	return true
end

function Trade.cancelTrade(self: cls, role: Types.Role?): boolean
	if table.find(stage_order, self.stage) > 5 then
		return false
	end

	if self._countdown_thread then
		coroutine.close(
			self._countdown_thread
		)
		self._countdown_thread = nil
	end

	if role then
		local opponent = self.getOpponent(role)
		Remotes.TradeCancelled:FireClient(
			self[opponent]
		)
	else
		Remotes.TradeCancelled:FireClient(
			self.instigator
		)
		Remotes.TradeCancelled:FireClient(
			self.buddy
		)
	end
	self:destroyClass()
	print(self)
	return true
end

function Trade.addToOffer(self: cls, role: Types.Role, asset: string): boolean
	print(self.stage)
	if self.stage ~= "ready" then return false end
	if #self.offers[role] >= Constants.MAX_OFFERS then return false end
	
	-- TODO playerdata ownership checks

	print(self:canAdd(role, asset))
	if not self:canAdd(role, asset) then return false end
	
	local asset_type = self.findAssetType(asset)
	local asset_value = self.calcAssetValue(asset, asset_type) or 0
	
	local offer: Types.TradeOffer = {
		asset = asset,
		type = asset_type
	}
	
	table.insert(
		self.offers[role],
		offer
	)
	self.offers_value[role] += asset_value
	
	
	self.cooldown:apply(
		self.instigator
	)
	self.locked = true	

	self:_clearAdvancement()

	local opponent = self.getOpponent(role)
	Remotes.AssetAdded:FireClient(
		self[opponent],
		offer
	)

	print(self)
	return true
end
function Trade.removefromOffer(self: cls, role: Types.Role, asset: string): boolean
	if self.stage ~= "ready" then return false end

	local asset_type = self.findAssetType(asset)
	local asset_value = self.calcAssetValue(asset, asset_type) or 0

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

			self:_clearAdvancement()
			
			local opponent = self.getOpponent(role)
			Remotes.AssetRemoved:FireClient(
				self[opponent],
				offer
			)

			print(self)
			return true
		end
	end
	print(self)
	return false
end

return Trade
