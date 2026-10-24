require('setupkoenv');G_defaults=require('luadefaults'):open()
G_reader_settings=require('luasettings'):open(os.getenv('KO_HOME')..'/settings.reader.lua')
local settings=G_reader_settings
settings:saveSetting('read_receipt_v2_online',false)
local Device=require('device');require('document/canvascontext'):init(Device)
local Screen=Device.screen;local BB=require('ffi/blitbuffer');local UI=require('ui/uimanager')
local root=assert(arg[0]:match('^(.*)/tests/[^/]+$'))..'/'
local file=assert(io.open(os.getenv('INK_SOURCE') or root..'2-inkfolio.lua'));local source=file:read('*a');file:close()
local api=assert(loadstring(source..[[
return {ink=Inkfolio,S=S,bars=ReadingBars,build=buildReceipt,render=renderReceipt,menu=receiptSettingsMenu,
 summary=summaryItems,cache=CACHE,key=bookKey,stars=scoreStars,run=RUN,store=store,background=receiptBackground,progress=PixelProgress,paper=ReceiptPaper,editor=AppearanceEditor,weather=WEATHER,launcher=receiptMenuWidget}
]]))()
local ink,S=api.ink,api.S
local passed,failed=0,0
local function check(name,fn)local ok,e=pcall(fn);if ok then passed=passed+1;print('PASS',name)else failed=failed+1;print('FAIL',name,e)end end
local now=os.time{year=2026,month=10,day=18,hour=20,min=0,sec=0}
local function stamp(day,hour,min)return os.time{year=2026,month=10,day=day,hour=hour or 12,min=min or 0,sec=0}end
local SQ=require('lua-ljsqlite3/init');local ds=require('datastorage')
local db=SQ.open(ds:getSettingsDir()..'/statistics.sqlite3')
db:exec('CREATE TABLE page_stat_data(id_book INTEGER,page INTEGER,start_time INTEGER,duration INTEGER);')
db:exec('CREATE VIEW page_stat AS SELECT * FROM page_stat_data;')
local rows={{1,1,stamp(1),5400},{1,2,stamp(3),0},{1,3,stamp(4,23,30),3600},{2,1,stamp(12),1800},{1,4,now-60,600}}
for _,r in ipairs(rows)do db:exec(string.format('INSERT INTO page_stat_data VALUES(%d,%d,%d,%d);',unpack(r)))end
db:close()
local ui={document={file='ui-test.epub',getPageCount=function()return 100 end},
 doc_props={title='排版测试样书',authors='示例作者'},doc_settings={data={doc_pages=100}},view={state={page=23}},
 statistics={id_curr_book=1,isEnabled=function()return true end,insertDB=function()end,avg_time=30},
 toc={getTocTitleByPage=function()return '第十二章：在轨道上继续探索'end}}
local curve=ink.readCurve
ink.wordState.tracking_since=stamp(1,0);ink.wordState.days={}
for i=1,18 do if i~=2 then ink.wordState.days[os.date('%Y-%m-%d',stamp(i))]={words=i==3 and 0 or i*1500,incomplete=i==18}end end
local words=ink.readWordChart
ink.readCurve=function(context,period)return curve(context,period,now)end
ink.readWordChart=function(period)return words(period,now)end
ink.estimatedWords=function()return 123456 end;ink.wakeWords=function()return 6789 end
api.cache[api.key(ui.doc_props)]={rating=8.8,url='https://book.douban.com/subject/1/'}
ink.monthly.record={year=2026,month=9,category='all',update_date='2026-10-08',url=ink.monthlyURL('all','2026-10-08'),complete=true,
 items={{rank=1,title='落在我身上的雨',author='陆庆屹',rating=9.1,url='https://book.douban.com/subject/2/'},
 {rank=2,title='无论如何，潜水',author='河美娜',rating=7.9,url='https://book.douban.com/subject/3/'},
 {rank=3,title='爱的辛劳：一名心理咨询师见证的欲望、创伤与人间',author='[美] 斯蒂芬·格罗斯',rating=8.3,url='https://book.douban.com/subject/4/'}}}
settings:saveSetting(S.auto_fit,false);settings:saveSetting(S.cover,false);settings:saveSetting(S.online,false)
settings:saveSetting(S.intro,true);settings:saveSetting(S.stats,true)
settings:saveSetting(S.summary,{'book_today','global_total'});settings:saveSetting(S.charts,{'week','month_words'})
settings:saveSetting(S.word_book,true);settings:saveSetting(S.word_session,true);settings:saveSetting(S.remain,false)
local Text=require('ui/widget/textboxwidget');local H=require('ui/widget/horizontalgroup');local V=require('ui/widget/verticalgroup')
local function unpad(widget)
 if widget and not widget.text and widget[2] and widget[2].text then return widget[2] end
 return widget
end
local function walk(widget,fn)fn(widget);for _,child in ipairs(widget)do walk(child,fn)end end
local function render(options)
 local fields={};local native=Text.new
 Text.new=function(self,args)local t=native(self,args);fields[#fields+1]=t;return t end
 local ok,w,valid,size=pcall(api.render,ui,ui.view.state,options or {width=.84,font=1,scale=.70,background='white',measure_only=true})
 Text.new=native;assert(ok,w);assert(w and valid,'native render invalid')
 return w,fields,size
end
local function find(fields,text)for _,t in ipairs(fields)do if t.text==text then return t end end end
local function count(fields,prefix)local n=0;for _,t in ipairs(fields)do if t.text:sub(1,#prefix)==prefix then n=n+1 end end;return n end
local Geom=require('ui/geometry');local Event=require('ui/event')
local output=os.getenv('INK_OUTPUT')or root..'checks'
local function saved()return require('dump')(settings.data,nil,true)end
local function paint(widget,path)
 local bb=BB.new(Screen:getWidth(),Screen:getHeight(),BB.TYPE_BB8);bb:fill(BB.COLOR_WHITE);widget:paintTo(bb,0,0)
 if path then bb:writePNG(output..'/'..path..'-'..Screen:getWidth()..'x'..Screen:getHeight()..'.png')end
 return bb
end
local function tap(widget,x,y)return widget:handleEvent(Event:new('Gesture',{ges='tap',pos=Geom:new{x=x,y=y,w=0,h=0}}))end
local function onStack(widget)for _,entry in ipairs(UI._window_stack)do if entry.widget==widget then return true end end;return false end
settings:saveSetting(S.stats,false);settings:saveSetting(S.intro,false)
settings:saveSetting(S.word_book,false);settings:saveSetting(S.word_session,false);settings:saveSetting(S.remain,false)
settings:saveSetting(S.date,true);settings:saveSetting(S.weather,true);settings:saveSetting(S.weather_tomorrow,false)
settings:saveSetting(S.width,.84);settings:saveSetting(S.font,1);settings:saveSetting(S.scale,.65)
ui.bookinfo={getCoverImage=function()local b=BB.new(160,220,BB.TYPE_BB8);b:fill(BB.COLOR_WHITE);return b end}
local warm=render({width=.84,font=1,scale=.65,measure_only=true});warm:free()
for _,style in ipairs({'classic','pixel','swiss','cover'})do
 check(style..' actual preview taps enter native-resolution draft and return without saving',function()
  settings:saveSetting(S.ui_style,style);local before=saved()
  local editor=api.editor:new{ui=ui};UI:show(editor);assert(editor.valid)
  paint(editor,'editor-'..style):free()
  local rect=editor.preview_image.dimen
  editor:change(style=='cover'and 'card_background'or 'background','black')
  assert(tap(editor,rect.x+rect.w/2,rect.y+rect.h/2));local full=assert(editor.fullscreen)
  assert(onStack(editor)and onStack(full)and not editor.pending)
  local bb=paint(full,'fullscreen-'..style);local canvas=editor.preview_canvas
  for y=0,Screen:getHeight()-1,11 do for x=0,Screen:getWidth()-1,11 do
   assert(bb:getPixel(x,y):getColor8().a==canvas:getPixel(x,y):getColor8().a,'full preview differs from latest draft')
  end end;bb:free()
  assert(tap(full,Screen:getWidth()/2,Screen:getHeight()/2))
  assert(not onStack(full)and not editor.fullscreen and onStack(editor)and not editor.closed)
  assert(editor.draft[style=='cover'and 'card_background'or 'background']=='black'and saved()==before)
  paint(editor):free();rect=editor.preview_image.dimen
  assert(tap(editor,rect.x+1,rect.y+1));assert(editor.fullscreen)
  editor.fullscreen:onAnyKeyPressed();assert(not editor.fullscreen and onStack(editor))
  editor:onCancel();assert(editor.closed and not onStack(editor)and saved()==before)
 end)
 check(style..' full preview closes with suspend without retaining drafts or buffers',function()
  settings:saveSetting(S.ui_style,style);local before=saved();local editor=api.editor:new{ui=ui};UI:show(editor)
  editor:onPreviewTap();local full=assert(editor.fullscreen);full:onSuspend()
  assert(editor.closed and not editor.fullscreen and not editor.preview_canvas and not onStack(full)and not onStack(editor)and saved()==before)
 end)
end
check('card palette controls preview, cancel and save independently from cover margins',function()
 settings:saveSetting(S.ui_style,'cover');settings:delSetting(S.card_background);settings:saveSetting(S.cover_background,'black')
 local before=saved();local editor=api.editor:new{ui=ui};UI:show(editor)
 local controls=editor[1][1][7];local row=controls.buttons[5]
 assert(row[1].text=='卡片底色'and row[2].checked_func()and row[2].text=='自动'and row[4].text=='深灰')
 row[3].callback();editor:refreshPreview();assert(editor.draft.card_background=='white'and editor.draft.cover_background=='black')
 editor:onCancel();assert(saved()==before)
 editor=api.editor:new{ui=ui};UI:show(editor);editor:change('card_background','black');editor:save()
 assert(settings:readSetting(S.card_background)=='black'and settings:readSetting(S.cover_background)=='black')
end)
local function solid(value,w,h)
 local b=BB.new(w or Screen:getWidth(),h or Screen:getHeight(),BB.TYPE_BB8);b:fill(BB.Color8(value));return b
end
for _,case in ipairs({{149,'white'},{150,'black'},{151,'black'}})do
 check('exact threshold end-to-end '..case[1],function()
  ui.bookinfo.getCoverImage=function()return solid(case[1])end
  local scene,fields=render({ui_style='cover',card_background='auto',measure_only=true})
  assert(scene.card_background==case[2])
  for _,t in ipairs(fields)do
   assert(t.bgcolor:getColor8().a==(case[2]=='black'and 51 or 255))
  end
  assert(scene[1].background:getColor8().a==(case[2]=='black'and 51 or 255))
  if case[1]~=151 then paint(scene,'threshold-'..case[1]):free()end
  scene:free()
 end)
end
for _,case in ipairs({{144,150,'white'},{149,150,'white'},{149,151,'black'},{150,151,'black'}})do
 check('fractional mean at threshold '..case[1]..' '..case[2],function()
  -- The rectangular ring has exactly twelve samples; two varied pixels
  -- check means below 150, exactly 150, and above 150 without rounding.
  local image=solid(150,6,6);image:setPixel(1,1,BB.Color8(case[1]));image:setPixel(2,1,BB.Color8(case[2]))
  local result=ink.cardBackground(image,{x=0,y=0,w=6,h=6},{x=2,y=2,w=2,h=2},BB.COLOR_WHITE,6,6,1,1)
  image:free();assert(result==case[3])
 end)
end
for _,shape in ipairs({{160,220},{300,100},{100,400}})do for _,margin in ipairs({'white','black'})do
 for _,shade in ipairs({0,64,128,149,150,151,192,255})do
 check('automatic card contrast '..shape[1]..' '..shape[2]..' '..margin..' '..shade,function()
  settings:saveSetting(S.ui_style,'cover');ui.bookinfo.getCoverImage=function()return solid(shade,shape[1],shape[2])end
  local scene,fields=render({ui_style='cover',card_width=.5,card_font=1,cover_background=margin,card_background='auto',measure_only=true})
  local cr,cover=scene.card_rect,scene.cover_rect
  -- Uniform full cover around the card must dominate unless a side falls in margins.
  if cover.x<cr.x and cover.y<cr.y and cover.x+cover.w>cr.x+cr.w and cover.y+cover.h>cr.y+cr.h then
   assert(scene.card_background==(shade>=150 and 'black'or 'white'))
  end
  local bg=scene.card_background=='black'and 51 or 255
  for _,t in ipairs(fields)do assert(t.bgcolor:getColor8().a==bg and t.fgcolor:getColor8().a~=bg)end
  local bb=paint(scene);assert(bb:getPixel(cr.x+cr.w/2,cr.y+scene[1].padding/2):getColor8().a==bg)
  if shape[1]==160 and shape[2]==220 and margin=='white'and (shade==0 or shade==192)then
   bb:writePNG(output..'/auto-solid-'..(shade==0 and 'dark'or 'light')..'-'..Screen:getWidth()..'x'..Screen:getHeight()..'.png')
  end
  bb:free();scene:free()
 end)
 end
end end
for _,surround in ipairs({32,224})do
 check('automatic card ignores covered interior and distant edges '..surround,function()
  ui.bookinfo.getCoverImage=function()return solid(surround)end
  local probe=render({ui_style='cover',card_background='white',measure_only=true});local cr=probe.card_rect;probe:free()
  ui.bookinfo.getCoverImage=function()
   local b=solid(surround);b:paintRect(cr.x,cr.y,cr.w,cr.h,BB.Color8(255-surround))
   b:paintRect(0,0,Screen:getWidth(),12,BB.Color8(255-surround));return b
  end
  local scene=render({ui_style='cover',card_background='auto',measure_only=true})
  assert(scene.card_background==(surround>=150 and 'black'or 'white'))
  paint(scene,'auto-card-'..surround):free();scene:free()
 end)
end
for _,manual in ipairs({'white','black'})do
 check('manual '..manual..' skips detection and preserves cover pixels and rounded corners',function()
  local detector=ink.cardBackground;ink.cardBackground=function()error('manual must skip detection')end
  ui.bookinfo.getCoverImage=function()return solid(180)end
  local ok,scene=pcall(render,{ui_style='cover',card_background=manual,measure_only=true});ink.cardBackground=detector;assert(ok,scene)
  local bb=paint(scene,'manual-card-'..manual);local cr=scene.card_rect
  assert(scene.card_background==manual and bb:getPixel(cr.x,cr.y):getColor8().a==180)
  local expected=manual=='black'and 51 or 255
  assert(scene[1].background:getColor8().a==expected and bb:getPixel(cr.x+cr.w/2,cr.y+scene[1].padding/2):getColor8().a==expected)
  assert(bb:getPixel(0,0):getColor8().a==180)
  bb:free();scene:free()
 end)
end
check('missing cover uses visible margin colour for detection without inventing a cover',function()
 ui.bookinfo.getCoverImage=function()return nil end
 for _,margin in ipairs({'white','black'})do
  local scene=render({ui_style='cover',cover_background=margin,card_background='auto',measure_only=true})
  assert(scene.cover_missing and scene.card_background==(margin=='white'and 'black'or 'white'));scene:free()
 end
end)
check('invalid card palette is rejected',function()
 assert(not pcall(api.render,ui,ui.view.state,{ui_style='cover',card_background='invalid'}))
end)
check('black card adapts summaries, optional values and progress together',function()
 settings:saveSetting(S.stats,true);settings:saveSetting(S.summary,{'global_today','global_total'})
 settings:saveSetting(S.word_book,true);settings:saveSetting(S.remain,true)
 ui.bookinfo.getCoverImage=function()return solid(224)end
 local scene,fields=render({ui_style='cover',card_background='auto',measure_only=true})
 assert(scene.card_background=='black'and find(fields,'今日阅读')and find(fields,'预计剩余'))
 for _,t in ipairs(fields)do assert(t.bgcolor:getColor8().a==51 and t.fgcolor:getColor8().a>=192)end
 local progress
 walk(scene[1],function(w)if w.percentage and w.fillcolor then progress=w end end)
 assert(progress and progress.fillcolor:getColor8().a==255 and progress.bgcolor:getColor8().a<128)
 paint(scene,'black-all-content'):free();scene:free()
 settings:saveSetting(S.stats,false);settings:saveSetting(S.word_book,false);settings:saveSetting(S.remain,false)
end)
local TouchMenu=require('ui/widget/touchmenu');local Center=require('ui/widget/container/centercontainer')
for _,style in ipairs({'classic','pixel','swiss','cover'})do for depth=0,2 do
 check(style..' outside gesture closes all menu levels and native launcher '..depth,function()
  settings:saveSetting(S.ui_style,style)
  local entries={};api.launcher:addToMainMenu(entries)
  local host=Center:new{dimen=Screen:getSize(),ignore='height'}
  host[1]=TouchMenu:new{width=Screen:getWidth(),tab_item_table={{text='工具',icon='appbar.tools',entries.read_receipt}},show_parent=host}
  UI:show(host);host[1]:onMenuSelect(entries.read_receipt)
  assert(not onStack(host),'native launcher must close when InkFolio settings open')
  local container=UI._window_stack[#UI._window_stack].widget;local menu=container[1]
  for level=1,depth do menu:onMenuSelect(menu.item_table[level==1 and 2 or 1])end
  assert(#menu.item_table_stack==depth);paint(container):free()
  local r=menu.dimen
  assert(r.h<Screen:getHeight(),'test requires visible outside area')
  local y=r.y+r.h<Screen:getHeight()and Screen:getHeight()-1 or 0
  assert(tap(container,Screen:getWidth()/2,y),'closing tap must be consumed')
  assert(not onStack(container)and menu.inkfolio_closed and not onStack(host))
 end)
end end
check('tapping inside menu does not dismiss it; Back still returns one level',function()
 ink.settings();local container=UI._window_stack[#UI._window_stack].widget;local menu=container[1]
 menu:onMenuSelect(menu.item_table[2]);menu:onMenuSelect(menu.item_table[1]);paint(container):free()
 assert(#menu.item_table_stack==2);menu:onBack();assert(#menu.item_table_stack==1 and onStack(container))
 local r=menu.dimen;assert(not menu:onTapCloseAllMenus(nil,{pos=Geom:new{x=r.x+r.w/2,y=r.y+2,w=0,h=0}}));assert(onStack(container))
 UI:close(container)
end)
for depth=0,2 do
 check('key-device menu outside gesture closes all levels '..depth,function()
  local touch,dpad=Device.isTouchDevice,Device.hasDPad
  Device.isTouchDevice=function()return false end;Device.hasDPad=function()return false end
  local ok,e=pcall(ink.settings);Device.isTouchDevice=touch;Device.hasDPad=dpad;assert(ok,e)
  local container=UI._window_stack[#UI._window_stack].widget;local menu=container[1]
  for level=1,depth do menu:onMenuSelect(menu.item_table[level==1 and 2 or 1])end
  paint(container):free();assert(#menu.item_table_stack==depth)
  local r=menu.dimen;local y=r.y+r.h<Screen:getHeight()and Screen:getHeight()-1 or 0
  assert(tap(container,Screen:getWidth()/2,y)and not onStack(container))
 end)
end
print('INTERACTIONS_PASS '..passed..' / FAIL '..failed);os.exit(failed==0 and 0 or 1)


