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
regEvents={}
function CreateFrame(kind,name) local w=widget(kind); rawset(w,"RegisterEvent",function(_,ev) regEvents[ev]=(regEvents[ev] or 0)+1 end); frames[#frames+1]=w; if name then _G[name]=w end; return w end
UIParent=widget(); UISpecialFrames={}; SlashCmdList={}
Minimap=widget(); GameTooltip=widget()
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
C_ChatInfo={RegisterAddonMessagePrefix=noop, SendAddonMessage=function(p,t,c,to) sent[#sent+1]={p,t,c,to} end}
''')
L.execute(r'''
opened=nil; registered=nil
Settings={
  RegisterCanvasLayoutCategory=function(panel,name) return {panel=panel,name=name,GetID=function() return 77 end} end,
  RegisterAddOnCategory=function(c) registered=c end,
  OpenToCategory=function(id) assert(not fight,"opening options in a fight"); opened=id end,
}
''')
# load the files the way the game does: in the order of the .toc, each with (addon name, shared table)
import os as _os
_dir=_os.path.dirname(_os.path.abspath(sys.argv[1]))
L.execute(r'''
-- everything on the page of the "How is ... doing" window, as one piece of text
function PG() local w=DadModeQuests; local out={}
  for _,b in ipairs(rawget(w,"blocks") or {}) do
    if type(b)=="string" then out[#out+1]=b
    elseif b.row then
      local l=((b.slot and b.slot~="") and ("["..b.slot.."] ") or "")..(b.title or "")
      for _,ch in ipairs(b.chips or {}) do l=l.."  "..ch.text end
      if b.button then l=l.."  <"..b.button.text..">" end
      out[#out+1]=l
      if b.sub and b.sub~="" then out[#out+1]="    "..(b.sub:gsub("\n","\n    ")) end
    elseif b.bar then local l=(b.label or ""); for _,it in ipairs(b.items) do l=l.." "..(it.on and "(x)" or "( )")..it.text end; out[#out+1]=l
    elseif b.tiles then for _,t in ipairs(b.tiles) do out[#out+1]=t.label..": "..t.value end end
  end
  return table.concat(out,"\n") end

-- the row whose title holds a word, and the small button with that text on a bar
function ROW(word) local w=DadModeQuests; for i=1,(rawget(w,"usedRows") or 0) do local r=w.rows[i]; local sp=rawget(r,"spec"); if sp and sp.title:find(word,1,true) then return r,sp,i end end end
function PILL(text) local w=DadModeQuests; for i=1,(rawget(w,"usedBars") or 0) do local b=w.bars[i]; for j,it in ipairs(b.spec.items) do if it.text==text then return b.pills[j],it end end end end
''')
L.execute('DadModeNS={}')
_load=L.eval('function(src,name) local f,e=(loadstring or load)(src,"@"..name); if not f then error(e) end; return f("DadMode", DadModeNS) end')
_files=[l.strip() for l in open(_os.path.join(_dir,'DadMode.toc')) if l.strip().endswith('.lua')]
assert _files and _files[0]=='Core.lua', _files
for _f in _files: _load(open(_os.path.join(_dir,_f)).read(), _f)
L.execute(r'''
local ev=nil
for _,f in ipairs(frames) do if rawget(f,"onOnEvent") then ev=f.onOnEvent end end
local function fire(e,...) ev(nil,e,...) end
-- before the addon's own ADDON_LOADED the events of the later files are not known yet... they are: every file has loaded
fire("ADDON_LOADED","SomeOtherAddon")
local before=regEvents.START_LOOT_ROLL
fire("ADDON_LOADED","DadMode"); fire("PLAYER_LOGIN")
-- the split into files: events added by the other files are listened for, and the shared table is filled
for _,ev in ipairs({"ADDON_LOADED","PLAYER_LOGIN","CHAT_MSG_ADDON","GROUP_ROSTER_UPDATE","START_LOOT_ROLL","LOOT_OPENED","CHAT_MSG_LOOT","TAXIMAP_OPENED","PLAYER_REGEN_ENABLED"}) do
  assert(regEvents[ev], "listening for "..ev)
end
assert(DadModeNS.db==DadModeDB and type(DadModeNS.Party)=="function" and type(DadModeNS.questData)=="table" and DadModeNS.helper==DadModeHelper, "shared table")
for _,g in ipairs({"DadMode_DungeonLines","DadMode_Compare","DadMode_TooltipLines","DadMode_TargetName","DadMode_Aim","DadMode_Gate","DadMode_FilterReply","DadMode_OpenGuides","DadMode_Notes","DadMode_ExtraMessage","DadMode_VersionLines","DadMode_WearMessage","DadMode_BagRows","DadMode_LayoutBlocks","DadMode_TestBox"}) do
  assert(type(_G[g])=="function", "every file loaded: "..g)
end
-- these tests are about everything else: both test guides are already approved
DadModeDB.guides={["bro bearfang"]={name="Bro Bearfang",state="yes"},["saqu off"]={name="Saqu Off",state="yes"}}
-- fresh install: role question shown once
assert(DadModeRole and DadModeRole.shown, "role window on first start")
assert(registered and registered.name=="DadMode", "page registered")
assert(DadMode_HasOptionsPage(), "has page")
local O=DadModeOptions
assert(#O.rows==15, "15 rows, got "..#O.rows)
O.onOnShow(O)
local function row(i) return O.rows[i].button end
local function click(i) row(i).onOnClick(row(i)) end
local function txt(i) return row(i).label.txt end
-- role
assert(txt(1):find("being guided"), txt(1))
click(1); assert(DadModeDB.helper==true and DadModeDB.roleChosen and txt(1):find("A guide"), txt(1))
assert(DadModeDB.alerts==false, "guide does not get calls")
click(1); assert(DadModeDB.helper==false and DadModeDB.alerts==true and DadModeDB.follow==true and DadModeDB.farWarning==true, "back to guided restores calls")
-- toggles
click(2); assert(DadModeDB.alerts==false and txt(2)=="Off"); click(2); assert(txt(2)=="On")
local c0=DadModeDB.sounds.call or 4; click(3); assert(DadModeDB.sounds.call==(c0 % 5)+1 or DadModeDB.sounds.call~=c0)
click(5); assert(DadModeDB.farWarning==false and txt(5)=="Off"); click(5)
click(6); assert(DadModeDB.follow==false and txt(6)=="Hidden"); click(6)
assert(txt(7)=="Medium"); click(7); assert(txt(7)=="Large" and DadModeDB.arrowSize==3); click(7); click(7); assert(txt(7)=="Medium")
-- window size
assert(txt(8)=="100%"); click(8); assert(txt(8)=="110%" and DadModeDB.scale==4)
click(8); assert(txt(8)=="125%"); click(8); assert(txt(8)=="80%"); click(8); click(8); assert(txt(8)=="100%" and DadModeDB.scale==3)
-- scale in a fight must not touch the secure bars
local touched=0
local old=DadModeHelper and rawget(DadModeHelper,"SetScale")
if DadModeHelper then rawset(DadModeHelper,"SetScale",function() assert(not fight,"BLOCKED: helper SetScale in a fight"); touched=touched+1 end) end
fight=true; click(8); fight=false
fire("PLAYER_REGEN_ENABLED")
assert(DadModeHelper==nil or touched>=1, "bar resized after the fight")
-- lock, minimap
click(10); assert(txt(10):find("Unlocked")); click(10); assert(txt(10):find("Locked"))
assert(txt(11)=="2 columns"); click(11); assert(txt(11)=="1 column" and DadModeDB.helperCols==1)
fight=true; click(11); fight=false; assert(DadModeDB.helperCols==1,"no layout change in a fight"); click(11); assert(txt(11)=="2 columns")
click(12)
assert(txt(13)=="On"); click(13); assert(DadModeDB.compare==false and txt(13)=="Off"); click(13); assert(DadModeDB.compare==true and txt(13)=="On")
assert(txt(14)=="Open")
click(15); assert(DadModeDB.minimap.hide and txt(15)=="Hidden"); click(15); assert(txt(15)=="Shown")
-- resize corners
local function fake(f,w,left,top)
  rawset(f,"sc",1); rawset(f,"SetScale",function(s,x) assert(not (s==DadModeHelper and fight),"BLOCKED: scale in a fight"); rawset(s,"sc",x) end)
  rawset(f,"GetScale",function(s) return rawget(s,"sc") end)
  rawset(f,"GetWidth",function() return w end); rawset(f,"GetLeft",function() return left end); rawset(f,"GetTop",function() return top end)
  rawset(f,"SetPoint",function(s,...) rawset(s,"pt",{...}) end)
end
DadModeDB.scale=3
local PK=DadModePicker; fake(PK,300,100,600)
local g=PK.grip; assert(g, "picker has a corner")
rawset(g,"sizing",nil)
cursor=550; function GetCursorPosition() return cursor,300 end
g.onOnMouseDown(g); assert(rawget(g,"sizing") and rawget(g,"onOnUpdate"))
g.onOnUpdate(g); assert(math.abs(PK.sc-1.5)<1e-6, "corner follows mouse: "..tostring(PK.sc))
assert(PK.pt[1]=="TOPLEFT" and math.abs(PK.pt[4]-100/1.5)<1e-6 and math.abs(PK.pt[5]-600/1.5)<1e-6, "top left stays put")
assert(math.abs(DadModeDB.winScale.picker-1.5)<1e-6)
cursor=5000; g.onOnUpdate(g); assert(PK.sc==2, "max")
cursor=0; g.onOnUpdate(g); assert(PK.sc==0.6, "min")
cursor=400; g.onOnUpdate(g); g.onOnMouseUp(g); assert(not rawget(g,"sizing") and rawget(g,"onOnUpdate")==nil and PK.sc==1)
-- window size setting multiplies with the corner drag
cursor=550; g.onOnMouseDown(g); g.onOnUpdate(g); g.onOnMouseUp(g)
click(8); assert(DadModeDB.scale==4 and math.abs(PK.sc-1.65)<1e-6, "110% of 1.5: "..tostring(PK.sc))
-- reset
click(9); assert(DadModeDB.winScale==nil and DadModeDB.scale==3 and DadModeDB.questSize==nil and PK.sc==1, "reset")
-- guide bar: corner refuses in a fight, and a fight mid-drag drops it
click(1); local H=DadModeHelper; assert(H and H.grip, "guide bar has a corner")
fake(H,302,200,500); local hg=H.grip; rawset(hg,"sizing",nil)
fight=true; hg.onOnMouseDown(hg); assert(not rawget(hg,"sizing"), "no resize in a fight"); fight=false
cursor=200+302*1.2; hg.onOnMouseDown(hg); hg.onOnUpdate(hg); assert(math.abs(H.sc-1.2)<1e-6)
cursor=200+176; hg.onOnUpdate(hg); assert(DadModeDB.helperCols==1 and math.abs(H.sc-1)<1e-6, "narrow: one column at normal size")
cursor=200+239; hg.onOnUpdate(hg); assert(DadModeDB.helperCols==1 and math.abs(H.sc-239/176)<1e-6, "just under the break")
cursor=200+241; hg.onOnUpdate(hg); assert(DadModeDB.helperCols==2 and math.abs(H.sc-241/302)<1e-6, "just over: two columns")
cursor=200+302*1.2; hg.onOnUpdate(hg); assert(DadModeDB.helperCols==2 and math.abs(H.sc-1.2)<1e-6)
fight=true; fire("PLAYER_REGEN_DISABLED"); assert(not rawget(hg,"sizing") and rawget(hg,"onOnUpdate")==nil, "dropped when the fight starts")
assert(DadModeDB.helperPos, "position saved"); fight=false
click(9); click(1)
-- quest window: real resize, remembered
local Q=DadModeQuests; assert(Q.grip, "quest window has a corner")
local qw,qh=460,540
rawset(Q,"GetWidth",function() return qw end); rawset(Q,"GetHeight",function() return qh end)
local tw; rawset(Q.text,"SetWidth",function(_,w) tw=w end)
local cw=436; rawset(Q.content,"SetWidth",function(_,w) cw=w end); rawset(Q.content,"GetWidth",function() return cw end)
local sized; rawset(Q,"StartSizing",function(_,c) sized=c end)
rawset(Q.grip,"sizing",nil)
Q.grip.onOnMouseDown(Q.grip); assert(sized=="BOTTOMRIGHT")
qw,qh=700,800; Q:Show(); Q.onOnSizeChanged(Q); assert(cw==676 and tw==668, "text re-wraps: "..tostring(tw))
Q.grip.onOnMouseUp(Q.grip); assert(DadModeDB.questSize[1]==700 and DadModeDB.questSize[2]==800)
SlashCmdList.DADMODE("resetsize"); assert(DadModeDB.questSize==nil)
-- opening
SlashCmdList.DADMODE("settings"); assert(opened==77, "slash opens page")
opened=nil; DadMode_OpenSettings(); assert(opened==77)
opened=nil; SlashCmdList.DADMODE(""); local P=DadModePicker; assert(P.shown)
P.more.onOnClick(P.more); assert(opened==77 and not P.shown, "Settings button opens the page and closes the small window")
-- in a fight: falls back to the small window, never opens the protected options frame
opened=nil; fight=true; DadMode_OpenSettings(); fight=false
assert(opened==nil and P.shown, "fallback in a fight")
-- role question is not asked again
DadModeRole.shown=false
fire("PLAYER_LOGIN")
-- minimap button
local P2=DadModePicker
DadModeDB.helper=false; P2.shown=false; DadMode_MinimapClick("LeftButton"); assert(P2.shown, "dad: left click opens the picker")
opened=nil; DadMode_MinimapClick("RightButton"); assert(opened==77, "right click: options")
DadMode_SetRole(true); local HB=DadModeHelper; assert(HB.shown)
DadModeQuests.shown=false
DadMode_MinimapClick("LeftButton"); assert(not HB.shown and DadModeDB.helperHidden and not DadModeQuests.shown, "guide: left click hides the bar")
fight=true; DadMode_MinimapClick("LeftButton"); assert(not HB.shown, "not in a fight"); fight=false
DadMode_MinimapClick("LeftButton"); assert(HB.shown and DadModeDB.helperHidden==nil, "and shows it again")
opened=nil; DadMode_MinimapClick("RightButton"); assert(opened==77)
DadMode_MinimapClick("LeftButton"); DadMode_SetRole(false); DadMode_SetRole(true); assert(HB.shown and DadModeDB.helperHidden==nil, "choosing guide brings the bar back")
-- ===== gear links and stats =====
local BRO="Bro Bearfang-CAMWOW EU5 Realm 4 PvP"
local function run() local t=timers; timers={}; for _,f in ipairs(t) do f() end; for i=1,40 do clock=clock+2; DadMode_PumpOutbox() end end
-- as the one being guided: answer a request with links and stats
DadMode_SetRole(false)
worn={[1]=2000,[16]=3000}
function GetInventoryItemLink(u,slot)
  if slot==1 then return "|cff1eff00|Hitem:2000:55:::::-12:::::|h[Hat of the Owl]|h|r" end
  if slot==16 then return "|cffffffff|Hitem:3000::::::::35:::::|h[Staff]|h|r" end
end
function UnitStat(u,i) return 10*i, 11*i, 0, 0 end
function UnitArmor() return 300, 345 end
function UnitHealthMax() return 1234 end
function UnitPowerMax() return 2345 end
function GetSpellBonusDamage(school) return school==6 and 41 or 20 end
function GetSpellBonusHealing() return 63 end
function GetSpellCritChance() return 4.26 end
clock=clock+100; local n0=#sent
fire("CHAT_MSG_ADDON","DADMODE","QREQ","PARTY",BRO); run()
local gl,ss
for i=n0+1,#sent do local b=sent[i][2]; if b:sub(1,3)=="GL:" then gl=b elseif b:sub(1,3)=="SS:" then ss=b end; assert(#b<=255,"message too long") end
assert(gl=="GL:1=item:2000:55:::::-12~16=item:3000::::::::35", tostring(gl))
assert(ss and ss:find("sta=33") and ss:find("int=44") and ss:find("spi=55") and ss:find("arm=345") and ss:find("hp=1234") and ss:find("mp=2345") and ss:find("sp=41") and ss:find("heal=63") and ss:find("scr=43"), tostring(ss))
assert(not ss:find("ap=") and not ss:find("mcr="), "what the game does not tell is left out")
-- a very long item never makes a message too long
function GetInventoryItemLink(u,slot) if slot==1 then return "|Hitem:2000"..string.rep(":123456",40).."|h[x]|h" end end
clock=clock+100; n0=#sent; fire("CHAT_MSG_ADDON","DADMODE","QREQ","PARTY",BRO); run()
for i=n0+1,#sent do assert(#sent[i][2]<=255) end
-- as a guide: receive and show
DadMode_SetRole(true)
C_Item.GetItemInfo=function(id) return (id==2000 and "Hat of the Owl") or (id==3000 and "Staff") or nil, nil, 2, 30 end
SlashCmdList.DADMODE("quests"); local QW=DadModeQuests
fire("CHAT_MSG_ADDON","DADMODE","ST:lv=35","PARTY",BRO)
fire("CHAT_MSG_ADDON","DADMODE","GR:1=2000:90~16=3000:100","PARTY",BRO)
fire("CHAT_MSG_ADDON","DADMODE","GL:1=item:2000:55:::::-12","PARTY",BRO)
fire("CHAT_MSG_ADDON","DADMODE","SS:sta=33~int=44~arm=345~hp=1234~scr=43","PARTY",BRO)
fire("CHAT_MSG_ADDON","DADMODE","QS:0","PARTY",BRO); fire("CHAT_MSG_ADDON","DADMODE","QE","PARTY",BRO)
QW.SetView("gear"); local T=PG()
assert(T:find("|Hitem:2000:55:::::-12|h[Hat of the Owl]|h",1,true), "exact item link")
assert(T:find("|Hitem:3000|h[Staff]|h",1,true), "falls back to the plain item when no link was sent")
assert(T:find("Stats",1,true) and T:find("Stamina: 33",1,true) and T:find("Armor: 345",1,true) and T:find("Health: 1234",1,true) and T:find("Spell crit: 4.3%",1,true), T)
assert(not T:find("Attack power",1,true))
-- hovering a link shows the game tooltip
local shownLink; rawset(GameTooltip,"SetHyperlink",function(_,l) shownLink=l end)
QW.content.onOnHyperlinkEnter(QW.content,"item:2000:55:::::-12"); assert(shownLink=="item:2000:55:::::-12")
QW.content.onOnHyperlinkLeave(QW.content)
-- an old DadMode on dad's side sends no stats: no Stats block, nothing breaks
fire("CHAT_MSG_ADDON","DADMODE","SS:","PARTY",BRO); DadMode_RenderQuests(); assert(not PG():find("Stats|r",1,true))
-- ===== call text says how far away =====
DadMode_SetRole(false); clock=clock+100
local AF2; for _,f in ipairs(frames) do if rawget(f,"text") and rawget(f,"from")~=nil then AF2=f end end
fire("CHAT_MSG_PARTY","!dad",BRO)
for _,f in ipairs(frames) do if rawget(f,"text") and rawget(f.text,"txt") and f.text.txt:find("Bro",1,true) and f.text.txt:find("wants you",1,true) then AF2=f end end
assert(AF2 and AF2.text.txt:find("50 yards away",1,true), AF2 and AF2.text.txt or "no alert")
-- ===== quest search and compare =====
DadMode_SetRole(true); clock=clock+100
local savedLog=qlog
qlog={ {title="Shared Quest",questID=501,level=30}, {title="Guide Only A",questID=502,level=31}, {title="Guide Only B",questID=503,level=32} }
local objsave=C_QuestLog.GetQuestObjectives
C_QuestLog.GetQuestObjectives=function(id) if id==501 then return {{text="2/8 Boar Tusk",finished=false}} end return {} end
SlashCmdList.DADMODE("quests"); QW.SetView("quests"); QW.ApplySearch("")
local m0=#sent
fire("CHAT_MSG_ADDON","DADMODE","QS:2","PARTY",BRO)
fire("CHAT_MSG_ADDON","DADMODE","Q:501~30~0~Shared Quest~-5/8 Boar Tusk^777~29~1~Dad Only Quest~+1/1 Golden Idol","PARTY",BRO)
fire("CHAT_MSG_ADDON","DADMODE","QE","PARTY",BRO)
local qc; for i=m0+1,#sent do if sent[i][2]:sub(1,3)=="QC:" then qc=sent[i][2] end end
assert(qc=="QC:502,503", "asks about the quests only I have: "..tostring(qc))
QW.SetView("quests"); T=PG()
assert(T:find("Shared Quest  you have it too",1,true) and T:find("you: 2/8 Boar Tusk",1,true), "my progress next to his")
assert(T:find("only Bro",1,true), "only dad mark")
assert(not T:find("Guide Only A",1,true), "missing quests live on their own tab")
QW.SetView("overview"); T=PG()
assert(T:find("Missing: 2 of your quests are not in his log",1,true) and T:find("1 ready to hand in",1,true) and not T:find("Shared Quest",1,true), T)
QW.SetView("missing"); T=PG()
assert(T:find("You have, Bro does not",1,true) and T:find("Guide Only A",1,true) and T:find("checking...",1,true) and not T:find("Dad Only Quest",1,true), T)
fire("CHAT_MSG_ADDON","DADMODE","QD:502=1,503=0","PARTY",BRO); T=PG()
assert(T:find("Guide Only A  already done",1,true) and T:find("Guide Only B  not picked up",1,true), T)
-- search works on both lists, and the box is only there on those two tabs
assert(QW.search.shown and QW.wipe.shown)
QW.ApplySearch("only b"); T=PG()
assert(T:find("Guide Only B",1,true) and not T:find("Guide Only A",1,true) and T:find("1 match the search",1,true))
QW.SetView("quests"); QW.ApplySearch("  IDOL "); T=PG()
assert(QW.filter=="idol" and T:find("Dad Only Quest",1,true) and not T:find("Shared Quest",1,true) and T:find("1 match the search",1,true), T)
QW.ApplySearch("zzz"); assert(PG():find("0 match the search",1,true))
QW.ApplySearch(""); T=PG(); assert(T:find("Shared Quest",1,true) and T:find("Dad Only Quest",1,true) and not T:find("match the search",1,true))
QW.SetView("gear"); assert(not QW.search.shown and not QW.wipe.shown, "no search box on the gear tab")
QW.SetView("overview"); assert(not QW.search.shown)
-- a refresh does not empty the list on screen: the new one swaps in when it is complete
QW.SetView("quests")
fire("CHAT_MSG_ADDON","DADMODE","QS:3","PARTY",BRO); T=PG()
assert(T:find("Shared Quest",1,true) and T:find("Dad Only Quest",1,true) and T:find("updating...",1,true), "old list stays while the new one loads")
fire("CHAT_MSG_ADDON","DADMODE","Q:501~30~0~Shared Quest~-6/8 Boar Tusk","PARTY",BRO); T=PG()
assert(T:find("5/8 Boar Tusk",1,true) and not T:find("6/8 Boar Tusk",1,true), "still the old one")
assert(DadMode_AutoRefreshDue()==false, "no automatic refresh while a list is coming in")
fire("CHAT_MSG_ADDON","DADMODE","Q:777~29~1~Dad Only Quest~+1/1 Golden Idol^888~31~0~Brand New Quest~-0/1 Thing","PARTY",BRO)
fire("CHAT_MSG_ADDON","DADMODE","QE","PARTY",BRO); T=PG()
assert(T:find("6/8 Boar Tusk",1,true) and T:find("Brand New Quest",1,true) and not T:find("updating",1,true) and T:find("quests|r  |cff9aa0a63|r",1,true), T)
-- an old DadMode loses the end of a long list: after a while show what arrived, and say so
fire("CHAT_MSG_ADDON","DADMODE","QS:29","PARTY",BRO)
fire("CHAT_MSG_ADDON","DADMODE","Q:501~30~0~Shared Quest~-7/8 Boar Tusk","PARTY",BRO)
clock=clock+10; DadMode_RenderQuests(); assert(PG():find("updating...",1,true) and PG():find("6/8",1,true))
clock=clock+20; DadMode_RenderQuests(); T=PG()
assert(T:find("only 1 of 29 arrived. Bro needs DadMode 1.18",1,true) and T:find("7/8 Boar Tusk",1,true), T)
-- automatic refresh: once a minute, not while typing
clock=clock+100; assert(DadMode_AutoRefreshDue()==true)
QW.search.onOnEditFocusGained(QW.search); assert(DadMode_AutoRefreshDue()==false, "not while typing in the search box")
QW.search.onOnEditFocusLost(QW.search); assert(DadMode_AutoRefreshDue()==true)
SlashCmdList.DADMODE("quests"); assert(DadMode_AutoRefreshDue()==false, "just asked")
-- first ever load shows the list as it grows
DadMode_SetRole(false); DadMode_SetRole(true)
fire("CHAT_MSG_ADDON","DADMODE","QS:2","PARTY",BRO); fire("CHAT_MSG_ADDON","DADMODE","QE","PARTY",BRO)
qlog[#qlog+1]={title="Guide Only C",questID=504,level=33}
fire("CHAT_MSG_ADDON","DADMODE","QS:0","PARTY",BRO); fire("CHAT_MSG_ADDON","DADMODE","QE","PARTY",BRO)
QW.SetView("missing")
clock=clock+10; DadMode_RenderQuests(); assert(PG():find("Guide Only C  unknown, Bro needs DadMode 1.16",1,true), PG())
-- the other side answers which quests are done
DadMode_SetRole(false)
C_QuestLog.IsQuestFlaggedCompleted=function(id) return id==502 end
m0=#sent; fire("CHAT_MSG_ADDON","DADMODE","QC:502,503","PARTY",BRO); assert(sent[#sent][2]=="QD:502=1,503=0", sent[#sent][2])
local many={}; for i=1,200 do many[i]=100000+i end
m0=#sent; fire("CHAT_MSG_ADDON","DADMODE","QC:"..table.concat(many,","),"PARTY",BRO)
local n=0; for i=m0+1,#sent do assert(#sent[i][2]<=255); for _ in sent[i][2]:gmatch("=") do n=n+1 end end; assert(n==60, "capped per request: "..n)
DadMode_SetRole(true); m0=#sent; fire("CHAT_MSG_ADDON","DADMODE","QC:502","PARTY",BRO); assert(#sent==m0, "a guide does not answer")
qlog=savedLog; C_QuestLog.GetQuestObjectives=objsave
-- ===== travel: zeppelins =====
DadMode_SetRole(false); DadModeDB.enabled=true; DadModeDB.alerts=true
local TK; for _,f in ipairs(frames) do if rawget(f,"onOnUpdate") then TK=f.onOnUpdate end end
local function tk() clock=clock+3; TK(nil,0.1) end
local AL; local function alertText() for _,f in ipairs(frames) do if rawget(f,"text") and rawget(f,"hint") and rawget(f,"onOnMouseDown") then AL=f end end; return AL.text.txt end
local function slot(word) for _,f in ipairs(frames) do if rawget(f,"near") and f.shown and f.name.txt and f.name.txt:find(word,1,true) then return f end end end
local saveP={n=units.player.n,w=units.player.w,inst=units.player.inst}
units.player.n,units.player.w,units.player.inst=1000,500,1
-- no platform spots known, marker on the other continent
DadModeDB.stops=nil
local W={map=1,x=0,y=0,n=5100,w=5000,cont=0,from="Bro"}
assert(DadMode_TravelStep(W)=="unknown")
assert(DadMode_TravelStep({n=1200,w=500,cont=1})==nil, "same continent, close: just walk")
-- spots arrive from the guide
fire("CHAT_MSG_ADDON","DADMODE","TS:ORG_GROM=1:1300:500~BAD=1:2:3~GROM_ORG=0:5000:5000~ORG_UC=1:1320:520~UC_ORG=0:9000:9000~UC_GROM=0:9050:9000~GROM_UC=0:5020:5000","PARTY",BRO)
local n=0; for k in pairs(DadModeDB.stops) do n=n+1 end; assert(n==6 and DadModeDB.stops.BAD==nil and DadModeDB.stops.ORG_GROM.n==1300, "six real platforms stored")
assert(DadMode_TravelStep(W)=="ORG_GROM", "Orgrimmar to Grom'gol, not via Undercity")
assert(DadMode_TravelStep({n=9100,w=9000,cont=0})=="ORG_UC", "marker near Undercity: the other platform")
DadModeDB.waypoint=W; tk()
local zs=slot("ZEPPELIN"); assert(zs and zs.dist.txt=="to Grom'gol  300 yd", zs and zs.dist.txt or "no zeppelin slot")
local at=alertText(); assert(at:find("Take the zeppelin to Grom'gol",1,true) and at:find("north side",1,true) and at:find("Snurk Bucksquick",1,true) and at:find("Orgrimmar",1,true), at)
-- on the platform: wait, marker stays
units.player.n=1295; tk(); assert(zs.dist.txt:find("wait here",1,true) and alertText():find("Right platform",1,true) and alertText():find("Grom'gol",1,true))
assert(DadModeDB.waypoint~=nil, "the marker is not cleared at the platform")
-- he lands at Grom'gol: back to the plain red arrow
units.player.n,units.player.w,units.player.inst=5000,5000,0; tk()
assert(alertText():find("Now follow the red arrow",1,true)); local ms2=slot("MARKER"); assert(ms2 and ms2.dist.txt=="100 yd", ms2 and ms2.dist.txt)
-- wrong zeppelin: he lands at Undercity instead, and gets the next step from there
DadModeDB.waypoint=W; units.player.n,units.player.w,units.player.inst=1000,500,1; tk(); assert(slot("ZEPPELIN"))
units.player.n,units.player.w,units.player.inst=9000,9005,0; tk()
assert(alertText():find("Take the zeppelin to Grom'gol",1,true) and alertText():find("Hin Denburg",1,true) and alertText():find("east side",1,true), alertText())
-- same continent but far: Undercity to Grom'gol beats walking; a short walk does not
assert(DadMode_TravelStep({n=5100,w=5000,cont=0})=="UC_GROM")
units.player.n,units.player.w=5300,5000; assert(DadMode_TravelStep({n=5100,w=5000,cont=0})==nil)
-- arriving at the marker still works
units.player.n,units.player.w=5100,5005; tk(); assert(DadModeDB.waypoint==nil and sent[#sent][2]=="WPHERE")
-- flight master: the reachable flight point closest to the goal
units.player.n,units.player.w,units.player.inst=1000,500,1
DadModeDB.waypoint={map=1,x=0,y=0,n=1900,w=500,cont=1,from="Bro"}
GetTaxiMapID=function() return 7 end
C_TaxiMap={GetAllTaxiNodes=function() return {{name="Near Camp",state=1,position={x=0.85,y=0}},{name="Far Post",state=1,position={x=0.1,y=0.9}},{name="Closest but unknown to him",state=2,position={x=0.9,y=0}}} end}
fire("TAXIMAP_OPENED"); assert(alertText():find("Fly to: Near Camp",1,true), alertText())
C_TaxiMap={GetAllTaxiNodes=function() return {{name="Barely Closer",state=1,position={x=0.2,y=0}}} end}
AL.text.txt=""; fire("TAXIMAP_OPENED"); assert(AL.text.txt=="", "no hint when flying hardly helps")
DadModeDB.waypoint=nil; fire("TAXIMAP_OPENED"); assert(AL.text.txt=="")
-- guide side: platform spots come from Questie and go out with the waypoint
DadMode_SetRole(true); DadModeDB.stops=nil
local QL=QuestieLoader
QuestieLoader={ImportModule=function(self,name)
  if name=="QuestieDB" then return {QueryNPCSingle=function(id,f)
      if id==9564 then return f=="name" and "Frezza" or {[14]={{50,10}}} end
      if id==12136 then return f=="name" and "Someone Else" or {[14]={{60,10}}} end
      return nil end,
    QueryQuestSingle=function() return nil end, QueryObjectSingle=function() return nil end}
  elseif name=="ZoneDB" then return {GetUiMapIdByAreaId=function(self,a) return 1000+a end} end
end}
pin=nil; m0=#sent; SlashCmdList.DADMODE("waypoint")
local ts; for i=m0+1,#sent do if sent[i][2]:sub(1,3)=="TS:" then ts=sent[i][2] end end
assert(ts=="TS:ORG_UC=1:1500:600~RATCHET_BB?=1:1630:872~BB_RATCHET?=1:1268:1270", "the platform whose name matched, plus the two rough boat towns: "..tostring(ts))
SlashCmdList.DADMODE("travel")
QuestieLoader=QL; units.player.n,units.player.w,units.player.inst=saveP.n,saveP.w,saveP.inst
-- ===== a long quest list under the game's send limit: nothing is lost =====
DadMode_SetRole(false); clock=clock+500
local saveLog2=qlog; qlog={}
for i=1,29 do qlog[i]={title="Long Quest Number "..i.." With A Long Name",questID=9000+i,level=30} end
local saveObj=C_QuestLog.GetQuestObjectives
C_QuestLog.GetQuestObjectives=function() return {{text="0/10 Something Quite Long To Collect",finished=false},{text="0/10 Another Long Thing To Collect",finished=false}} end
-- the game: a burst of 10, then one more per second; anything faster is refused with code 3
local realSend=C_ChatInfo.SendAddonMessage
local allow,last,got,refused=10,clock,{},0
C_ChatInfo.SendAddonMessage=function(pfx,body,chan)
  allow=math.min(10,allow+(clock-last)); last=clock
  if allow<1 then refused=refused+1; return 3 end
  allow=allow-1; got[#got+1]=body; return 0
end
fire("CHAT_MSG_ADDON","DADMODE","QREQ","PARTY",BRO)
local first=#got
for i=1,400 do clock=clock+0.1; DadMode_PumpOutbox() end
local total,ended=0,false
for _,b in ipairs(got) do if b:sub(1,2)=="Q:" then for _ in b:gmatch("[^%^]+") do total=total+1 end end; if b=="QE" then ended=true end; assert(#b<=255) end
assert(total==29 and ended, "all 29 quests and the end marker arrive: "..total)
assert(first<=6, "starts with a short burst, not everything at once: "..first)
assert(refused<=2, "it paces itself instead of hammering the limit: "..refused)
-- a second request while the answer is still going out does not start a second copy
got={}; allow=10; clock=clock+100
fire("CHAT_MSG_ADDON","DADMODE","QREQ","PARTY",BRO); local g1=#got
clock=clock+6; fire("CHAT_MSG_ADDON","DADMODE","QREQ","PARTY",BRO)
for i=1,400 do clock=clock+0.1; DadMode_PumpOutbox() end
local starts=0; for _,b in ipairs(got) do if b:sub(1,3)=="QS:" then starts=starts+1 end end
assert(starts==1, "one answer, not two: "..starts)
C_ChatInfo.SendAddonMessage=realSend; qlog=saveLog2; C_QuestLog.GetQuestObjectives=saveObj
-- ===== version check, guide bar warnings, help button =====
local function tk2() clock=clock+1; TK(nil,0.1) end
assert(DadMode_VersionNumber("1.14.2")<DadMode_VersionNumber("1.18.0") and DadMode_VersionNumber("1.9")<DadMode_VersionNumber("1.10.1") and DadMode_VersionNumber("junk")==0)
-- there is no help button (removed in 1.21.1), and an old "HELP" message does nothing
DadMode_SetRole(false); DadModeDB.enabled=true; tk2(); assert(DadModeHelp==nil)
-- answering the short status request
clock=clock+60; m0=#sent; fire("CHAT_MSG_ADDON","DADMODE","SREQ","PARTY",BRO)
assert(#sent==m0+3 and sent[m0+1][2]:sub(1,5)=="PERM:" and sent[m0+2][2]:sub(1,3)=="ST:" and sent[m0+3][2]:sub(1,3)=="ST:", "what he shares, then two status messages, nothing else")
fire("CHAT_MSG_ADDON","DADMODE","SREQ","PARTY",BRO); assert(#sent==m0+3, "not more often than every 20 seconds")
-- guide side
DadMode_SetRole(true); tk2()
local HB2=DadModeHelper
clock=clock+60; m0=#sent; tk2(); local polled=false; for i=m0+1,#sent do if sent[i][2]=="SREQ" then polled=true end end; assert(polled, "guide polls the short status")
local sb2=sounds; local before=alertText()
fire("CHAT_MSG_ADDON","DADMODE","HELP:Stranglethorn Vale","PARTY",BRO)
assert(sounds==sb2 and alertText()==before, "a help message from an older version is ignored")
fire("CHAT_MSG_ADDON","DADMODE","ST:lv=35~dead=1~cb=0~bf=0~bt=64~brk=2~tp=1","PARTY",BRO)
fire("CHAT_MSG_ADDON","DADMODE","ST:v=1.0.2","PARTY",BRO); fire("CHAT_MSG_ADDON","DADMODE","HI:1.0.2","PARTY",BRO)
tk2(); local nt=HB2.note.txt
-- the strip: who, level and distance on one line, what needs attention on the next
assert(nt:find("|cffe8c36aBro|r  35",1,true) and nt:find(" yd|r\n",1,true), nt)
assert(nt:find("DEAD|r, ",1,true) and nt:find("bags full",1,true) and nt:find("2 broken",1,true) and nt:find("1 talent point",1,true), nt)
assert(nt:find("has DadMode 1.0.2, you have",1,true), nt)
assert(HB2.status.txt:find("Bro: ",1,true) and HB2.status.txt:find("bags full",1,true), "top line carries what matters most when no call is running")
assert(HB2.stripOn==true and HB2.note.shown, "the strip is there when there is somebody to guide")
-- gear that is getting worn is said before it breaks
fire("CHAT_MSG_ADDON","DADMODE","ST:lv=35~dead=0~bf=20~bt=64~brk=0~dur=18~fd=0","PARTY",BRO); tk2(); nt=HB2.note.txt
assert(nt:find("gear 18%",1,true) and nt:find("no food",1,true) and not nt:find("broken",1,true) and not nt:find("bags",1,true), nt)
fire("CHAT_MSG_ADDON","DADMODE","ST:lv=35~dead=0~bf=20~bt=64~brk=0~dur=60~fd=3~z=Stranglethorn Vale","PARTY",BRO); fire("CHAT_MSG_ADDON","DADMODE","HI:1.3.4","PARTY",BRO); tk2(); nt=HB2.note.txt
assert(nt:find("Bro|r  35  Stranglethorn Vale",1,true) and nt:find("all good",1,true), nt)
-- a newer version in the party: one line in chat, once
do
  local said={}; local rp=print; print=function(x) said[#said+1]=tostring(x) end
  fire("CHAT_MSG_ADDON","DADMODE","HI:9.9.9","PARTY",BRO); fire("CHAT_MSG_ADDON","DADMODE","HI:9.9.9","PARTY",BRO); print=rp
  local c=0; for _,l in ipairs(said) do if l:find("DadMode 9.9.9 is out",1,true) and l:find("CurseForge",1,true) then c=c+1 end end
  assert(c==1, "told once: "..c.." "..table.concat(said," || "))
end
tk2(); assert(HB2.note.txt:find("newer than yours",1,true))
-- nobody to guide: the strip goes away and the bar gets shorter. Not during a fight.
do
  local k1,k2=units.party1,units.party2; local hgt; rawset(HB2,"SetHeight",function(_,h) hgt=h end)
  DadModeDB.helperFolded=false; tk2(); HB2.Layout(); local withStrip=hgt
  units.party1,units.party2=nil,nil
  fight=true; clock=clock+1; tk2(); assert(HB2.stripOn==true, "the bar does not change size in a fight")
  fight=false; clock=clock+1; tk2(); assert(HB2.stripOn==false and not HB2.note.shown and hgt<withStrip, "gone, and the bar is shorter: "..tostring(hgt).." < "..tostring(withStrip))
  units.party1,units.party2=k1,k2; clock=clock+1; tk2(); assert(HB2.stripOn==true and HB2.note.shown and hgt==withStrip, "back with the party")
  rawset(HB2,"SetHeight",nil)
end
m0=#sent; clock=clock+40; fire("GROUP_ROSTER_UPDATE"); local hi=false; for i=m0+1,#sent do if sent[i][2]:sub(1,3)=="HI:" then hi=true end end; assert(hi, "says its version when the party changes")
fire("CHAT_MSG_ADDON","DADMODE","ST:lv=35~dead=0~cb=0~bf=20~bt=64~brk=0","PARTY",BRO)
-- ===== boats, and recording a dock by hand =====
DadMode_SetRole(true); DadModeDB.stops={}
local sp={n=units.player.n,w=units.player.w,inst=units.player.inst}
units.player.n,units.player.w,units.player.inst=2000,700,1
SlashCmdList.DADMODE("stop")                       -- lists the names, saves nothing
assert(next(DadModeDB.stops)==nil)
SlashCmdList.DADMODE("stop ratchet_bb"); assert(DadModeDB.stops.RATCHET_BB and DadModeDB.stops.RATCHET_BB.manual and DadModeDB.stops.RATCHET_BB.n==2000)
units.player.n,units.player.w,units.player.inst=6000,6000,0
SlashCmdList.DADMODE("stop BB_RATCHET"); assert(DadModeDB.stops.BB_RATCHET.cont==0)
SlashCmdList.DADMODE("stop nonsense"); local cnt=0; for _ in pairs(DadModeDB.stops) do cnt=cnt+1 end; assert(cnt==2)
units.player.n,units.player.w,units.player.inst=1000,500,1
pin=nil; m0=#sent; SlashCmdList.DADMODE("waypoint"); for i=1,10 do clock=clock+2; DadMode_PumpOutbox() end
local ts2; for i=m0+1,#sent do if sent[i][2]:sub(1,3)=="TS:" then ts2=sent[i][2] end end
assert(ts2=="TS:RATCHET_BB!=1:2000:700~BB_RATCHET!=0:6000:6000", tostring(ts2))
-- many stops go out as several messages, none too long
for _,k in ipairs({"ORG_UC","ORG_GROM","UC_ORG","UC_GROM","GROM_ORG","GROM_UC","STEAM_POWDER","POWDER_STEAM","ZEPHRAS_SKY","SKY_ZEPHRAS"}) do DadModeDB.stops[k]={cont=1,n=-12345,w=-23456} end
clock=clock+100; m0=#sent; SlashCmdList.DADMODE("waypoint"); for i=1,20 do clock=clock+2; DadMode_PumpOutbox() end
local tsn,keys=0,0; for i=m0+1,#sent do local b=sent[i][2]; if b:sub(1,3)=="TS:" then tsn=tsn+1; assert(#b<=255); for _ in b:gmatch("=") do keys=keys+1 end end end
assert(tsn>=2 and keys==12, "all twelve stops, in several messages: "..tsn.." / "..keys)
-- the other side: a hand-recorded spot replaces a looked-up one, not the other way round
DadMode_SetRole(false); DadModeDB.stops={RATCHET_BB={cont=1,n=1,w=1}}
fire("CHAT_MSG_ADDON","DADMODE","TS:RATCHET_BB!=1:1100:500~BB_RATCHET!=0:6000:6000","PARTY",BRO)
assert(DadModeDB.stops.RATCHET_BB.n==1100 and DadModeDB.stops.RATCHET_BB.manual and DadModeDB.stops.BB_RATCHET.n==6000)
fire("CHAT_MSG_ADDON","DADMODE","TS:RATCHET_BB=1:9:9","PARTY",BRO); assert(DadModeDB.stops.RATCHET_BB.n==1100)
-- boat route and its words
local WB={map=1,x=0,y=0,n=6100,w=6000,cont=0,from="Bro"}
assert(DadMode_TravelStep(WB)=="RATCHET_BB")
DadModeDB.waypoint=WB; DadModeDB.enabled=true; DadModeDB.alerts=true; tk()
assert(slot("BOAT") and slot("BOAT").dist.txt=="to Booty Bay  100 yd", slot("BOAT") and slot("BOAT").dist.txt or "no boat slot")
assert(alertText():find("Take the boat to Booty Bay",1,true) and alertText():find("dock at Ratchet",1,true), alertText())
units.player.n=1095; tk(); assert(alertText():find("Right dock",1,true))
units.player.n,units.player.w,units.player.inst=6000,6000,0; tk(); assert(alertText():find("You took the boat",1,true))
DadModeDB.waypoint=nil; units.player.n,units.player.w,units.player.inst=sp.n,sp.w,sp.inst
-- ===== dungeon tab =====
DadMode_SetRole(true); clock=clock+500
local QL2=QuestieLoader
local dq={ [601]={name="Into the Deep",questLevel=38,requiredLevel=33,startedBy={{9001}},zoneOrSort=5000},
           [602]={name="The Drowned King",questLevel=40,requiredLevel=39,startedBy={{9002}},zoneOrSort=5001},
           [603]={name="Lost Tablets",questLevel=37,requiredLevel=30,startedBy={nil,{7001}},zoneOrSort=5000},
           [604]={name="Old Business",questLevel=36,requiredLevel=30,startedBy={{9001}},zoneOrSort=5000},
           [700]={name="Elsewhere Quest",questLevel=20,zoneOrSort=4000} }
local journey={zoneMap={[5000]={[601]=true,[603]=true,[604]=true},[5001]={[602]=true},[4000]={[700]=true}}}
QuestieLoader={ImportModule=function(self,name)
  if name=="QuestieDB" then return {
      QueryQuestSingle=function(id,f) return dq[id] and dq[id][f] end,
      QueryNPCSingle=function(id,f) if f=="name" then return id==9001 and "Archivist Vel" or "King's Herald" end; if f=="zoneID" then return 33 end end,
      QueryObjectSingle=function(id,f) if f=="name" then return "Soggy Crate" end; if f=="zoneID" then return 0 end end}
  elseif name=="ZoneDB" then return {
      GetDungeons=function() return {[5000]={"The Drowned City",{5001},33,{}},[4000]={"Empty Hole",nil,1,{}},[4500]={"No Quests Here",nil,1,{}}} end,
      GetLocalizedDungeonName=function(self,id) return id==5000 and "The Drowned City" or nil end,
      GetUiMapIdByAreaId=function(self,a) return 1000+a end}
  elseif name=="QuestieJourney" then return journey end
end}
local oldArea=C_Map.GetAreaInfo; C_Map.GetAreaInfo=function(id) return id==33 and "Stranglethorn Vale" or nil end
local dl=DadMode_Dungeons(); assert(#dl==2 and dl[1].name=="Empty Hole" and dl[2].name=="The Drowned City" and dl[2].count==4, "dungeons with quests, both area numbers counted")
qlog={ {title="Lost Tablets",questID=603,level=37} }
SlashCmdList.DADMODE("quests")
fire("CHAT_MSG_ADDON","DADMODE","ST:lv=38","PARTY",BRO); fire("CHAT_MSG_ADDON","DADMODE","ST:z=The Drowned City","PARTY",BRO)
fire("CHAT_MSG_ADDON","DADMODE","QS:1","PARTY",BRO)
fire("CHAT_MSG_ADDON","DADMODE","Q:601~38~0~Into the Deep~-2/5 Deep Pearl","PARTY",BRO)
fire("CHAT_MSG_ADDON","DADMODE","QE","PARTY",BRO)
QW.dungeon=false; QW.SetView("dungeon"); T=PG()
assert(T:find("Pick a dungeon",1,true) and T:find("The Drowned City  Bro is here  <Open>",1,true) and T:find("Empty Hole  <Open>",1,true) and not QW.search.shown, T)
assert(T:find("The Drowned City",1,true) < T:find("Empty Hole",1,true), "the one he stands in comes first")
-- pick it
m0=#sent; do local r=ROW("The Drowned City"); assert(r.btn.shown and r.btn.label.txt=="Open"); r.btn.onOnClick(r.btn) end
assert(QW.dungeon==5000 and QW.view=="dungeon" and QW.search.shown)
local asked; for i=m0+1,#sent do if sent[i][2]:sub(1,3)=="QC:" then asked=sent[i][2] end end
assert(asked=="QC:602,603,604", "asks about the dungeon quests he does not have: "..tostring(asked))
T=PG()
assert(T:find("Bro in The Drowned City",1,true) and T:find("4 quests",1,true) and T:find("Into the Deep  in his log",1,true) and T:find("2/5 Deep Pearl",1,true) and T:find("checking...",1,true), T)
fire("CHAT_MSG_ADDON","DADMODE","QD:602=0,603=0,604=1","PARTY",BRO); T=PG()
assert(T:find("In his log: 1",1,true) and T:find("Not picked up: 2",1,true) and T:find("Already done: 1",1,true), T)
assert(T:find("The Drowned King  not picked up",1,true) and T:find("starts at: King's Herald, Stranglethorn Vale",1,true) and T:find("needs level 39, he is 38",1,true), T)
assert(T:find("Lost Tablets  not picked up  you have it",1,true) and T:find("starts at: Soggy Crate",1,true), T)
assert(T:find("Old Business  already done",1,true) and not T:find("Elsewhere Quest",1,true))
QW.ApplySearch("king"); T=PG(); assert(T:find("The Drowned King",1,true) and not T:find("Old Business",1,true) and T:find("1 match the search",1,true)); QW.ApplySearch("")
-- back to the list
do local p=PILL("Other dungeon"); assert(p and p.shown); p.onOnClick(p) end; assert(QW.dungeon==false and PG():find("Pick a dungeon",1,true))
-- hovering a dungeon name does not try to show an item tooltip
shownLink=nil; QW.content.onOnHyperlinkEnter(QW.content,"dadmode:dungeon:5000"); assert(shownLink==nil)
-- no Questie on this computer
QuestieLoader=nil; QW.SetView("dungeon"); assert(PG():find("needs the Questie addon",1,true))
QuestieLoader=QL2; C_Map.GetAreaInfo=oldArea; QW.SetView("overview")
-- ===== rough boat spots (the town, not the dock) =====
DadMode_SetRole(false); DadModeDB.stops={}
-- without Questie: the zone's map is found by its name
local QL3=QuestieLoader; QuestieLoader=nil
local gmi,gmc=C_Map.GetMapInfo,C_Map.GetMapChildrenInfo
C_Map.GetBestMapForUnit=C_Map.GetBestMapForUnit or function() return 1434 end
C_Map.GetMapInfo=function(id) return {parentMapID=(id==900) and 0 or 900} end
C_Map.GetMapChildrenInfo=function(id,t,all) assert(id==900 and all==true); return {{name="The Barrens",mapID=1413},{name="Stranglethorn Vale",mapID=1434}} end
fire("CHAT_MSG_ADDON","DADMODE","TS:BB_RATCHET?=0:6000:6000","PARTY",BRO)
assert(DadModeDB.stops.BB_RATCHET.approx and DadModeDB.stops.BB_RATCHET.n==6000)
SlashCmdList.DADMODE("travel")
assert(DadModeDB.stops.RATCHET_BB and DadModeDB.stops.RATCHET_BB.approx and DadModeDB.stops.RATCHET_BB.n==1630 and DadModeDB.stops.RATCHET_BB.w==872, "Ratchet from the map name")
-- better kinds replace worse, never the other way
fire("CHAT_MSG_ADDON","DADMODE","TS:BB_RATCHET=0:6010:6000","PARTY",BRO); assert(DadModeDB.stops.BB_RATCHET.n==6010 and not DadModeDB.stops.BB_RATCHET.approx)
fire("CHAT_MSG_ADDON","DADMODE","TS:BB_RATCHET?=0:1:1","PARTY",BRO); assert(DadModeDB.stops.BB_RATCHET.n==6010)
fire("CHAT_MSG_ADDON","DADMODE","TS:BB_RATCHET!=0:6020:6000","PARTY",BRO); assert(DadModeDB.stops.BB_RATCHET.n==6020 and DadModeDB.stops.BB_RATCHET.manual)
fire("CHAT_MSG_ADDON","DADMODE","TS:BB_RATCHET=0:2:2","PARTY",BRO); assert(DadModeDB.stops.BB_RATCHET.n==6020)
-- walking to a rough spot: "go to the dock" from further away, and different words
local sp3={n=units.player.n,w=units.player.w,inst=units.player.inst}
units.player.n,units.player.w,units.player.inst=1500,872,1
DadModeDB.waypoint={map=1,x=0,y=0,n=6100,w=6000,cont=0,from="Bro"}; DadModeDB.enabled=true; DadModeDB.alerts=true; tk()
assert(slot("BOAT") and slot("BOAT").dist.txt=="to Booty Bay  130 yd", slot("BOAT") and slot("BOAT").dist.txt)
units.player.n=1600; tk(); assert(slot("BOAT").dist.txt:find("go to the dock",1,true) and alertText():find("You are in Ratchet",1,true) and alertText():find("Go to the dock",1,true), alertText())
DadModeDB.waypoint=nil; units.player.n,units.player.w,units.player.inst=sp3.n,sp3.w,sp3.inst
C_Map.GetMapInfo,C_Map.GetMapChildrenInfo=gmi,gmc; QuestieLoader=QL3
-- ===== gear comparison =====
DadMode_SetRole(true); clock=clock+1000
local items={
  [8001]={name="Old Cloth Hood",q=2,lvl=31,loc="INVTYPE_HEAD",class=4,sub=1,stats={ITEM_MOD_STAMINA_SHORT=4,ITEM_MOD_SPIRIT_SHORT=6}},
  [8002]={name="Drowned Crown",q=3,lvl=38,loc="INVTYPE_HEAD",class=4,sub=1,need=33,stats={ITEM_MOD_STAMINA_SHORT=10,ITEM_MOD_INTELLECT_SHORT=4,ITEM_MOD_SPIRIT_SHORT=3}},
  [8003]={name="Plate Helm",q=3,lvl=40,loc="INVTYPE_HEAD",class=4,sub=4,stats={}},
  [8004]={name="Weak Ring",q=2,lvl=20,loc="INVTYPE_FINGER",class=4,sub=0,stats={}},
  [8005]={name="Good Ring",q=2,lvl=35,loc="INVTYPE_FINGER",class=4,sub=0,stats={}},
  [8006]={name="New Ring",q=3,lvl=30,loc="INVTYPE_FINGER",class=4,sub=0,stats={}},
  [8007]={name="Fine Cloak",q=2,lvl=36,loc="INVTYPE_CLOAK",class=4,sub=1,stats={}},
  [8008]={name="Grey Hood",q=0,lvl=45,loc="INVTYPE_HEAD",class=4,sub=1,stats={}},
  [8009]={name="High Hood",q=3,lvl=44,loc="INVTYPE_HEAD",class=4,sub=1,need=42,stats={}},
  [8010]={name="Health Potion",q=1,lvl=30,loc="",class=0,sub=1,stats={}},
  [8011]={name="Tower Shield",q=2,lvl=38,loc="INVTYPE_SHIELD",class=4,sub=6,stats={}},
  [8012]={name="Leather Cap",q=3,lvl=39,loc="INVTYPE_HEAD",class=4,sub=2,stats={}},
}
local function iid(link) return tonumber(tostring(link):match("item:(%d+)")) end
local oldItem=C_Item
C_Item={ GetItemInfoInstant=function(l) local it=items[iid(l)]; if not it then return nil end; return iid(l),"","",it.loc,1,it.class,it.sub end,
         GetItemInfo=function(l) local it=items[iid(l)]; if not it then return nil end; return it.name,l,it.q,it.lvl,it.need or 0 end,
         GetItemStats=function(l) local it=items[iid(l)]; return it and it.stats end,
         GetItemInfoInstantOld=nil }
ITEM_MOD_STAMINA_SHORT="Stamina"; ITEM_MOD_INTELLECT_SHORT="Intellect"; ITEM_MOD_SPIRIT_SHORT="Spirit"
-- his gear: cloth hood, two rings, nothing on the back
fire("CHAT_MSG_ADDON","DADMODE","ST:lv=38","PARTY",BRO); fire("CHAT_MSG_ADDON","DADMODE","ST:cl=PRIEST","PARTY",BRO)
fire("CHAT_MSG_ADDON","DADMODE","GR:1=8001:90~11=8005:-1~12=8004:-1","PARTY",BRO)
fire("CHAT_MSG_ADDON","DADMODE","GL:1=item:8001:55","PARTY",BRO)
local function L(id) return "|cff0070dd|Hitem:"..id.."::::::::38|h["..items[id].name.."]|h|r" end
local r=DadMode_Compare(L(8002),"Bro")
assert(r and r.gap==7 and r.better==nil and r.level==38 and r.wornLevel==31 and r.slot==1 and r.worn=="item:8001:55" and not r.cannot, "facts about the head, no verdict")
assert(table.concat(r.gains,",")=="+4 Intellect,+6 Stamina" and table.concat(r.loses,",")=="-3 Spirit", table.concat(r.gains,",").." / "..table.concat(r.loses,","))
assert(DadMode_Compare(L(8003),"Bro").cannot=="can not wear plate")
assert(DadMode_Compare(L(8011),"Bro").cannot=="can not use shields")
assert(DadMode_Compare(L(8010),"Bro")==nil, "a potion is not gear")
local rr=DadMode_Compare(L(8006),"Bro"); assert(rr.slot==12 and rr.wornLevel==20 and rr.gap>0, "rings: against the weaker one")
local rc=DadMode_Compare(L(8007),"Bro"); assert(rc.empty and rc.better==nil and rc.slot==15, "empty slot")
assert(DadMode_Compare("item:8001","Bro").same==true)
assert(DadMode_Compare(L(8009),"Bro").needs==42)
-- tooltip lines
local tl=table.concat(DadMode_TooltipLines(L(8002)),"\n")
assert(tl:find("Bro|r wears |cff1eff00[Old Cloth Hood]",1,true) and tl:find("item level 31",1,true) and tl:find("This one: item level 38",1,true) and tl:find("(+7)",1,true) and tl:find("gains|r  |cff6fcf97+4 Intellect, +6 Stamina|r",1,true) and tl:find("loses|r  |cffeb7a7a-3 Spirit|r",1,true), tl)
assert(not tl:upper():find("BETTER",1,true) and not tl:upper():find("WORSE",1,true) and not tl:lower():find("upgrade",1,true), "no verdict in the tooltip")
assert(table.concat(DadMode_TooltipLines(L(8003)),"\n"):find("Bro can not wear plate",1,true))
assert(table.concat(DadMode_TooltipLines("item:8001"),"\n"):find("Bro|r wears this",1,true))
assert(table.concat(DadMode_TooltipLines(L(8007)),"\n"):find("nothing|r in that slot (Back)",1,true))
assert(#DadMode_TooltipLines(L(8010))==0)
DadModeDB.compare=false; assert(#DadMode_TooltipLines(L(8002))==0, "switched off"); DadModeDB.compare=nil
DadMode_SetRole(false); assert(#DadMode_TooltipLines(L(8002))==0, "only for guides"); DadMode_SetRole(true)
-- a warrior under 40 wears mail, and leather is flagged as lighter, not as an upgrade
fire("CHAT_MSG_ADDON","DADMODE","ST:cl=WARRIOR","PARTY",BRO)
assert(DadMode_Compare(L(8003),"Bro").cannot=="can not wear plate")
fire("CHAT_MSG_ADDON","DADMODE","ST:lv=40","PARTY",BRO); fire("CHAT_MSG_ADDON","DADMODE","ST:cl=WARRIOR","PARTY",BRO)
assert(DadMode_Compare(L(8003),"Bro").cannot==nil and DadMode_Compare(L(8012),"Bro").lighter=="leather")
fire("CHAT_MSG_ADDON","DADMODE","ST:lv=38","PARTY",BRO); fire("CHAT_MSG_ADDON","DADMODE","ST:cl=PRIEST","PARTY",BRO)
-- drops
local printed={}; local oldAdd=DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage
local realPrint=print; print=function(msg) printed[#printed+1]=tostring(msg) end
local function said(word) for _,p in ipairs(printed) do if p:find(word,1,true) then return true end end end
GetLootRollItemLink=function(id) return id==1 and L(8002) or L(8008) end
fire("START_LOOT_ROLL",1); local n1=#printed
fire("START_LOOT_ROLL",2)
fire("CHAT_MSG_LOOT","Bro receives loot: "..L(8002)..".")
GetNumLootItems=function() return 3 end; GetLootSlotLink=function(i) return ({L(8003),L(8010),L(8007)})[i] end
fire("LOOT_OPENED")
print=realPrint
assert(#printed>0, "drop notices were printed")
if true then
  assert(said("Bro can wear") and said("Drowned Crown") and said("+4 Intellect, +6 Stamina") and said("-3 Spirit"), table.concat(printed," || "))
  assert(not said("upgrade") and not said("BETTER") and not said("better"), "no verdict on drops")
  local c=0; for _,p in ipairs(printed) do if p:find("Drowned Crown",1,true) then c=c+1 end end; assert(c==1, "the same drop is announced once")
  assert(not said("Grey Hood") and not said("Plate Helm") and not said("Health Potion"), "grey, unwearable and non-gear are ignored")
  assert(said("Fine Cloak") and said("slot is empty"), table.concat(printed," || "))
end
C_Item=oldItem
-- ===== his class comes from the game when his own addon is too old to send it =====
DadMode_SetRole(true)
do
  local oldItem2=C_Item
  local it={ [8101]={n="Leather Cap",lvl=30,loc="INVTYPE_HEAD",sub=2}, [8102]={n="Mail Coif",lvl=39,loc="INVTYPE_HEAD",sub=3}, [8103]={n="Plate Helm",lvl=39,loc="INVTYPE_HEAD",sub=4}, [8104]={n="Round Shield",lvl=38,loc="INVTYPE_SHIELD",sub=6} }
  local function id2(l) return tonumber(tostring(l):match("item:(%d+)")) end
  C_Item={ GetItemInfoInstant=function(l) local x=it[id2(l)]; if not x then return nil end; return id2(l),"","",x.loc,1,4,x.sub end,
           GetItemInfo=function(l) local x=it[id2(l)]; if not x then return nil end; return x.n,l,3,x.lvl,0 end }
  local oldClass,oldLevel=UnitClass,UnitLevel
  UnitClass=function(u) return "Shaman","SHAMAN" end
  local lvNow=38; UnitLevel=function(u) return lvNow end
  local SAQ="Saqu Off-CAMWOW EU5 Realm 4 PvP"
  fire("CHAT_MSG_ADDON","DADMODE","ST:bf=10~bt=64","PARTY",SAQ)          -- an old version: no level, no class
  fire("CHAT_MSG_ADDON","DADMODE","GR:1=8101:90","PARTY",SAQ)
  local d0=nil
  -- forget what earlier tests stored
  DadMode_TooltipLines("item:8101")
  local function tip(id) local out={}; for _,l in ipairs(DadMode_TooltipLines("item:"..id)) do if l:find("Saqu",1,true) or l:sub(1,2)=="  " then out[#out+1]=l end end; return table.concat(out,"\n") end
  -- level 38 shaman: leather, and shields are fine
  local t1=tip(8102)
  assert(t1:find("Saqu can not wear mail",1,true), "a level 38 shaman wears leather: "..t1)
  assert(tip(8103):find("Saqu can not wear plate",1,true))
  assert(not tip(8104):find("Saqu can not use shields",1,true), "shamans use shields")
  assert(DadMode_Compare("item:8102","Saqu").cannot=="can not wear mail")
  UnitClass,UnitLevel=oldClass,oldLevel; C_Item=oldItem2
end
-- ===== gear in his bags, and "put it on" =====
do
  local oldItem3,oldCont=C_Item,C_Container
  local it={ [8201]={n="Leather Cap",q=2,lvl=30,loc="INVTYPE_HEAD",class=4,sub=2}, [8202]={n="Mail Coif",q=3,lvl=41,loc="INVTYPE_HEAD",class=4,sub=3,stats={ITEM_MOD_STAMINA_SHORT=9}},
             [8203]={n="Plate Helm",q=3,lvl=45,loc="INVTYPE_HEAD",class=4,sub=4}, [8204]={n="Weak Mail Coif",q=2,lvl=25,loc="INVTYPE_HEAD",class=4,sub=3},
             [8205]={n="Healing Potion",q=1,lvl=30,loc="",class=0,sub=1}, [8206]={n="Travel Bag",q=1,lvl=10,loc="INVTYPE_BAG",class=1,sub=0},
             [8207]={n="Stone Mace",q=2,lvl=40,loc="INVTYPE_WEAPONMAINHAND",class=2,sub=4}, [8208]={n="Guild Tabard",q=1,lvl=1,loc="INVTYPE_TABARD",class=4,sub=0} }
  local function id3(l) return tonumber(tostring(l):match("item:(%d+)")) or (type(l)=="number" and l) end
  C_Item={ GetItemInfoInstant=function(l) local x=it[id3(l)]; if not x then return nil end; return id3(l),"","",x.loc,1,x.class,x.sub end,
           GetItemInfo=function(l) local x=it[id3(l)]; if not x then return nil end; return x.n,l,x.q,x.lvl,0 end,
           GetItemStats=function(l) local x=it[id3(l)]; return x and (x.stats or {}) end,
           EquipItemByName=function(l) equipped=id3(l) end }
  local bagsNow={ [0]={8205,8202,8206}, [1]={8203,8204,8208,8207} }
  C_Container={ GetContainerNumSlots=function(b) return bagsNow[b] and #bagsNow[b] or 0 end,
                GetContainerNumFreeSlots=function() return 5,0 end,
                GetContainerItemInfo=function(b,sl) local id=bagsNow[b] and bagsNow[b][sl]; if not id then return nil end; return {itemID=id,stackCount=1,hyperlink="|cff0070dd|Hitem:"..id..":77::::::40|h["..it[id].n.."]|h|r"} end,
                GetItemCooldown=function() return 0,0 end }
  -- his side: only real gear is sent
  DadMode_SetRole(false)
  local bg=DadMode_ReadBagGear()
  assert(bg[1]=="BGS:4" and bg[2]=="BG:item:8202:77::::::40~item:8203:77::::::40~item:8204:77::::::40~item:8207:77::::::40", table.concat(bg," || "))
  for _,b in ipairs(bg) do assert(#b<=255) end
  -- many long items: several messages, capped at 16
  bagsNow={ [0]={} }; for i=1,30 do bagsNow[0][i]=8202 end
  local big=DadMode_ReadBagGear(); assert(big[1]=="BGS:16" and #big>=3, "capped: "..big[1].." in "..#big.." messages"); for _,b in ipairs(big) do assert(#b<=255) end
  bagsNow={ [0]={8205,8202,8206}, [1]={8203,8204,8208,8207} }
  -- guide's side
  DadMode_SetRole(true)
  local SAQ="Saqu Off-CAMWOW EU5 Realm 4 PvP"
  local oc,ol=UnitClass,UnitLevel; UnitClass=function() return "Shaman","SHAMAN" end; UnitLevel=function() return 40 end
  fire("CHAT_MSG_ADDON","DADMODE","ST:lv=40~bf=10~bt=64","PARTY",SAQ); fire("CHAT_MSG_ADDON","DADMODE","ST:cl=SHAMAN","PARTY",SAQ)
  fire("CHAT_MSG_ADDON","DADMODE","GR:1=8201:90","PARTY",SAQ)
  SlashCmdList.DADMODE("quests"); QW.SetView("gear")
  assert(PG():find("Saqu needs DadMode 1.21 or newer",1,true), "old version: bag gear unknown")
  for _,b in ipairs(bg) do fire("CHAT_MSG_ADDON","DADMODE",b,"PARTY",SAQ) end
  assert(DadMode_BagUpgrades==nil, "nothing counts better items any more")
  local function page() local out={}; for _,t in ipairs(QW.texts) do if t.txt and t.txt~="" then out[#out+1]=t.txt end end; return table.concat(out,"\n") end
  local function row(word) for i=1,QW.usedRows do local sp=QW.rows[i].spec; if sp and sp.title:find(word,1,true) then return QW.rows[i], sp, i end end end
  local function chips(sp) local o={}; for _,c in ipairs(sp.chips) do o[#o+1]=((c.kind=="good" and "G") or (c.kind=="bad" and "R") or (c.kind=="gooddim" and "g") or (c.kind=="baddim" and "r") or "?")..c.text end; return table.concat(o,",") end
  local G=page()
  assert(G:find("In his bags",1,true) and not G:upper():find("BETTER",1,true) and not G:find("tell him to put it on",1,true), G)
  assert(QW.usedRows==4, "one row for each thing to wear: "..QW.usedRows)
  local r1,s1,i1=row("|Hitem:8202:77::::::40|hMail Coif|h")
  assert(r1 and r1.shown and s1.slot=="Head" and s1.title:find("  41",1,true), "the coif has a row")
  assert(s1.sub:find("instead of",1,true) and s1.sub:find("|Hitem:8201|hLeather Cap|h",1,true) and s1.sub:find("  30",1,true), s1.sub)
  assert(chips(s1)=="G+9 Stamina" and r1.chips[1].shown and r1.chips[1].text.txt=="+9 Stamina", chips(s1))
  assert(s1.button.text=="Put it on" and s1.button.kind=="action" and r1.btn.shown and r1.btn.label.txt=="Put it on")
  -- a weaker item is listed with its facts and can be picked too: the guide decides
  local r2,s2,i2=row("Weak Mail Coif"); assert(s2.button and s2.button.text=="Put it on" and i1<i2, "higher item level first within a slot")
  local r3,s3=row("Stone Mace"); assert(s3.slot=="Main hand" and s3.sub:find("his main hand slot is empty",1,true) and s3.button, s3.sub)
  -- what he can not wear: the reason, no button, and last
  local r4,s4,i4=row("Plate Helm"); assert(s4.sub:find("Saqu can not wear plate",1,true) and not s4.button and not r4.btn.shown and i4==4, s4.sub)
  -- the guide bar no longer judges his bags
  clock=clock+1; TK(nil,0.1); assert(not (DadModeHelper.note.txt or ""):find("in his bags",1,true), DadModeHelper.note.txt)
  -- text after the rows is still there
  assert(PG():find("Average item level",1,true), "what he wears is above the rows")
  -- nothing in bags
  fire("CHAT_MSG_ADDON","DADMODE","BGS:0","PARTY",SAQ); assert(page():find("Nothing to wear in his bags",1,true) and QW.usedRows==0 and not QW.rows[1].shown)
  for _,b in ipairs(bg) do fire("CHAT_MSG_ADDON","DADMODE",b,"PARTY",SAQ) end
  -- the guide clicks the button
  r1,s1=row("|hMail Coif|h"); m0=#sent; r1.btn.onOnClick(r1.btn)
  assert(sent[#sent][2]=="WEAR:item:8202:77::::::40", "sent")
  r1,s1=row("|hMail Coif|h"); assert(r1.btn.label.txt=="Asked" and s1.button.kind=="wait" and s1.button.onClick, "asked, and he can ask again")
  fire("CHAT_MSG_ADDON","DADMODE","WEARSEEN:8202","PARTY",SAQ); r1=row("|hMail Coif|h"); assert(r1.btn.label.txt=="He sees it")
  fire("CHAT_MSG_ADDON","DADMODE","WEARNO:8202","PARTY",SAQ); r1,s1=row("|hMail Coif|h"); assert(r1.btn.label.txt=="Didn't work" and s1.button.kind=="bad")
  fire("CHAT_MSG_ADDON","DADMODE","WEARGONE:8202","PARTY",SAQ); r1=row("|hMail Coif|h"); assert(r1.btn.label.txt=="Not in bags")
  fire("CHAT_MSG_ADDON","DADMODE","WEAROK:8202","PARTY",SAQ); r1,s1=row("|hMail Coif|h"); assert(r1.btn.label.txt=="He put it on" and s1.button.kind=="done")
  m0=#sent; r1.btn.onOnClick(r1.btn); assert(#sent==m0, "nothing more to click once it is on")
  -- another tab: the rows go away
  QW.SetView("overview"); assert(QW.usedRows==0 and not QW.rows[1].shown and not QW.rows[4].shown, "rows only on the Gear tab"); QW.SetView("gear")
  -- lighter armor and a level he does not have yet are stated, not judged
  do
    it[8209]={n="Hide Cap",q=2,lvl=44,loc="INVTYPE_HEAD",class=4,sub=2}; it[8210]={n="Future Coif",q=3,lvl=50,loc="INVTYPE_HEAD",class=4,sub=3}
    local keep=C_Item.GetItemInfo; C_Item.GetItemInfo=function(l) local x=it[id3(l)]; if not x then return nil end; return x.n,l,x.q,x.lvl,(id3(l)==8210) and 45 or 0 end
    fire("CHAT_MSG_ADDON","DADMODE","BGS:2","PARTY",SAQ); fire("CHAT_MSG_ADDON","DADMODE","BG:item:8209~item:8210","PARTY",SAQ)
    local _,sa=row("Hide Cap"); assert(sa.sub:find("this is leather, he can wear mail",1,true) and sa.button, sa.sub)
    local _,sb,ib=row("Future Coif"); assert(sb.sub:find("needs level 45",1,true) and not sb.button and ib==2, sb.sub)
    C_Item.GetItemInfo=keep
    for _,b in ipairs(bg) do fire("CHAT_MSG_ADDON","DADMODE",b,"PARTY",SAQ) end
  end
  -- ===== the stats that count for him, and the sort switch =====
  do
    it[8204].stats={ITEM_MOD_STRENGTH_SHORT=6}; it[8201].stats={ITEM_MOD_STAMINA_SHORT=2}; ITEM_MOD_STRENGTH_SHORT="Strength"
    DadModeDB.focus=nil; DadModeDB.gearSort=nil; DadMode_RenderQuests()
    local _,sa,ia=row("|hMail Coif|h"); local _,sb,ib=row("Weak Mail Coif"); local _,sc,ic=row("Stone Mace")
    assert(chips(sa)=="G+7 Stamina" and chips(sb)=="R-2 Stamina,G+6 Strength", chips(sa).." / "..chips(sb))
    assert(ia<ib and ib<ic, "nothing picked: by slot, the higher item level first")
    local T=PG()
    assert(T:find("What counts for Saqu? Click his stats. ( )Stamina ( )Strength",1,true) and T:find("Sort (x)By slot ( )Item level",1,true) and not T:find("His stats",1,true), T)
    assert(QW.usedBars==2 and QW.bars[1].shown and QW.bars[1].pills[2].label.txt=="Strength" and QW.bars[1].pills[2].on==false)
    -- the guide says Strength counts for him
    local p=PILL("Strength"); p.onOnClick(p)
    assert(DadModeDB.focus.saqu.ITEM_MOD_STRENGTH_SHORT=="Strength" and DadModeDB.gearSort=="stats", "kept between sessions, and the list follows")
    _,sa,ia=row("|hMail Coif|h"); _,sb,ib=row("Weak Mail Coif"); _,sc,ic=row("Stone Mace")
    assert(ib<ia and ib<ic, "the item that gains his stat comes first")
    assert(chips(sb)=="G+6 Strength,r-2 Stamina" and chips(sa)=="g+7 Stamina", "his stat bright and first, the rest dimmed: "..chips(sb).." / "..chips(sa))
    T=PG(); assert(T:find("( )Stamina (x)Strength",1,true) and T:find("Sort ( )By slot ( )Item level (x)His stats",1,true), T)
    assert(PILL("Strength").on==true)
    -- an item that loses his stat sinks below the ones that do not touch it
    it[8201].stats={ITEM_MOD_STAMINA_SHORT=2,ITEM_MOD_STRENGTH_SHORT=3}; it[8204].stats={ITEM_MOD_STRENGTH_SHORT=1}; DadMode_RenderQuests()
    _,sb,ib=row("Weak Mail Coif"); _,sc,ic=row("Stone Mace"); _,sa,ia=row("|hMail Coif|h")
    assert(ic<ib and ia>ib, "mace 0, weak coif -2, coif -3: "..ic.." "..ib.." "..ia)
    it[8201].stats={ITEM_MOD_STAMINA_SHORT=2}; it[8204].stats={ITEM_MOD_STRENGTH_SHORT=6}
    -- by item level: the biggest step up first, an empty slot counts in full
    p=PILL("Item level"); p.onOnClick(p); assert(DadModeDB.gearSort=="level")
    _,sa,ia=row("|hMail Coif|h"); _,sb,ib=row("Weak Mail Coif"); _,sc,ic=row("Stone Mace")
    assert(ic<ia and ia<ib, "mace +40, coif +11, weak coif -5")
    p=PILL("By slot"); p.onOnClick(p); _,sa,ia=row("|hMail Coif|h"); _,sc,ic=row("Stone Mace"); assert(ia<ic and DadModeDB.gearSort=="slot")
    -- what he can not wear stays last in every order, with no stat boxes
    local r4,s4,i4=row("Plate Helm"); assert(i4==4 and #s4.chips==0)
    -- switching the stat off again
    p=PILL("Strength"); p.onOnClick(p); assert(next(DadModeDB.focus.saqu)==nil and not PG():find("His stats",1,true))
    DadModeDB.gearSort="stats"; DadMode_RenderQuests(); _,sa,ia=row("|hMail Coif|h"); assert(ia==1, "nothing picked: his stats falls back to by slot")
    _,sb=row("Weak Mail Coif"); assert(chips(sb)=="R-2 Stamina,G+6 Strength", "nothing dimmed without a pick")
    -- the header: who, class, level and zone, on every tab
    local NS=DadModeNS; local keepBro=NS.questData.Bro; NS.questData.Bro=nil
    fire("CHAT_MSG_ADDON","DADMODE","ST:z=Stranglethorn Vale","PARTY",SAQ)
    assert(QW.title.txt=="|cffe8c36aSaqu|r  |cff9aa0a6Shaman, level 40, Stranglethorn Vale|r", QW.title.txt)
    assert(not PG():find("|cffe8c36aSaqu|r\n",1,true), "one person: the name is in the header, not repeated on the page")
    -- the overview is a grid of tiles
    QW.SetView("overview")
    assert(QW.usedGrids==1 and QW.grids[1].shown and QW.grids[1].tiles[1].label.txt=="Level" and QW.grids[1].tiles[1].value.txt:find("40",1,true), "tiles")
    assert(QW.title.txt:find("Shaman, level 40",1,true) and QW.usedRows==0 and QW.usedBars==0 and not QW.bars[1].shown)
    NS.questData.Bro=keepBro; DadMode_RenderQuests(); assert(QW.title.txt=="|cffe8c36aHow are they doing|r")
    QW.SetView("gear")
    DadModeDB.focus=nil; DadModeDB.gearSort=nil; it[8204].stats=nil; it[8201].stats=nil; DadMode_RenderQuests()
  end
  -- his side: the gold button
  DadMode_SetRole(false); DadModeDB.alerts=true
  worn={[1]=8201}
  fire("CHAT_MSG_ADDON","DADMODE","WEAR:item:8202:77::::::40","PARTY",SAQ)
  assert(DadModeWear and DadModeWear.shown and DadModeWear.label.txt=="CLICK TO PUT ON: Mail Coif" and sent[#sent][2]=="WEARSEEN:8202", "button shown")
  assert(alertText():find("Saqu|r says: put on",1,true) and alertText():find("Mail Coif",1,true))
  fight=true; DadModeWear.onOnClick(DadModeWear); assert(equipped==nil and DadModeWear.shown, "not during a fight"); fight=false
  timers={}; DadModeWear.onOnClick(DadModeWear); assert(equipped==8202, "equips on his own click")
  worn[1]=8202; for _,f in ipairs(timers) do f() end
  assert(not DadModeWear.shown and sent[#sent][2]=="WEAROK:8202" and alertText():find("You put it on",1,true))
  -- it did not go on by itself
  worn[1]=8201; fire("CHAT_MSG_ADDON","DADMODE","WEAR:item:8202","PARTY",SAQ); timers={}; DadModeWear.onOnClick(DadModeWear); for _,f in ipairs(timers) do f() end
  assert(sent[#sent][2]=="WEARNO:8202" and alertText():find("right-click",1,true) and DadModeWear.shown)
  -- already on, or not in his bags
  worn[1]=8202; fire("CHAT_MSG_ADDON","DADMODE","WEAR:item:8202","PARTY",SAQ); assert(sent[#sent][2]=="WEAROK:8202")
  worn[1]=8201; fire("CHAT_MSG_ADDON","DADMODE","WEAR:item:9999","PARTY",SAQ); assert(sent[#sent][2]=="WEARGONE:9999")
  -- the button goes away by itself after two minutes
  fire("CHAT_MSG_ADDON","DADMODE","WEAR:item:8202","PARTY",SAQ); assert(DadModeWear.shown); clock=clock+130; TK(nil,0.1); assert(not DadModeWear.shown)
  -- a guide ignores it
  DadMode_SetRole(true); m0=#sent; fire("CHAT_MSG_ADDON","DADMODE","WEAR:item:8202","PARTY",SAQ); assert(#sent==m0)
  UnitClass,UnitLevel=oc,ol; C_Item,C_Container=oldItem3,oldCont; worn={}
end
-- ===== who runs which version =====
DadMode_SetRole(true); clock=clock+100
fire("CHAT_MSG_ADDON","DADMODE","HI:1.0.2:d","PARTY",BRO)
fire("CHAT_MSG_ADDON","DADMODE","HI:9.9.9:g","PARTY","Saqu Off-CAMWOW EU5 Realm 4 PvP")
local vl=table.concat(DadMode_VersionLines(),"\n")
assert(vl:find("You: guide, DadMode ",1,true) and vl:find("Bro: being guided, DadMode 1.0.2",1,true) and vl:find("older than yours",1,true), vl)
assert(vl:find("Saqu: guide, DadMode 9.9.9",1,true) and vl:find("newer than yours",1,true), vl)
QW.SetView("overview"); assert(PG():find("DadMode in this party",1,true) and PG():find("Saqu: guide, DadMode 9.9.9",1,true))
QW.SetView("quests"); assert(not PG():find("DadMode in this party",1,true))
-- asking and answering
clock=clock+60; m0=#sent; SlashCmdList.DADMODE("status")
local askedWho,hi2=false,nil; for i=m0+1,#sent do if sent[i][2]=="HI?" then askedWho=true end; if sent[i][2]:sub(1,3)=="HI:" then hi2=sent[i][2] end end
assert(askedWho and hi2 and hi2:match("^HI:[%d%.]+:g$"), "asks, and says its own version and role: "..tostring(hi2))
clock=clock+60; m0=#sent; fire("CHAT_MSG_ADDON","DADMODE","HI?","PARTY",BRO); assert(sent[#sent][2]:match("^HI:[%d%.]+:g$"), "answers when asked")
fire("CHAT_MSG_ADDON","DADMODE","HI:1.19.1","PARTY",BRO); assert(DadMode_VersionLines()[2]:find("Bro: being guided, DadMode 1.19.1",1,true) or table.concat(DadMode_VersionLines(),"\n"):find("DadMode 1.19.1",1,true), "an older HI without a role still counts")
-- ===== guides have to be approved, and permissions =====
do
  local SAQ="Saqu Off-CAMWOW EU5 Realm 4 PvP"
  local function lastTo() return sent[#sent][2] end
  local function sentSince(n,pat) for i=n+1,#sent do if sent[i][2]:find(pat,1,true) then return sent[i][2] end end end
  DadMode_SetRole(false); DadModeDB.enabled=true; DadModeDB.alerts=true; clock=clock+1000
  -- carry-over from before 1.22: people he had picked are approved the first time they act
  DadModeDB.guides={}; DadModeDB.perm={}; DadModeDB.guidesInit=nil; DadModeDB.marked={bro=true}
  DadMode_TrustInit(); assert(DadModeDB.guidesInit and DadModeDB.legacyGuides.bro and not DadModeDB.legacyGuides.saqu)
  DadMode_TrustInit(); assert(DadModeDB.legacyGuides.bro, "runs once")
  local s1=sounds; fire("CHAT_MSG_ADDON","DADMODE","PING:hello","PARTY",BRO)
  assert(sounds==s1+1 and DadModeDB.guides["bro bearfang"].state=="yes" and DadModeDB.guides["bro bearfang"].name=="Bro Bearfang" and DadModeDB.legacyGuides.bro==nil, "picked before: approved, stored under the full name")
  assert(not (DadModeApprove and DadModeApprove.shown), "no box for him")
  -- somebody he never picked: nothing happens, a box asks, the guide is told
  clock=clock+100; s1=sounds; local m1=#sent; local a1=alertText()
  fire("CHAT_MSG_ADDON","DADMODE","PING:come here stranger","PARTY",SAQ)
  assert(alertText()==a1, "no call shown")
  assert(DadModeApprove.shown and DadModeApprove.text.txt:find("Saqu Off",1,true) and DadModeApprove.text.txt:find("wants to be your guide",1,true))
  assert(sentSince(m1,"LOCKED:ask:saqu"), "the guide is told")
  -- the addon's own polling never opens a box, and nothing leaks
  DadModeApprove.no.onOnClick(DadModeApprove.no); DadModeDB.guides["saqu off"]=nil; assert(not DadModeApprove.shown)
  clock=clock+100; m1=#sent
  fire("CHAT_MSG_ADDON","DADMODE","SREQ","PARTY",SAQ); fire("CHAT_MSG_ADDON","DADMODE","QREQ:a","PARTY",SAQ)
  for i=1,10 do clock=clock+2; DadMode_PumpOutbox() end
  assert(not sentSince(m1,"ST:") and not sentSince(m1,"QS:") and sentSince(m1,"LOCKED:ask:saqu"), "no data for an unapproved guide")
  assert(not DadModeApprove.shown, "the addon's own polling does not open a box")
  -- a click on Refresh, a waypoint or "put it on" does ask
  clock=clock+100; m1=#sent; fire("CHAT_MSG_ADDON","DADMODE","QREQ","PARTY",SAQ); for i=1,10 do clock=clock+2; DadMode_PumpOutbox() end
  assert(not sentSince(m1,"ST:") and DadModeApprove.shown)
  DadModeDB.waypoint=nil; fire("CHAT_MSG_ADDON","DADMODE","WP:1434:0.5:0.5","PARTY",SAQ); assert(DadModeDB.waypoint==nil, "no waypoint from him")
  fire("CHAT_MSG_ADDON","DADMODE","WEAR:item:8202","PARTY",SAQ); assert(not (DadModeWear and DadModeWear.shown))
  fire("CHAT_MSG_PARTY","!dad",SAQ); assert(alertText()==a1, "the chat way of calling is closed too")
  -- Yes
  m1=#sent; DadModeApprove.yes.onOnClick(DadModeApprove.yes)
  assert(DadModeDB.guides["saqu off"].state=="yes" and DadModeDB.marked.saqu==true and sentSince(m1,"UNLOCK:saqu") and not DadModeApprove.shown, "approved, picked, guide told")
  clock=clock+100; s1=sounds; fire("CHAT_MSG_ADDON","DADMODE","PING:now it works","PARTY",SAQ); assert(sounds==s1+1 and alertText():find("now it works",1,true))
  -- No is remembered, and two people are asked one after the other
  DadModeDB.guides={}; clock=clock+100
  fire("CHAT_MSG_ADDON","DADMODE","PING:a","PARTY",SAQ); fire("CHAT_MSG_ADDON","DADMODE","PING:b","PARTY",BRO); fire("CHAT_MSG_ADDON","DADMODE","PING:a again","PARTY",SAQ)
  assert(DadModeApprove.text.txt:find("Saqu Off",1,true))
  DadModeApprove.no.onOnClick(DadModeApprove.no); assert(DadModeDB.guides["saqu off"].state=="no" and DadModeApprove.shown and DadModeApprove.text.txt:find("Bro Bearfang",1,true), "the next one")
  DadModeApprove.yes.onOnClick(DadModeApprove.yes); assert(not DadModeApprove.shown and DadModeDB.guides["bro bearfang"].state=="yes")
  clock=clock+100; m1=#sent; a1=alertText(); fire("CHAT_MSG_ADDON","DADMODE","PING:please","PARTY",SAQ)
  assert(alertText()==a1 and not DadModeApprove.shown and sentSince(m1,"LOCKED:no:saqu"), "refused: no box again")
  -- permissions: everything on unless switched off
  DadModeDB.guides["saqu off"]={name="Saqu Off",state="yes"}
  local function reply() clock=clock+100; local n=#sent; fire("CHAT_MSG_ADDON","DADMODE","QREQ","PARTY",SAQ); for i=1,40 do clock=clock+2; DadMode_PumpOutbox() end; local t={}; for i=n+1,#sent do t[#t+1]=sent[i][2] end; return table.concat(t," || ") end
  local r=reply(); assert(r:find("PERM:status=1~gold=1~quests=1~gear=1~call=1~waypoint=1~wear=1",1,true) and r:find("g=124050",1,true) and r:find("|| Q:",1,true) and r:find("GR:",1,true), r)
  DadModeDB.perm.gold=false; r=reply(); assert(r:find("gold=0",1,true) and not r:find("g=124050",1,true) and r:find("lv=",1,true), "gold hidden, the rest of the status stays: "..r)
  DadModeDB.perm.quests=false; r=reply(); assert(r:find("QS:0",1,true) and not r:find("|| Q:",1,true) and r:find("|| QE",1,true), r)
  clock=clock+100; m1=#sent; C_QuestLog.IsQuestFlaggedCompleted=function() return true end
  fire("CHAT_MSG_ADDON","DADMODE","QC:101,102","PARTY",SAQ); assert(not sentSince(m1,"QD:"), "no answer about finished quests either")
  DadModeDB.perm.gear=false; r=reply(); assert(not r:find("GR:",1,true) and not r:find("BGS:",1,true) and not r:find("SS:",1,true), r)
  DadModeDB.perm.status=false; r=reply(); assert(not r:find("ST:",1,true) and not r:find("CN:",1,true) and r:find("status=0",1,true), r)
  DadModeDB.perm={}
  DadModeDB.perm.call=false; clock=clock+100; m1=#sent; a1=alertText(); fire("CHAT_MSG_ADDON","DADMODE","PING:x","PARTY",SAQ)
  assert(alertText()==a1 and sentSince(m1,"DENY:call:saqu")); fire("CHAT_MSG_PARTY","!dad",SAQ); assert(alertText()==a1)
  DadModeDB.perm.call=nil
  DadModeDB.perm.waypoint=false; clock=clock+100; m1=#sent; DadModeDB.waypoint=nil; fire("CHAT_MSG_ADDON","DADMODE","WP:1434:0.5:0.5","PARTY",SAQ)
  assert(DadModeDB.waypoint==nil and sentSince(m1,"DENY:waypoint:saqu")); DadModeDB.perm.waypoint=nil
  fire("CHAT_MSG_ADDON","DADMODE","WP:1434:0.5:0.5","PARTY",SAQ); assert(DadModeDB.waypoint~=nil, "allowed again"); DadModeDB.waypoint=nil
  DadModeDB.perm.wear=false; clock=clock+100; m1=#sent; fire("CHAT_MSG_ADDON","DADMODE","WEAR:item:8202","PARTY",SAQ); assert(sentSince(m1,"DENY:wear:saqu")); DadModeDB.perm.wear=nil
  -- the My guides page
  DadModeDB.guides={["saqu off"]={name="Saqu Off",state="yes"},["bro bearfang"]={name="Bro Bearfang",state="no"}}
  opened=nil; SlashCmdList.DADMODE("guides"); local GP=DadModeGuides; assert(GP, "page exists"); DadMode_RefreshGuides()
  assert(GP.people[1].text.txt:find("Saqu Off",1,true) and GP.people[1].text.txt:find("approved",1,true) and GP.people[1].button.label.txt=="Remove")
  assert(GP.people[2].text.txt:find("Bro Bearfang",1,true) and GP.people[2].text.txt:find("refused",1,true) and GP.people[2].button.label.txt=="Forget" and not GP.people[3].button.shown)
  assert(#GP.perms==7 and GP.perms[2].key=="gold" and GP.perms[2].button.label.txt:find("Yes",1,true))
  GP.perms[2].button.onOnClick(GP.perms[2].button); assert(DadModeDB.perm.gold==false and GP.perms[2].button.label.txt:find("No",1,true))
  GP.perms[2].button.onOnClick(GP.perms[2].button); assert(DadModeDB.perm.gold==true and GP.perms[2].button.label.txt:find("Yes",1,true))
  GP.people[2].button.onOnClick(GP.people[2].button); assert(DadModeDB.guides["bro bearfang"]==nil and GP.people[2].button.shown==false, "forgotten: he is asked again next time")
  GP.people[1].button.onOnClick(GP.people[1].button); assert(next(DadModeDB.guides)==nil and GP.none.txt:find("Nobody yet",1,true))
  -- ===== the guide's side =====
  DadModeDB.guides={["bro bearfang"]={name="Bro Bearfang",state="yes"},["saqu off"]={name="Saqu Off",state="yes"}}
  DadMode_SetRole(true); clock=clock+100
  SlashCmdList.DADMODE("quests"); QW.SetView("overview")
  fire("CHAT_MSG_ADDON","DADMODE","ST:lv=38~g=5","PARTY",BRO); assert(PG():find("Level: 38",1,true))
  fire("CHAT_MSG_ADDON","DADMODE","LOCKED:ask:somebodyelse","PARTY",BRO); assert(PG():find("Level: 38",1,true), "an answer meant for another guide is not mine")
  fire("CHAT_MSG_ADDON","DADMODE","LOCKED:ask:dad","PARTY",BRO)
  assert(PG():find("Bro|r has not approved you as a guide yet",1,true) and not PG():find("Level: 38",1,true), PG())
  fire("CHAT_MSG_ADDON","DADMODE","ST:lv=39","PARTY",BRO); fire("CHAT_MSG_ADDON","DADMODE","GR:1=8001:90","PARTY",BRO)
  assert(not PG():find("Level: 39",1,true) and QW.usedRows==0, "what I overhear from him is not shown")
  clock=clock+1; TK(nil,0.1); assert(not DadModeHelper.note.txt:find("Bro:",1,true), "no warnings about him either")
  fire("CHAT_MSG_ADDON","DADMODE","LOCKED:no:dad","PARTY",BRO); assert(PG():find("said no to you as a guide",1,true))
  m1=#sent; fire("CHAT_MSG_ADDON","DADMODE","UNLOCK:dad","PARTY",BRO); assert(not PG():find("said no",1,true) and sentSince(m1,"QREQ"), "approved: asks again by itself")
  fire("CHAT_MSG_ADDON","DADMODE","ST:lv=39","PARTY",BRO); assert(PG():find("Level: 39",1,true))
  -- calling somebody who has not approved me, or who takes no calls
  clock=clock+100; DadModeHelper.callBtn.onOnClick(DadModeHelper.callBtn); fire("CHAT_MSG_ADDON","DADMODE","LOCKED:ask:dad","PARTY",BRO); TK(nil,0.1)
  assert(DadModeHelper.status.txt:find("Bro has not approved you",1,true), DadModeHelper.status.txt)
  fire("CHAT_MSG_ADDON","DADMODE","UNLOCK:dad","PARTY",BRO); clock=clock+100; TK(nil,0.1)
  DadModeHelper.callBtn.onOnClick(DadModeHelper.callBtn); fire("CHAT_MSG_ADDON","DADMODE","DENY:call:dad","PARTY",BRO); TK(nil,0.1)
  assert(DadModeHelper.status.txt:find("Bro takes no calls from guides",1,true), DadModeHelper.status.txt)
  -- what he does not share, said plainly on each tab
  fire("CHAT_MSG_ADDON","DADMODE","PERM:status=0~gold=1~quests=0~gear=0~call=1~waypoint=1~wear=1","PARTY",BRO)
  QW.SetView("overview"); assert(PG():find("Bro does not share his status with guides",1,true))
  QW.SetView("quests"); assert(PG():find("Bro does not share his quests with guides",1,true))
  QW.SetView("missing"); assert(PG():find("does not share his quests",1,true))
  QW.SetView("gear"); assert(PG():find("Bro does not share his gear with guides",1,true))
  fire("CHAT_MSG_ADDON","DADMODE","PERM:status=1~gold=1~quests=1~gear=1~call=1~waypoint=1~wear=1","PARTY",BRO)
  fire("CHAT_MSG_ADDON","DADMODE","ST:lv=39","PARTY",BRO)
  QW.SetView("overview"); assert(PG():find("Level: 39",1,true) and not PG():find("does not share",1,true))
  -- a guide never answers and never gets a box
  m1=#sent; fire("CHAT_MSG_ADDON","DADMODE","PING:x","PARTY",SAQ); fire("CHAT_MSG_ADDON","DADMODE","QREQ","PARTY",SAQ)
  assert(not (DadModeApprove and DadModeApprove.shown) and not sentSince(m1,"LOCKED"))
end
-- ===== names on the buttons, and aiming at one person =====
do
  local SAQ="Saqu Off-CAMWOW EU5 Realm 4 PvP"
  DadMode_SetRole(true); clock=clock+1000; DadModeDB.aim=nil
  local H=DadModeHelper
  -- two people to guide, both on a version that knows addresses
  fire("CHAT_MSG_ADDON","DADMODE","HI:1.23.0:d","PARTY",BRO); fire("CHAT_MSG_ADDON","DADMODE","HI:1.23.0:d","PARTY",SAQ)
  fire("CHAT_MSG_ADDON","DADMODE","WPHERE","PARTY",BRO)          -- no waypoint or call left over from earlier tests
  TK(nil,0.1); clock=clock+100; TK(nil,0.1); TK(nil,0.1)
  assert(H.aimBtn.label.txt:find("Guiding: ",1,true) and H.aimBtn.label.txt:find("everyone",1,true) and H.aimBtn.label.txt:find("click to change",1,true), H.aimBtn.label.txt)
  assert(H.callBtn.label.txt=="Call everyone" and H.wpBtn.label.txt=="Waypoint for all" and H.howBtn.label.txt=="How are they doing")
  local m=#sent; clock=clock+10; SlashCmdList.DADPING("hello all"); assert(sent[#sent][2]=="PING:hello all", "to everyone: no address")
  H.callBtn.onOnClick(H.callBtn); assert(sent[#sent][2]=="CLEAR")
  -- pick one
  H.aimBtn.onOnClick(H.aimBtn); TK(nil,0.1)
  local first=DadMode_TargetName(); assert(first=="Saqu" or first=="Bro")
  assert(H.callBtn.label.txt=="Call "..first and H.wpBtn.label.txt=="Waypoint for "..first and H.howBtn.label.txt=="How is "..first.." doing" and H.aimBtn.label.txt:find(first,1,true))
  clock=clock+10; SlashCmdList.DADPING("just you"); assert(sent[#sent][2]=="TO:"..first:lower()..":PING:just you", sent[#sent][2])
  DadModeHelper.callBtn.onOnClick(DadModeHelper.callBtn); assert(sent[#sent][2]=="TO:"..first:lower()..":CLEAR", sent[#sent][2])
  pin=nil; clock=clock+10; SlashCmdList.DADMODE("waypoint"); local wp; for i=#sent,1,-1 do if sent[i][2]:find("WP:",1,true) then wp=sent[i][2]; break end end
  assert(wp:sub(1,#("TO:"..first:lower()..":WP:"))=="TO:"..first:lower()..":WP:", wp)
  -- the other one, then everyone again
  H.aimBtn.onOnClick(H.aimBtn); local second=DadMode_TargetName(); assert(second and second~=first)
  H.aimBtn.onOnClick(H.aimBtn); assert(DadMode_TargetName()==nil and DadModeDB.aim==nil)
  -- somebody on an older version gets it without an address, or it would be lost
  fire("CHAT_MSG_ADDON","DADMODE","HI:1.22.0:d","PARTY",BRO); DadModeDB.aim="bro"
  clock=clock+10; SlashCmdList.DADPING("old one"); assert(sent[#sent][2]=="PING:old one", sent[#sent][2])
  assert(DadMode_AimAt("Saqu","WEAR:item:1")=="TO:saqu:WEAR:item:1" and DadMode_AimAt("Bro","WEAR:item:1")=="WEAR:item:1")
  -- a guide in the party is not somebody to guide: one person left, named on the buttons, no address needed
  H.callBtn.onOnClick(H.callBtn)          -- cancel the call that is still running
  fire("CHAT_MSG_ADDON","DADMODE","HI:1.23.0:g","PARTY",SAQ); DadModeDB.aim=nil; TK(nil,0.1)
  assert(DadMode_TargetName()=="Bro" and H.callBtn.label.txt:find("Bro",1,true) and H.aimBtn.label.txt:find("Bro",1,true) and not H.aimBtn.label.txt:find("click",1,true), H.aimBtn.label.txt)
  clock=clock+100; SlashCmdList.DADPING("only one"); assert(sent[#sent][2]=="PING:only one")
  -- the window names him too
  SlashCmdList.DADMODE("quests"); DadMode_RenderQuests()
  -- receiving: a message aimed at me arrives, one aimed at somebody else does not
  DadMode_SetRole(false); DadModeDB.alerts=true; DadModeDB.enabled=true
  DadModeDB.guides={["bro bearfang"]={name="Bro Bearfang",state="yes"},["saqu off"]={name="Saqu Off",state="yes"}}
  clock=clock+100; local s0=sounds; local a0=alertText()
  fire("CHAT_MSG_ADDON","DADMODE","TO:somebody:PING:not for me","PARTY",BRO); assert(sounds==s0 and alertText()==a0, "aimed at somebody else")
  fire("CHAT_MSG_ADDON","DADMODE","TO:dad:PING:this is for me","PARTY",BRO); assert(sounds==s0+1 and alertText():find("this is for me",1,true), "aimed at me")
  fire("CHAT_MSG_ADDON","DADMODE","TO:dad:CLEAR","PARTY",BRO)
  -- aimed and not approved: still closed
  DadModeDB.guides["bro bearfang"]=nil; clock=clock+100; a0=alertText()
  fire("CHAT_MSG_ADDON","DADMODE","TO:dad:PING:let me in","PARTY",BRO); assert(alertText()==a0 and DadModeApprove.shown)
  DadModeApprove.yes.onOnClick(DadModeApprove.yes)
  fire("CHAT_MSG_ADDON","DADMODE","TO::broken","PARTY",BRO); fire("CHAT_MSG_ADDON","DADMODE","TO:dad","PARTY",BRO)
end
-- ===== looking at the box alone =====
do
  DadMode_SetRole(false); DadModeDB.guides={}; DadModeDB.marked={}; local m=#sent
  SlashCmdList.DADMODE("testbox"); SlashCmdList.DADMODE("testbox")
  assert(DadModeApprove.shown and DadModeApprove.text.txt:find("Test Guide",1,true))
  DadModeApprove.yes.onOnClick(DadModeApprove.yes)
  assert(not DadModeApprove.shown and DadModeDB.guides["test guide"].state=="yes" and next(DadModeDB.marked)==nil and #sent==m, "listed, but nobody is picked and nothing is sent")
  SlashCmdList.DADMODE("testbox"); DadModeApprove.no.onOnClick(DadModeApprove.no); assert(DadModeDB.guides["test guide"].state=="no")
  DadModeDB.guides={}
end
-- ===== personal data goes by whisper to the guide who asked =====
do
  local SAQ="Saqu Off-CAMWOW EU5 Realm 4 PvP"
  local function drain() for i=1,60 do clock=clock+2; DadMode_PumpOutbox() end end
  local function since(n) local t={}; for i=n+1,#sent do t[#t+1]=sent[i] end; return t end
  DadMode_SetRole(false); DadModeDB.perm={}; clock=clock+1000
  DadModeDB.guides={["bro bearfang"]={name="Bro Bearfang",state="yes"},["saqu off"]={name="Saqu Off",state="yes"}}
  -- a request: every part of the answer is whispered to the one who asked
  local n=#sent; fire("CHAT_MSG_ADDON","DADMODE","QREQ","PARTY",BRO); drain()
  local got=since(n); assert(#got>=5, "an answer went out")
  local heads={}
  for _,m in ipairs(got) do
    assert(m[3]=="WHISPER" and m[4]==BRO, "whispered to Bro, exactly as the game named him: "..tostring(m[2]):sub(1,20).." on "..tostring(m[3]))
    heads[m[2]:match("^(%u+)")]=true
  end
  assert(heads.PERM and heads.ST and heads.QS and heads.QE and heads.GR, "status, quests and gear all in it")
  -- the short status and the finished-quest answer too
  clock=clock+100; n=#sent; fire("CHAT_MSG_ADDON","DADMODE","SREQ","PARTY",BRO); drain()
  got=since(n); assert(#got==3); for _,m in ipairs(got) do assert(m[3]=="WHISPER" and m[4]==BRO) end
  C_QuestLog.IsQuestFlaggedCompleted=function() return true end
  n=#sent; fire("CHAT_MSG_ADDON","DADMODE","QC:101","PARTY",BRO); assert(sent[#sent][2]=="QD:101=1" and sent[#sent][3]=="WHISPER" and sent[#sent][4]==BRO)
  -- the guide says whispers do not arrive: the same answer on the party channel
  clock=clock+100; n=#sent; fire("CHAT_MSG_ADDON","DADMODE","QREQ:p","PARTY",BRO); drain()
  got=since(n); assert(#got>=5); for _,m in ipairs(got) do assert(m[3]=="PARTY" and m[4]==nil, "party channel when asked for") end
  n=#sent; fire("CHAT_MSG_ADDON","DADMODE","QC:101","PARTY",BRO); assert(sent[#sent][3]=="PARTY", "and the follow-up answers as well")
  clock=clock+100; n=#sent; fire("CHAT_MSG_ADDON","DADMODE","SREQ:p","PARTY",BRO); drain(); got=since(n); assert(#got==3 and got[1][3]=="PARTY")
  -- back to whispers as soon as he asks the normal way
  clock=clock+100; n=#sent; fire("CHAT_MSG_ADDON","DADMODE","QREQ","PARTY",BRO); drain(); assert(since(n)[1][3]=="WHISPER")
  -- two guides ask at the same time: each gets his own copy, one after the other
  clock=clock+100; n=#sent
  fire("CHAT_MSG_ADDON","DADMODE","QREQ","PARTY",BRO); fire("CHAT_MSG_ADDON","DADMODE","QREQ","PARTY",SAQ); fire("CHAT_MSG_ADDON","DADMODE","QREQ","PARTY",SAQ); drain(); drain()
  local toBro,toSaq,ends=0,0,0
  for _,m in ipairs(since(n)) do if m[4]==BRO then toBro=toBro+1 elseif m[4]==SAQ then toSaq=toSaq+1 end; if m[2]=="QE" then ends=ends+1 end end
  assert(toBro>=5 and toSaq==toBro and ends==2, "one copy each: "..toBro.." / "..toSaq.." / "..ends)
  -- an unapproved guide still gets nothing, by whisper or otherwise
  DadModeDB.guides["saqu off"]=nil; clock=clock+100; n=#sent; fire("CHAT_MSG_ADDON","DADMODE","QREQ:ap","PARTY",SAQ); drain()
  for _,m in ipairs(since(n)) do assert(m[2]:sub(1,7)=="LOCKED:", "only the refusal: "..m[2]) end
  assert(not DadModeApprove.shown, "and no box for an automatic request")
  DadModeDB.guides["saqu off"]={name="Saqu Off",state="yes"}

  -- ===== the guide's side: the safety net =====
  DadMode_SetRole(true); clock=clock+1000
  fire("CHAT_MSG_ADDON","DADMODE","HI:1.25.0:d","PARTY",BRO); fire("CHAT_MSG_ADDON","DADMODE","HI:1.25.0:g","PARTY",SAQ)
  assert(not DadMode_WhisperBad("Bro"))
  -- whispers arrive: nothing more is asked
  n=#sent; SlashCmdList.DADMODE("quests")
  fire("CHAT_MSG_ADDON","DADMODE","PERM:status=1~gold=1~quests=1~gear=1~call=1~waypoint=1~wear=1","WHISPER",BRO)
  for i=1,10 do clock=clock+2; DadMode_PrivateTick() end
  for _,m in ipairs(since(n)) do assert(not m[2]:find("QREQ:p",1,true), "no second request when whispers work") end
  -- whispers do not arrive: one more request, for the party channel, aimed at him
  clock=clock+100; n=#sent; SlashCmdList.DADMODE("quests")
  clock=clock+3; DadMode_PrivateTick(); for _,m in ipairs(since(n)) do assert(not m[2]:find("QREQ:p",1,true), "not before six seconds") end
  clock=clock+4; DadMode_PrivateTick(); DadMode_PrivateTick()
  local fb=0; for _,m in ipairs(since(n)) do if m[2]=="TO:bro:QREQ:p" then fb=fb+1; assert(m[3]=="PARTY") end end
  assert(fb==1, "asked once more, on the party channel: "..fb)
  fire("CHAT_MSG_ADDON","DADMODE","ST:lv=40","PARTY",BRO)
  assert(DadMode_WhisperBad("Bro"), "remembered: his whispers do not arrive")
  -- from then on the party request goes out straight away, also for the short status
  clock=clock+100; n=#sent; SlashCmdList.DADMODE("quests"); local direct=false
  for _,m in ipairs(since(n)) do if m[2]=="TO:bro:QREQ:p" then direct=true end end; assert(direct, "no six second wait any more")
  fire("CHAT_MSG_ADDON","DADMODE","ST:lv=40","PARTY",BRO)
  n=#sent; clock=clock+60; TK(nil,0.1); local st=false
  for _,m in ipairs(since(n)) do if m[2]=="TO:bro:SREQ:p" then st=true end end; assert(st, "short status the same way")
  -- a whisper gets through later: back to normal
  fire("CHAT_MSG_ADDON","DADMODE","ST:lv=40","WHISPER",BRO); assert(not DadMode_WhisperBad("Bro"))
  -- somebody on a version before whispers answers on the party channel anyway: no safety net needed
  fire("CHAT_MSG_ADDON","DADMODE","HI:1.24.0:d","PARTY",BRO); clock=clock+100; n=#sent; SlashCmdList.DADMODE("quests")
  for i=1,10 do clock=clock+2; DadMode_PrivateTick() end
  for _,m in ipairs(since(n)) do assert(not m[2]:find("QREQ:p",1,true)) end
  -- nobody answers at all: it gives up quietly
  fire("CHAT_MSG_ADDON","DADMODE","HI:1.25.0:d","PARTY",BRO); clock=clock+100; n=#sent; SlashCmdList.DADMODE("quests")
  for i=1,30 do clock=clock+2; DadMode_PrivateTick() end
  fb=0; for _,m in ipairs(since(n)) do if m[2]=="TO:bro:QREQ:p" then fb=fb+1 end end; assert(fb==1 and not DadMode_WhisperBad("Bro"), "one try, then quiet: "..fb)
end
-- ===== guiding somebody who is not in my party =====
do
  local function since(n) local t={}; for i=n+1,#sent do t[#t+1]=sent[i] end; return t end
  local function drain() for i=1,60 do clock=clock+2; DadMode_PumpOutbox() end end
  local B="Bro Bearfang-CAMWOW EU5 Realm 4 PvP"
  local W=DadModeQuests
  local keepBro,keepSaqu=units.party2,units.party1
  local PERMS="PERM:status=1~gold=1~quests=1~gear=1~call=1~waypoint=1~wear=1"
  -- as a guide: Bro answers while he is in my party, so he is remembered
  DadMode_SetRole(true); DadModeDB.known=nil; clock=clock+100
  fire("CHAT_MSG_ADDON","DADMODE","ST:lv=47~cl=SHAMAN","WHISPER",B)
  assert(DadModeDB.known.bro and DadModeDB.known.bro.name=="Bro" and DadModeDB.known.bro.full==B and DadModeDB.known.bro.id=="bro bearfang", "remembered")
  assert(DadMode_RemoteState("Bro")==nil, "in my party")
  -- he leaves the party. Opening the window asks him by whisper.
  units.party2=nil
  clock=clock+100; local n=#sent; SlashCmdList.DADMODE("quests"); W.SetView("overview")
  local w; for _,m in ipairs(since(n)) do if m[3]=="WHISPER" then w=m end end
  assert(w and w[2]=="QREQ" and w[4]==B, "asked by whisper, by the name the game gave")
  assert(DadMode_RemoteState("Bro")=="asking" and PG():find("Asking Bro by whisper",1,true) and not PG():find("Level: 47",1,true), "what he said earlier is not shown as if it were now: "..PG())
  -- he answers by whisper
  n=#sent
  fire("CHAT_MSG_ADDON","DADMODE",PERMS,"WHISPER",B)
  fire("CHAT_MSG_ADDON","DADMODE","ST:lv=48~cl=SHAMAN","WHISPER",B)
  fire("CHAT_MSG_ADDON","DADMODE","QS:1","WHISPER",B); fire("CHAT_MSG_ADDON","DADMODE","Q:9001~30~0~Far Away Quest~-1/2 Thing","WHISPER",B); fire("CHAT_MSG_ADDON","DADMODE","QE","WHISPER",B)
  assert(DadMode_RemoteState("Bro")=="ok" and PG():find("Level: 48",1,true) and PG():find("Bro is not in your party. Asked by whisper.",1,true), PG())
  W.SetView("quests"); assert(PG():find("Far Away Quest",1,true))
  local qc; for _,m in ipairs(since(n)) do if m[2]:sub(1,3)=="QC:" then qc=m end end
  assert(qc and qc[3]=="WHISPER" and qc[4]==B, "the question about finished quests goes by whisper too")
  -- somebody else with the same first name is not him
  fire("CHAT_MSG_ADDON","DADMODE","ST:lv=59","WHISPER","Bro Other-Some Realm"); W.SetView("overview"); assert(PG():find("Level: 48",1,true) and not PG():find("Level: 59",1,true))
  -- a call by whisper from outside the party is not a thing
  fire("CHAT_MSG_ADDON","DADMODE","HI:9.9.9:d","WHISPER",B)
  -- "put it on" goes by whisper, and so does his answer
  n=#sent; DadMode_TellWear("Bro","item:8202"); assert(sent[#sent][2]=="WEAR:item:8202" and sent[#sent][3]=="WHISPER" and sent[#sent][4]==B)
  fire("CHAT_MSG_ADDON","DADMODE","WEAROK:8202","WHISPER",B); assert(DadModeNS.questData.Bro.wearTold["item:8202"]=="ok")
  -- no answer
  clock=clock+100; SlashCmdList.DADMODE("quests"); clock=clock+10; DadMode_RenderQuests()
  assert(DadMode_RemoteState("Bro")=="silent" and PG():find("Bro|r does not answer",1,true) and not PG():find("Level: 48",1,true), PG())
  -- not online: the game's own line says so, and it stays out of the chat window
  ERR_CHAT_PLAYER_NOT_FOUND_S="No player named '%s' is currently playing."
  clock=clock+100; SlashCmdList.DADMODE("quests")
  assert(DadMode_RemoteSystem("No player named 'Someone Else' is currently playing.")==false, "other lines pass")
  assert(DadMode_RemoteSystem("No player named 'Bro Bearfang' is currently playing.")==true, "this one is ours")
  assert(DadMode_RemoteState("Bro")=="offline" and PG():find("Bro|r is not online",1,true), PG())
  clock=clock+100; assert(DadMode_RemoteSystem("No player named 'Bro Bearfang' is currently playing.")==false, "not long after asking")
  -- back in my party: the normal way again
  units.party2=keepBro; assert(DadMode_RemoteState("Bro")==nil)
  clock=clock+100; n=#sent; SlashCmdList.DADMODE("quests"); for _,m in ipairs(since(n)) do assert(m[3]~="WHISPER", "nobody is asked by whisper when everybody is here") end
  -- alone, with nobody remembered
  units.party2=nil; SlashCmdList.DADMODE("forget bro"); assert(DadModeDB.known.bro==nil and DadModeNS.questData.Bro==nil)
  units.party1=nil; clock=clock+100; n=#sent; SlashCmdList.DADMODE("quests"); clock=clock+10; DadMode_RenderQuests()
  assert(#sent==n and PG():find("You are not in a party",1,true) and not PG():find("Dad needs",1,true), PG())
  units.party1=keepSaqu

  -- as the one being guided: an approved guide outside the party asks
  DadMode_SetRole(false); DadModeDB.guides=DadModeDB.guides or {}
  DadModeDB.guides["bro bearfang"]={name="Bro Bearfang",state="yes"}
  clock=clock+400; n=#sent; fire("CHAT_MSG_ADDON","DADMODE","QREQ","WHISPER",B); drain()
  local got=since(n); assert(#got>=4 and got[1][2]:sub(1,5)=="PERM:", "he answers: "..#got)
  for _,m in ipairs(got) do assert(m[3]=="WHISPER" and m[4]==B, "only to him: "..m[2]:sub(1,12).." on "..tostring(m[3])) end
  -- a call or a waypoint by whisper from outside the party does nothing
  local AL2; for _,f in ipairs(frames) do if rawget(f,"text") and rawget(f,"hint") and rawget(f,"onOnMouseDown") then AL2=f end end
  AL2.text:SetText("x"); n=#sent
  fire("CHAT_MSG_ADDON","DADMODE","PING:says: come to me","WHISPER",B); fire("CHAT_MSG_ADDON","DADMODE","WP:1434:0.5:0.5","WHISPER",B)
  assert(AL2.text.txt=="x" and #sent==n and not DadModeDB.waypoint, "calls and waypoints need a party")
  -- "put it on" from outside: the answer goes back by whisper
  clock=clock+100; n=#sent; fire("CHAT_MSG_ADDON","DADMODE","WEAR:item:9999","WHISPER",B)
  assert(sent[#sent][2]=="WEARGONE:9999" and sent[#sent][3]=="WHISPER" and sent[#sent][4]==B)
  -- a stranger gets nothing at all: no answer, no box
  clock=clock+400; n=#sent; fire("CHAT_MSG_ADDON","DADMODE","QREQ","WHISPER","Stranger Danger-Some Realm"); drain()
  assert(#sent==n and not DadModeApprove.shown, "silence for strangers")
  -- and so does a guide he has said no to, or taken back his yes from
  DadModeDB.guides["bro bearfang"].state="no"
  clock=clock+400; n=#sent; fire("CHAT_MSG_ADDON","DADMODE","QREQ","WHISPER",B); drain(); assert(#sent==n, "refused: silence")
  DadModeDB.guides["bro bearfang"]=nil
  clock=clock+400; n=#sent; fire("CHAT_MSG_ADDON","DADMODE","QREQ","WHISPER",B); drain(); assert(#sent==n and not DadModeApprove.shown, "not approved: silence, and no box from outside the party")
  units.party2=keepBro; DadMode_SetRole(true)
end
-- ===== whispers arrive or not: said on the Overview =====
do
  local B="Bro Bearfang-CAMWOW EU5 Realm 4 PvP"
  fire("CHAT_MSG_ADDON","DADMODE","ST:lv=40","WHISPER",B)
  local t=table.concat(DadMode_VersionLines(),"\n"); assert(t:find("answers by whisper",1,true), t)
end
print("OPTIONS_TESTS_PASSED")
''')
