--[[
Copyright (c) 2012 Xgoff

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

Except as contained in this notice, the name(s) of the above copyright holders
shall not be used in advertising or otherwise to promote the sale, use or
other dealings in this Software without prior written authorization.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
--]]

assert(love._version:match "^0.8", "fakecanvas requires LOVE 0.8")
assert(debug, "fake canvases require access to the debug library")

local canvas_supported      = love.graphics.isSupported "canvas"
local npot_supported        = love.graphics.isSupported "npot"
local pixeleffect_supported = love.graphics.isSupported "pixeleffect"

local function nextpo2 (x) return 2^math.ceil(math.log(x) / math.log(2)) end
local function prevpo2 (x) return 2^math.floor(math.log(x) / math.log(2)) end

local _types = { "Canvas" == true, "Object" == true, "Drawable" == true }
local canvas = { }
local canvasmt = { __index = canvas }

local canvases = setmetatable({ }, { __mode = "k" })

local options = {
	-- flip fake canvas images vertically (then unflip with quad) in order to 
	-- match real canvas orientation. this only makes a difference inside 
	-- shaders, when using the canvas' texture coordinates. if you do not need
	-- to use this information, you can get a performance boost by disabling
	-- this option. you can enable or disable vflipping for individual fake
	-- canvases by placing setOption() calls around the newCanvas() call.
	vflip = true, 
}

local blank
function canvas:clear (...) -- other option is chucking out the imagedata and creating a new one, but i'd probably end up using mapPixel anyway
	local nargs = select("#", ...)
	
	if nargs == 0 then
		local id = canvases[self]._imagedata
		id:paste(blank, 0, 0, 0, 0, id:getWidth(), id:getHeight()) 
	elseif nargs == 1 and type(...) == "table" then
		local t = ...
		local r, g, b, a = tonumber(t[1]) or 0, tonumber(t[2]) or 0, tonumber(t[3]) or 0, tonumber(t[4]) or 255
		canvases[self]._imagedata:mapPixel(function () return r, g, b, a end)
	else
		local r, g, b, a = ...
		r, g, b, a = tonumber(r) or 0, tonumber(g) or 0, tonumber(b) or 0, tonumber(a) or 255
		canvases[self]._imagedata:mapPixel(function () return r, g, b, a end)
	end
end

function canvas:getFilter () 
	return canvases[self]._image:getFilter() 
end

function canvas:getImageData () 
	return canvases[self]._imagedata 
end

function canvas:getWrap () 
	return canvases[self]._image:getWrap() 
end

function canvas:renderTo (renderfunc) 
	love.graphics.setCanvas(self)
	renderfunc()
	love.graphics.setCanvas()
end

function canvas:setFilter (min, mag) 
	canvases[self]._image:setFilter(min, mag) 
end

function canvas:setWrap (h, v) 
	canvases[self]._image:setWrap(h, v) 
end

function canvas:type () 
	return "Canvas" 
end

function canvas:typeOf (type) 
	return not not _types[type] 
end

-- internal
function canvas:_getImage ()
	return canvases[self]._image
end

function canvas:_getQuad ()
	return canvases[self]._quad
end

local function Canvas (width, height)
	local c = { }
	
	local sw, sh = love.graphics.getWidth(), love.graphics.getHeight()
	
	local w, h
	if npot_supported then -- awesome, just limit to screen size
		w = math.min(sw, tonumber(width) or sw)
		h = math.min(sh, tonumber(height) or sh)
	else -- well that sucks
		w = math.min(prevpo2(sw), nextpo2(tonumber(width) or 1))
		h = math.min(prevpo2(sh), nextpo2(tonumber(height) or 1))
	end
	
	c._imagedata  = love.image.newImageData(w, h)
	c._image      = love.graphics.newImage(c._imagedata)
	c._quad       = love.graphics.newQuad(0, 0, w, h, w, h)
	c._vflip      = options.vflip
	
	if options.vflip then
		c._quad:flip(false, true) -- flip vertically part 0
	end
	
	local p = newproxy(true)
	
	canvases[p] = c
	
	getmetatable(p).__index = canvasmt.__index
	
	return p --setmetatable(p, canvasmt)
end

local current_canvas
local function getCanvas ()
	return current_canvas
end

local _fb_states = { }

local ccount = 0
local function screenshot (state)
	local canvas   = state.canvas
	
	love.graphics.setColor(255, 255, 255, 255)
	
	local drawn = love.graphics.newScreenshot()
	
	if canvas._vflip then -- flip vertically (unfortunately) so it can later be drawn unflipped in order to match texcoords of real canvases. part 1
		love.graphics.setBackgroundColor(0, 0, 0, 0)
		love.graphics.clear()
		
		local flipped = love.graphics.newImage(drawn) 
		love.graphics.draw(flipped, 0, canvas._imagedata:getHeight(), 0, 1, -1)
		
		drawn = love.graphics.newScreenshot()
	end
	
	canvas._imagedata:paste(drawn, 0, 0, 0, 0, canvas._imagedata:getWidth(), canvas._imagedata:getHeight())
	canvas._image = love.graphics.newImage(canvas._imagedata) -- apparently images don't update when their imagedata changes, so
	
	love.graphics.draw(canvas._image, 0, 0)
	love.graphics.setBackgroundColor(unpack(state.color))
	love.graphics.setScissor(unpack(state.scissor))
end

local function setCanvas (...)
	assert(select("#", ...) == 0 or (select("#", ...) == 1 and type(...) == "userdata"), "Incorrect parameter type: expected userdata")
	love.graphics.setStencil() -- fortunately LOVE does this as well which makes things much easier
	
	local to = ...
	if to then
		local old_canvas = current_canvas
		local current_canvas = canvases[to]
		
		local current_state = { 
			canvas  = current_canvas,
			data    = love.graphics.newScreenshot(),
			color   = { love.graphics.getBackgroundColor() },
			scissor = { love.graphics.getScissor() },
		}
		current_state.image = love.graphics.newImage(current_state.data)
		
		if #_fb_states > 0 then
			screenshot(table.remove(_fb_states))
		end
		
		love.graphics.setScissor()
		love.graphics.setBackgroundColor(0, 0, 0, 0)
		love.graphics.clear()

		table.insert(_fb_states, current_state)
		
	else
		if #_fb_states == 0 then return end -- only possible if multiple consecutive setCanvas() calls are made with no arguments; nothing to do

		screenshot(table.remove(_fb_states))
		
		while #_fb_states > 0 do
			table.remove(_fb_states)
		end
		
		current_canvas = nil
	end
end

local registry = debug.getregistry() -- naughty!

 -- throwaway, forces LOVE to load the :send() method
if pixeleffect_supported then
	love.graphics.newPixelEffect [[vec4 effect( vec4 x, Image y, vec2 z, vec2 w) { return vec4(0, 0, 0, 0); }]]
end

local _love_funcs = { 
	getCanvas = love.graphics.getCanvas,
	setCanvas = love.graphics.setCanvas,
	newCanvas = love.graphics.newCanvas,
	
	draw      = love.graphics.draw,
	drawq     = love.graphics.drawq,
	
	pe_send   = pixeleffect_supported and registry.PixelEffect.send,
	--technically sendCanvas should also be wrapped but that's not officially exposed
}
local _wrap_funcs = { 
	getCanvas = getCanvas,
	setCanvas = setCanvas,
	newCanvas = Canvas,
	
	draw = function (obj, x, y, r, sx, sy, ox, oy, kx, ky)
		if canvases[obj] then
			return _love_funcs.drawq(obj:_getImage(), obj:_getQuad(), x or 0, y or 0, r, sx, sy, ox, oy, kx, ky) -- flip texcoords part 2
		end
		return _love_funcs.draw(obj, x, y, r, sx, sy, ox, oy, kx, ky)
	end,
	drawq = function (obj, x, y, r, sx, sy, ox, oy, kx, ky)
		if canvases[obj] then
			return _love_funcs.drawq(obj:_getImage(), x, y, r, sx, sy, ox, oy, kx, ky)
		end
		return _love_funcs.drawq(obj, x, y, r, sx, sy, ox, oy, kx, ky)
	end,
	
	pe_send   = function (pe, name, data)
		if canvases[data] then
			return _love_funcs.pe_send(pe, name, data:_getImage())
		end
		return _love_funcs.pe_send(pe, name, data)
	end,
}

local M = { }

-- enable use of fake canvases
-- state: 
--    true:  use fake canvases even if real ones are supported 
--    false: disable canvases entirely
--    nil:   use real or fake canvases based on support
function M.enable (state)
	if state == true or not canvas_supported then
		love.graphics.getCanvas = _wrap_funcs.getCanvas
		love.graphics.setCanvas = _wrap_funcs.setCanvas
		love.graphics.newCanvas = _wrap_funcs.newCanvas
		love.graphics.draw      = _wrap_funcs.draw
		love.graphics.drawq     = _wrap_funcs.drawq
		
		if pixeleffect_supported then
			registry.PixelEffect.send = _wrap_funcs.pe_send
		end
	elseif state == false then 
		love.graphics.getCanvas = function () return nil end
		love.graphics.setCanvas = function () end
		love.graphics.newCanvas = function () error("canvases disabled", 2) end
		love.graphics.draw      = _love_funcs.draw
		love.graphics.drawq     = _love_funcs.drawq
		
		if pixeleffect_supported then
			registry.PixelEffect.send = _love_funcs.pe_send
		end
	elseif state == nil and canvas_supported then
		love.graphics.getCanvas = _love_funcs.getCanvas
		love.graphics.setCanvas = _love_funcs.setCanvas
		love.graphics.newCanvas = _love_funcs.newCanvas
		love.graphics.draw      = _love_funcs.draw
		love.graphics.drawq     = _love_funcs.drawq
		if pixeleffect_supported then
			registry.PixelEffect.send = _love_funcs.pe_send
		end
	end
	return M
end

function M.getMaxCanvasSize (hw, hh)
	local w, h = love.graphics.getWidth(), love.graphics.getHeight()
	hw, hh = tonumber(hw) or w, tonumber(hh) or h
	
	if npot_supported then
		return math.min(hw, w), math.min(hh, h)
	else
		return prevpo2(math.min(hw, w)), prevpo2(math.min(hh, h))
	end
end

function M.setOption (name, value)
	options[name] = value
end

function M.getOption (name)
	return options[name]
end

blank = love.image.newImageData(M.getMaxCanvasSize())

M.enable()

return M