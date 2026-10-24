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
 doc_props={title='挽救计划',authors='安迪·威尔'},doc_settings={data={doc_pages=100}},view={state={page=23}},
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


local Font=require('ui/font');local Render=require('ui/renderimage')
settings:saveSetting(S.ui_style,assert(os.getenv('INK_STYLE')))
settings:saveSetting(S.cover,true);settings:saveSetting(S.date,true);settings:saveSetting(S.weather,true);settings:saveSetting(S.weather_tomorrow,true)
settings:saveSetting(S.stats,true);settings:saveSetting(S.summary,{'global_today','global_total'});settings:saveSetting(S.summary_metric,'words')
settings:saveSetting(S.word_book,false);settings:saveSetting(S.word_session,false);settings:saveSetting(S.remain,true)
api.weather.records.lqYjK={day=os.date('%Y-%m-%d'),updated_at=os.time(),forecasts={[os.date('%Y-%m-%d')]='晴 12～23°C',[os.date('%Y-%m-%d',os.time()+86400)]='多云 14～25°C'}}
ui.bookinfo={getCoverImage=function()
 local bb=BB.new(600,900,BB.TYPE_BB8);bb:fill(BB.COLOR_GRAY_5)
 bb:paintRect(0,0,600,245,BB.COLOR_BLACK);bb:paintRect(0,245,190,655,BB.COLOR_BLACK)
 bb:paintRect(360,320,180,360,BB.COLOR_GRAY_9);bb:paintRect(0,760,600,140,BB.COLOR_BLACK)
 local function label(value,size,y,maxh)
  local t
  repeat
   if t then t:free()end
   t=require('ui/widget/textwidget'):new{text=value,face=Font:getFace('NotoSans-Regular.ttf',size),bold=true,padding=0,
    fgcolor=BB.COLOR_WHITE,bgcolor=BB.COLOR_BLACK}
   size=size-1
  until (t:getSize().w<=520 and t:getSize().h<=maxh)or size<8
  local h=t:getSize().h;t:paintTo(bb,math.floor((600-t:getSize().w)/2),y);t:free();return h
 end
 local th=label('挽救计划',44,45,100);label('PROJECT HAIL MARY',20,45+th+16,50)
 label('安迪·威尔',22,785,55);label('示意封面 · 非原版设计',12,860,30)
 return bb
end}
local options={width=.78,font=1,scale=.78,background='white',card_font=1,cover_background='white'}
local scene,valid=api.build(ui,ui.view.state,options);assert(valid,'preview does not fit')
local bb=BB.new(Screen:getWidth(),Screen:getHeight(),BB.TYPE_BB8);bb:fill(BB.COLOR_WHITE);scene:paintTo(bb,0,0)
bb:writePNG(assert(os.getenv('PREVIEW_OUT')));bb:free();scene:free()
