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
 summary=summaryItems,cache=CACHE,key=bookKey,stars=scoreStars,run=RUN,store=store,background=receiptBackground,progress=PixelProgress,paper=ReceiptPaper,editor=AppearanceEditor,weather=WEATHER,launcher=receiptMenuWidget,remember=rememberReceipt,home=homeReceiptContext,quicklook=Quicklook}
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
local Reader=require('apps/reader/readerui');local Font=require('ui/font');local Geom=require('ui/geometry');local Event=require('ui/event')
local output=os.getenv('INK_OUTPUT')or root..'checks'
local function saved()return require('dump')(settings.data,nil,true)end
local function paint(widget,path)
 local b=BB.new(Screen:getWidth(),Screen:getHeight(),BB.TYPE_BB8);b:fill(BB.COLOR_BLACK);widget:paintTo(b,0,0)
 if path then b:writePNG(output..'/'..path..'-'..Screen:getWidth()..'x'..Screen:getHeight()..'.png')end;return b
end
local function tap(w,r)return w:handleEvent(Event:new('Gesture',{ges='tap',pos=Geom:new{x=r.x+r.w/2,y=r.y+r.h/2,w=0,h=0}}))end
local reading_paints=0
local margin=math.floor(Screen:getWidth()*.07)
local reading_title=Text:new{text='正在阅读 · 第十二章',face=Font:getFace('NotoSans-Regular.ttf',18),width=Screen:getWidth()-2*margin,justified=false}
local reading_body=Text:new{text=string.rep('纸上的文字与阅读时的位置保持一致。我们在书页之间停留，也在故事之中继续前行。\n\n',8),
 face=Font:getFace('NotoSans-Regular.ttf',18),width=Screen:getWidth()-2*margin,height=math.floor(Screen:getHeight()*.78),justified=false}
ui.view.paintTo=function(self,b,x,y)
 reading_paints=reading_paints+1;b:paintRect(x,y,Screen:getWidth(),Screen:getHeight(),BB.COLOR_WHITE)
 b:paintRect(x,y,8,Screen:getHeight(),BB.COLOR_GRAY_9)
 reading_title:paintTo(b,x+margin,y+margin)
 reading_body:paintTo(b,x+margin,y+margin+Screen:scaleBySize(34))
end
local cover_reads=0
ui.bookinfo={getCoverImage=function()cover_reads=cover_reads+1;local b=BB.new(160,220,BB.TYPE_BB8);b:fill(BB.Color8(220));return b end}
local function setup()
 Reader.instance=ui;settings:saveSetting(S.ui_style,'paper');settings:saveSetting(S.card_width,.5);settings:saveSetting(S.card_font,1)
 settings:delSetting(S.paper_card_background);settings:saveSetting(S.card_background,'auto');settings:saveSetting(S.cover_background,'black')
 settings:saveSetting(S.stats,false);settings:saveSetting(S.word_book,false);settings:saveSetting(S.word_session,false);settings:saveSetting(S.remain,false)
 settings:saveSetting(S.weather,false);settings:saveSetting(S.weather_tomorrow,false);settings:saveSetting(S.cover_weather,'off');settings:saveSetting(S.date,true)
end
setup()
check('paper is the fifth skin and shares the existing card data and typography',function()
 assert(#ink.UI_STYLES==5 and ink.UI_STYLES[5].id=='paper'and ink.UI_STYLES[5].label=='纸上')
 assert(ink.isCardStyle()and ink.paperActive(ui))
 local s,fields=render({ui_style='paper',measure_only=true});assert(s.background_style=='paper'and s.card_background=='white')
 assert(find(fields,ui.doc_props.title)and find(fields,ui.doc_props.authors)and find(fields,'23%')and find(fields,'23 / 100 页'))
 local c,cf=render({ui_style='cover',card_background='white',measure_only=true});assert(c.card_rect.w==s.card_rect.w and c.card_rect.h==s.card_rect.h)
 assert(#fields==#cf);for i,t in ipairs(fields)do assert(t.text==cf[i].text and t.face==cf[i].face and t.width==cf[i].width)end
 s:free();c:free()
end)
check('paper repaints the reading page and does not copy overlays or load the cover',function()
 setup();Screen.bb:fill(BB.COLOR_BLACK);local before=saved();local reads=cover_reads
 local expected=ink.readingBackdrop(ui);local s=render({ui_style='paper',measure_only=true});local b=paint(s,'paper-white');local r=s.card_rect
 assert(cover_reads==reads and saved()==before)
 for y=0,Screen:getHeight()-1,13 do for x=0,Screen:getWidth()-1,13 do
  if x<r.x or x>=r.x+r.w or y<r.y or y>=r.y+r.h then assert(b:getPixel(x,y):getColor8().a==expected:getPixel(x,y):getColor8().a)end
 end end
 expected:free();b:free();s:free()
end)
for _,width in ipairs({.4,.5,.85})do for _,font in ipairs({.8,1,1.2})do for _,color in ipairs({'white','black'})do
 check('paper layout '..width..' '..font..' '..color,function()
  setup();local s,fields=render({ui_style='paper',card_width=width,card_font=font,paper_card_background=color,measure_only=true})
  assert(s.background_style=='paper'and s.card_background==color and s.card_rect.w==math.floor(Screen:getWidth()*width))
  for _,t in ipairs(fields)do assert(t.bgcolor:getColor8().a==(color=='black'and 51 or 255))end
  if width==.5 and font==1 then paint(s,'paper-'..color):free()end
  s:free()
 end)
end end end
check('paper never invokes automatic card detection, defaults white and rejects auto',function()
 setup();local detector=ink.cardBackground;ink.cardBackground=function()error('paper must not detect')end
 local ok,s=pcall(render,{ui_style='paper',measure_only=true});ink.cardBackground=detector;assert(ok,s);assert(s.card_background=='white');s:free()
 assert(not pcall(api.render,ui,ui.view.state,{ui_style='paper',paper_card_background='auto'}))
end)
check('paper background and full preview follow reading colours in night mode',function()
 setup();local night=Screen.night_mode;Screen.night_mode=true
 local ok,err=pcall(function()
  local s=render({ui_style='paper',measure_only=true});local b=paint(s);assert(b:getPixel(0,0):getColor8().a==153);b:free();s:free()
  local e=api.editor:new{ui=ui};UI:show(e);assert(e.preview_image.original_in_nightmode==false)
  e:onPreviewTap();b=paint(e.fullscreen);assert(b:getPixel(0,0):getColor8().a==153);b:free();e:onCancel()
 end)
 Screen.night_mode=night;assert(ok,err)
end)
check('reading editor enables paper, excludes automatic and cover background controls, and keeps its captured page',function()
 setup();settings:saveSetting(S.ui_style,'cover');local before=saved();local e=api.editor:new{ui=ui};UI:show(e)
 assert(e.controls.buttons[1][6].enabled and e:selectStyle('paper'));paint(e,'paper-editor'):free()
 assert(#e.controls.buttons==5 and #e.controls.buttons[4]==3)
 assert(e.controls.buttons[4][1].text=='卡片底色'and e.controls.buttons[4][2].text=='白色'and e.controls.buttons[4][2].checked_func())
 local paints=reading_paints;e:change('paper_card_background','black');e:refreshPreview();assert(reading_paints==paints)
 paint(e):free();local r=e.preview_image.dimen;assert(tap(e,r));assert(e.fullscreen)
 local b=paint(e.fullscreen,'paper-editor-fullscreen');assert(b:getPixel(0,0):getColor8().a==153);b:free()
 e.fullscreen:onTap();assert(not e.fullscreen and e.draft.paper_card_background=='black'and saved()==before)
 e:onCancel();assert(saved()==before)
end)
check('paper save preserves cover colours and defaults across editor reopen',function()
 setup();settings:saveSetting(S.ui_style,'cover');local e=api.editor:new{ui=ui};UI:show(e);assert(e:selectStyle('paper'))
 e:change('paper_card_background','black');e:save();assert(ink.uiStyle().id=='paper'and settings:readSetting(S.paper_card_background)=='black')
 assert(settings:readSetting(S.card_background)=='auto'and settings:readSetting(S.cover_background)=='black')
 e=api.editor:new{ui=ui};UI:show(e);assert(e.draft.paper_card_background=='black');e:onCancel()
end)
check('paper unavailable outside reading is gray and cannot be selected by calling its callback',function()
 setup();Reader.instance=nil;settings:saveSetting(S.ui_style,'cover');local before=saved();local e=api.editor:new{ui=ui};UI:show(e)
 local choice=e.controls.buttons[1][6];assert(not choice.enabled and not choice.checked_func())
 local message=ink.message;local reason;ink.message=function(s)reason=s end
 local ok=choice.callback();local selected=ink.selectUIStyle('paper');ink.message=message
 assert(not selected and reason and e.draft.ui_style=='cover'and saved()==before)
 e:onCancel()
end)
check('paper has the same unsupported menu restrictions and exclusive weather as cover',function()
 setup();settings:saveSetting(S.cover_weather,'today');local rows=api.menu().sub_item_table;local content=rows[2].sub_item_table
 for _,item in ipairs({content[2],content[4].sub_item_table[4],content[5],content[6],rows[3]})do assert(not item.enabled_func())end
 content[1].sub_item_table[2].callback();assert(ink.weatherSelected(1)and not ink.weatherSelected(0));settings:saveSetting(S.cover_weather,'off')
end)
check('paper quicklook and screenshot render the current reading page',function()
 setup();local box=api.quicklook:new{ui=ui,state=ui.view.state};assert(box[1][1].background_style=='paper');paint(box,'paper-quicklook'):free();box:free()
 settings:saveSetting('screenshot_dir',os.getenv('KO_HOME')..'/screenshots');ink.saveScreenshot()
 local lfs=require('libs/libkoreader-lfs');local path
 for name in lfs.dir(os.getenv('KO_HOME')..'/screenshots')do if name:match('^Inkfolio_.*%.png$')then path=os.getenv('KO_HOME')..'/screenshots/'..name end end
 assert(path);local img=require('ui/renderimage'):renderImageFile(path);assert(img and img:getPixel(0,0):getColor8().a==153);img:free()
end)
local function sleep(ui_arg)
 local supports=Device.supportsScreensaver;Device.supportsScreensaver=function()return true end
 local ss={screensaver_type='book_receipt',prefix='',ui=ui_arg};local ok,err=pcall(require('ui/screensaver').show,ss);Device.supportsScreensaver=supports
 assert(ok,err);assert(ss.screensaver_widget);return ss
end
check('paper reading lockscreen uses reading page and retains selected skin',function()
 setup();local ss=sleep(ui);assert(ss.screensaver_widget.widget.background_style=='paper');paint(ss.screensaver_widget,'paper-sleep'):free()
 UI:close(ss.screensaver_widget);Device.screen_saver_mode=false;assert(ink.uiStyle().id=='paper')
end)
local lastpath=os.getenv('KO_HOME')..'/recent.epub';local file=assert(io.open(lastpath,'wb'));file:close()
local BookInfo=require('apps/filemanager/filemanagerbookinfo');local nativeCover=BookInfo.getCoverImage
BookInfo.getCoverImage=function()local b=BB.new(160,220,BB.TYPE_BB8);b:fill(BB.Color8(220));return b end
check('home lockscreen uses most recent book cover for this sleep only even with stale reader argument',function()
 setup();ui.document.file=lastpath;settings:saveSetting('lastfile',lastpath);api.remember(ui);Reader.instance=nil
 local before=saved();local ss=sleep(ui);local scene=ss.screensaver_widget.widget
 assert(scene.background_style=='cover'and scene.card_background=='black'and scene.cover_rect.w>0 and saved()==before)
 paint(ss.screensaver_widget,'paper-home-cover'):free();UI:close(ss.screensaver_widget);Device.screen_saver_mode=false
 Reader.instance=ui;ss=sleep(ui);assert(ss.screensaver_widget.widget.background_style=='paper');UI:close(ss.screensaver_widget);Device.screen_saver_mode=false
 assert(ink.uiStyle().id=='paper')
end)
check('home appearance keeps selected paper disabled while previewing actual cover settings',function()
 setup();ui.document.file=lastpath;settings:saveSetting('lastfile',lastpath);api.remember(ui);Reader.instance=nil
 local context=assert(api.home());local e=api.editor:new{ui=context};UI:show(e);paint(e,'paper-home-editor'):free()
 assert(not e.controls.buttons[1][6].enabled and e.controls.buttons[1][6].checked_func())
 assert(#e.controls.buttons==5 and e.controls.buttons[4][1].text=='卡片底色'and #e.controls.buttons[4]==3)
 assert(not e.controls.buttons[4][2].enabled and not e.controls.buttons[4][3].enabled)
 local color=e.draft.paper_card_background;e.controls.buttons[4][3].callback();assert(e.draft.paper_card_background==color)
 e:save();assert(ink.uiStyle().id=='paper'and settings:readSetting(S.paper_card_background)=='white')
 assert(settings:readSetting(S.card_background)=='auto')
end)
check('missing last book remains explicit and does not change paper selection',function()
 Reader.instance=nil;settings:saveSetting('lastfile',lastpath..'-missing');local ss=sleep(nil)
 assert(not ss.screensaver_widget.widget.background_style);UI:close(ss.screensaver_widget);Device.screen_saver_mode=false;assert(ink.uiStyle().id=='paper')
end)
BookInfo.getCoverImage=nativeCover;Reader.instance=nil;reading_title:free();reading_body:free()
print('PAPER_PASS '..passed..' / FAIL '..failed);os.exit(failed==0 and 0 or 1)
