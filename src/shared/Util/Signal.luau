--!strict
-- Minimal synchronous signal for module-to-module events (server and client).
-- Handlers run in connection order; a handler error is reported and does not
-- stop the remaining handlers.

export type Connection = {
	Connected: boolean,
	Disconnect: (self: Connection) -> (),
}

export type Signal<T...> = {
	Connect: (self: Signal<T...>, handler: (T...) -> ()) -> Connection,
	Once: (self: Signal<T...>, handler: (T...) -> ()) -> Connection,
	Fire: (self: Signal<T...>, T...) -> (),
	DisconnectAll: (self: Signal<T...>) -> (),
}

type Slot<T...> = { handler: (T...) -> (), connection: Connection }

local Signal = {}

function Signal.new<T...>(): Signal<T...>
	local slots: { Slot<T...> } = {}
	local self = {} :: Signal<T...>

	function self.Connect(_: Signal<T...>, handler: (T...) -> ()): Connection
		local connection = { Connected = true } :: Connection
		local slot = { handler = handler, connection = connection }
		function connection.Disconnect(conn: Connection)
			if not conn.Connected then
				return
			end
			conn.Connected = false
			local index = table.find(slots, slot)
			if index then
				table.remove(slots, index)
			end
		end
		table.insert(slots, slot)
		return connection
	end

	function self.Once(sig: Signal<T...>, handler: (T...) -> ()): Connection
		local connection: Connection
		connection = sig:Connect(function(...: T...)
			connection:Disconnect()
			handler(...)
		end)
		return connection
	end

	function self.Fire(_: Signal<T...>, ...: T...)
		-- snapshot so handlers may disconnect themselves safely
		local snapshot = table.clone(slots)
		for _, slot in snapshot do
			if slot.connection.Connected then
				local ok, err = pcall(function(...: T...): any
					slot.handler(...)
					return nil
				end, ...)
				if not ok then
					warn("[Signal] handler error: " .. tostring(err))
				end
			end
		end
	end

	function self.DisconnectAll(_: Signal<T...>)
		for _, slot in slots do
			slot.connection.Connected = false
		end
		table.clear(slots)
	end

	return self
end

return Signal
