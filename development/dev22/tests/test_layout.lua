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
 summary=summaryItems,cache=CACHE,key=bookKey,stars=scoreStars,run=RUN,store=store,background=receiptBackground}
]]))()
local ink,S=api.ink,api.S
if os.getenv('INK_STYLE') then settings:saveSetting(S.ui_style,os.getenv('INK_STYLE')) end
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
check('no-duration-row day remains unknown',function()local c=assert(curve(ui,'month',now));assert(c.days[2].seconds==nil and c.missing>0)end)
check('explicit native zero row stays numeric zero',function()local c=assert(curve(ui,'month',now));assert(c.days[3].seconds==0)end)
check('native positive duration preserved',function()local c=assert(curve(ui,'month',now));assert(c.days[1].seconds==5400)end)
check('duration spanning midnight divided between days',function()local c=assert(curve(ui,'month',now));assert(c.days[4].seconds==1800 and c.days[5].seconds==1800)end)
check('future dates remain empty and uncounted',function()local c=assert(curve(ui,'month',now));assert(c.days[19].future and c.days[19].seconds==nil and c.elapsed==18)end)
check('current duration clipped to current time',function()local c=assert(curve(ui,'month',now));assert(c.days[18].seconds==61)end)
check('calendar average denominator remains elapsed calendar days',function()local c=assert(curve(ui,'month',now));assert(c.average==c.total/18 and c.known==6 and c.missing==12)end)
check('empty query yields unknown days rather than all zeros',function()local c=assert(curve(ui,'month',os.time{year=2026,month=8,day=18,hour=12}));assert(c.known==0 and c.average==nil and c.missing==18)end)
check('disabled native statistics gives explicit unavailable state',function()local c,e=curve({statistics={isEnabled=function()return false end}},'week',now);assert(not c and e:find('开启'))end)
check('database query error never becomes zero chart',function()
 local open=SQ.open;SQ.open=function()return {exec=function()error('test query failure')end,close=function()end}end
 local ok,c,e=pcall(curve,ui,'month',now);SQ.open=open;assert(ok and not c and e:find('失败'))
end)
ink.wordState.tracking_since=stamp(1,0);ink.wordState.days={}
for i=1,18 do if i~=2 then ink.wordState.days[os.date('%Y-%m-%d',stamp(i))]={words=i==3 and 0 or i*1500,incomplete=i==18}end end
local words=ink.readWordChart
check('word missing and zero remain distinct',function()local c=words('month',now);assert(c.days[2].words==nil and c.days[3].words==0 and c.missing==1)end)
check('partial record marker and total preserved',function()local c=words('month',now);assert(c.incomplete and c.days[18].incomplete and c.total>0)end)
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
check('native main labels use clear regular body font',function()
 local w,fs=render();local a,b=find(fs,'章节'),find(fs,'估算已读');assert(a.face==b.face and not a.bold and not b.bold and not a.height_overflow_show_ellipsis);w:free()
end)
check('secondary progress numbers share regular font while percentage stays emphasized',function()
 local w,fs=render();local p,a,b=find(fs,'23 / 100 页'),find(fs,'12.3万字'),find(fs,'6789字')
 assert(p and a and b and p.face==a.face and a.face==b.face and not p.bold and not a.bold and not b.bold)
 assert(find(fs,'23%').bold and find(fs,'23%').face.size>p.face.size);w:free()
end)
check('percentage remains stronger than progress values',function()
 local w,fs=render();assert(find(fs,'23%').face.size>find(fs,'23 / 100 页').face.size);w:free()
end)
check('optional progress rows respect actual selection',function()
 settings:saveSetting(S.word_book,false);settings:saveSetting(S.word_session,false);settings:saveSetting(S.remain,true)
 local w,fs=render();assert(not find(fs,'估算已读') and not find(fs,'本次唤醒') and find(fs,'预计剩余'));w:free()
 settings:saveSetting(S.word_book,true);settings:saveSetting(S.word_session,true);settings:saveSetting(S.remain,false)
end)
for _,choice in ipairs({{},{S.word_book},{S.word_session},{S.remain},{S.word_book,S.word_session},{S.word_book,S.remain},{S.word_session,S.remain}})do
 check('progress selection '..table.concat(choice,','),function()
  for _,key in ipairs({S.word_book,S.word_session,S.remain})do settings:saveSetting(key,false)end
  for _,key in ipairs(choice)do settings:saveSetting(key,true)end
  local w,fs=render();assert(ink.progressCount()==#choice and find(fs,'章节') and find(fs,'当前页码'))
  for _,item in ipairs({{S.word_book,'估算已读'},{S.word_session,'本次唤醒'},{S.remain,'预计剩余'}})do
   assert((find(fs,item[2])~=nil)==ink.progressEnabled(item[1]))
  end;w:free()
 end)
end
settings:saveSetting(S.word_book,true);settings:saveSetting(S.word_session,true);settings:saveSetting(S.remain,false)
check('progress labels and values have matching widths and row spacing',function()
 local w=render();local rows={};walk(w,function(v)if getmetatable(v)==H and v[1] and (unpad(v[1]).text=='当前页码' or unpad(v[1]).text=='估算已读' or unpad(v[1]).text=='本次唤醒')then rows[#rows+1]=v end end)
 assert(#rows==3);for i=2,3 do assert(rows[i][1]:getSize().w==rows[1][1]:getSize().w and rows[i][3]:getSize().w==rows[1][3]:getSize().w and rows[i]:getSize().h==rows[1]:getSize().h)end;w:free()
end)
check('summary titles left-aligned and columns exactly equal',function()
 local w,fs=render();local a,b=find(fs,'本书今日'),find(fs,'全局累计');assert(a and b and a.width==b.width and a.alignment=='left' and b.alignment=='left');w:free()
end)
check('summary duration first, stronger than page count',function()
 local w=render();local blocks={};walk(w,function(v)if getmetatable(v)==V and v[1] and v[1][1] and (v[1][1].text=='本书今日' or v[1][1].text=='全局累计')then blocks[#blocks+1]=v end end)
 assert(#blocks==2);for _,b in ipairs(blocks)do assert(unpad(b[3][1]).text=='时长' and unpad(b[5][1]).text=='页数' and b[3][3].face.size>b[5][3].face.size and b[3][3].bold and not b[5][3].bold)end;w:free()
end)
check('one summary uses available width with left title',function()
 settings:saveSetting(S.summary,{'global_total'});local w,fs,size=render();assert(find(fs,'全局累计').width>size.width*.7 and find(fs,'全局累计').alignment=='left');w:free();settings:saveSetting(S.summary,{'book_today','global_total'})
end)
check('zero selected summaries retain selected charts',function()
 settings:saveSetting(S.summary,{});local w,fs=render();assert(not find(fs,'本书今日') and find(fs,'本周全局阅读时长') and find(fs,'本月全局阅读字数'));w:free();settings:saveSetting(S.summary,{'book_today','global_total'})
end)
check('chart explanations moved to settings with untruncated data',function()
 local w,fs=render();assert(count(fs,'短横：0')==0);for _,t in ipairs(fs)do if t.text:sub(1,3)=='短' or t.text:find('日均',1,true) or t.text:find('已记录',1,true)then assert(not t.height_overflow_show_ellipsis and not t.height)end end;w:free()
end)
check('no statistics suppresses selected summaries and charts',function()
 settings:saveSetting(S.stats,false);local w,fs=render();assert(not find(fs,'阅读摘要') and count(fs,'短横：0')==0);w:free();settings:saveSetting(S.stats,true)
end)
check('narrow large-type trend details wrap without ellipsis',function()
 local w,fs=render({width=.55,font=1.2,scale=.6,background='white',measure_only=true})
 for _,t in ipairs(fs)do if t.text:find('已记录',1,true) or t.text:sub(1,#'短横')=='短横' then
  assert(not t.height_overflow_show_ellipsis and not t.height)
  local natural=require('ui/widget/textwidget'):new{text=t.text,face=t.face,padding=0,bold=t.bold}
  if natural:getSize().w>t.width then assert(t:getSize().h>t.line_height_px+1)end;natural:free()
 end end;w:free()
end)
check('large axis label width measured from actual text',function()
 local data={metric='words',days={{words=123456789,day=1},{words=0,day=2},{day=3}}}
 local b=api.bars:new{width=math.floor(Screen:getWidth()*.7),height=120,font_size=12,stroke=2,data=data}
 local bb=BB.new(b.width,120,BB.TYPE_BB8);bb:fill(BB.COLOR_WHITE);b:paintTo(bb,0,0);bb:free();b:free()
end)
check('missing slash and recorded zero produce distinct pixels',function()
 local b=api.bars:new{width=500,height=130,font_size=12,stroke=2,data={metric='words',days={{day=1},{words=0,day=2},{words=100,day=3}}}}
 local bb=BB.new(500,130,BB.TYPE_BB8);bb:fill(BB.COLOR_WHITE);b:paintTo(bb,0,0)
 local font=require('ui/font'):getFace('cfont',12);local bottom=130-math.floor(font.size*1.8)
 local lefttext=require('ui/widget/textwidget'):new{text='100字',face=font,padding=0};local left=math.ceil(lefttext:getSize().w)+4;lefttext:free()
 local cell=(498-left)/3;local function black(i)local n=0;local gx=left+math.floor((i-.5)*cell)
 for y=bottom-8,bottom-1 do for x=gx-25,gx+25 do if bb:getPixel(x,y):getColor8().a<64 then n=n+1 end end end;return n end
 assert(black(1)>0 and black(2)>black(1)*2);bb:free();b:free()
end)
local chart_ids={'week','month','week_words','month_words'}
for i=1,#chart_ids do for j=i+1,#chart_ids do
 check('native chart combination '..chart_ids[i]..'+'..chart_ids[j],function()
  settings:saveSetting(S.charts,{chart_ids[i],chart_ids[j]});local w,fs,size=render();local bars={};walk(w,function(v)if getmetatable(v)==api.bars then bars[#bars+1]=v end end)
  assert(#bars==2 and bars[1].width==bars[2].width and bars[1].height==bars[2].height and count(fs,'短横：0')==0)
  local bb=BB.new(size.width,size.height,BB.TYPE_BB8);bb:fill(BB.COLOR_WHITE);w:paintTo(bb,0,0);bb:free();w:free()
 end)
end end
for _,summary in ipairs({{}, {'book_today'}, {'book_today','global_total'}})do
 for _,chart in ipairs({{}, {'week'}, {'week','month_words'}})do
  check('module counts summary='..#summary..' charts='..#chart,function()
   settings:saveSetting(S.summary,summary);settings:saveSetting(S.charts,chart)
   local w,fs,size=render();assert(count(fs,'短横：0')==0);assert(size.width<=Screen:getWidth() and size.height<Screen:getHeight())
   local bb=BB.new(size.width,size.height,BB.TYPE_BB8);bb:fill(BB.COLOR_WHITE);w:paintTo(bb,0,0);bb:free();w:free()
  end)
 end
end
check('summary and chart limits remain independent',function()
 settings:saveSetting(S.summary,{'book_today','global_total'});settings:saveSetting(S.charts,{'week','month_words'});assert(#api.summary()==2 and #ink.chartItems()==2)
 settings:saveSetting(S.charts,{'week','month','week_words'});assert(not pcall(ink.chartItems));settings:saveSetting(S.charts,{'week','month_words'})
end)
check('native full receipt paints selected configuration',function()
 local w,valid=api.build(ui,ui.view.state,{width=.84,font=1,scale=.70,background='white'});assert(valid)
 local bb=BB.new(Screen:getWidth(),Screen:getHeight(),BB.TYPE_BB8);bb:fill(BB.COLOR_WHITE);w:paintTo(bb,0,0)
 bb:writePNG(root..'checks/layout-'..Screen:getWidth()..'x'..Screen:getHeight()..'-'..(os.getenv('INK_STYLE') or 'classic')..'.png');bb:free();w:free()
end)
for _,font in ipairs({.8,1.2})do
 check('native receipt at selectable font '..font,function()
  local w,valid=api.build(ui,ui.view.state,{width=.84,font=font,scale=.7,background='white'});assert(valid)
  local bb=BB.new(Screen:getWidth(),Screen:getHeight(),BB.TYPE_BB8);bb:fill(BB.COLOR_WHITE);w:paintTo(bb,0,0);bb:free();w:free()
 end)
end
check('menu choices and limits remain available',function()
 local rows=api.menu().sub_item_table;assert(#rows==9 and rows[2].text=='显示内容' and rows[3].text=='阅读目标' and rows[4].text=='外观调整' and rows[5].text=='联网设置')
 local content=rows[2].sub_item_table;assert(content[1].text=='顶部信息' and content[3].text=='阅读进度' and content[4].text=='阅读摘要')
 assert(#content[3].sub_item_table==5 and content[6].sub_item_table[2].text=='锁屏时轮换')
end)
check('monthly list keeps category without QR or display month',function()
 local w,fs=render();assert(find(fs,'豆瓣月榜'));assert(not find(fs,'2026年9月'))
 local found=false;walk(w,function(v)if getmetatable(v)==require('ui/widget/qrwidget')then found=true end end);assert(not found);w:free()
end)
check('native settings dialog still constructs and closes',function()
 local native=UI.show;local container;UI.show=function(_,w)container=w end
 local ok,e=pcall(ink.settings);UI.show=native;assert(ok,e);assert(container and container[1].onTapCloseAllMenus);container:free()
end)
local Reader=require('apps/reader/readerui');Reader.instance=ui
settings:saveSetting(S.width,.84);settings:saveSetting(S.scale,.70);settings:saveSetting(S.font,1);settings:saveSetting(S.background,'white')
settings:saveSetting('screenshot_dir',os.getenv('KO_HOME')..'/screenshots')
check('screenshot remains native PNG and never advances group',function()
 ink.monthly.cursor=1;local shown,close=UI.show,UI.close;local messages={};UI.show=function(_,w)messages[#messages+1]=w end
 local ok,e=pcall(ink.saveScreenshot);UI.show=shown;UI.close=close;assert(ok,e)
 local lfs=require('libs/libkoreader-lfs');local found=false
 for name in lfs.dir(os.getenv('KO_HOME')..'/screenshots')do if name:match('^Inkfolio_.*%.png$')then assert(lfs.attributes(os.getenv('KO_HOME')..'/screenshots/'..name,'size')>0);found=true end end
 assert(found and ink.monthly.cursor==1);for _,w in ipairs(messages)do w:free()end
end)
check('offline screensaver renders and duplicate shows do not rotate twice',function()
 local record=ink.monthly.record;local n=#record.items
 for i=1,n do local item={};for k,v in pairs(record.items[i])do item[k]=v end;item.rank=i+n;item.url='https://book.douban.com/subject/'..(i+10)..'/';record.items[n+i]=item end
 local supports=Device.supportsScreensaver;Device.supportsScreensaver=function()return true end
 local saver=require('ui/screensaver');local ss={screensaver_type='book_receipt',prefix='',ui=ui}
 ink.monthly.cursor=1;settings:saveSetting(S.monthly_rotate,true);Device.screen_saver_mode=false
 local ok,e=pcall(function()saver.show(ss);assert(ink.monthly.cursor==4);saver.show(ss);assert(ink.monthly.cursor==4)end)
 if ss.screensaver_widget then UI:close(ss.screensaver_widget)end
 Device.supportsScreensaver=supports;Device.screen_saver_mode=false;settings:saveSetting(S.monthly_rotate,false)
 for i=#record.items,n+1,-1 do record.items[i]=nil end;ink.monthly.cursor=1;assert(ok,e)
end)
print('LAYOUT_PASS '..passed..' / FAIL '..failed);os.exit(failed==0 and 0 or 1)

