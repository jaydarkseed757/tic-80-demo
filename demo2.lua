-- title:  demo with rotating cube
-- author: Jay
-- desc:   bouncing sprite, scroller, wireframe 3D cube
-- script: lua

-- screen geometry
scr_w=240
scr_h=136
spr_size=8

-- the scroller owns the top strip, down to the divider line
hud_h=14

-- sprite position
x=120
y=68

-- sprite velocity
vx=1
vy=1

-- scroller variables
scroll_x=scr_w
scroll_text="WELCOME TO TIC-80! * ROTATING 3D CUBE * CLASSIC DEMO EFFECTS * GREETINGS TO ALL RETRO CODERS * "
-- measure the real rendered width offscreen rather than assuming 6px per glyph,
-- so the wrap stays correct if the font is ever changed
scroll_w=print(scroll_text,0,-8)
color_cycle=0

-- rotation angles
rx=0
ry=0
rz=0

-- cube vertices
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

-- rotated/projected vertices, reused every frame so the draw loop allocates nothing
proj={}
for i=1,#cube do proj[i]={0,0,0} end

-- edge draw order, sorted back to front each frame
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

function TIC()
	-- update sprite position
	x=x+vx
	y=y+vy

	-- bounce off the edges, staying clear of the scroller strip
	if x<=0 or x>=scr_w-spr_size then vx=-vx end
	if y<=hud_h or y>=scr_h-spr_size then vy=-vy end

	-- update scroller
	scroll_x=scroll_x-1
	if scroll_x<-scroll_w then scroll_x=scr_w end

	-- update color cycle slowly, skipping 0 so the text is never black on black
	color_cycle=color_cycle+0.05
	local text_color=1+math.floor(color_cycle)%15

	-- update rotation
	rx=rx+0.02
	ry=ry+0.03
	rz=rz+0.01

	-- clear screen
	cls(0)

	-- draw scroller with color cycling
	print(scroll_text,scroll_x,2,text_color)
	line(0,12,scr_w-1,12,13)

	-- rotate and project each vertex once, then reuse it for all three of its edges
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

	-- vertices on top of the wireframe
	for i=1,#proj do
		local p=proj[i]
		circ(p[1],p[2],2,depth_color(p[3]))
	end

	-- draw sprite
	spr(1,x,y,0)
end

-- <TILES>
-- 001:0022220020444402424444244234432432333323323333232033330200222200
-- </TILES>
