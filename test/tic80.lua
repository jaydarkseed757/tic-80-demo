-- A minimal headless fake of the TIC-80 API.
--
-- A TIC-80 cart is a single script that calls global drawing functions and
-- defines the TIC() and SCN() callbacks. This installs stand-ins for the parts
-- of that API the demo uses, so the cart can be loaded and stepped under plain
-- Lua and its behaviour asserted on.
--
-- What it models:
--   * print() returning a rendered width, with the fixed-width font advancing
--     FONT_CELL*scale per character
--   * poke() into the palette registers, recorded for inspection
--   * the render order: TIC() draws the whole frame, then the frame is scanned
--     out one line at a time with SCN(line) running before each line. That
--     ordering is the entire reason mid-frame palette changes work, and it is
--     where scene-boundary bugs hide, so frame() reproduces it faithfully.
--
-- What it does not model: a real framebuffer, clipping, sound, input, or the
-- true variable-width font metrics (FONT_VAR_W is an average, and only feeds
-- the scroller's wrap distance).
--
-- Because it cannot execute the emulator, it cannot confirm that TIC-80 really
-- samples the palette per scanline. It checks that the cart asks for the right
-- thing, not that the hardware obliges.

local M={}

M.SCREEN_W=240
M.SCREEN_H=136
M.PAL_ADDR=0x3FC0
M.PAL_BYTES=48
M.FONT_CELL=8
M.FONT_VAR_W=6

-- Recording allocates, which would swamp a garbage measurement. Turn it off
-- around anything that counts heap growth.
M.recording=true
M.calls={}
M.pokes={}
M.poke_count=0
M.frames=0

-- Positional rather than table-taking, because a table constructed at the call
-- site would allocate even when recording is off, and the allocation test needs
-- to measure the cart rather than this harness. `a` and `b` carry per-shape
-- extras (radius, sprite id, text, scale).
local function rec(kind,x,y,x2,y2,c,a,b)
	if not M.recording then return end
	M.calls[#M.calls+1]={kind=kind,x=x,y=y,x2=x2,y2=y2,c=c,a=a,b=b}
end

function M.reset()
	M.calls={}
	M.pokes={}
	M.poke_count=0
end

-- The cart is loaded with the fake API already in place, because carts call
-- drawing functions at load time (measuring text, for instance).
function M.load(path)
	M.install()
	local chunk,err=loadfile(path)
	if not chunk then error("could not load cart: "..tostring(err),2) end
	chunk()
end

-- One frame: draw, then scan out. `hooks.before_scanout` runs in between,
-- which is where a test can note which scene is about to be scanned. Takes the
-- hooks table as-is rather than defaulting it, so a plain frame() allocates
-- nothing.
function M.frame(hooks)
	TIC()
	if hooks and hooks.before_scanout then hooks.before_scanout() end
	if SCN then
		for line=0,M.SCREEN_H-1 do SCN(line) end
	end
	M.frames=M.frames+1
end

function M.install()
	local g=_G

	g.cls=function(c) rec("cls",nil,nil,nil,nil,c) end

	g.print=function(text,x,y,color,fixed,scale,smallfont)
		local n=#tostring(text)
		scale=scale or 1
		rec("print",x,y,nil,nil,color,text,scale)
		return n*(fixed and M.FONT_CELL or M.FONT_VAR_W)*scale
	end

	g.line=function(x0,y0,x1,y1,c) rec("line",x0,y0,x1,y1,c) end
	g.circ=function(x,y,r,c) rec("circ",x,y,nil,nil,c,r) end
	g.circb=function(x,y,r,c) rec("circb",x,y,nil,nil,c,r) end
	g.elli=function(x,y,a,b,c) rec("elli",x,y,nil,nil,c,a,b) end
	g.rect=function(x,y,w,h,c) rec("rect",x,y,nil,nil,c,w,h) end
	g.rectb=function(x,y,w,h,c) rec("rectb",x,y,nil,nil,c,w,h) end
	g.tri=function(x1,y1,x2,y2,x3,y3,c) rec("tri",x1,y1,x2,y2,c,x3,y3) end
	g.trib=function(x1,y1,x2,y2,x3,y3,c) rec("trib",x1,y1,x2,y2,c,x3,y3) end
	g.textri=function(x1,y1,x2,y2,x3,y3) rec("textri",x1,y1,x2,y2) end
	g.pix=function(x,y,c) rec("pix",x,y,nil,nil,c) end
	g.spr=function(id,x,y,key) rec("spr",x,y,nil,nil,key,id) end
	g.map=function() rec("map") end

	g.poke=function(addr,val)
		M.poke_count=M.poke_count+1
		if M.recording then M.pokes[#M.pokes+1]={addr=addr,val=val} end
	end
	g.poke4=function(addr,val)
		M.poke_count=M.poke_count+1
		if M.recording then M.pokes[#M.pokes+1]={addr=addr,val=val,nibble=true} end
	end
	g.peek=function() return 0 end
	g.peek4=function() return 0 end
	g.memcpy=function() end
	g.memset=function() end
	g.vbank=function() return 0 end

	g.sfx=function() end
	g.music=function() end
	g.btn=function() return false end
	g.btnp=function() return false end
	g.key=function() return false end
	g.keyp=function() return false end
	g.mouse=function() return 0,0,false,false,false,0,0 end
	g.fget=function() return false end
	g.fset=function() end
	g.sync=function() end
	g.reset=function() end
	g.exit=function() end
	g.trace=function() end
	g.time=function() return M.frames*1000/60 end
	g.tstamp=function() return 0 end
end

return M
