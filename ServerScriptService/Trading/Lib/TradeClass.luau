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
	type: Types.TradableType,
	amount: number
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
	local active_trades_copy = Trade.active_trades
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
	for _, trade in Trade.active_trades do
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

	local data = self.instigator_data:GetInventorySize()
	self.instigator_unit_size_left = data.size - data.units
	
	self.buddy = nil :: Player
	self.buddy_data = nil
	self.buddy_unit_size_left = nil
	
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
	
	if self.role_data.buddy.trading then
		self.role_data.buddy.trading = false
	end
		
	self.role_data.instigator.trading = false

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
	
	self.buddy = buddy

	local accepted = Remotes.InvokeTrade:InvokeClient(buddy, self.instigator.UserId)
	if typeof(accepted) ~= 'boolean' then
		Trade.unregisterTrade(self.ID)
		self:destroyClass()

		return false, 500 
	end
	

	print('accepted?', accepted, self)

	
	if not accepted then
		print('NOT ACCEPTED! or data is not loaded')
		Trade.unregisterTrade(self.ID)
		self:destroyClass()

		return false, 411
	end

	self.buddy_data = PlayerDataService.GetPlayerDataInstance(buddy)

	local instigator_trades = Trade.GetTrades(self.instigator)
	for _, trade in instigator_trades do
		if trade.in_progress then
			print('instigator trade already in progress', self.instigator)

			Remotes.TradeCancelled:FireClient(buddy, 410)
			Trade.unregisterTrade(self.ID)
			self:destroyClass()

			return false, 410
		end
	end
	
	
	local buddy_trades = Trade.GetTrades(buddy)
	for _, trade in buddy_trades do
		if trade.in_progress then
			print('buddy trade already in progress', self.buddy)
			
			Remotes.TradeCancelled:FireClient(buddy, 410)
			Trade.unregisterTrade(self.ID)
			self:destroyClass()

			return false, 410
		end
	end
	

	if self.closed then
		Remotes.TradeCancelled:FireClient(buddy, 500)

		Trade.unregisterTrade(self.ID)
		self:destroyClass()

		return false, 500
	end

	print('did it get here?')
	--Trade.unregisterPlayerTrades(
	--	buddy,
	--	self.ID
	--)
	--Trade.unregisterPlayerTrades(
	--	self.instigator,
	--	self.ID
	--)

	local data = self.buddy_data:GetInventorySize()
	self.buddy_unit_size_left = data.size - data.units

	self.role_data.buddy = self.buddy_data
	
	self.in_progress = true
	self.stage =  "ready"

	print('did it get here?')
	
	self.role_data.buddy.trading = true
	self.role_data.instigator.trading = true

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
		local player_data = self.role_data[role] -- TODO change (intellisense)

		for index, offer: offerType in offers do
			local owns = self.hasAsset(player_data, offer.asset, offer.type, offer.amount)
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
	print(self.offers)
	
	for role, offers in self.offers do
		local player_data = self.role_data[role] -- TODO change (intellisense)
		
		for index, offer: offerType in offers do
			print(offer)
			self.removeAsset(player_data, offer.asset, offer.type, offer.amount)
		end
	end
	
	-- insert from other side
	for role, offers in self.offers do
		local player_data = self.role_data[role] -- TODO change (intellisense)

		local opponent = self.getOpponent(role)
		for index, offer: offerType in self.offers[opponent] do
			self.addAsset(player_data, offer.asset, offer.type, offer.amount)
		end
	end
	
	
	self.in_progress = false
	self.stage = "completed"
	-- TODO remove units and items from both sides, then insert them

	Remotes.TradeConfirmed:FireClient(
		self.instigator
	)
	Remotes.TradeConfirmed:FireClient(
		self.buddy
	)

	self.role_data.instigator:AddTradeToHistory({
		buddy_id = self.buddy.UserId,
		date = DateTime.now().UnixTimestamp,
		
		offer = self.offers
	})
	self.role_data.buddy:AddTradeToHistory({
		buddy_id = self.instigator.UserId,
		date = DateTime.now().UnixTimestamp,

		offer = self.offers
	})
	
	
	-- TODO add player statistics/trading history

	local instigator = self.instigator
	local buddy = self.buddy
	local offers = self.offers
	self.logTrade({
			instigator = instigator,
			buddy = buddy,
			
			offers = offers,
			offer_values = self.offers_value
	})

	self:destroyClass()
end

function Trade.readyCountdown(self: cls)
	self.stage = "ready_counting_down"

	self:_clearAdvancement()
	self.stage = "confirm" 
end
function Trade.confirmCountdown(self: cls)
	self.stage = "confirm_counting_down"

	task.wait(
		Constants.CONFIRMATION_WAIT_TIME
	)
	self.stage = "pending"

	task.wait(
		Constants.COMPLETE_TRADE_TIME
	)
	self:_clearAdvancement()
	
	self:_completeTrade()
end


function Trade.submitAdvance(self: cls, role: Types.Role): boolean
	if table.find(stage_order, self.stage) > 5 or self.stage_advancement[role] then
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

	return true
end

function Trade.cancelAdvance(self: cls, role: Types.Role): boolean
	if table.find(stage_order, self.stage) > 5 or not self.stage_advancement[role] then
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
	return true
end

function Trade.cancelTrade(self: cls, code: Constants.TRADE_IDS, role: Types.Role?): boolean
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
			self[opponent],
			code
		)
	else
		Remotes.TradeCancelled:FireClient(
			self.instigator,
			code
		)
		Remotes.TradeCancelled:FireClient(
			self.buddy,
			code
		)
	end
	self:destroyClass()
	return true
end

function Trade.addToOffer(self: cls, role: Types.Role, asset: string, amount: number?): boolean
	print(self.stage)
	if self.stage ~= "ready" then return false end
	if #self.offers[role] >= Constants.MAX_OFFERS then return false end
	
	amount = amount or 1
	-- TODO playerdata ownership checks

	print(self:canAdd(role, asset, amount))
	if not self:canAdd(role, asset, amount) then return false end
	
	
	local asset_type = self.findAssetType(asset)
	local asset_value = self.calcAssetValue(asset, asset_type) or 0
	
	local offer: Types.TradeOffer = {
		asset = asset,
		type = asset_type,
		amount = amount
	}
	
	local found = false
	for index, local_offer: Types.TradeOffer in self.offers[role] do
		if local_offer.asset == asset then
			found = index
			break
		end
	end

	if not found then
		table.insert(
			self.offers[role],
			offer
		)
	else
		self.offers[role][found].amount += amount
	end

	self.offers_value[role] += (asset_value * amount)
	
	if asset_type == "unit" then
		if role == "buddy" then
			self.instigator_unit_size_left -= 1
		elseif role == "instigator" then
			self.buddy_unit_size_left -= 1
		end
	end
	
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

	return true
end
function Trade.removefromOffer(self: cls, role: Types.Role, asset: string, amount: number?): boolean
	if self.stage ~= "ready" then return false end

	amount = amount or 1

	local asset_type = self.findAssetType(asset)
	local asset_value = self.calcAssetValue(asset, asset_type) or 0

	for index, offer: Types.TradeOffer in self.offers[role] do
		if offer.asset == asset then
			if amount > offer.amount then -- is client trying to delete more in the offer than actually exist?
				amount = offer.amount
			end
			
			offer.amount -= amount

			if offer.amount == 0 then
				table.remove(
					self.offers[role],
					index
				)
			end

			self.offers_value[role] -= asset_value * amount
			
			if asset_type == "unit" then
				if role == "buddy" then
					self.instigator_unit_size_left += 1
				elseif role == "instigator" then
					self.buddy_unit_size_left += 1
				end
			end
			
			self.cooldown:apply(
				self.instigator
			)
			self.locked = true

			self:_clearAdvancement()
			
			local opponent = self.getOpponent(role)
			Remotes.AssetRemoved:FireClient(
				self[opponent],
				offer -- return active offer state, NOT change
			)

			return true
		end
	end
	return false
end

return Trade
