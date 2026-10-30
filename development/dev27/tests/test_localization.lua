require('setupkoenv');G_defaults=require('luadefaults'):open()
G_reader_settings=require('luasettings'):open(os.getenv('KO_HOME')..'/settings.reader.lua')
local settings=G_reader_settings
settings:saveSetting('read_receipt_v2_online',false)
settings:saveSetting('read_receipt_v2_language',os.getenv('INK_START_LANGUAGE')or 'zh_CN')
settings:flush()
G_reader_settings=require('luasettings'):open(settings.file);settings=G_reader_settings
local Device=require('device')
if os.getenv('INK_TOUCH_ONLY')=='1'then Device.hasDPad=function()return false end end
require('document/canvascontext'):init(Device)
local Screen=Device.screen;local BB=require('ffi/blitbuffer');local UI=require('ui/uimanager')
local root=assert(arg[0]:match('^(.*)/tests/[^/]+$'))
local source=assert(io.open(root..'/2-inkfolio.lua')):read('*a')
local api=assert(loadstring(source..[[
return {ink=Inkfolio,S=S,render=renderReceipt,build=buildReceipt,menu=receiptSettingsMenu,
 weather=WEATHER,weatherText=weatherText,parse=parseWeather,run=RUN,editor=AppearanceEditor,
 duration=duration,words=formatWordCount,summary=SUMMARY_ITEMS,themes=UI_THEMES,city=selectedWeatherCity,
 about=showAbout,store=store}
]]))()
local ink,S,W=api.ink,api.S,api.weather
local passed,failed=0,0
local function check(name,fn)local ok,e=pcall(fn);if ok then passed=passed+1;print('PASS',name)else failed=failed+1;print('FAIL',name,e)end end
local function english(text,where)
 assert(type(text)=='string',(where or '')..' not text')
 assert(not text:find('[\228-\233][\128-\191][\128-\191]'),(where or '')..' contains untranslated text: '..text)
end
local Text=require('ui/widget/textboxwidget')
local ui={document={file='english-layout.epub',getPageCount=function()return 358 end},
 doc_props={title='Flowers for Algernon',authors='Daniel Keyes',publisher='Mariner Books'},
 doc_settings={data={doc_pages=358}},view={state={page=123}},
 statistics={id_curr_book=1,isEnabled=function()return true end,insertDB=function()end,avg_time=45},
 toc={getTocTitleByPage=function()return 'Progress Report 9'end}}
require('apps/reader/readerui').instance=ui
ui.view.paintTo=function(self,bb,x,y)
 bb:fill(BB.COLOR_WHITE)
 local text=Text:new{text=string.rep('The morning light fell across the open book. She turned the page and kept reading.\n\n',12),face=require('ui/font'):getFace('NotoSerif-Regular.ttf',18),width=math.floor(Screen:getWidth()*.86),height=math.floor(Screen:getHeight()*.9),justified=false}
 text:paintTo(bb,math.floor(Screen:getWidth()*.07),math.floor(Screen:getHeight()*.06));text:free()
end
local now=os.time();local today=os.date('%Y-%m-%d')
local SQ=require('lua-ljsqlite3/init');local ds=require('datastorage')
local db=SQ.open(ds:getSettingsDir()..'/statistics.sqlite3')
db:exec('CREATE TABLE page_stat_data(id_book INTEGER,page INTEGER,start_time INTEGER,duration INTEGER);')
db:exec('CREATE VIEW page_stat AS SELECT * FROM page_stat_data;')
db:exec(string.format('INSERT INTO page_stat_data VALUES(1,123,%d,3600);',now-7200));db:close()
ui.bookinfo={getCoverImage=function()
 local bb=BB.new(600,800,BB.TYPE_BB8);bb:fill(BB.Color8(220))
 local t=Text:new{text='FLOWERS\nFOR\nALGERNON',face=require('ui/font'):getFace('NotoSans-Regular.ttf',48*600/Screen:scaleBySize(600)),bold=true,width=520,alignment='center',justified=false}
 t:paintTo(bb,40,80);t:free();return bb
end}
settings:saveSetting(S.auto_fit,false);settings:saveSetting(S.intro,false)
settings:saveSetting(S.cover,true);settings:saveSetting(S.stats,true)
settings:saveSetting(S.summary,{'global_today','global_total'});settings:saveSetting(S.summary_metric,'words')
settings:saveSetting(S.word_book,true);settings:saveSetting(S.word_session,true);settings:saveSetting(S.remain,false)
ink.estimatedWords=function()return 123456 end;ink.wakeWords=function()return 6789 end
W.records.lqYjK={day=today,forecasts={[today]='晴 12～23°C',[ink.weatherDate(1)]='雷阵雨 9～21°C'},updated_at=now};W.error=nil
local function canvas(widget,path,keep)
 local bb=BB.new(Screen:getWidth(),Screen:getHeight(),BB.TYPE_BB8);bb:fill(BB.COLOR_WHITE);widget:paintTo(bb,0,0)
 if path then bb:writePNG((os.getenv('INK_OUTPUT')or root..'/checks')..'/'..path..'-'..Screen:getWidth()..'x'..Screen:getHeight()..'.png')end
 bb:free();if not keep then widget:free()end
end
local function capture(fn)
 local show=UI.show;local result;UI.show=function(_,w)result=w end
 local ok,e=pcall(fn);UI.show=show;assert(ok,e);assert(result,'no dialog');return result
end
check('four localized skins exclude the retired reading-page skin',function()assert(#ink.UI_STYLES==4 and not api.themes.paper)end)
check('defaults keep weather text and independent language',function()assert(ink.weatherDisplay()=='text'and settings:readSetting('language')==nil)end)
check('weather and date settings use the same position-neutral label in all styles and both languages',function()
 for _,language in ipairs({'zh_CN','en_US'})do
  ink.selectLanguage(language)
  for _,style in ipairs({'classic','pixel','swiss','cover'})do
   settings:saveSetting(S.ui_style,style)
   local item=api.menu().sub_item_table[2].sub_item_table[1]
   assert(item.text==(language=='en_US'and 'Weather & Date'or '天气与日期'))
   assert(item.help_text:find(language=='en_US'and 'bottom of Cover cards'or '卡片底部',1,true))
   assert(#item.sub_item_table==5)
  end
 end
 settings:delSetting(S.ui_style);ink.selectLanguage('zh_CN')
end)
check('source and parser tokens survive locale changes',function()
 local raw=assert(io.open(root..'/tests/fixtures/nmc-suzhou.json')):read('*a');local chinese=api.parse(raw,'lqYjK','2026-10-25')
 ink.selectLanguage('en_US');assert(api.parse(raw,'lqYjK','2026-10-25')==chinese)
 assert(api.city().name=='苏州市'and ink.monthlyCategory().source=='全部')
end)
check('labels switch immediately and restore Chinese exactly',function()
 ink.selectLanguage('en_US');assert(ink.UI_STYLES[1].label=='Receipt'and api.themes.cover.label=='Cover')
 assert(api.summary[2].label=='Today'and ink.GOAL_PERIODS[2].title=='This Week')
 ink.selectLanguage('zh_CN');assert(ink.UI_STYLES[1].label=='小票'and api.summary[2].label=='今日阅读');ink.selectLanguage('en_US')
end)
check('English units and US date order',function()
 assert(ink.pagePosition(1,1)=='1 / 1 page');assert(ink.translate('')=='')
 assert(api.duration(7380)=='2h 3m'and api.duration(60)=='1 min')
 assert(api.words(1)=='1 word'and api.words(180)=='180 words'and api.words(25000)=='25k words')
 assert(ink.displayDate(os.time{year=2026,month=10,day=28,hour=12})=='Oct 28, 2026')
end)
check('English goal input uses thousands and keeps stored target',function()
 local amount=assert(ink.parseGoalTarget('25','words'));assert(amount==25000 and not ink.parseGoalTarget('2.5','words'))
 ink.setGoal('metric','words');ink.setGoal('target',amount);assert(ink.goalTargetText()=='25k words')
 ink.selectLanguage('zh_CN');assert(ink.goalTargetText()=='2.5万字');ink.selectLanguage('en_US');assert(ink.goalConfig().values.day_words==25000)
end)
check('English menus and help contain no untranslated UI',function()
 local function scan(rows)for _,r in ipairs(rows)do
  if r.text and r.text~='简体中文'then english(r.text,'menu')end
  if r.help_text then english(r.help_text,'help')end
  if r.text_func then english(r.text_func(),'dynamic menu')end
  if r.sub_item_table then scan(r.sub_item_table)end
 end end
 scan(api.menu().sub_item_table)
end)
check('locations have English display names and stable station identities',function()
 local rows=api.menu().sub_item_table[2].sub_item_table[1].sub_item_table[4].sub_item_table;local n=0
 for _,r in ipairs(rows)do english(r.text,'region');for _,c in ipairs(r.sub_item_table or {})do english(c.text,'city');n=n+1 end end
 assert(n>330 and ink.cityLabel(api.city())=='Suzhou')
end)
check('English forecasts reuse raw cache without refetching',function()
 assert(api.weatherText():find('Suzhou',1,true)and api.weatherText():find('Clear 12–23°C',1,true))
 assert(api.weatherText(1,false)=='Tomorrow Thunderstorms 9–21°C')
 assert(ink.forecastDisplay('未知状态 9～12°C')=='未知状态 9–12°C'and W.records.lqYjK.forecasts[today]=='晴 12～23°C')
end)
check('unknown and mixed conditions retain text',function()
 assert(not ink.weatherCondition('未知状态'));local id,name=ink.weatherCondition('晴转雨');assert(not id and name=='Clear → Rain')
end)
check('every mapped condition renders vector art in both palettes',function()
 local n=0;for state,pair in pairs(ink.WEATHER_CONDITIONS)do
  local id,name=ink.weatherCondition(state);assert(id==pair[1]and ink.WEATHER_ART[id]);english(name,'condition');n=n+1
  local icon=ink.WeatherIcon:new{condition=id,size=24};local bb=BB.new(24,24,BB.TYPE_BB8);bb:fill(BB.COLOR_WHITE);icon:paintTo(bb,0,0)
  local count=0;for y=0,23 do for x=0,23 do if bb:getPixel(x,y):getColor8().a<200 then count=count+1 end end end
  assert(count>5 and count<450,state);icon:setDark();icon:paintTo(bb,0,0);assert(bb:getPixel(0,0):getColor8().a==51,state);icon:free();bb:free()
 end;assert(n>=45)
end)
check('About and release notes use complete English prose',function()
 for _,fn in ipairs({api.about,ink.showChangelog})do local w=capture(fn);english(w.title,'about title');english(w.text,'about body');w:free()end
end)
check('statistics help, diagnostics and source status are English',function()
 english(ink.statisticsText(),'statistics help');english(ink.diagnosticText(false):gsub('香萃打字机体','Xiangcui Typewriter'),'diagnostics');english(ink.informationText(ui),'sources')
end)
check('weather display choice persists without changing date selection',function()
 local row=api.menu().sub_item_table[2].sub_item_table[1].sub_item_table[5];assert(row.text=='Weather Display')
 local before=settings:readSetting(S.weather_tomorrow);row.sub_item_table[2].callback();assert(ink.weatherDisplay()=='icons'and settings:readSetting(S.weather_tomorrow)==before)
 row.sub_item_table[1].callback();assert(ink.weatherDisplay()=='text')
end)
for _,style in ipairs({'classic','pixel','swiss','cover'})do for _,mode in ipairs({'text','icons'})do for _,both in ipairs({false,true})do
 if style~='cover'or not both then check('native English '..style..' '..mode..' '..tostring(both),function()
  settings:saveSetting(S.ui_style,style);settings:saveSetting(S.weather_display,mode);settings:saveSetting(S.weather_tomorrow,both);settings:saveSetting(S.charts,{})
  local fields={};local old=Text.new;Text.new=function(self,args)if args.text then fields[#fields+1]=args.text end;return old(self,args)end
  local ok,w,valid=pcall(api.render,ui,ui.view.state,{ui_style=style,width=.84,font=1,scale=.70,background='white',card_width=.65,card_background='white'})
  Text.new=old;assert(ok,w);assert(valid,style..' failed to fit');for _,text in ipairs(fields)do english(text,'render')end
  canvas(w,'english-'..style..'-'..mode..(both and '-two-days'or ''))
 end)end
end end end
check('English appearance controls render',function()
 settings:saveSetting(S.ui_style,'cover');settings:saveSetting(S.card_width,.5);local e=api.editor:new{ui=ui};assert(e.valid);canvas(e,'english-editor')
end)

check('icons scale the complete artwork at small and large sizes',function()
 for _,size in ipairs({10,16,32,64})do
  local icon=ink.WeatherIcon:new{condition='sun',size=size};local bb=BB.new(size,size,BB.TYPE_BB8);bb:fill(BB.COLOR_WHITE);icon:paintTo(bb,0,0)
  assert(icon.image:getWidth()==size and icon.image:getHeight()==size)
  local quadrants={0,0,0,0}
  for y=0,size-1 do for x=0,size-1 do if bb:getPixel(x,y):getColor8().a<220 then
   local q=(y<size/2 and 0 or 2)+(x<size/2 and 1 or 2);quadrants[q]=quadrants[q]+1
  end end end
  for _,v in ipairs(quadrants)do assert(v>0,'cropped sun at '..size)end;icon:free();bb:free()
 end
end)
check('valid cached forecast icons survive refreshes and failures in both languages',function()
 settings:saveSetting(S.weather_display,'icons')
 local function txt(text,role,width,align)return Text:new{text=text,face=require('ui/font'):getFace('NotoSans-Regular.ttf',14),width=width,alignment=align or 'left',justified=false}end
 local record=W.records.lqYjK
 for _,language in ipairs({'zh_CN','en_US'})do
  ink.selectLanguage(language)
  api.run.worker={kind='weather',city='lqYjK'}
  local w=ink.weatherWidget(0,true,txt,250,'left',20);assert(w.inkfolio_weather);w:free();api.run.worker=nil
  W.error='天气获取失败';W.attempt_city='lqYjK';W.attempt_day=today
  w=ink.weatherWidget(0,true,txt,250,'left',20);assert(w.inkfolio_weather);w:free()
  W.records.lqYjK=nil
  w=ink.weatherWidget(0,true,txt,250,'left',20);assert(not w.inkfolio_weather and w.text:find(language=='en_US'and 'Weather unavailable'or '天气获取失败',1,true));w:free()
  W.error=nil;api.run.worker={kind='weather',city='lqYjK'}
  w=ink.weatherWidget(0,true,txt,250,'left',20);assert(not w.inkfolio_weather and w.text:find(language=='en_US'and 'Updating'or '获取中',1,true));w:free()
  api.run.worker=nil;W.records.lqYjK=record
 end
 W.error=nil;W.attempt_city=nil;W.attempt_day=nil;ink.selectLanguage('en_US')
end)
check('native dialogs keep English buttons with KOReader set to Chinese',function()
 local gettext=require('gettext');gettext.changeLang('zh_CN')
 local w=capture(api.about);local close=false
 for _,row in ipairs(w.button_table.buttons_layout)do for _,button in ipairs(row)do if button.text=='Close'then close=true end;assert(button.text~='关闭'and button.text~='查找');if button.id=='find'then assert(button.text=='Find')end end end
 assert(close);w:free();gettext.changeLang('C')
end)
check('stored Chinese status messages are translated on display',function()
 local old=ink.monthly.error;local result=ink.monthly.result
 ink.monthly.error='月榜月份或分类标识不匹配，可能受到访问限制';ink.monthly.result='failed'
 english(ink.informationText(ui),'stored status');ink.monthly.error=old;ink.monthly.result=result
end)
check('text entered by users and book metadata stay unchanged',function()
 local original=ui.doc_props.title;ui.doc_props.title='中文书名'
 settings:saveSetting(S.footer,'自定义文字');settings:saveSetting(S.ui_style,'swiss');settings:saveSetting(S.weather_display,'icons')
 local fields={};local old=Text.new;Text.new=function(self,args)if args.text then fields[args.text]=true end;return old(self,args)end
 local ok,w,valid=pcall(api.render,ui,ui.view.state,{width=.84,font=1,scale=.7,background='white'})
 Text.new=old;assert(ok,w);assert(valid and fields['中文书名']and fields['自定义文字']);w:free();ui.doc_props.title=original;settings:delSetting(S.footer)
end)
check('skin colors and English target survive language changes on disk',function()
 settings:saveSetting(S.card_background,'black');settings:saveSetting(S.background,'transparent')
 settings:saveSetting(S.weather_display,'icons');ink.selectLanguage('zh_CN');ink.selectLanguage('en_US')
 local saved=dofile(settings.file);assert(saved[S.language]=='en_US'and saved[S.card_background]=='black'and saved[S.background]=='transparent'and saved[S.weather_display]=='icons')
end)
check('native English cover fits minimum width and largest font',function()
 settings:saveSetting(S.ui_style,'cover');settings:saveSetting(S.weather_tomorrow,false)
 for _,color in ipairs({'white','black'})do
  local w,valid=api.render(ui,ui.view.state,{ui_style='cover',card_width=.4,card_font=1.2,card_background=color})
  assert(valid);canvas(w,'english-cover-minimum-'..color)
 end
 settings:saveSetting(S.card_background,'auto')
end)
check('native Chinese icons render with unchanged D19 labels',function()
 ink.selectLanguage('zh_CN');settings:saveSetting(S.ui_style,'cover');settings:saveSetting(S.weather_display,'icons')
 local w,valid=api.render(ui,ui.view.state,{ui_style='cover',card_width=.5,card_background='black'});assert(valid);canvas(w,'chinese-cover-icons')
 ink.selectLanguage('en_US')
end)
check('weather icon atlas uses native renderer in both palettes',function()
 local bb=BB.new(720,430,BB.TYPE_BB8);bb:fill(BB.COLOR_WHITE)
 local ids={'sun','partly_cloudy','cloud','showers','rain','thunder','snow','sleet','hail','fog','haze','dust'}
 for i,id in ipairs(ids)do
  local col=(i-1)%6;local row=math.floor((i-1)/6);local x=col*120;local y=row*210
  local icon=ink.WeatherIcon:new{condition=id,size=48};icon:paintTo(bb,x+36,y+12);icon:free()
  local name=Text:new{text=({sun='Clear',partly_cloudy='Partly cloudy',cloud='Cloudy',showers='Showers',rain='Rain',thunder='Thunderstorms',snow='Snow',sleet='Rain and snow',hail='Hail',fog='Fog',haze='Haze',dust='Dust'})[id],face=require('ui/font'):getFace('NotoSans-Regular.ttf',12*600/Screen:scaleBySize(600)),width=116,alignment='center',justified=false};name:paintTo(bb,x+2,y+68);name:free()
  bb:paintRect(x,y+104,120,100,BB.COLOR_GRAY_3)
  icon=ink.WeatherIcon:new{condition=id,size=48};icon:setDark();icon:paintTo(bb,x+36,y+125);icon:free()
 end
 bb:writePNG((os.getenv('INK_OUTPUT')or root..'/checks')..'/weather-atlas-'..Screen:getWidth()..'x'..Screen:getHeight()..'.png');bb:free()
end)


check('weather icon replaces the condition immediately before the temperature',function()
 local function txt(text,role,width,align)return Text:new{text=text,face=require('ui/font'):getFace('NotoSans-Regular.ttf',14),width=width,alignment=align or 'left',justified=false}end
 settings:saveSetting(S.weather_display,'icons')
 for _,language in ipairs({'zh_CN','en_US'})do
  ink.selectLanguage(language)
  for _,include_city in ipairs({true,false})do for _,align in ipairs({'left','center','right'})do
   local w=ink.weatherWidget(0,include_city,txt,400,align,24);local texts={};local icon_pos
   local text_paint,icon_paint=Text.paintTo,ink.WeatherIcon.paintTo
   Text.paintTo=function(self,bb,x,y)texts[#texts+1]={widget=self,x=x,y=y};return text_paint(self,bb,x,y)end
   ink.WeatherIcon.paintTo=function(self,bb,x,y)icon_pos={x=x,y=y,w=self:getSize().w};return icon_paint(self,bb,x,y)end
   local bb=BB.new(400,200,BB.TYPE_BB8);bb:fill(BB.COLOR_WHITE);local ok,e=pcall(w.paintTo,w,bb,0,0)
   Text.paintTo,ink.WeatherIcon.paintTo=text_paint,icon_paint;bb:free();assert(ok,e)
   assert(#texts==2 and icon_pos)
   local prefix,value=texts[1],texts[2]
   assert(not prefix.widget.text:find('°C',1,true)and value.widget.text:find('°C',1,true))
   assert(prefix.y+prefix.widget:getBaseline()==value.y+value.widget:getBaseline(),'weather baselines differ')
   assert(prefix.x+prefix.widget:getSize().w<=icon_pos.x and icon_pos.x+icon_pos.w<=value.x,'condition icon is out of reading order')
   assert(value.x+value.widget:getSize().w<=400,'weather exceeds its column')
   w:free()
  end end
 end
 ink.selectLanguage('en_US')
end)
check('language label is exactly English',function()
 local rows=api.menu().sub_item_table;assert(rows[#rows-1].sub_item_table[2].text=='English')
end)
check('About opens through the native menu repeatedly on this device profile',function()
 for _,language in ipairs({'zh_CN','en_US','en_US'})do
  ink.selectLanguage(language);ink.settings();local root=assert(ink.settings_container);local menu=root[1]
  local last=menu.item_table[#menu.item_table];assert(last.text==(language=='en_US'and 'About'or '关于'))
  local viewer=capture(function()menu:onMenuSelect(last)end)
  assert(viewer.button_table.buttons_layout)
  if os.getenv('INK_TOUCH_ONLY')=='1'then assert(viewer.button_table.layout==nil)end
  canvas(viewer,'about-'..language..(os.getenv('INK_TOUCH_ONLY')=='1'and '-touch'or '-keys'),true)
  viewer:free();UI:close(root)
 end
end)
check('Chinese single-day icon layout retains the city and day before the condition',function()
 ink.selectLanguage('zh_CN');settings:saveSetting(S.weather_city,'xEdTH')
 W.records.xEdTH={day=today,forecasts={[today]='中雨 14～20°C'},updated_at=now}
 settings:saveSetting(S.weather_display,'icons');settings:saveSetting(S.weather_tomorrow,false)
 local w,valid=api.render(ui,ui.view.state,{ui_style='swiss',width=.84,font=1,scale=.7,background='white'})
 assert(valid);canvas(w,'chinese-modern-weather-order');settings:delSetting(S.weather_city);ink.selectLanguage('en_US')
end)


check('all English information viewers open without a DPad focus layout',function()
 ink.selectLanguage('en_US')
 for _,open in ipairs({api.about,ink.showChangelog,ink.showStatisticsHelp,ink.showDiagnostics,ink.previewDiagnostics})do
  local viewer=capture(open);assert(viewer.button_table.buttons_layout)
  if os.getenv('INK_TOUCH_ONLY')=='1'then assert(viewer.button_table.layout==nil)end
  english(viewer.title,'viewer title');viewer:free()
 end
end)

check('language menu rebuilds only InkFolio settings',function()
 local old=UI.nextTick;local next_fn;UI.nextTick=function(_,fn)next_fn=fn end
 local rows=api.menu().sub_item_table;local row=rows[#rows-1];assert(row.text=='Language');row.sub_item_table[1].callback()
 UI.nextTick=old;assert(ink.language()=='zh_CN'and next_fn);assert(api.menu().sub_item_table[4].text=='外观调整')
end)

check('native language selection safely replaces the complete menu',function()
 ink.selectLanguage('zh_CN');ink.settings();local before=assert(ink.settings_container);local menu=before[1]
 local old=UI.nextTick;local next_fn;UI.nextTick=function(_,fn)next_fn=fn end
 local rows=menu.item_table;menu:onMenuSelect(rows[#rows-1]);menu:onMenuSelect(menu.item_table[2]);UI.nextTick=old
 assert(ink.language()=='en_US'and ink.settings_container==before and next_fn)
 next_fn();local after=assert(ink.settings_container);assert(after~=before and after[1].item_table[4].text=='Appearance')
 canvas(after[1],'english-settings-menu',true);UI:close(after)
end)

print(string.format('LOCALIZATION_PASS %d / FAIL %d',passed,failed));if failed>0 then os.exit(1)end
