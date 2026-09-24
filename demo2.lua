-- title:  demo
-- author: Jay
-- desc:   copper bars, DYCP scroller, wireframe cube
-- script: lua

-- screen geometry
scr_w=240
scr_h=136
spr_size=8

-- the cube scene's scroller owns the top strip, down to the divider line
hud_h=14

-- ---------------------------------------------------------------- palette ---
-- SWEETIE-16, TIC-80's default, kept as data so the whole palette can be
-- rewritten each frame scaled by `fade`. Fading the palette rather than the
-- pixels is how the originals did transitions: it costs 48 pokes a frame and
-- works no matter what is on screen.
pal_addr=0x3FC0
pal_default={
	{0x1a,0x1c,0x2c},{0x5d,0x27,0x5d},{0xb1,0x3e,0x53},{0xef,0x7d,0x57},
	{0xff,0xcd,0x75},{0xa7,0xf0,0x70},{0x38,0xb7,0x64},{0x25,0x71,0x79},
	{0x29,0x36,0x6f},{0x3b,0x5d,0xc9},{0x41,0xa6,0xf6},{0x73,0xef,0xf7},
	{0xf4,0xf4,0xf4},{0x94,0xb0,0xc2},{0x56,0x6c,0x86},{0x33,0x3c,0x57}
}
fade=1

function set_pal(i,r,g,b)
	local a=pal_addr+i*3
	poke(a,math.floor(r*fade))
	poke(a+1,math.floor(g*fade))
	poke(a+2,math.floor(b*fade))
end

-- rewrite every entry at the current fade level; scenes that touch the palette
-- mid-frame (see SCN) override individual entries on top of this
function reset_pal()
	for i=0,15 do
		local c=pal_default[i+1]
		set_pal(i,c[1],c[2],c[3])
	end
end

-- ------------------------------------------------------------ sine tables ---
-- precomputed because every effect below wants the same wave, and a table
-- read is roughly three times cheaper than math.sin
sin_len=256
sin_tab={}
for i=0,sin_len-1 do sin_tab[i]=math.sin(i/sin_len*2*math.pi) end

function isin(i)
	return sin_tab[math.floor(i)%sin_len]
end

-- --------------------------------------------------------- copper bars -----
-- Colour 0 is the background, so repoking palette entry 0 once per scanline
-- paints a full-screen gradient for no per-pixel cost at all. This is the
-- Amiga copper trick: the framebuffer stores indices and the palette is
-- sampled at scanout, so changing it part-way down the frame only affects the
-- lines below. 136 scanlines x 16 entries is also how you escape the 16
-- colour limit.
bar_h=20
bars={
	{hue={0x73,0xef,0xf7},amp=44,speed=0.9,phase=0},
	{hue={0x41,0xa6,0xf6},amp=52,speed=-1.3,phase=64},
	{hue={0xef,0x7d,0x57},amp=38,speed=1.7,phase=128},
	{hue={0xa7,0xf0,0x70},amp=48,speed=-0.7,phase=192}
}

-- per-scanline colour, rebuilt in update and consumed by SCN
line_r={}
line_g={}
line_b={}
for i=0,scr_h-1 do line_r[i]=0 line_g[i]=0 line_b[i]=0 end

function bars_build(t)
	for y=0,scr_h-1 do
		line_r[y]=0
		line_g[y]=0
		line_b[y]=0
	end
	for i=1,#bars do
		local b=bars[i]
		local cy=scr_h/2+isin(b.phase+t*b.speed)*b.amp
		local half=bar_h/2
		local top=math.floor(cy-half)
		local hue=b.hue
		for y=top,top+bar_h-1 do
			if y>=0 and y<scr_h then
				-- squared falloff from the middle, so each bar reads as a
				-- rounded tube rather than a flat stripe
				local d=(y-cy)/half
				local s=1-d*d
				if s>0 then
					-- later bars paint over earlier ones, as a copper list did
					line_r[y]=hue[1]*s
					line_g[y]=hue[2]*s
					line_b[y]=hue[3]*s
				end
			end
		end
	end
end

-- last colour written this frame, so unchanged scanlines cost nothing. A real
-- copper list only emitted a write where the colour actually changed, and most
-- lines here are plain background.
bars_last_r=-1
bars_last_g=-1
bars_last_b=-1

function bars_scanline(line)
	local r=line_r[line]
	if not r then return end
	local g,b=line_g[line],line_b[line]
	if r==bars_last_r and g==bars_last_g and b==bars_last_b then return end
	bars_last_r=r
	bars_last_g=g
	bars_last_b=b
	set_pal(0,r,g,b)
end

-- ------------------------------------------------------------ DYCP logo -----
logo_text="TIC-80"
logo_scale=4
-- measured rather than assumed, so it stays centred if the text or font change
logo_w=print(logo_text,0,-64,0,true,logo_scale)
logo_x=(scr_w-logo_w)//2
logo_y=24

function logo_draw(t)
	local y=logo_y+isin(t*0.8)*4
	-- three passes, darkest first, for a cheap bevel
	print(logo_text,logo_x+3,y+3,15,true,logo_scale)
	print(logo_text,logo_x+1,y+1,14,true,logo_scale)
	print(logo_text,logo_x,y,12,true,logo_scale)
end

-- -------------------------------------------------------- DYCP scroller -----
-- "Different Y Char Position": every character gets its own Y from the sine
-- table, which is the signature C64 scroller and the reason it was hard on
-- real hardware. Here it is just one print per character.
dycp_text="** GREETINGS FROM TIC-80 ** COPPER BARS AND A DYCP SCROLLER LIKE IT IS 1989 ** "
dycp_scale=2
dycp_char_w=print("W",0,-64,0,true,dycp_scale)
dycp_amp=20
dycp_y=scr_h-46
dycp_x=scr_w
dycp_colors={12,11,10,4,3,2,5,6}
-- split once at init so the draw loop does no string work
dycp_chars={}
for i=1,#dycp_text do dycp_chars[i]=dycp_text:sub(i,i) end

function dycp_draw(t)
	for i=1,#dycp_text do
		local cx=dycp_x+(i-1)*dycp_char_w
		-- only the handful of characters actually on screen are drawn
		if cx>-dycp_char_w and cx<scr_w then
			local cy=dycp_y+isin(t*2+i*14)*dycp_amp
			local ch=dycp_chars[i]
			local col=dycp_colors[(i+math.floor(t/4))%#dycp_colors+1]
			print(ch,cx+2,cy+2,15,true,dycp_scale)
			print(ch,cx,cy,col,true,dycp_scale)
		end
	end
end

-- ------------------------------------------------------------ cube scene ----
scroll_x=scr_w
scroll_text="WELCOME TO TIC-80! * ROTATING 3D CUBE * CLASSIC DEMO EFFECTS * GREETINGS TO ALL RETRO CODERS * "
-- measure the real rendered width offscreen rather than assuming 6px per glyph
scroll_w=print(scroll_text,0,-8)
color_cycle=0

-- sprite position and velocity
x=120
y=68
vx=1
vy=1

rx=0
ry=0
rz=0

cube={
	{-20,-20,-20},{20,-20,-20},{20,20,-20},{-20,20,-20},
	{-20,-20,20},{20,-20,20},{20,20,20},{-20,20,20}
}

-- the 12 edges: back face, front face, then the struts joining them
edges={
	{1,2},{2,3},{3,4},{4,1},
	{5,6},{6,7},{7,8},{8,5},
	{1,5},{2,6},{3,7},{4,8}
}

-- distance from the cube centre to any vertex, so depth shading can normalise z
cube_r=20*math.sqrt(3)
cube_cx=120
cube_cy=68
fov=200

-- reused every frame so the draw loop allocates nothing
proj={}
for i=1,#cube do proj[i]={0,0,0} end
order={}
for i=1,#edges do order[i]=i end

-- dimmest to brightest: the further away an edge is, the darker it is drawn
depth_shades={8,9,10,11,12}

function depth_color(z)
	local t=(z+cube_r)/(2*cube_r)
	local i=math.floor(t*#depth_shades)+1
	if i<1 then i=1 end
	if i>#depth_shades then i=#depth_shades end
	return depth_shades[i]
end

-- sin/cos are passed in because all eight vertices share the same three angles
function rotate3d(px,py,pz,ca,sa,cb,sb,cc,sc)
	-- rotate around x
	local y1=py*ca-pz*sa
	local z1=py*sa+pz*ca
	-- rotate around y
	local x2=px*cb-z1*sb
	local z2=px*sb+z1*cb
	-- rotate around z
	local x3=x2*cc-y1*sc
	local y3=x2*sc+y1*cc
	return x3,y3,z2
end

function edge_depth(i)
	local e=edges[i]
	return proj[e[1]][3]+proj[e[2]][3]
end

function farther_first(a,b)
	return edge_depth(a)<edge_depth(b)
end

-- -------------------------------------------------------------- scenes ------
-- A scene is {name, dur, enter, update, draw, scanline}. `dur` is in frames.
-- The director owns nothing but time; each scene owns its own state and resets
-- it in enter(), so scenes are restartable and the demo can loop.
scenes={
	{
		name="copper bars",
		dur=60*14,
		enter=function()
			dycp_x=scr_w
		end,
		update=function(t)
			bars_build(t)
			-- reset_pal has just rewritten entry 0, so force the first
			-- scanline of this frame to write
			bars_last_r=-1
			dycp_x=dycp_x-2
			if dycp_x<-#dycp_text*dycp_char_w then dycp_x=scr_w end
		end,
		draw=function(t)
			-- colour 0 is the copper gradient, painted per scanline by SCN
			cls(0)
			logo_draw(t)
			dycp_draw(t)
		end,
		scanline=bars_scanline
	},
	{
		name="wireframe cube",
		dur=60*12,
		enter=function()
			x=120
			y=68
			scroll_x=scr_w
		end,
		update=function(t)
			-- move the sprite and bounce it off the edges, staying clear of
			-- the scroller strip
			x=x+vx
			y=y+vy
			if x<=0 or x>=scr_w-spr_size then vx=-vx end
			if y<=hud_h or y>=scr_h-spr_size then vy=-vy end

			scroll_x=scroll_x-1
			if scroll_x<-scroll_w then scroll_x=scr_w end

			color_cycle=color_cycle+0.05

			rx=rx+0.02
			ry=ry+0.03
			rz=rz+0.01
		end,
		draw=function(t)
			cls(0)

			-- skip 0 so the text is never black on black
			local text_color=1+math.floor(color_cycle)%15
			print(scroll_text,scroll_x,2,text_color)
			line(0,12,scr_w-1,12,13)

			-- rotate and project each vertex once, then reuse it for all
			-- three of its edges
			local ca,sa=math.cos(rx),math.sin(rx)
			local cb,sb=math.cos(ry),math.sin(ry)
			local cc,sc=math.cos(rz),math.sin(rz)
			for i=1,#cube do
				local px,py,pz=rotate3d(cube[i][1],cube[i][2],cube[i][3],ca,sa,cb,sb,cc,sc)
				local scale=fov/(fov+pz)
				local p=proj[i]
				p[1]=px*scale+cube_cx
				p[2]=py*scale+cube_cy
				p[3]=pz
			end

			-- draw the wireframe back to front so near edges overlap far ones
			table.sort(order,farther_first)
			for i=1,#order do
				local e=edges[order[i]]
				local a,b=proj[e[1]],proj[e[2]]
				line(a[1],a[2],b[1],b[2],depth_color((a[3]+b[3])/2))
			end

			for i=1,#proj do
				local p=proj[i]
				circ(p[1],p[2],2,depth_color(p[3]))
			end

			spr(1,x,y,0)
		end
	}
}

-- ------------------------------------------------------------- director -----
scene_index=1
scene_frame=0
fade_frames=30

function update_fade()
	local d=scenes[scene_index].dur
	if scene_frame<fade_frames then
		fade=scene_frame/fade_frames
	elseif scene_frame>d-fade_frames then
		fade=(d-scene_frame)/fade_frames
	else
		fade=1
	end
	if fade<0 then fade=0 end
	if fade>1 then fade=1 end
end

-- called once per scanline before it is drawn, which is where any palette
-- trickery has to happen. Older TIC-80 builds name this callback `scanline`.
function SCN(line)
	local s=scenes[scene_index].scanline
	if s then s(line) end
end
scanline=SCN

function TIC()
	local s=scenes[scene_index]
	update_fade()
	-- re-establish the full palette at the current fade before the scene gets
	-- a chance to override entries in SCN
	reset_pal()

	s.update(scene_frame)
	s.draw(scene_frame)

	scene_frame=scene_frame+1
	if scene_frame>=s.dur then
		scene_frame=0
		scene_index=scene_index%#scenes+1
		scenes[scene_index].enter()
	end
end

scenes[scene_index].enter()

-- <TILES>
-- 001:0022220020444402424444244234432432333323323333232033330200222200
-- </TILES>
