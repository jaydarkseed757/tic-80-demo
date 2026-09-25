-- Regression tests for demo2.lua, run headlessly against the fake TIC-80 API.
--
--   lua5.4 test/run.lua
--
-- These check the things a stub can actually establish: that the cart loads and
-- runs, that the scene director sequences and fades correctly, that every
-- palette write is a legal byte at a legal address, and that the draw calls
-- stay sane. They cannot confirm that TIC-80 samples the palette per scanline
-- or that the tile data decodes the way it is meant to -- both need the
-- emulator.

local out=print                         -- kept before the stub replaces print
local here=arg[0]:match("^(.*)/[^/]*$") or "."
package.path=here.."/?.lua;"..package.path
local tic=require("tic80")

local failures=0
local checks=0

local function ok(cond,name,detail)
	checks=checks+1
	if cond then
		out(("  pass  %s"):format(name))
	else
		failures=failures+1
		out(("  FAIL  %s%s"):format(name,detail and ("\n          "..detail) or ""))
	end
end

local function section(name)
	out(("\n%s"):format(name))
end

-- ---------------------------------------------------------------- load ------
-- CART=path overrides the cart under test, which is how the checks themselves
-- get verified: mutate a copy, confirm the matching check goes red.
local cart=os.getenv("CART") or (here.."/../demo2.lua")
section("loading")
out(("        cart: %s"):format(cart))
local loaded,err=pcall(tic.load,cart)
ok(loaded,"cart loads without error",not loaded and tostring(err) or nil)
if not loaded then os.exit(1) end

-- ------------------------------------------------------------ structure -----
section("scene table")
ok(type(scenes)=="table" and #scenes>0,"scenes is a non-empty table")
local shape_bad={}
for i,s in ipairs(scenes) do
	local why
	if type(s.name)~="string" then why="name is not a string"
	elseif type(s.dur)~="number" or s.dur<1 then why="dur is not a positive number"
	elseif type(s.enter)~="function" then why="enter is not a function"
	elseif type(s.update)~="function" then why="update is not a function"
	elseif type(s.draw)~="function" then why="draw is not a function"
	elseif s.scanline~=nil and type(s.scanline)~="function" then why="scanline is not a function"
	end
	if why then shape_bad[#shape_bad+1]=("scene %d (%s): %s"):format(i,tostring(s.name),why) end
end
ok(#shape_bad==0,"every scene has the required fields",table.concat(shape_bad,"; "))

local loop_frames=0
for _,s in ipairs(scenes) do loop_frames=loop_frames+s.dur end
out(("        %d scenes, %d frames per loop (%.1fs at 60fps)")
	:format(#scenes,loop_frames,loop_frames/60))

-- --------------------------------------------------------------- run --------
-- Three full loops, watching everything at once.
section("running three full loops")
local visited={}
local drew,scanned
local boundary_bad={}
local pal_addr_bad,pal_val_bad={},{}
local color_bad,coord_bad={},{}
local spr_minx,spr_maxx,spr_miny,spr_maxy=math.huge,-math.huge,math.huge,-math.huge
local fade_seen={}
local fade_min,fade_max=math.huge,-math.huge
local fade_step_max=0
local fade_prev=nil

-- note which scene drew the frame, by hooking the clear
local real_cls=cls
cls=function(c) drew=scenes[scene_index].name real_cls(c) end

local function finite(v)
	return type(v)=="number" and v==v and v~=math.huge and v~=-math.huge
end

for f=1,loop_frames*3 do
	tic.reset()
	drew=nil
	tic.frame({before_scanout=function() scanned=scenes[scene_index].name end})
	visited[scenes[scene_index].name]=true

	if drew and scanned and drew~=scanned and #boundary_bad<5 then
		boundary_bad[#boundary_bad+1]=
			("frame %d: drew '%s' but scanned out '%s'"):format(f,drew,scanned)
	end

	for _,p in ipairs(tic.pokes) do
		if p.addr<tic.PAL_ADDR or p.addr>=tic.PAL_ADDR+tic.PAL_BYTES then
			if #pal_addr_bad<5 then pal_addr_bad[#pal_addr_bad+1]=("0x%X"):format(p.addr) end
		end
		if type(p.val)~="number" or p.val~=math.floor(p.val) or p.val<0 or p.val>255 then
			if #pal_val_bad<5 then pal_val_bad[#pal_val_bad+1]=tostring(p.val) end
		end
	end

	for _,c in ipairs(tic.calls) do
		if c.c~=nil and c.kind~="spr" then
			if type(c.c)~="number" or c.c~=math.floor(c.c) or c.c<0 or c.c>15 then
				if #color_bad<5 then
					color_bad[#color_bad+1]=("%s colour %s"):format(c.kind,tostring(c.c))
				end
			end
		end
		for _,k in ipairs{"x","y","x2","y2"} do
			if c[k]~=nil and not finite(c[k]) then
				if #coord_bad<5 then
					coord_bad[#coord_bad+1]=("%s %s=%s"):format(c.kind,k,tostring(c[k]))
				end
			end
		end
		if c.kind=="spr" then
			spr_minx=math.min(spr_minx,c.x) spr_maxx=math.max(spr_maxx,c.x)
			spr_miny=math.min(spr_miny,c.y) spr_maxy=math.max(spr_maxy,c.y)
		end
	end

	fade_min=math.min(fade_min,fade)
	fade_max=math.max(fade_max,fade)
	if fade_prev then fade_step_max=math.max(fade_step_max,math.abs(fade-fade_prev)) end
	fade_prev=fade
end

local names={}
for k in pairs(visited) do names[#names+1]=k end
table.sort(names)
ok(#names==#scenes,"every scene runs","visited: "..table.concat(names,", "))

-- This is the regression test for the scene-advance ordering bug: SCN fires
-- during scanout, after TIC returns, so a scene advanced at the wrong point
-- leaves one frame drawn by one scene and scanned out by another.
ok(#boundary_bad==0,"the scene that draws a frame also scans it out",
	table.concat(boundary_bad,"; "))

section("palette writes")
ok(#pal_addr_bad==0,
	("every write lands in 0x%X..0x%X"):format(tic.PAL_ADDR,tic.PAL_ADDR+tic.PAL_BYTES-1),
	#pal_addr_bad>0 and ("stray: "..table.concat(pal_addr_bad,", ")) or nil)
ok(#pal_val_bad==0,"every write is an integer 0..255",
	#pal_val_bad>0 and ("bad: "..table.concat(pal_val_bad,", ")) or nil)

section("draw calls")
ok(#color_bad==0,"every colour is an integer 0..15",table.concat(color_bad,"; "))
ok(#coord_bad==0,"no NaN or infinite coordinates",table.concat(coord_bad,"; "))
ok(spr_minx>=0 and spr_maxx<=tic.SCREEN_W-8 and spr_miny>=0 and spr_maxy<=tic.SCREEN_H-8,
	"sprites stay on screen",
	("x %g..%g, y %g..%g"):format(spr_minx,spr_maxx,spr_miny,spr_maxy))

section("fades")
ok(fade_min<0.01,"fade reaches black",("min %.4f"):format(fade_min))
ok(fade_max>0.99,"fade reaches full",("max %.4f"):format(fade_max))
-- A scene shorter than 2*fade_frames used to overlap its fade in and out and
-- jump part-way through. The expected step is 1/fade width, per scene.
local step_limit=0
for _,s in ipairs(scenes) do
	local fw=math.min(fade_frames,s.dur//2)
	if fw>=1 then step_limit=math.max(step_limit,1/fw) end
end
ok(fade_step_max<=step_limit+1e-9,"fade never jumps more than one step",
	("largest step %.4f, limit %.4f"):format(fade_step_max,step_limit))

-- ------------------------------------------------------- restartability -----
-- The director's contract is that enter() resets a scene's state, so the same
-- scene produces the same frames on every loop. This catches state that leaks
-- across a loop, which is what an incomplete enter() looks like.
section("restartability")
local function signature(calls)
	local parts={}
	for _,c in ipairs(calls) do
		parts[#parts+1]=("%s:%s,%s,%s,%s,%s"):format(c.kind,
			tostring(c.x),tostring(c.y),tostring(c.x2),tostring(c.y2),tostring(c.c))
	end
	return table.concat(parts,"|")
end

local sample=20                          -- frames sampled from each scene
local function capture()
	local seen={}
	for _=1,loop_frames do
		tic.reset()
		tic.frame()
		local n=scenes[scene_index].name
		seen[n]=seen[n] or {}
		if #seen[n]<sample then seen[n][#seen[n]+1]=signature(tic.calls) end
	end
	return seen
end
-- Two windows of exactly loop_frames are already in phase with each other, so
-- both sample the same frames of each scene without needing to align first.
local pass1=capture()
local pass2=capture()
local drift={}
for name,sigs in pairs(pass1) do
	local other=pass2[name]
	if not other then
		drift[#drift+1]=name.." missing from second loop"
	else
		for i=1,#sigs do
			if sigs[i]~=other[i] then
				drift[#drift+1]=("%s differs at sampled frame %d"):format(name,i)
				break
			end
		end
	end
end
ok(#drift==0,"each scene draws identically on every loop",table.concat(drift,"; "))

-- ---------------------------------------------------------- allocation ------
-- Recording allocates, so it is off here; the demo itself should allocate
-- nothing per frame.
section("allocation")
tic.recording=false
for _=1,200 do tic.frame() end
collectgarbage("collect")
local before=collectgarbage("count")
collectgarbage("stop")
for _=1,loop_frames do tic.frame() end
local growth=collectgarbage("count")-before
collectgarbage("restart")
tic.recording=true
ok(growth<1,"no heap growth over a full loop with the collector stopped",
	("%.2f KB over %d frames"):format(growth,loop_frames))

-- -------------------------------------------------------- copper bars -------
-- Scene-specific, and both of these are regressions.
section("copper bars")
if bars_build and line_s and bar_h and isin then
	local half=bar_h/2

	-- Does each bar cover its whole falloff? The loop used to run for exactly
	-- bar_h lines from floor(cy-half), which truncated the bottom edge while
	-- leaving the top soft -- a hard line under every bar. Measured from what
	-- bars_build actually produced, with one bar so the extent is unambiguous;
	-- recomputing the falloff here instead would only re-test the formula.
	local saved=bars
	bars={{hue={255,255,255},amp=44,speed=1,phase=0}}
	local trunc=nil
	for t=0,2000 do
		bars_build(t)
		local cy=tic.SCREEN_H/2+isin(t)*44
		local mn,mx
		for y=0,tic.SCREEN_H-1 do
			if line_s[y]>0 then
				mn=mn or y
				mx=y
			end
		end
		-- skip frames where the screen edge does the clipping
		if mn and mn>0 and mx<tic.SCREEN_H-1 then
			local want_mn=math.floor(cy-half)+1
			local want_mx=math.ceil(cy+half)-1
			if mn~=want_mn or mx~=want_mx then
				trunc=("t=%d cy=%.2f: covered %d..%d, expected %d..%d")
					:format(t,cy,mn,mx,want_mn,want_mx)
				break
			end
		end
	end
	bars=saved
	ok(trunc==nil,"each bar covers its full falloff",trunc)

	-- With all the bars running, brightness along the screen should never jump
	-- more than one step of the falloff. A truncated edge or a dim bar painted
	-- over a bright one (which is what later-wins-over-brightest did where two
	-- bars cross) both show up as a cliff here.
	local limit=(1-(1-2/bar_h)^2)*1.3
	local worst,where=0,nil
	for t=0,2000 do
		bars_build(t)
		for y=1,tic.SCREEN_H-1 do
			local step=math.abs(line_s[y]-line_s[y-1])
			if step>worst then
				worst=step
				where=("t=%d line %d: %.2f -> %.2f"):format(t,y,line_s[y-1],line_s[y])
			end
		end
	end
	ok(worst<=limit,"brightness never jumps more than one falloff step",
		("largest %.3f, limit %.3f (%s)"):format(worst,limit,where or "-"))
else
	out("  skip  copper bar checks (scene not present)")
end

-- -------------------------------------------------------------- done --------
out(("\n%d checks, %d failed"):format(checks,failures))
os.exit(failures==0 and 0 or 1)
