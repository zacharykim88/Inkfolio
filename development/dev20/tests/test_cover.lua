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
 summary=summaryItems,cache=CACHE,key=bookKey,stars=scoreStars,run=RUN,store=store,background=receiptBackground,progress=PixelProgress,paper=ReceiptPaper,editor=AppearanceEditor,weather=WEATHER}
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


local Font=require('ui/font');local Reader=require('apps/reader/readerui')
local output=os.getenv('INK_OUTPUT')or root..'checks'
local function same(t)return require('dump')(t,nil,true)end
local function select()
 settings:saveSetting(S.ui_style,'cover');settings:delSetting(S.cover_weather);settings:delSetting(S.card_width);settings:saveSetting(S.card_font,1)
 settings:saveSetting(S.cover_background,'white');settings:saveSetting(S.date,true)
 settings:saveSetting(S.weather,true);settings:saveSetting(S.weather_tomorrow,false)
end
local function picture(w,h)
 local bb=BB.new(w,h,BB.TYPE_BB8);bb:fill(BB.COLOR_GRAY_5)
 bb:paintRect(0,0,math.floor(w*.35),h,BB.COLOR_BLACK)
 bb:paintRect(math.floor(w*.55),math.floor(h*.10),math.floor(w*.35),math.floor(h*.45),BB.COLOR_GRAY_9)
 return bb
end
ui.bookinfo={getCoverImage=function()return picture(160,220)end}
select()
check('cover is a fourth skin and uses an independent fifty-percent default card',function()
 assert(#ink.UI_STYLES==5 and ink.UI_STYLES[4].id=='cover')
 local scene,_,size=render();assert(scene.card_rect.w==math.floor(Screen:getWidth()*.5))
 assert(scene.card_rect.x==math.floor((Screen:getWidth()-scene.card_rect.w)/2))
 assert(scene.card_rect.y==math.floor((Screen:getHeight()-scene.card_rect.h)/2))
 assert(scene:getSize().w==Screen:getWidth()and scene:getSize().h==Screen:getHeight());scene:free()
end)
check('fixed content remains present when all optional modules are disabled',function()
 for _,key in ipairs({S.word_book,S.word_session,S.remain,S.stats,S.date,S.weather,S.weather_tomorrow})do settings:saveSetting(key,false)end
 local scene,fields=render();assert(find(fields,ui.doc_props.title)and find(fields,ui.doc_props.authors))
 assert(find(fields,'23%')and find(fields,'23 / 100 页')and find(fields,'第十二章：在轨道上继续探索'))
 assert(not find(fields,'估算已读')and not find(fields,'阅读摘要')and not find(fields,'今日阅读'))
 scene:free()
end)
check('missing author and chapter are explicit',function()
 local author,toc=ui.doc_props.authors,ui.toc;ui.doc_props.authors='';ui.toc=nil
 local scene,fields=render();assert(find(fields,'未提供作者')and find(fields,'暂无章节信息'));scene:free()
 ui.doc_props.authors=author;ui.toc=toc
end)
for _,shape in ipairs({{160,220},{300,100},{100,400}})do
 for _,bg in ipairs({'white','black'})do
  check('cover fit preserves aspect '..shape[1]..'x'..shape[2]..' '..bg,function()
   select();settings:saveSetting(S.cover,false);settings:saveSetting(S.background,'transparent');settings:saveSetting(S.cover_background,bg)
   ui.bookinfo.getCoverImage=function()return picture(shape[1],shape[2])end
   local before=same(settings.data);local scene=render();local p=scene.cover_rect;assert(p and p.x>=0 and p.y>=0)
   assert(p.x+p.w<=Screen:getWidth()and p.y+p.h<=Screen:getHeight())
   assert(math.abs(p.w*shape[2]-p.h*shape[1])<=math.max(shape[1],shape[2]))
   assert(p.w>=Screen:getWidth()-1 or p.h>=Screen:getHeight()-1)
   local bb=BB.new(Screen:getWidth(),Screen:getHeight(),BB.TYPE_BB8);bb:fill(BB.COLOR_WHITE);scene:paintTo(bb,0,0)
   if p.x>0 or p.y>0 then assert(bb:getPixel(0,0):getColor8().a==(bg=='black'and 0 or 255))end
   assert(same(settings.data)==before);bb:free();scene:free()
  end)
 end
end
check('missing cover is visibly identified with the chosen background',function()
 select();ui.bookinfo.getCoverImage=function()return nil end
 local scene=render();assert(scene.cover_missing and scene[2].text=='封面不可用'and not scene.cover_rect);scene:free()
end)
check('unexpected cover read failure is reported instead of being hidden',function()
 ui.bookinfo.getCoverImage=function()error('test cover access failure')end
 local ok,err=pcall(api.render,ui,ui.view.state,{card_width=.6,card_font=1,measure_only=true})
 assert(not ok and tostring(err):find('test cover access failure',1,true))
end)
ui.bookinfo.getCoverImage=function()return picture(160,220)end
local choices={{},{S.word_book},{S.word_session},{S.remain},{S.word_book,S.word_session},{S.word_book,S.remain},{S.word_session,S.remain}}
for _,choice in ipairs(choices)do for _,summary in ipairs({{}, {'global_today'},{'global_today','global_total'}})do
 for _,weather in ipairs({{false,false},{true,false},{false,true},{true,true}})do
  check('card modules '..#choice..' '..#summary..' '..tostring(weather[1])..tostring(weather[2]),function()
   select();settings:saveSetting(S.stats,#summary>0);settings:saveSetting(S.summary,summary)
   for _,key in ipairs({S.word_book,S.word_session,S.remain})do settings:saveSetting(key,false)end
   for _,key in ipairs(choice)do settings:saveSetting(key,true)end
   settings:saveSetting(S.weather,weather[1]);settings:saveSetting(S.weather_tomorrow,weather[2])
   local scene,fields,size=render();local cr=scene.card_rect;local positions={};local paint=Text.paintTo
   Text.paintTo=function(self,bb,x,y)positions[self]={x=x,y=y};return paint(self,bb,x,y)end
   local bb=BB.new(Screen:getWidth(),Screen:getHeight(),BB.TYPE_BB8);bb:fill(BB.COLOR_WHITE);scene:paintTo(bb,0,0);Text.paintTo=paint
   assert(cr.y>=0 and cr.y+cr.h<=Screen:getHeight())
   for _,t in ipairs(fields)do if positions[t]then
    assert(not t.height_overflow_show_ellipsis)
    assert(positions[t].x>=cr.x and positions[t].x+t.width<=cr.x+cr.w)
    assert(positions[t].y>=cr.y and positions[t].y+t:getSize().h<=cr.y+cr.h)
   end end
   for _,item in ipairs({{S.word_book,'估算已读'},{S.word_session,'本次唤醒'},{S.remain,'预计剩余'}})do
    assert((find(fields,item[2])~=nil)==ink.progressEnabled(item[1]))
   end
   if #summary>0 then assert(find(fields,'今日阅读'))end
   bb:free();scene:free()
   local full,valid=api.build(ui,ui.view.state,{ui_style='cover',card_width=.6,card_font=1,cover_background='white'});assert(valid);full:free()
  end)
 end
end end
for _,width in ipairs({.4,.6,.85})do for _,font in ipairs({.8,1,1.2})do
 check('card appearance grid '..width..' '..font,function()
  select();local scene,fields,size=render({ui_style='cover',card_width=width,card_font=font,cover_background='black',measure_only=true})
  assert(scene.card_rect.w==math.floor(Screen:getWidth()*width))
  local full,valid=api.build(ui,ui.view.state,{ui_style='cover',card_width=width,card_font=font,cover_background='black'})
  if scene.card_rect.h>Screen:getHeight()-math.max(1,math.floor(24*math.floor(Screen:getWidth()*width)/720+.5))then assert(not valid)else assert(valid)end
  scene:free();full:free()
 end)
end end
check('summary columns align when their headings wrap differently',function()
 select();settings:saveSetting(S.stats,true);settings:saveSetting(S.summary,{'global_today','global_total'})
 local scene,fields=render({ui_style='cover',card_width=.4,card_font=1.2,measure_only=true})
 local native=Text.paintTo;local pos={};Text.paintTo=function(self,bb,x,y)pos[self]={y=y,baseline=y+self:getBaseline()};return native(self,bb,x,y)end
 local bb=BB.new(Screen:getWidth(),math.max(Screen:getHeight(),scene.card_rect.h),BB.TYPE_BB8);bb:fill(BB.COLOR_WHITE)
 scene[1]:paintTo(bb,0,0);Text.paintTo=native
 local a,b=find(fields,'1分钟'),find(fields,'3时10分');assert(a and b and pos[a].baseline==pos[b].baseline)
 bb:free();scene:free()
end)
check('overlong content produces an explicit invalid preview without hiding text',function()
 select();local title=ui.doc_props.title;ui.doc_props.title=string.rep('超长书名完整保留',100)
 local scene,fields=render();assert(find(fields,ui.doc_props.title)and scene.card_rect.h>Screen:getHeight());scene:free()
 local full,valid=api.build(ui,ui.view.state,{ui_style='cover',card_width=.6,card_font=1});assert(not valid);full:free();ui.doc_props.title=title
end)
check('cover appearance cancel and save do not modify ticket appearance',function()
 select();settings:saveSetting(S.ui_style,'classic');settings:saveSetting(S.width,.84);settings:saveSetting(S.font,1.1);settings:saveSetting(S.scale,.65);settings:saveSetting(S.background,'transparent')
 local before=same(settings.data);local editor=api.editor:new{ui=ui};UI:show(editor);assert(editor:selectStyle('cover'))
 assert(editor.draft.card_width==.5 and editor.valid);editor:change('cover_background','black');editor:refreshPreview();editor:onCancel();assert(same(settings.data)==before)
 editor=api.editor:new{ui=ui};UI:show(editor);assert(editor:selectStyle('cover'));editor:change('card_width',.65);editor:change('cover_background','black');editor:refreshPreview();assert(editor.valid);editor:save()
 assert(ink.uiStyle().id=='cover'and settings:readSetting(S.card_width)==.65 and settings:readSetting(S.cover_background)=='black')
 assert(settings:readSetting(S.width)==.84 and settings:readSetting(S.font)==1.1 and settings:readSetting(S.scale)==.65 and settings:readSetting(S.background)=='transparent')
end)
check('cover numeric controls and black-white background choices fit the screen',function()
 select();local editor=api.editor:new{ui=ui};UI:show(editor);assert(editor.valid)
 local controls=editor.controls;assert(#controls.buttons==6 and #controls.buttons[1]==6 and #controls.buttons[4]==3 and #controls.buttons[5]==4)
 assert(controls.buttons[2][2].text:find('50%',1,true)and controls.buttons[3][2].text:find('100%',1,true))
 editor:onCancel()
end)
check('cover screenshot and lockscreen share the full-screen renderer',function()
 select();settings:saveSetting(S.stats,false);Reader.instance=ui
 settings:saveSetting('screenshot_dir',os.getenv('KO_HOME')..'/screenshots')
 local shown,close=UI.show,UI.close;local widgets={};UI.show=function(_,w)widgets[#widgets+1]=w end
 local ok,err=pcall(ink.saveScreenshot);UI.show=shown;UI.close=close;assert(ok,err)
 local lfs=require('libs/libkoreader-lfs');local found=false;for n in lfs.dir(os.getenv('KO_HOME')..'/screenshots')do if n:match('^Inkfolio_.*%.png$')then found=true end end;assert(found)
 for _,w in ipairs(widgets)do w:free()end
 local supports=Device.supportsScreensaver;Device.supportsScreensaver=function()return true end
 local saver=require('ui/screensaver');local ss={screensaver_type='book_receipt',prefix='',ui=ui};saver.show(ss)
 assert(ss.screensaver_widget and ss.screensaver_widget.widget and ss.screensaver_widget.widget.card_rect)
 UI:close(ss.screensaver_widget);Device.supportsScreensaver=supports
end)
local function menuRows()return api.menu().sub_item_table end
check('cover disables unsupported menus and their actions without changing saved settings',function()
 select();settings:saveSetting(S.intro,true);settings:saveSetting(S.stats,true)
 local rows=menuRows();local content=rows[2].sub_item_table
 local targets={content[2],content[4].sub_item_table[4],content[5],content[6],rows[3]}
 local before=same(settings.data)
 local function disabled(item)
  assert(item.enabled_func and item.enabled_func()==false,item.text)
  if item.callback then item.callback()end
  for _,child in ipairs(item.sub_item_table or {})do disabled(child)end
 end
 for _,item in ipairs(targets)do disabled(item)end
 assert(same(settings.data)==before)
 assert(content[1].sub_item_table[1].checked_func() and not content[1].sub_item_table[2].checked_func())
 assert(not content[3].enabled_func and not content[4].enabled_func)
 for _,style in ipairs({'classic','pixel','swiss'})do
  settings:saveSetting(S.ui_style,style)
  for _,item in ipairs(targets)do assert(item.enabled_func(),style..' '..item.text)end
 end
 settings:saveSetting(S.ui_style,'cover');assert(same(settings.data)==before)
end)
check('cover weather remains exclusive, optional and independent of paper choices',function()
 select();settings:saveSetting(S.weather,true);settings:saveSetting(S.weather_tomorrow,true)
 local rows=menuRows()[2].sub_item_table[1].sub_item_table
 assert(rows[1].checked_func()and not rows[2].checked_func())
 rows[2].callback();assert(not rows[1].checked_func()and rows[2].checked_func())
 assert(settings:readSetting(S.cover_weather)=='tomorrow'and settings:readSetting(S.weather)and settings:readSetting(S.weather_tomorrow))
 rows[1].callback();assert(rows[1].checked_func()and not rows[2].checked_func())
 rows[1].callback();assert(not ink.weatherEnabled()and settings:readSetting(S.cover_weather)=='off')
 settings:saveSetting(S.ui_style,'swiss');assert(ink.weatherSelected(0)and ink.weatherSelected(1))
 settings:saveSetting(S.ui_style,'cover');assert(not ink.weatherEnabled())
 rows[2].callback();assert(ink.weatherSelected(1)and not ink.weatherSelected(0))
end)
check('cover selection rejects corrupt values and derives the initial choice without writing',function()
 select();settings:saveSetting(S.weather,false);settings:saveSetting(S.weather_tomorrow,true)
 local before=same(settings.data);assert(ink.coverWeather()=='tomorrow'and same(settings.data)==before)
 settings:saveSetting(S.weather_tomorrow,false);assert(ink.coverWeather()=='off')
 settings:saveSetting(S.cover_weather,'invalid');assert(not pcall(ink.coverWeather));settings:delSetting(S.cover_weather)
end)
check('appearance drafts use the preview skin weather rules',function()
 select();settings:saveSetting(S.weather,true);settings:saveSetting(S.weather_tomorrow,true);settings:saveSetting(S.cover_weather,'off')
 -- A cover draft must use its own choice even while a paper skin is active.
 settings:saveSetting(S.ui_style,'swiss')
 local scene,fields=render({ui_style='cover',measure_only=true})
 for _,t in ipairs(fields)do assert(not t.text:find('苏州',1,true))end;scene:free()
 settings:saveSetting(S.ui_style,'cover')
 scene,fields=render({ui_style='swiss',width=.84,font=1,scale=.6,measure_only=true})
 local found=0;for _,t in ipairs(fields)do if t.text:find('待联网更新',1,true)then found=found+1 end end
 assert(found==2);scene:free()
end)
for _,width in ipairs({.4,.5,.85})do for _,font in ipairs({.8,1.2})do
 for _,choice in ipairs({'off','today','tomorrow'})do for _,date in ipairs({false,true})do
 for _,status in ipairs({'晴 12～23°C','天气获取失败','雷阵雨转大到暴雨 -12～-3°C'})do
 check('cover weather-date row '..width..' '..font..' '..choice..' '..tostring(date)..' '..status,function()
  select();settings:saveSetting(S.stats,false);settings:saveSetting(S.word_book,false);settings:saveSetting(S.word_session,false);settings:saveSetting(S.remain,false)
  settings:saveSetting(S.date,date);settings:saveSetting(S.cover_weather,choice)
  api.weather.error=nil;api.weather.records.lqYjK={day=os.date('%Y-%m-%d'),forecasts={[os.date('%Y-%m-%d')]=status,[ink.weatherDate(1)]=status}}
  local scene,fields=render({ui_style='cover',card_width=width,card_font=font,measure_only=true})
  local native=Text.paintTo;local pos={};Text.paintTo=function(self,bb,x,y)pos[self]={x=x,y=y,baseline=y+self:getBaseline()};return native(self,bb,x,y)end
  local bb=BB.new(Screen:getWidth(),Screen:getHeight(),BB.TYPE_BB8);bb:fill(BB.COLOR_WHITE);scene:paintTo(bb,0,0);Text.paintTo=native
  local d=find(fields,os.date('%Y.%m.%d'));local weather
  for _,t in ipairs(fields)do if t.text:find('苏州',1,true)then assert(not weather);weather=t end end
  assert((d~=nil)==date and (weather~=nil)==(choice~='off'))
  local left,right
  if weather then
   assert(weather.alignment=='left'and weather.text:find(choice=='today'and '今日'or '明日',1,true))
   left=pos[weather].x;assert(left==scene.card_rect.x+scene[1].padding+scene[1].bordersize)
  end
  if d then
   assert(d.alignment=='right'and not d.height_overflow_show_ellipsis and d:getAllLineCount()==1)
   right=pos[d].x+d.width;assert(right==scene.card_rect.x+scene.card_rect.w-scene[1].padding-scene[1].bordersize)
  end
  if d and weather then assert(pos[d].baseline==pos[weather].baseline and pos[weather].x+weather.width<pos[d].x)end
  for _,t in ipairs(fields)do if pos[t]then assert(pos[t].x>=scene.card_rect.x and pos[t].x+t.width<=scene.card_rect.x+scene.card_rect.w);assert(pos[t].y+t:getSize().h<=scene.card_rect.y+scene.card_rect.h)end end
  bb:free();scene:free()
 end)
 end end end
end end
check('native cover content settings reflect disabled controls',function()
 select();settings:saveSetting(S.stats,true)
 local show=UI.show;local container;UI.show=function(_,w)container=w end
 local ok,e=pcall(ink.settings);UI.show=show;assert(ok,e);local menu=container[1]
 menu:onMenuSelect(menu.item_table[2])
 local disabled,tapped=false,false
 walk(container,function(widget)
  if type(widget.text)=='string'and widget.text:find('图书与榜单',1,true)and widget.fgcolor then assert(widget.fgcolor:getColor8().a>0);disabled=true end
  if widget.item and widget.item.text=='图书与榜单'and widget.onTapSelect then
   local count=#menu.item_table_stack;widget:onTapSelect();assert(#menu.item_table_stack==count);tapped=true
  end
 end)
 assert(disabled and tapped,tostring(disabled)..' / '..tostring(tapped))
 local bb=BB.new(Screen:getWidth(),Screen:getHeight(),BB.TYPE_BB8);bb:fill(BB.COLOR_WHITE);container:paintTo(bb,0,0)
 bb:writePNG(output..'/cover-menu-'..Screen:getWidth()..'x'..Screen:getHeight()..'.png');bb:free();container:free()
end)
select();settings:saveSetting(S.word_book,false);settings:saveSetting(S.word_session,false);settings:saveSetting(S.remain,true)
settings:saveSetting(S.stats,true);settings:saveSetting(S.summary,{'global_today'});settings:saveSetting(S.cover_weather,'tomorrow')
check('native cover preview exported',function()
 local scene=render();local bb=BB.new(Screen:getWidth(),Screen:getHeight(),BB.TYPE_BB8);bb:fill(BB.COLOR_WHITE);scene:paintTo(bb,0,0)
 bb:writePNG(output..'/cover-'..Screen:getWidth()..'x'..Screen:getHeight()..'.png');bb:free();scene:free()
end)
print('COVER_PASS '..passed..' / FAIL '..failed);os.exit(failed==0 and 0 or 1)
