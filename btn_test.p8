pico-8 cartridge // http://www.pico-8.com
version 16
__lua__

-- rg35xx button tester
-- fake-08 button mapping:
--   btn(0)=left  btn(1)=right  btn(2)=up  btn(3)=down
--   btn(4)=b     btn(5)=a
--   btn(6)=start btn(7)=select

-- draw a circular face button
function cbtn(x,y,r,label,pressed,pc)
 circfill(x,y,r, pressed and pc or 1)
 circ(x,y,r, pressed and 7 or 5)
 local lx = x - (#label==1 and 1 or 3)
 print(label, lx, y-3, pressed and 7 or 13)
end

-- draw a dpad arm rect
function darm(x0,y0,x1,y1,pressed)
 rectfill(x0,y0,x1,y1, pressed and 6 or 5)
 rect(x0,y0,x1,y1, pressed and 7 or 13)
end

-- draw a small pill button (start/select)
function pbtn(x,y,label,pressed)
 local w=#label*4+3
 rectfill(x,y,x+w,y+6, pressed and 5 or 1)
 rect(x,y,x+w,y+6, pressed and 7 or 5)
 print(label, x+2, y+1, pressed and 7 or 13)
end

-- draw a shoulder button
function sbtn(x,y,label,pressed)
 rectfill(x,y,x+19,y+6, pressed and 6 or 1)
 rect(x,y,x+19,y+6, pressed and 7 or 5)
 print(label, x+3, y+1, pressed and 7 or 13)
end

function _draw()
 cls(0)

 -- background body
 rectfill(4,12,123,118,1)
 rect(4,12,123,118,5)

 -- top shoulders strip
 rect(4,12,43,18,5)
 rect(84,12,123,18,5)

 -- screen bezel
 rectfill(44,15,83,42,0)
 rect(44,15,83,42,13)
 rect(45,16,82,41,5)

 -- title
 print("btn test",47,18,5)

 -- active button name on screen
 local active=""
 if btn(0) then active=active.."L " end
 if btn(1) then active=active.."R " end
 if btn(2) then active=active.."U " end
 if btn(3) then active=active.."D " end
 if btn(4) then active=active.."B " end
 if btn(5) then active=active.."A " end
 if btn(6) then active=active.."ST " end
 if btn(7) then active=active.."SE" end
 if active=="" then active="--" end
 print(active, 47, 30, 11)

 -- ===== L1 / R1 shoulders =====
 sbtn(5,13,"l1",btn(8))
 sbtn(99,13,"r1",btn(9))

 -- ===== D-PAD =====
 -- center at (32, 80)
 local cx,cy=32,80
 local aw,al=5,8  -- arm width half, arm length

 darm(cx-aw, cy-al-aw, cx+aw, cy-al,   btn(2))  -- up
 darm(cx-aw, cy+al,    cx+aw, cy+al+aw,btn(3))  -- down
 darm(cx-al-aw, cy-aw, cx-al, cy+aw,   btn(0))  -- left
 darm(cx+al,    cy-aw, cx+al+aw, cy+aw,btn(1))  -- right
 -- center piece
 rectfill(cx-aw,cy-aw,cx+aw,cy+aw,5)

 -- dpad direction arrows
 print("\14",cx-2,cy-al-aw-1,btn(2) and 7 or 5)  -- up arrow
 print("\15",cx-2,cy+al+aw+1,btn(3) and 7 or 5)  -- down
 print("\16",cx-al-aw-5,cy-3,btn(0) and 7 or 5)  -- left
 print("\17",cx+al+aw+1,cy-3,btn(1) and 7 or 5)  -- right

 -- ===== SELECT / START =====
 pbtn(47,80,"sel",btn(7))
 pbtn(68,80,"sta",btn(6))

 -- ===== FACE BUTTONS =====
 -- RG35XX layout: X=top Y=left A=right B=bottom
 -- fake-08: btn(4)=b  btn(5)=a  (x and y not standard, share a/b or unmapped)
 local bx,by=97,78
 local br=7

 -- X (top)
 cbtn(bx,    by-br-3, br, "x", false,   12)
 -- Y (left)
 cbtn(bx-br-3,by,     br, "y", false,   11)
 -- A (right) = btn(5)
 cbtn(bx+br+3,by,     br, "a", btn(5),  8)
 -- B (bottom) = btn(4)
 cbtn(bx,    by+br+3, br, "b", btn(4),  9)

 -- note under face buttons
 print("x/y=unmapped",bx-20,by+br+14,5)

 -- ===== STATUS BAR =====
 rectfill(4,108,123,118,0)
 rect(4,108,123,118,5)
 print("active:",6,110,5)

 local blist={
  {0,"L",10},{1,"R",10},{2,"U",10},{3,"D",10},
  {4,"B",9},{5,"A",8},{6,"ST",3},{7,"SE",3}
 }
 local sx=40
 for i=1,#blist do
  local b=blist[i]
  local p=btn(b[1])
  rectfill(sx,109,sx+11,117, p and b[3] or 0)
  rect(sx,109,sx+11,117, p and 7 or 5)
  print(b[2], sx+1, 111, p and 7 or 13)
  sx=sx+13
 end

end

function _update()
end
__gfx__
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
