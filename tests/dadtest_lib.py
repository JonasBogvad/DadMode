import lupa, math, sys
L=lupa.LuaRuntime()
L.execute(r'''
math.atan2 = math.atan2 or math.atan
local noop=function() end
local function widget(kind)
  local w={shown=true,kind=kind}
  return setmetatable(w,{__index=function(t,k)
    if k=="IsShown" then return function(s) return s.shown end end
    if k=="Show" then return function(s) s.shown=true end end
    if k=="Hide" then return function(s) s.shown=false end end
    if k=="SetShown" then return function(s,v) s.shown=v and true or false end end
    if k=="CreateFontString" then return function() return widget("fs") end end
    if k=="CreateTexture" then return function() return widget("tex") end end
    if k=="SetText" then return function(s,x) assert(type(x)=="string"); s.txt=x end end
    if k=="GetStringWidth" then return function() return 400 end end
    if k=="GetCenter" then return function() return 400,300 end end
    if k=="GetWidth" then return function() return 140 end end
    if k=="GetEffectiveScale" then return function() return 1 end end
    if k=="GetStringHeight" then return function() return 40 end end
    if k=="SetAlpha" then return function(s,a) s.alpha=a end end
    if k=="SetAlphaFromBoolean" then return function(s,v,a,b) s.alpha="game decides" end end
    if k=="SetRotation" then return function(s,x) s.rot=x end end
    if k=="SetScript" then return function(s,n,f) s["on"..n]=f end end
    if k=="SetAttribute" then return function(s,a,v) local t=rawget(s,"attr") or {}; rawset(s,"attr",t); t[a]=v end end
    if k=="who" or k=="hideAt" or k=="asked" or k=="errorShown" or k=="dragging" or k=="pulsing" then return nil end
    if k=="StopMovingOrSizing" then return function(s) assert(not fight,"BLOCKED: StopMovingOrSizing in a fight"); rawset(s,"stopped",(rawget(s,"stopped") or 0)+1) end end
    if k=="GetPoint" then return function() return "CENTER",nil,"CENTER",1,2 end end
    return noop end})
end
frames={}
function CreateFrame(kind,name) local w=widget(kind); frames[#frames+1]=w; if name then _G[name]=w end; return w end
UIParent=widget(); UISpecialFrames={}; SlashCmdList={}
Minimap=widget(); GameTooltip=widget()
registered=nil
local libs={["LibDataBroker-1.1"]={NewDataObject=function(self,name,o) return o end},
  ["LibDBIcon-1.0"]={Register=function(self,name,o,dbt) registered=o end, Hide=function() hidden=true end, Show=function() hidden=false end}}
function LibStub(n) return assert(libs[n]) end
function GetCursorPosition() return 500,300 end
clock=100; function GetTime() return clock end
units={player={name="Dad",n=1000,w=500}, party1={name="Saqu",n=1100,w=500}, party2={name="Bro",n=1000,w=550}}
facing=0
function UnitExists(u) return units[u]~=nil end
function UnitName(u) return units[u] and units[u].name end
function UnitIsConnected(u) return units[u] and not units[u].offline end
inrange=true; rangeSecret=false; SECRET={}
function UnitInRange(u) if rangeSecret then return SECRET, true end return inrange, true end
function issecretvalue(v) return v==SECRET end
function UnitPosition(u) local x=units[u]; if not x or x.hidden then return nil end return x.n,x.w,0,x.inst or 1 end
function GetPlayerFacing() return facing end
function IsInGroup() return true end
timers={}; C_Timer={After=function(_,f) timers[#timers+1]=f end}
fight=false
function InCombatLockdown() return fight end
sounds=0; lastSound=nil; function PlaySound(id) sounds=sounds+1; lastSound=id end
sent={}
qlog={ {isHeader=true,title="Stranglethorn"},
  {title="Stolen Shipment",questID=101,level=37}, {title="Where's the Key?",questID=102,level=38},
  {title="Bloodscalp Ears; and more ~ stuff",questID=103,level=36} }
C_QuestLog={GetNumQuestLogEntries=function() return #qlog end, GetInfo=function(i) return qlog[i] end,
  IsComplete=function(id) return id==102 end, IsOnQuest=function(id) return id==101 end,
  GetQuestObjectives=function(id) if id==101 then return {{text="0/8 Stolen Shipment",finished=false}} elseif id==103 then return {{text="10/15 Bloodscalp Ear",finished=false},{text="20/20 Shrunken Head",finished=true}} end return {} end}
function UnitLevel() return 37 end function UnitXP() return 6200 end function UnitXPMax() return 10000 end
function GetMoney() return 124050 end function UnitIsDeadOrGhost() return false end function UnitIsAFK() return false end
function UnitAffectingCombat() return true end
function GetRealZoneText() return "Stranglethorn Vale" end function GetSubZoneText() return "Nesingwary's Expedition" end
function GetBindLocation() return "Orgrimmar" end
function GetInventoryItemDurability(slot) if slot==5 then return 0,100 elseif slot==7 then return 41,100 end end
bagitems={ {itemID=1,stackCount=12}, {itemID=2,stackCount=4}, {itemID=3,stackCount=1} }
C_Container={GetContainerNumSlots=function(b) return b<=3 and 16 or 0 end, GetContainerNumFreeSlots=function(b) return b==0 and 3 or 0, 0 end,
  GetContainerItemInfo=function(b,sl) if b==0 then return bagitems[sl] end end, GetItemCooldown=function() return 100, 1800 end}
worn={[1]=7001,[5]=7005,[7]=7007,[16]=7016}
function GetInventoryItemID(u,slot) return worn[slot] end
C_Item={GetItemInfoInstant=function(id) return id,"","","",0,0,(id==1 and 5) or (id==2 and 7) or 1 end,
  GetItemInfo=function(id) if id==7016 then return nil end local n={[7001]="Silk Headband",[7005]="Robes of Arcana",[7007]="Azure Silk Pants",[1]="Ice Cold Milk",[2]="Heavy Wool Bandage",[3]="Lesser Healing Potion"} return n[id],nil,2,30+(id-7000) end,
  RequestLoadItemDataByID=function() end}
pin=nil; setpin=nil; tracked=false
C_Map={GetAreaInfo=function(id) return id==33 and "Stranglethorn Vale" or nil end,
  HasUserWaypoint=function() return pin~=nil or setpin~=nil end, GetUserWaypoint=function() return pin or setpin end,
  GetBestMapForUnit=function() return 1434 end, GetPlayerMapPosition=function() return {GetXY=function() return 0.2812,0.7441 end} end,
  CanSetUserWaypointOnMap=function(id) return id~=999 end, SetUserWaypoint=function(p) setpin=p end, ClearUserWaypoint=function() setpin=nil end}
function CreateVector2D(x,y) return {x=x,y=y} end
C_Map.GetWorldPosFromMapPos=function(map,v) return 1,{GetXY=function() return 1000+v.x*1000, 500+v.y*1000 end} end
UiMapPoint={CreateFromCoordinates=function(m,x,y) return {uiMapID=m,position={x=x,y=y}} end}
C_SuperTrack={SetSuperTrackedUserWaypoint=function(v) tracked=v end}
QuestieLoader={ImportModule=function(self,name) return {
 QueryNPCSingle=function(id,field) if id==2495 then return field=="name" and "Zimmix Sputterspark" or field=="zoneID" and 33 or nil end end,
 QueryObjectSingle=function() end,
 QueryQuestSingle=function(id,field)
  if field=="finishedBy" then return id==102 and {{2495},nil} or id==101 and {{2495},nil} or nil end
  if field=="nextQuestInChain" then return id==102 and 555 or 0 end
  if id==555 and field=="name" then return "Zimmix's Great Escape" end
  if id==555 and field=="questLevel" then return 39 end end} end}
C_AddOns={GetAddOnMetadata=function() return "1.3.4" end}
C_ChatInfo={RegisterAddonMessagePrefix=noop, SendAddonMessage=function(p,t,c) sent[#sent+1]={p,t,c} end}
''')
# load the files the way the game does: in the order of the .toc, each with (addon name, shared table)
import os as _os
_dir=_os.path.dirname(_os.path.abspath(sys.argv[1]))
L.execute('DadModeNS={}')
_load=L.eval('function(src,name) local f,e=(loadstring or load)(src,"@"..name); if not f then error(e) end; return f("DadMode", DadModeNS) end')
_files=[l.strip() for l in open(_os.path.join(_dir,'DadMode.toc')) if l.strip().endswith('.lua')]
assert _files and _files[0]=='Core.lua', _files
for _f in _files: _load(open(_os.path.join(_dir,_f)).read(), _f)
L.execute(r'''
local ev, tick
for _,f in ipairs(frames) do if rawget(f,"onOnEvent") then ev=f.onOnEvent end end
local function fire(e,...) ev(nil,e,...) end
DadModeDB={enabled=true}      -- a computer that already used DadMode
fire("ADDON_LOADED","DadMode"); fire("PLAYER_LOGIN")
-- these tests are about everything else: both test guides are already approved
DadModeDB.guides={["bro bearfang"]={name="Bro Bearfang",state="yes"},["saqu off"]={name="Saqu Off",state="yes"}}
assert(not DadModeRole.shown and DadModeDB.roleChosen,"existing installs are not asked")
for _,f in ipairs(frames) do if rawget(f,"onOnUpdate") then tick=f.onOnUpdate end end
local function near(a,b,m) assert(a and math.abs(a-b)<1e-6, m.." got "..tostring(a).." want "..b) end
local d,a=DadMode_Locate("party1"); near(d,100,"dist north"); near(a,0,"north = straight up")
d,a=DadMode_Locate("party2"); near(d,50,"dist west"); near(a,math.pi/2,"west = turn left")
facing=math.pi/2; d,a=DadMode_Locate("party1"); near(a,-math.pi/2,"facing west, target north = right")
facing=0
units.party1.hidden=true; d,a=DadMode_Locate("party1"); assert(d==nil and a=="unknown")
units.party1.hidden=nil; units.player.hidden=true; d,a=DadMode_Locate("party1"); assert(d==nil and a=="dungeon")
units.player.hidden=nil; units.party2.inst=2; d,a=DadMode_Locate("party2"); assert(d==nil and a=="elsewhere"); units.party2.inst=nil
fire("GROUP_ROSTER_UPDATE"); assert(DadModePicker.shown,"picker opens")
-- it asks once in a lifetime, not every party
assert(DadModeDB.askedOnce and not DadModePicker.showSettings,"asked once, settings folded away")
DadModePicker.shown=false; fire("GROUP_ROSTER_UPDATE"); assert(not DadModePicker.shown,"no second pop-up")
-- and never for a helper
DadModeDB.askedOnce=nil; DadModeDB.helper=true; fire("GROUP_ROSTER_UPDATE"); assert(not DadModePicker.shown,"helpers are never asked")
DadModeDB.helper=false; DadModeDB.askedOnce=true
-- compact window: settings hidden until asked for
local PW=DadModePicker; SlashCmdList.DADMODE("")
assert(PW.shown and not PW.size.shown and not PW.callSound.shown and not PW.role.shown and PW.close.shown and PW.more.label.txt=="Settings","compact view")
PW.more.onOnClick(PW.more); assert(PW.size.shown and PW.callSound.shown and not PW.role.shown and PW.more.label.txt=="Fewer options","settings shown")
assert(PW.size.label.txt=="Arrow size: Medium"); PW.size.onOnClick(PW.size); assert(DadModeDB.arrowSize==3 and PW.size.label.txt=="Arrow size: Large")
PW.size.onOnClick(PW.size); assert(DadModeDB.arrowSize==1 and PW.size.label.txt=="Arrow size: Small"); PW.size.onOnClick(PW.size)
PW.more.onOnClick(PW.more); assert(not PW.size.shown)
DadModeDB.alerts=false; SlashCmdList.DADMODE(""); assert(PW.role.shown and PW.role.label.txt:find("CALLS ARE OFF"),"calls-off warning shows even with settings folded")
DadModeDB.alerts=true; PW.shown=true
-- dungeon: no positions at all
DadModeDB.marked.Saqu=true
for _,u in pairs(units) do u.hidden=true end
tick(nil,0.1)
local slot; for _,f in ipairs(frames) do if rawget(f,"near") then slot=f end end
assert(slot and slot.near.shown and slot.far.shown and slot.near.alpha==1 and slot.far.alpha==0,"in range in a dungeon")
inrange=false; tick(nil,0.1); assert(slot.near.alpha==0 and slot.far.alpha==1,"too far in a dungeon")
rangeSecret=true; tick(nil,0.1); assert(slot.far.alpha=="game decides","secret value handed to the game")
for _,u in pairs(units) do u.hidden=nil end
tick(nil,0.1); assert(not slot.near.shown and not slot.far.shown,"labels gone outdoors")
DadModeDB.marked.Saqu=nil
local P=DadModePicker
assert(P.names[1].who=="Saqu" and P.names[2].who=="Bro" and not P.names[3].shown)
P.names[1].onOnClick(P.names[1]); assert(DadModeDB.marked.Saqu)
tick(nil,0.1); assert(DadModeBar.shown,"bar shown")
local FB=DadModeFollow
assert(FB.shown and FB.attr.macrotext=="/follow party1" and FB.label.txt=="FOLLOW Saqu","follow button")
-- a call from Bro switches it, but not during a fight
fight=true
fire("CHAT_MSG_PARTY","!dad","Bro Bearfang-CAMWOW EU5 Realm 4 PvP"); tick(nil,0.1); assert(FB.attr.macrotext=="/follow party1","unchanged in a fight")
fight=false; tick(nil,0.1); assert(FB.attr.macrotext=="/follow party2","follows the caller")
-- Bro is far away: no flashing, and the call text says how far
local farD=DadMode_Locate("party2"); assert(farD and farD>30, "test assumes Bro starts far away")
assert(FB.label.txt=="FOLLOW Bro" and not rawget(FB,"pulsing"),"no flash when the caller is too far to follow")
assert(DadModeAlert==nil or true)
local bn,bw=units.party2.n,units.party2.w
units.party2.n,units.party2.w=units.player.n+20,units.player.w; tick(nil,0.1)
assert(FB.label.txt=="CLICK TO FOLLOW Bro" and FB.pulsing,"button flashes once the caller is close")
units.party2.n,units.party2.w=bn,bw; tick(nil,0.1)
assert(FB.label.txt=="FOLLOW Bro" and not FB.pulsing,"and stops when he walks off again")
-- no positions at all: in sight flashes, out of sight does not
units.party2.hidden=true; UnitIsVisible=function() return true end; tick(nil,0.1); assert(FB.pulsing,"dungeon, in sight: flashes")
UnitIsVisible=function() return false end; tick(nil,0.1); assert(not FB.pulsing,"not in sight: calm")
UnitIsVisible=nil; tick(nil,0.1); assert(FB.pulsing,"unknown: flashes like before")
units.party2.hidden=nil; units.party2.n,units.party2.w=units.player.n+20,units.player.w; tick(nil,0.1)
assert(FB.label.txt=="CLICK TO FOLLOW Bro" and FB.pulsing)
fire("CHAT_MSG_PARTY","!dad ok","Bro Bearfang-CAMWOW EU5 Realm 4 PvP"); tick(nil,0.1); assert(FB.attr.macrotext=="/follow party1")
assert(FB.label.txt=="FOLLOW Saqu" and not FB.pulsing,"flash stops")
clock=clock+30
units.party1.n=1300; tick(nil,0.1); clock=clock+5; local s0=sounds; tick(nil,0.1); assert(sounds==s0+1,"far beep")
assert(lastSound==3175,"far away uses the quiet map ping")
clock=clock+5; tick(nil,0.1); assert(sounds==s0+1,"no spam")
local AF; for _,f in ipairs(frames) do if rawget(f,"onOnMouseDown") and rawget(f,"hint") then AF=f end end
clock=clock+70; AF.text:SetText("x"); tick(nil,0.1); assert(sounds==s0+1 and AF.text.txt=="x","a minute later: nothing more, no sound and no text")
-- in another zone on purpose: no warning, a grey arrow that says where they are
units.party1.n=1010; tick(nil,0.1)
local zoneOf={player=1434,party1=1454}; local keepMap=C_Map.GetBestMapForUnit
C_Map.GetBestMapForUnit=function(u) return zoneOf[u] or 1434 end
C_Map.GetMapInfo=function(id) return {name=(id==1454 and "Orgrimmar" or "Stranglethorn Vale")} end
units.party1.n=1300; clock=clock+2; tick(nil,0.1); clock=clock+5; AF.text:SetText("x"); tick(nil,0.1)
assert(sounds==s0+1 and AF.text.txt=="x","in another zone: quiet")
local sq; for _,f in ipairs(frames) do if rawget(f,"near") and rawget(f,"name") and f.name.txt=="Saqu" then sq=f end end
assert(sq and sq.dist.txt=="in Orgrimmar" and sq.arrow.shown, sq and sq.dist.txt or "no arrow for Saqu")
-- a call from there still shows the distance
fire("CHAT_MSG_ADDON","DADMODE","PING:says: come to me","PARTY","Saqu Off-CAMWOW EU5 Realm 4 PvP"); tick(nil,0.1)
assert(sq.dist.txt:find(" yd",1,true),"a call wins over the zone name: "..sq.dist.txt)
fire("CHAT_MSG_ADDON","DADMODE","CLEAR","PARTY","Saqu Off-CAMWOW EU5 Realm 4 PvP"); clock=clock+100; s0=sounds-1
tick(nil,0.1); assert(sq.dist.txt=="in Orgrimmar" and sounds==s0+1,"after the call: quiet again")
-- the same zone again and still far: now it is a real "you are lost"
zoneOf.party1=1434; clock=clock+2; tick(nil,0.1); clock=clock+5; tick(nil,0.1)
assert(sounds==s0+2 and sq.dist.txt:find(" yd",1,true) and AF.text.txt:find("far from Saqu",1,true),"same zone and far: one warning"); s0=s0+1
C_Map.GetBestMapForUnit=keepMap; C_Map.GetMapInfo=nil
units.party1.n=1010; tick(nil,0.1); units.party1.n=1300; tick(nil,0.1); clock=clock+5; tick(nil,0.1)
assert(sounds==s0+2,"came back and drifted off again: one more sound"); s0=s0+1
P.showSettings=true; P.farSound.onOnClick(P.farSound); assert(DadModeDB.sounds.far==3 and lastSound==5274 and P.farSound.label.txt=="Far: Bell"); s0=s0+1
for i=1,3 do P.farSound.onOnClick(P.farSound) end; assert(P.farSound.label.txt=="Far: No sound"); s0=s0+2
P.farSound.onOnClick(P.farSound); P.farSound.onOnClick(P.farSound); assert(DadModeDB.sounds.far==2); s0=s0+2
clock=clock+10
units.party1.n=1200; units.party2.w=700
fire("CHAT_MSG_ADDON","DADMODE","PING:says: come to me","PARTY","Bro Bearfang-CAMWOW EU5 Realm 4 PvP"); assert(sounds==s0+2,"addon ping")
assert(lastSound==8960,"a call uses the ready check sound")
assert(sent[#sent][2]=="ACK" and sent[#sent-1][2]=="VER:1.3.4","version and ack sent back")

assert(AF.shown and AF.text.txt:find("Bro"))
fire("CHAT_MSG_ADDON","DADMODE","PING:again","PARTY","Bro Bearfang-CAMWOW EU5 Realm 4 PvP"); assert(sounds==s0+2,"spam ignored")
tick(nil,0.1)
-- helper cancels
fire("CHAT_MSG_ADDON","DADMODE","CLEAR","PARTY","Bro Bearfang-CAMWOW EU5 Realm 4 PvP"); assert(not AF.shown,"cancel hides text")
-- chat ping, then dad walks to Saqu
clock=clock+10
fire("CHAT_MSG_PARTY","!dad look at me","Saqu Off-CAMWOW EU5 Realm 4 PvP"); assert(sounds==s0+3,"chat ping"); assert(AF.shown)
fire("CHAT_MSG_PARTY","hello dad","Saqu Off-CAMWOW EU5 Realm 4 PvP"); assert(sounds==s0+3)
clock=clock+20; tick(nil,0.1); assert(not AF.shown,"text gone after 10s")
units.party1.n=1005; tick(nil,0.1)
assert(AF.shown and AF.text.txt:find("You found Saqu"),"arrival"); assert(sent[#sent][2]=="HERE")
-- click clears, chat cancel works, strangers and self ignored
clock=clock+10; units.party1.n=1200
fire("CHAT_MSG_PARTY","!dad","Saqu Off-CAMWOW EU5 Realm 4 PvP"); assert(AF.shown); AF.onOnMouseDown(AF); assert(not AF.shown,"click clears")
clock=clock+10; fire("CHAT_MSG_PARTY","!dad come","Saqu Off-CAMWOW EU5 Realm 4 PvP"); assert(AF.shown)
fire("CHAT_MSG_PARTY","!dad ok","Saqu Off-CAMWOW EU5 Realm 4 PvP"); assert(not AF.shown,"chat cancel")
local sn=sounds
fire("CHAT_MSG_WHISPER","!dad","Stranger Danger-CAMWOW EU5 Realm 4 PvP"); fire("CHAT_MSG_ADDON","DADMODE","PING:","PARTY","Dad Oldman-CAMWOW EU5 Realm 4 PvP"); assert(sounds==sn,"strangers and self ignored")
local c0=#sent
SlashCmdList.DADPING("  over here "); assert(sent[#sent][2]=="PING:over here" and sent[#sent][3]=="PARTY")
SlashCmdList.DADMODE("helper"); assert(DadModeDB.helper and DadModeHelper.shown and DadModeDB.alerts==false)
local H=DadModeHelper
assert(H.star.label.txt=="Star on my head")
assert(#H.buttons==8 and H.buttons[1].shown,"8 buttons")
assert(H.star.attr.type1=="macro" and H.star.attr.macrotext1:find("/tm 1") and H.star.attr.type2==nil,"left click marks, right click is not a game action")
assert(H.beam.attr.type1=="worldmarker" and H.beam.attr.action1=="set" and H.beam.attr.marker1==5 and H.beam.attr.type2=="worldmarker" and H.beam.attr.action2=="clear" and H.beam.attr.marker2==5,"beam: left places, right removes")
H.fold.onOnClick(H.fold); assert(DadModeDB.helperFolded and not H.buttons[1].shown and H.fold.label.txt=="+","folded")
fight=true; H.fold.onOnClick(H.fold); assert(DadModeDB.helperFolded,"no unfolding during a fight"); fight=false
H.fold.onOnClick(H.fold); assert(not DadModeDB.helperFolded and H.buttons[1].shown,"unfolded")
H.star.onPostClick(H.star,"LeftButton"); assert((DadModeDB.helperIcon or 1)==1,"left click does not change the icon")
H.star.onPostClick(H.star,"RightButton",true); H.star.onPostClick(H.star,"RightButton",false)
assert(DadModeDB.helperIcon==2 and H.star.label.txt=="Circle on my head" and H.star.attr.macrotext1:find("/tm 2") and H.beam.attr.marker1==6 and H.beam.attr.marker2==6,"right click: next icon, once per click")
clock=clock+1; fight=true; H.star.onPostClick(H.star,"RightButton"); assert(DadModeDB.helperIcon==2,"not in a fight"); fight=false
assert(H.callBtn.label.txt:find("^Call"))
for _,f in ipairs(frames) do if rawget(f,"label") and f.label.txt=="Come to me" then f.onOnClick(f) end end
assert(sent[#sent][2]=="PING:says: come to me", "helper ping")
tick(nil,0.1); assert(H.status.txt:find("Calling"),H.status.txt)
assert(H.callBtn.label.txt:find("Cancel my call"),"call button turns into cancel")
fire("CHAT_MSG_ADDON","DADMODE","VER:1.3.4","PARTY","Bro Bearfang-CAMWOW EU5 Realm 4 PvP")
fire("CHAT_MSG_ADDON","DADMODE","ACK","PARTY","Bro Bearfang-CAMWOW EU5 Realm 4 PvP"); tick(nil,0.1)
assert(H.status.txt:find("Bro got it") and H.status.txt:find("yd"),H.status.txt)
fire("CHAT_MSG_ADDON","DADMODE","HERE","PARTY","Bro Bearfang-CAMWOW EU5 Realm 4 PvP"); tick(nil,0.1)
assert(H.status.txt:find("Bro is with you"),H.status.txt)
H.callBtn.onOnClick(H.callBtn); assert(sent[#sent][2]=="PING:","no call running: it calls")
tick(nil,0.1); assert(H.callBtn.label.txt:find("Cancel my call"))
H.callBtn.onOnClick(H.callBtn); assert(sent[#sent][2]=="CLEAR","cancel sent")
tick(nil,0.1); assert(H.callBtn.label.txt:find("^Call"),"back to call")
-- waypoint button: send, then the same button removes
pin=nil; assert(H.wpBtn.label.txt:find("^Waypoint"))
H.wpBtn.onOnClick(H.wpBtn,"LeftButton"); assert(sent[#sent][2]:sub(1,3)=="WP:"); tick(nil,0.1); assert(H.wpBtn.label.txt:find("Remove the waypoint"))
H.wpBtn.onOnClick(H.wpBtn,"LeftButton"); assert(sent[#sent][2]=="WPC"); tick(nil,0.1); assert(H.wpBtn.label.txt:find("^Waypoint"))
H.wpBtn.onOnClick(H.wpBtn,"RightButton"); assert(sent[#sent][2]=="WPC","right click always removes")
H.wpBtn.onOnClick(H.wpBtn,"LeftButton"); fire("CHAT_MSG_ADDON","DADMODE","WPHERE","PARTY","Bro Bearfang-CAMWOW EU5 Realm 4 PvP"); tick(nil,0.1); assert(H.wpBtn.label.txt:find("^Waypoint"),"arrived: button resets")
H.wpBtn.onOnClick(H.wpBtn,"LeftButton"); fire("CHAT_MSG_ADDON","DADMODE","WPNO","PARTY","Bro Bearfang-CAMWOW EU5 Realm 4 PvP"); tick(nil,0.1); assert(H.wpBtn.label.txt:find("^Waypoint"),"refused: button resets")
-- one column
local wd; rawset(H,"SetWidth",function(_,w) wd=w end)
DadModeDB.helperCols=1; assert(H.Layout() and wd==176); fight=true; assert(H.Layout()==false); fight=false
DadModeDB.helperCols=nil; H.Layout(); assert(wd==302)
-- waypoints. As helper: no pin set, so my own position goes out
SlashCmdList.DADMODE("waypoint"); assert(sent[#sent][2]=="WP:1434:0.2812:0.7441",sent[#sent][2])
pin={uiMapID=1413,position={x=0.5,y=0.25}}
SlashCmdList.DADMODE("waypoint"); assert(sent[#sent][2]=="WP:1413:0.5000:0.2500","my map pin is preferred")
fire("CHAT_MSG_ADDON","DADMODE","WPOK","PARTY","Bro Bearfang-CAMWOW EU5 Realm 4 PvP"); fire("CHAT_MSG_ADDON","DADMODE","WPNO","PARTY","Bro Bearfang-CAMWOW EU5 Realm 4 PvP")
-- as dad: receive one
pin=nil; DadModeDB.alerts=true; local sw=sounds; clock=clock+5
fire("CHAT_MSG_ADDON","DADMODE","WP:1434:0.2812:0.7441","PARTY","Bro Bearfang-CAMWOW EU5 Realm 4 PvP")
assert(setpin and setpin.uiMapID==1434 and math.abs(setpin.position.x-0.2812)<1e-6 and tracked==true and sent[#sent][2]=="WPOK" and sounds==sw+1,"waypoint set and tracked")
local wp=DadModeDB.waypoint; assert(wp and math.abs(wp.n-1281.2)<0.01 and math.abs(wp.w-1244.1)<0.01 and wp.cont==1,"marker in world coordinates")
tick(nil,0.1)
local ms; for _,f in ipairs(frames) do if rawget(f,"near") and f.name.txt and f.name.txt:find("MARKER") then ms=f end end
assert(ms and ms.shown and ms.dist.txt:find("yd"),"red marker arrow shown")
assert(sent[#sent][2]=="WPOK")
units.player.n=1281; units.player.w=1244; tick(nil,0.1)
assert(DadModeDB.waypoint==nil and setpin==nil and sent[#sent][2]=="WPHERE","arrived at the marker")
fire("CHAT_MSG_ADDON","DADMODE","WPHERE","PARTY","Bro Bearfang-CAMWOW EU5 Realm 4 PvP")
units.player.n=1000; units.player.w=500; clock=clock+5
fire("CHAT_MSG_ADDON","DADMODE","WP:1434:0.2812:0.7441","PARTY","Bro Bearfang-CAMWOW EU5 Realm 4 PvP")
fire("CHAT_MSG_ADDON","DADMODE","WP:999:0.5:0.5","PARTY","Bro Bearfang-CAMWOW EU5 Realm 4 PvP"); assert(sent[#sent][2]=="WPNO" and setpin.uiMapID==1434,"map that does not allow pins")
fire("CHAT_MSG_ADDON","DADMODE","WPC","PARTY","Bro Bearfang-CAMWOW EU5 Realm 4 PvP"); assert(setpin==nil and DadModeDB.waypoint==nil,"cleared")
fire("CHAT_MSG_ADDON","DADMODE","WP:1434:0.5:0.5","PARTY","Stranger Danger-CAMWOW EU5 Realm 4 PvP"); assert(setpin==nil,"strangers cannot set it")
DadModeDB.alerts=false; pin=nil
-- quests: as a helper I ask, and a dad-role addon would answer. Here I play both ends.
SlashCmdList.DADMODE("quests"); assert(DadModeQuests.shown and sent[#sent][2]=="QREQ")
assert(DadModeQuests.text.txt:find("Asking"))
local n1=#sent
fire("CHAT_MSG_ADDON","DADMODE","QREQ","PARTY","Bro Bearfang-CAMWOW EU5 Realm 4 PvP"); assert(#sent==n1,"helpers do not answer")
DadModeDB.helper=false
fire("CHAT_MSG_ADDON","DADMODE","QREQ","PARTY","Bro Bearfang-CAMWOW EU5 Realm 4 PvP")
for i=1,30 do clock=clock+2; DadMode_PumpOutbox() end
local out={}; for i=n1+1,#sent do out[#out+1]=sent[i][2] end
assert(out[1]=="PERM:status=1~gold=1~quests=1~gear=1~call=1~waypoint=1~wear=1","first what he shares"); table.remove(out,1)
assert(out[1]:sub(1,3)=="ST:" and out[2]:sub(1,3)=="ST:" and out[3]=="QS:3" and out[4]:sub(1,2)=="Q:" and out[5]=="QE" and out[6]:sub(1,3)=="GR:" and out[#out-1]=="CN:1:5=12~2:7=4~3:1=1" and out[#out]=="BGS:0", table.concat(out," || "))
for _,b in ipairs(out) do assert(#b<=255,"message too long") ; fire("CHAT_MSG_ADDON","DADMODE",b,"PARTY","Bro Bearfang-CAMWOW EU5 Realm 4 PvP") end
DadModeDB.helper=true
assert(DadModeQuests.view=="overview","opens on the overview")
local ov=DadModeQuests.text.txt
assert(ov:find("Quests|r  3",1,true) and ov:find("1 ready to hand in",1,true) and not ov:find("Stolen Shipment"),"overview: counts, not the list")
DadModeQuests.SetView("quests")
local qt=ov..DadModeQuests.text.txt
print((qt:gsub("|c%x%x%x%x%x%x%x%x",""):gsub("|r","")))
assert(qt:find("level 37") and qt:find("62%% to 38") and qt:find("12g") and qt:find("in a fight") and qt:find("Stranglethorn Vale, Nesingwary") and qt:find("3 free") and qt:find("of 64") and qt:find("worst piece 0%%") and qt:find("1 broken") and qt:find("Food and drink: 12") and qt:find("Bandages: 4") and qt:find("Potions: 1") and qt:find("Hearthstone: Orgrimmar") and qt:find("DadMode 1.3.4"), "status card")
assert(qt:find("Bro") and qt:find("Stolen Shipment") and qt:find("you have it too") and qt:find("ready to hand in") and qt:find("10/15 Bloodscalp Ear") and qt:find("20/20 Shrunken Head"), qt)
assert(qt:find("Where's the Key") < qt:find("Stolen Shipment"),"ready quests first")
-- gear view
local TB=DadModeQuests.tabs; assert(TB.overview and TB.quests and TB.missing and TB.gear,"four tabs")
TB.gear.onOnClick(TB.gear); assert(DadModeQuests.view=="gear")
assert(DadModeQuests.text.txt:find("1x Lesser Healing Potion") and DadModeQuests.text.txt:find("12x Ice Cold Milk") and DadModeQuests.text.txt:find("4x Heavy Wool Bandage"),"which consumables")
local gt=DadModeQuests.text.txt
print((gt:gsub("|c%x%x%x%x%x%x%x%x",""):gsub("|r","")))
assert(gt:find("Silk Headband") and gt:find("item level 31") and gt:find("Chest:") and gt:find("BROKEN") and gt:find("Legs:") and gt:find("Shoulders:.-EMPTY") and gt:find("Main hand:.-loading") and gt:find("Average item level: 34") and not gt:find("Stolen Shipment") and not gt:find("Shirt"),"gear view")
fire("GET_ITEM_INFO_RECEIVED",7016,true)
TB.quests.onOnClick(TB.quests); assert(DadModeQuests.text.txt:find("Stolen Shipment"),"back to quests")
assert(qt:find("hand in: Zimmix Sputterspark, Stranglethorn Vale") and select(2,qt:gsub("hand in:",""))==1,"hand-in shown only for the ready quest")
assert(qt:find("then: Zimmix's Great Escape %[39%]") and select(2,qt:gsub("then:",""))==1,"follow-up quest shown once")
-- I am a helper with calls off: someone calls me, they get MUTED back
assert(DadModeDB.alerts==false)
clock=clock+10; local sb=sounds
fire("CHAT_MSG_ADDON","DADMODE","PING:","PARTY","Bro Bearfang-CAMWOW EU5 Realm 4 PvP"); assert(sounds==sb and sent[#sent][2]=="MUTED","muted reply")
fire("CHAT_MSG_ADDON","DADMODE","MUTED","PARTY","Bro Bearfang-CAMWOW EU5 Realm 4 PvP")
SlashCmdList.DADMODE("status"); SlashCmdList.DADMODE("debug")
-- nobody answers
SlashCmdList.DADPING(""); assert(#timers>0); timers[#timers]()
local real=C_ChatInfo.SendAddonMessage
C_ChatInfo.SendAddonMessage=function() return 11 end
local before=#timers; SlashCmdList.DADPING("x"); assert(#timers==before,"refused call starts no wait")
C_ChatInfo.SendAddonMessage=real
-- drag the helper bar, a fight starts mid-drag: it must let go before the lock, and not error after
H.onOnDragStart(H); assert(rawget(H,"dragging"))
fire("PLAYER_REGEN_DISABLED"); fight=true
assert(not rawget(H,"dragging") and rawget(H,"stopped")==1,"let go when the fight starts")
H.onOnDragStop(H); H.onOnDragStart(H); H.onOnDragStop(H)      -- all ignored in a fight, no blocked call
fight=false
H.onOnDragStart(H); H.onOnDragStop(H); assert(rawget(H,"stopped")==2,"normal drag still works")
SlashCmdList.DADMODE("helper"); assert(not DadModeHelper.shown)
assert(registered and registered.icon and not DadModeMinimapButton,"library button used")
DadModeDB.helper=false; DadModePicker.shown=false
registered.OnClick(nil,"LeftButton"); assert(DadModePicker.shown)
registered.OnTooltipShow(GameTooltip)
SlashCmdList.DADMODE("minimap"); assert(hidden==true); SlashCmdList.DADMODE("minimap"); assert(hidden==false)
local sq=sounds; clock=clock+10; units.party1.n=1200
SlashCmdList.DADMODE("test"); assert(sounds==sq+1 and AF.shown and AF.text.txt:find("Saqu") and AF.text.txt:find("test"),"self test")
tick(nil,0.1); assert(DadModeBar.shown,"arrow appears for the test even with nobody picked or alerts off")
SlashCmdList.DADMODE("clear"); SlashCmdList.DADMODE(""); SlashCmdList.DADMODE("off"); tick(nil,0.1); assert(not DadModeBar.shown)
P.move.onOnClick(P.move); local fw=DadModeDB.farWarning; P.far.onOnClick(P.far); assert(DadModeDB.farWarning==(not fw))
print("TESTS_PASSED")
''')
