--- @sync entry

local function entry()
	local tab = cx.active
	if not tab.mode.is_normal or #tab.selected > 0 or tab.finder or tab.current.files.filter then
		ya.emit("escape", {})
	else
		ya.emit("leave", {})
	end
end

return { entry = entry }
