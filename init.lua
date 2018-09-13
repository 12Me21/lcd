local RESOLUTION = 80

-- 2 node pixels (to match the texture) + 2 screen pixels (for padding)
local TOP_BORDER = 2/16 * RESOLUTION + 2
local SIDE_BORDER = 1/16 * RESOLUTION + 2

-- These control the spacing between chars
local CHAR_WIDTH = 6
local CHAR_HEIGHT = 9

local LINE_LENGTH = math.floor((RESOLUTION - SIDE_BORDER * 2) / CHAR_WIDTH)
local NUMBER_OF_LINES = math.floor((RESOLUTION - TOP_BORDER * 2) / CHAR_HEIGHT)

--adjust the borders so that the text is "centered"
TOP_BORDER = math.floor(RESOLUTION - CHAR_HEIGHT * NUMBER_OF_LINES) / 2
SIDE_BORDER = math.floor(RESOLUTION - CHAR_WIDTH * LINE_LENGTH) / 2

-- (Iterator function)
-- Wraps a string to a certain size and avoid breaking words if possible.
-- O(n)
-- Returns the cursor position and index given a string + width/height
local function wrap_text(text, columns, rows)
	local last_space
	local prev_line_end = 0
	local x, y = 0, -1
	local i = 0
	return function()
		i = i + 1
		if i > #text then return end -- stop at the end of the string
		-- At the start of each line, move the cursor to the next row, and
		-- scan the following characters to decide where the next line starts
		if i == prev_line_end + 1 then
			x = 0
			y = y + 1
			if y == rows then return end -- stop
			-- Search for a spot to break the line
			-- (Either the first \n, or last space)
			for j = i, prev_line_end + columns do
				local char = text:sub(j,j)
				if char == "" or char == "\n" then
					prev_line_end = j
					break
				elseif char == " " then
					prev_line_end = j
				end
			end
			-- If there wasn't a nice spot to break the line:
			if prev_line_end + 1 == i then prev_line_end = prev_line_end + columns end
		else
			x = x + 1
		end
		
		return x, y, i
	end
end

-- Generate texture string
local function generate_texture(text, columns, rows)
	local texture = "[combine:"..RESOLUTION.."x"..RESOLUTION
	for x, y, i in wrap_text(text, columns, rows) do
		print(x,y)
		local char = text:byte(i)
		if char >= 33 and char <= 127 then -- printable ASCII + 1 (except space)
			-- :<x>,<y>=lcd_.png\^[sheet\:96x1\:<char>,0
			-- (those are real backslashes in the string)
			texture = texture..":"..
				(SIDE_BORDER + x * CHAR_WIDTH)..",".. -- dest x
				(TOP_BORDER + y * CHAR_HEIGHT).. -- dest y
				[[=lcd_.png\^[sheet\:96x1\:]].. -- source sheet
				(char - 32)..",0" -- source tile
		end
	end
	return texture
end

-- If you want to split the font sheet into one file for each character
-- (Which might be faster or slower, I'm not sure. It's certainly a million times more annoying to deal with 96 texture files)
-- name them "lcd_1.png" to "lcd_95.png", where the number is the ascii code of minus 32
-- and use this function instead of the previous one:

--[[local function generate_texture(text, columns, rows)
	local texture = "[combine:"..RESOLUTION.."x"..RESOLUTION
	for x, y, i in wrap_text(text, columns, rows) do
		print(x,y)
		local char = text:byte(i)
		if char >= 33 and char <= 127 then -- printable ASCII + 1 (except space)
			-- :<x>,<y>=font.png\^[sheet\:96x1\:<byte>,0
			-- (those are real backslashes in the string, not escaped chars)
			texture = texture..":"..
				(SIDE_BORDER + x * CHAR_WIDTH)..",".. -- dest x
				(TOP_BORDER + y * CHAR_HEIGHT).. -- dest y
				"=lcd_"..(char-32)..".png" -- source image
		end
	end
	return texture
end--]]

local entity_pos = {
	-- on ceiling
	-- [0] = {delta = {x = 0, y = 0.437, z = 0}, pitch = -math.pi/2},
	-- on ground
	-- [1] = {delta = {x = 0, y =-0.437, z = 0}, pitch = math.pi/2},
	-- sides
	[2] = {delta = {x =  0.437, y = 0, z = 0}, yaw = -math.pi/2},
	[3] = {delta = {x = -0.437, y = 0, z = 0}, yaw =  math.pi/2},
	[4] = {delta = {x = 0, y = 0, z =  0.437}, yaw =  0        },
	[5] = {delta = {x = 0, y = 0, z = -0.437}, yaw =  math.pi  },
}

local function get_text_entity(pos)
	for _, object in ipairs(minetest.get_objects_inside_radius(pos, 0.5)) do
		local object_entity = object:get_luaentity()
		if object_entity and object_entity.name == "lcd:text" then
			return object
		end
	end
end

local function create_text_entity(pos)
	local lcd_info = entity_pos[minetest.get_node(pos).param2]
	if lcd_info then
		local text = minetest.add_entity(vector.add(pos, lcd_info.delta), "lcd:text")
		text:set_yaw(lcd_info.yaw)
	end
end

local function draw_text_entity(entity, text)
	entity:set_texture_mod(generate_texture(text, LINE_LENGTH, NUMBER_OF_LINES))
end

local function readable(thing)
	if type(thing) == "string" then
		return thing
	elseif type(thing) == "number" then
		return tostring(thing)
	else
		return dump(thing) -- should improve this
	end
end

local function on_digiline_receive(pos, _, channel, message)
	message = readable(message)
	local meta = minetest.get_meta(pos)
	if meta:get_string("channel") == channel then
		if message ~= meta:get_string("text") then
			meta:set_string("text", message)
			-- I'm thinking about disabling infotext because it gets in the way when you're reading the screen
			-- Maybe I should add some options in the formspec for things like this?
			-- Or display the backup text in the formspec instead of the infotext
			meta:set_string("infotext", message)
			local entity = get_text_entity(pos)
			if entity then
				draw_text_entity(get_text_entity(pos), message)
			else
				minetest.log("warning", "Could not find LCD text entity at "..minetest.pos_to_string(pos, 0))
			end
		end
	end
end

minetest.register_node("lcd:lcd", {
	description = "Digiline LCD",
	
	tiles = {"lcd_front.png"},
	inventory_image = "lcd_item.png",
	
	paramtype = "light",
	sunlight_propagates = true,
	light_source = 6,
	
	paramtype2 = "wallmounted",
	drawtype = "nodebox",
	node_box = {
		type = "wallmounted",
		wall_top = {-0.5, 7/16, -0.5, 0.5, 0.5, 0.5}
	},
	
	groups = {choppy = 3, dig_immediate = 2},
	
	-- Don't allow placing on floor/ceiling since minetest STILL doesn't allow you to set the pitch of entities apparently
	after_place_node = function(pos)
		local param2 = minetest.get_node(pos).param2
		if param2 == 0 or param2 == 1 then
			minetest.swap_node(pos, {name = "lcd:lcd", param2 = 3})
		end
	end,
	
	on_construct = function(pos)
		minetest.get_meta(pos):set_string("formspec", "field[channel;Channel;${channel}]")
		create_text_entity(pos)
	end,
	on_destruct = function(pos)
		local entity = get_text_entity(pos)
		if entity then
			entity:remove()
		else
			minetest.log("warning", "Could not find LCD text entity to remove at "..minetest.pos_to_string(pos, 0))
		end
	end,
	
	on_receive_fields = function(pos, _, fields, sender)
		local name = sender:get_player_name()
		if minetest.is_protected(pos, name) then
			minetest.record_protection_violation(pos, name)
			return
		end
		if fields.channel then
			minetest.get_meta(pos):set_string("channel", fields.channel)
		end
	end,
	
	digiline = {effector = {
		action = on_digiline_receive
	}},
})

minetest.register_entity("lcd:text", {
	collisionbox = {0, 0, 0, 0, 0, 0},
	visual = "upright_sprite",
	textures = {""},
	
	on_activate = function(self)
		local entity = self.object
		draw_text_entity(entity, minetest.get_meta(entity:get_pos()):get_string("text"))
	end,
})

minetest.register_craft({
	output = "lcd:lcd",
	recipe = {
		{"default:steel_ingot", "digilines:wire_std_00000000", "default:steel_ingot"},
		-- It would make more sense for this recipe to use the microcontroller, I think
		-- But the microcontroller seems to be mostly deprecated in favor of the luacontroller
		{"mesecons_lightstone:lightstone_green_off","mesecons_luacontroller:luacontroller0000","mesecons_lightstone:lightstone_green_off"},
		{"default:glass","default:glass","default:glass"}
	}
})