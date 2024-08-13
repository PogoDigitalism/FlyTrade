local SharedTypes = {}

export type Role = "instigator" | "buddy"

export type SettingType = "request" | "inventory"
export type SettingValue = "none" | "public" | "friends"

export type TradableType = "unit" | "item"

export type UnitInventory = {
	string
}
export type ItemInventory = {
	[string] : {
		amount: number
	}
}

export type TradeList = {
	user_id: number,

	trade_settings: {
		request: SettingValue,
		inventory: SettingValue
	}
}

return SharedTypes
