-- Collection of Trade Class functions that should be adapted to the game the trading system is implemented in.
local ReplicatedStorage = game:GetService('ReplicatedStorage')

local Types = require(ReplicatedStorage:WaitForChild('Trading'):WaitForChild('SharedTypes'))
local Constants = require(ReplicatedStorage:WaitForChild('Trading'):WaitForChild('SharedConstants'))

local UnitList = require(ReplicatedStorage:WaitForChild('Units'):WaitForChild('Lib'):WaitForChild('UnitList'))
local ItemList = require(ReplicatedStorage:WaitForChild('Items'):WaitForChild('Lib'):WaitForChild('ItemList'))

local GameSpecific = {}
GameSpecific.__index = GameSpecific

local function exceedsMaxDiff(value1: number, value2: number): boolean
	if value1 == value2 then return false end
	
	local min = math.min(value1, value2)
	local max = math.max(value1, value2)
	
	local threshold = max * (1-(Constants.MAX_VALUE_DIFFERENCE/100))
	
	return min < max
end

function GameSpecific.calcAssetValue(asset: string, type: Types.TradableType): number
	if type == "unit" then
		return UnitList[asset].chance

	elseif type == "item" then
		return ItemList[asset].trade_value
	end
end

function GameSpecific.findAssetType(asset: string): Types.TradableType | nil
	local is_type: Types.TradableType = nil
	if UnitList[asset] then
		is_type = "unit"
	elseif ItemList[asset] then
		is_type = "item"
	end
	return is_type
end

function GameSpecific.removeAsset(player_data: {}, asset: string, asset_type: Types.TradableType)
	if asset_type == "unit" then
		player_data:RemoveUnit(asset)

	elseif asset_type == "item" then
		player_data:RemoveItems({
			{name=asset, copies=1}
		})
	end
end

function GameSpecific.isTradable(asset: string, asset_type: Types.TradableType): boolean
	if asset_type == "unit" then
		if not UnitList[asset].tradable then return false end

	elseif asset_type == "item" then
		if not ItemList[asset].tradable then return false end
	end
end

function GameSpecific.hasAsset(player_data: {}, asset: string, asset_type: Types.TradableType): boolean
	local owns = false
	if asset_type == "unit" then
		owns = player_data:OwnsUnit(asset, 1)

	elseif asset_type == "item" then
		owns = player_data:HasItems(asset, 1)
	end
end

function GameSpecific.canAdd(self, role: Types.Role, asset: string): boolean
	local asset_type = GameSpecific.findAssetType(asset)
	if not asset_type then return false end
	
	local asset_value = GameSpecific.calcAssetValue(asset, asset_type)
	
	local exceeded: boolean = false
	if role == "instigator" then
		exceeded = exceedsMaxDiff(
			self.offers_value.instigator + asset_value,
			self.offers_value.buddy
		)
	elseif role == "buddy" then
		exceeded = exceedsMaxDiff(
			self.offers_value.instigator,
			self.offers_value.buddy + asset_value
		)
	end
	if exceeded then return false end
	
	local player_data = self.role_data[role]
	
	if not GameSpecific.isTradable(asset, asset_type) then return false end
	if not GameSpecific.hasAsset(player_data, asset, asset_type) then return false end
	
	return true
end


return GameSpecific
