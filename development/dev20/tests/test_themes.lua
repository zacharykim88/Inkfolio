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
 summary=summaryItems,cache=CACHE,key=bookKey,stars=scoreStars,run=RUN,store=store,background=receiptBackground,progress=PixelProgress,paper=ReceiptPaper,editor=AppearanceEditor}
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

local function inkCentre(t,p)
 local top,bottom
 for y=0,math.min(t._bb:getHeight(),t:getLineHeight())-1 do
  for x=0,t._bb:getWidth()-1 do if t._bb:getPixel(x,y):getColor8().a<128 then
   top=top or y;bottom=y;break
  end end
 end
 assert(top and bottom,'no first-line ink: '..t.text)
 return p.y+(top+bottom)/2
end
local function headerAligned(a,b,pos)return math.abs(inkCentre(a,pos[a])-inkCentre(b,pos[b]))<=1.5 end

local Font=require('ui/font')
local function text(fields,value) return find(fields,value) end
local function positions(widget,size)
 local native=Text.paintTo;local pos={}
 Text.paintTo=function(self,bb,x,y)pos[self]={x=x,y=y,baseline=y+self:getBaseline()};return native(self,bb,x,y)end
 local bb=BB.new(size.width,size.height,BB.TYPE_BB8);bb:fill(BB.COLOR_WHITE)
 local ok,e=pcall(widget.paintTo,widget,bb,0,0);Text.paintTo=native;bb:free();assert(ok,e);return pos
end
ui.bookinfo={getCoverImage=function()
 local bb=BB.new(160,220,BB.TYPE_BB8);bb:fill(BB.COLOR_BLACK)
 local title=Text:new{text='UI\nTEST',face=Font:getFace('NotoSans-Regular.ttf',22),bold=true,fgcolor=BB.COLOR_WHITE,bgcolor=BB.COLOR_BLACK,
  width=140,alignment='left',justified=false}
 title:paintTo(bb,10,24);title:free();return bb
end}
settings:saveSetting(S.cover,true);settings:saveSetting(S.summary,{'global_today','global_month'});settings:saveSetting(S.summary_metric,'words')
local native_snapshot=ink.statisticsSnapshot
ink.statisticsSnapshot=function(context)return native_snapshot(context,now)end
ink.setGoal('period','month');ink.setGoal('metric','words');ink.setGoal('target',150000);ink.setGoal('enabled',true)

local dump=require('dump')
local function encoded(t)return dump(t,nil,true)end
local function functionState()
 local snap=ink.statisticsSnapshot(ui)
 local chosen={}
 for _,item in ipairs(api.summary())do chosen[#chosen+1]=ink.summaryData(snap,item)end
 return encoded({goal=ink.goalSnapshot(ui,now,snap),summary=chosen,words=ink.wordState.days,
    matching=ink.matchState,cache=api.cache,monthly=ink.monthly,run={active=api.run.active,token=api.run.token,index=api.run.index,processed=api.run.processed}})
end
local function savedSettings()
 local rows={}
 for k,v in pairs(settings.data)do if k~=S.ui_style and (k:find('^read_receipt_v2_') or k=='screensaver_type') then rows[k]=v end end
 return encoded(rows)
end
local function choose(id)assert(ink.selectUIStyle(id))end
check('only one renderer and shared data model exist in the integrated patch',function()
 local _,n=source:gsub('local function renderReceipt%(','');assert(n==1)
 local _,v=source:gsub('local S = {','');assert(v==1)
 assert(#ink.UI_STYLES==5)
end)
check('old installations default to classic with no implicit settings migration',function()
 assert(not settings:readSetting(S.ui_style) and ink.uiStyle().id=='classic')
end)
local settings_before=savedSettings();local data_before=functionState()
for _,id in ipairs({'classic','pixel','swiss','pixel','classic','swiss'})do
 check('switch to '..id..' preserves settings and all functional state',function()
  choose(id);assert(ink.uiStyle().id==id);assert(savedSettings()==settings_before)
  assert(functionState()==data_before)
 end)
end
check('chosen style survives native settings reopen',function()
 local reopened=require('luasettings'):open(os.getenv('KO_HOME')..'/settings.reader.lua')
 assert(reopened:readSetting(S.ui_style)=='swiss')
end)
check('invalid style is rejected without a write or fallback',function()
 local before=encoded(settings.data);assert(not pcall(ink.selectUIStyle,'unknown'));assert(encoded(settings.data)==before)
 assert(not pcall(ink.uiStyle,{ui_style='unknown'}))
end)
check('write failure restores previous style and preserves all other settings',function()
 local before=encoded(settings.data);local flush=settings.flush;settings.flush=function()error('write denied')end
 local ok=pcall(ink.selectUIStyle,'classic');settings.flush=flush
 assert(not ok and encoded(settings.data)==before)
end)
check('missing inactive fonts do not prevent the active style rendering',function()
 choose('swiss');local native=Font.getFace
 Font.getFace=function(self,name,...)if name=='fusion-pixel-12px-proportional-zh_hans.otf' or name:find('Xiangcui',1,true) then return nil end;return native(self,name,...)end
 local ok,paper,fields,size=pcall(render,{width=.84,font=1,scale=.65,background='white',measure_only=true})
 Font.getFace=native;assert(ok,paper);assert(paper.theme.id=='swiss');paper:free()
end)
for _,id in ipairs({'classic','pixel'})do
 check('missing required '..id..' font rejects switch and retains current style',function()
  choose('swiss');local name=id=='classic' and 'Xiangcui-Dazijiti-main/香萃打字机体 W40.ttf' or 'fusion-pixel-12px-proportional-zh_hans.otf';local native=Font.getFace
  Font.getFace=function(self,font,...)if font==name then return nil end;return native(self,font,...)end
  local ok,result,reason=pcall(ink.selectUIStyle,id);Font.getFace=native
  assert(ok and not result and reason:find(name,1,true) and ink.uiStyle().id=='swiss')
 end)
end
check('style labels live in appearance instead of a separate settings menu',function()
 assert(#ink.UI_STYLES==5 and ink.UI_STYLES[1].label=='小票' and ink.UI_STYLES[2].label=='像素' and ink.UI_STYLES[3].label=='现代')
 local rows=api.menu().sub_item_table;assert(#rows==8)
 for _,row in ipairs(rows)do assert(row.text~='UI风格')end
 assert(rows[4].text=='外观调整' and rows[4].callback)
end)
check('native content submenu returns to logically ordered root settings',function()
 local show=UI.show;local container;UI.show=function(_,w)container=w end
 local ok,e=pcall(ink.settings);UI.show=show;assert(ok,e);local menu=container[1]
 local bb=BB.new(Screen:getWidth(),Screen:getHeight(),BB.TYPE_BB8);bb:fill(BB.COLOR_WHITE);container:paintTo(bb,0,0)
 bb:writePNG(root..'checks/settings-'..Screen:getWidth()..'x'..Screen:getHeight()..'.png');bb:free()
 menu:onMenuSelect(menu.item_table[2]);assert(#menu.item_table_stack==1)
 menu:onMenuSelect(menu.item_table[3]);assert(#menu.item_table_stack==2)
 menu:backToUpperMenu(true);assert(#menu.item_table_stack==1)
 menu:backToUpperMenu(true);assert(#menu.item_table_stack==0 and #menu.item_table==8)
 assert(menu.item_table[3].text=='阅读目标' and menu.item_table[4].text=='外观调整');container:free()
end)
local function uiTexts(fields)
 local strings={}
 for _,t in ipairs(fields)do
  strings[t.text]=true
 end
 return encoded(strings)
end
local compare
for _,id in ipairs({'classic','pixel','swiss'})do
 check('same view data and components in '..id,function()
  choose(id);local paper,fields,size=render();local content=uiTexts(fields)
  if not compare then compare=content else assert(compare==content,'view text changed with theme')end
  local qr,graphs=0,0
  walk(paper,function(n)if getmetatable(n)==require('ui/widget/qrwidget')then qr=qr+1 end;if getmetatable(n)==api.bars then graphs=graphs+1 end end)
  assert(qr==0 and graphs==2 and paper.theme.id==id);paper:free()
 end)
 check('diagnostics identify only active '..id..' font dependencies',function()
  choose(id);local t=ink.diagnosticContextText();assert(t:find('UI风格：'..ink.uiStyle().label,1,true))
  for _,font in ipairs(ink.uiStyle().assets)do assert(t:find('界面字体 '..font..'：可加载',1,true))end
 end)
end
-- Every emitted row is painted with real native font metrics.
for _,id in ipairs({'classic','pixel','swiss'})do for _,font in ipairs({.8,1,1.2})do for _,width in ipairs({.55,.84,.90})do
 check(id..' full grid font='..font..' width='..width,function()
  choose(id);local paper,fields,size=render({width=width,font=font,scale=.65,background='white',measure_only=true})
  assert(size.width<=Screen:getWidth() and size.height<Screen:getHeight())
  local pos=positions(paper,size)
  if id=='classic' then
   local pure_width=size.width-paper.shadow_width
   local radius=math.max(9,math.floor(math.max(8,math.floor(math.min(pure_width/22,17)))*1.2))
   local center=paper.padding_top+paper.stub_y
   for _,t in ipairs(fields)do if pos[t] then
    assert(pos[t].y+t:getSize().h<center-radius or pos[t].y>center+radius,'side notch collides with '..t.text)
   end end
  end
  for _,t in ipairs(fields)do if pos[t] then
   assert(pos[t].x>=0 and pos[t].x+t.width<=size.width,'horizontal overflow '..t.text)
   assert(pos[t].y>=0 and pos[t].y+t:getSize().h<=size.height,'vertical overflow '..t.text)
  end end
  local dates,amount,percent,labels={}
  for _,t in ipairs(fields)do
   if t.text=='2026.10.18' then dates[1]=t end
   if t.text:find('15.0万字',1,true)then amount=t end
   if t.text=='166%'then percent=t end
  end
  assert(dates[1] and amount and percent and amount:getAllLineCount()==1)
  assert(dates[1].face==find(fields,'章节').face and dates[1].face.size<=amount.face.size and percent.face.size==amount.face.size)
  local brand=assert(find(fields,'INKFOLIO'));local goal=assert(find(fields,'本月阅读目标'));local book=assert(find(fields,ui.doc_props.title))
  assert(not find(fields,'日期') and dates[1].alignment=='right')
  assert(headerAligned(dates[1],brand,pos) and pos[dates[1]].x+dates[1].width==size.width-paper.padding_right-paper.shadow_width)
  assert(pos[brand].x+brand.width<pos[dates[1]].x and brand:getAllLineCount()==1 and dates[1]:getAllLineCount()==1)
  assert(pos[goal].x==paper.padding_left and pos[goal].y>pos[book].y+book:getSize().h)
  walk(paper,function(n)if getmetatable(n)==require('ui/widget/imagewidget') then
   assert(n.dimen.y+n.dimen.h==pos[amount].y+amount:getSize().h and pos[amount].x+amount.width<n.dimen.x)
   assert(math.abs(n.dimen.w*220-n.dimen.h*160)<=220 and n.dimen.x+n.dimen.w==size.width-paper.padding_right-paper.shadow_width)
  end end)
  assert(pos[amount].baseline==pos[percent].baseline)
  assert(pos[percent].x==paper.padding_left and pos[percent].y>=pos[goal].y+goal:getSize().h)
  paper:free()
 end)
end end end
check('removed modules have no code or settings entry',function()
 assert(not source:find('墨笺',1,true) and not source:find('QRWidget',1,true))
 assert(not source:find('stampState',1,true) and not source:find('paintStamp',1,true))
 assert(not source:find('getPowerDevice',1,true) and not source:find('hasBattery',1,true))
 assert(S.qr==nil)
 local rows=api.menu().sub_item_table[2].sub_item_table[2].sub_item_table
 assert(#rows==3 and rows[1].text=='封面' and rows[2].text=='评分' and rows[3].text=='豆瓣月榜')
 assert(api.menu().text=='InkFolio 设置')
end)
for _,id in ipairs({'classic','pixel','swiss'})do
 check(id..' masthead shares width with right-aligned date without reading status',function()
  choose(id)
  for _,page in ipairs({1,23,100})do
   ui.view.state.page=page;local paper,fields,size=render()
   local brand=assert(find(fields,'INKFOLIO'));local date=assert(find(fields,'2026.10.18'));local pos=positions(paper,size)
   assert(pos[brand].x==paper.padding_left and pos[date].x+date.width==size.width-paper.padding_right-paper.shadow_width and headerAligned(brand,date,pos))
   assert(not find(fields,'待读') and not find(fields,'在读') and not find(fields,'读完') and not find(fields,'电量'))
   paper:free()
  end
  ui.view.state.page=23
 end)
 check(id..' long book title uses the same two-line limit',function()
  choose(id);local title=ui.doc_props.title;local long=string.rep('长书名排版检查',15);ui.doc_props.title=long
  local paper,fields,size=render();ui.doc_props.title=title
  local found=false;for _,t in ipairs(fields)do if t.text:find('长书名排版检查',1,true)then
   found=true;assert(t.lines_per_page==2 and t.line_with_ellipsis==2)
  end end
  assert(found and size.height<Screen:getHeight());paper:free()
 end)
 check(id..' rendering never queries battery capacity',function()
  choose(id);local native=Device.getPowerDevice;Device.getPowerDevice=function()error('removed battery access')end
  local ok,paper=pcall(render);Device.getPowerDevice=native;assert(ok,paper);paper:free()
 end)
 check(id..' monthly rows fill content width with aligned measured columns',function()
  choose(id);local paper,fields,size=render();local pos=positions(paper,size)
  local first_title,first_author,first_rating
  local contentw=size.width-paper.padding_left-paper.padding_right-paper.shadow_width
  for _,item in ipairs(ink.monthlyItems())do
   local a,b,c=assert(find(fields,item.title)),assert(find(fields,item.author)),assert(find(fields,string.format('%.1f分',item.rating)))
   assert(pos[a].baseline==pos[b].baseline and pos[b].baseline==pos[c].baseline)
   assert(a.face==b.face and b.face==c.face and a.bold==b.bold and b.bold==c.bold)
   assert(a.lines_per_page==1 and b.lines_per_page==1 and c.lines_per_page==1)
   assert(pos[c].x+c.width==paper.padding_left+contentw)
   assert(pos[a].x+a.width<pos[b].x and pos[b].x+b.width<pos[c].x)
   if first_title then assert(pos[a].x==pos[first_title].x and pos[b].x==pos[first_author].x and pos[c].x==pos[first_rating].x)end
   first_title,first_author,first_rating=a,b,c
  end
  paper:free()
 end)
 check(id..' empty footer collapses while custom text keeps full width and wraps',function()
  choose(id);settings:delSetting(S.footer);local empty,fields,size=render();empty:free()
  settings:saveSetting(S.footer,'   ');local blank,_,bs=render();assert(bs.height==size.height);blank:free()
  local message=string.rep('自定义底部文字 ',15);settings:saveSetting(S.footer,message)
  local full,fs,sz=render();local footer=assert(find(fs,require('util').trim(message)))
  assert(footer.width==sz.width-full.padding_left-full.padding_right-full.shadow_width and footer.alignment=='left')
  assert(footer:getAllLineCount()>1 and not footer.height_overflow_show_ellipsis and sz.height>size.height)
  full:free();settings:delSetting(S.footer)
 end)
end
for _,id in ipairs({'classic','pixel','swiss'})do
 check(id..' shared auxiliary grayscale and primary text emphasis',function()
  choose(id);local paper,fields=render()
  assert(find(fields,'今日阅读') and not find(fields,'今日'))
  assert(find(fields,'已记录').fgcolor:getColor8().a==BB.COLOR_GRAY_3:getColor8().a)
  for _,t in ipairs(fields)do
   if t.text:find('日均',1,true)then assert(t.fgcolor:getColor8().a==BB.COLOR_GRAY_3:getColor8().a)end
  end
  assert(find(fields,'166%').fgcolor:getColor8().a==0)
  local date=find(fields,'2026.10.18');local amount
  for _,t in ipairs(fields)do if t.text:find('15.0万字',1,true)then amount=t end end
  assert(date.face==find(fields,'章节').face and date.face.size<amount.face.size and not date.bold and not amount.bold and find(fields,'166%').bold)
  if id=='pixel' then assert(date.face.realname==amount.face.realname and not amount.face.realname:find('InkfolioMatrix',1,true))end
  paper:free()
 end)
end
check('pixel card uses one font family for Chinese Latin digits units and chart axes',function()
 choose('pixel');local paper,fields,size=render();local family=Font:getFace('fusion-pixel-12px-proportional-zh_hans.otf',20).realname
 local pos=positions(paper,size)
 for _,t in ipairs(fields)do if pos[t] then
  assert(t.face.realname==family,'mixed pixel font: '..t.text)
  for _,c in ipairs(require('util').splitToChars(t.text))do
   if c~='\n' then assert(t.face.ftsize:hasGlyph(require('ffi/util').utf8charcode(c)),'pixel glyph missing: '..c)end
  end
 end end
 walk(paper,function(n)if getmetatable(n)==api.bars then assert(Font:getFace(n.theme.fonts.body,n.font_size).realname==family)end end)
 local amount
 for _,t in ipairs(fields)do if t.text:find('15.0万字',1,true)then amount=t end end
 assert(amount and amount.face.realname==find(fields,'166%').face.realname)
 assert(pos[amount].baseline==pos[find(fields,'166%')].baseline)
 assert(not ink.diagnosticContextText():find('InkfolioMatrix',1,true));paper:free()
end)
check('classic brand shares the book font while information uses one sans family',function()
 choose('classic');local paper,fields,size=render();local brand=find(fields,'INKFOLIO');local book=find(fields,ui.doc_props.title)
 local body=Font:getFace('cfont',20).realname
 assert(brand and book and brand.face.realname==book.face.realname and brand.face.realname~=body)
 local pos=positions(paper,size);local bold=Font:getBoldVariantName(body)
 for _,t in ipairs(fields)do if pos[t] and t~=brand and t~=book then assert(t.face.realname==body or t.face.realname==bold,'non-title serif: '..t.text)end end
 for _,c in ipairs(require('util').splitToChars('INKFOLIOInkFolio排版测试样书'))do
  assert(brand.face.ftsize:hasGlyph(require('ffi/util').utf8charcode(c)),'classic title glyph missing: '..c)
 end
 assert(not ink.diagnosticContextText():find('Cinzel',1,true));paper:free()
end)
for _,id in ipairs({'classic','pixel','swiss'})do
 check(id..' long legal goal wraps complete values left without reducing type',function()
  choose(id);local old=ink.goalConfig();local day=ink.wordState.days['2026-10-18'];local stats=settings:readSetting(S.stats);local monthly=settings:readSetting(S.intro)
  local ok,e=pcall(function()
   settings:saveSetting(S.stats,false);settings:saveSetting(S.intro,false)
   ink.wordState.days['2026-10-18']={words=9007199254740000}
   ink.setGoal('period','day');ink.setGoal('metric','words');ink.setGoal('target',1000);ink.setGoal('enabled',true)
   local paper,fields,size=render({width=.55,font=1.2,scale=.65,background='white',measure_only=true})
   local g=ink.goalSnapshot(ui,now);local title=assert(find(fields,g.title));local percent=assert(find(fields,string.format('%.0f%%',g.percent)))
   local amount=assert(find(fields,g.amount_text..' / '..g.target_text));local pos=positions(paper,size)
   assert(pos[title].x==paper.padding_left and pos[percent].x==paper.padding_left)
   assert(pos[percent].y>=pos[title].y+title:getSize().h and pos[percent].baseline==pos[amount].baseline)
   assert(amount.face.size==percent.face.size and not amount.height_overflow_show_ellipsis)
   assert(amount:getAllLineCount()>=1 and size.width<=Screen:getWidth() and size.height<Screen:getHeight())
   assert(pos[amount].x+amount.width<=size.width-paper.padding_right-paper.shadow_width and pos[amount].y+amount:getSize().h<pos[find(fields,'阅读进度')].y)
   local bb=BB.new(size.width,size.height,BB.TYPE_BB8);bb:fill(BB.COLOR_WHITE);paper:paintTo(bb,0,0)
   bb:writePNG(root..'checks/goal-wrap-'..id..'-'..Screen:getWidth()..'x'..Screen:getHeight()..'.png');bb:free();paper:free()
  end)
  ink.wordState.days['2026-10-18']=day;settings:saveSetting(S.stats,stats);settings:saveSetting(S.intro,monthly);ink.saveGoal(old);assert(ok,e)
 end)
 check(id..' unavailable goal preserves target while disabling collapses the block',function()
  choose(id);local old=ink.goalConfig();local error=ink.wordState.storage_error
  local ok,e=pcall(function()
   ink.setGoal('period','day');ink.setGoal('metric','words');ink.setGoal('target',25000);ink.setGoal('enabled',true)
   ink.wordState.storage_error='test unavailable word records'
   local paper,fields,size=render();assert(find(fields,'今日阅读目标') and find(fields,'目标 2.5万字') and find(fields,'—') and not find(fields,'0%'))
   assert(not find(fields,'日期') and find(fields,'2026.10.18'));paper:free()
   ink.setGoal('enabled',false);local off,fs,sz=render();assert(not find(fs,'今日阅读目标') and sz.height<=size.height)
   local pos=positions(off,sz);assert(headerAligned(find(fs,'INKFOLIO'),find(fs,'2026.10.18'),pos));off:free()
  end)
  ink.wordState.storage_error=error;ink.saveGoal(old);assert(ok,e)
 end)
end
for _,id in ipairs({'classic','pixel','swiss'})do
 check(id..' proportional cover variants align with target data and leave titles two lines',function()
  choose(id);local original_cover=ui.bookinfo.getCoverImage;local title,author=ui.doc_props.title,ui.doc_props.authors
  local ok,e=pcall(function()
   ui.doc_props.title=string.rep('阿加莎克里斯蒂侦探小说大全集',4);ui.doc_props.authors=string.rep('阿加莎克里斯蒂',3)
   for _,dims in ipairs({{160,220},{100,300},{200,200},{300,100},{16,22},{60,600}})do
    ui.bookinfo.getCoverImage=function()local bb=BB.new(dims[1],dims[2],BB.TYPE_BB8);bb:fill(BB.COLOR_GRAY_3);return bb end
    local paper,fields,size=render({width=.55,font=1.2,scale=.65,background='white',measure_only=true});local pos=positions(paper,size)
    local goal=assert(find(fields,'本月阅读目标'));local amount
    for _,t in ipairs(fields)do if t.text:find('15.0万字',1,true)then amount=t end end
    local images=0
    walk(paper,function(n)if getmetatable(n)==require('ui/widget/imagewidget')then
     images=images+1;local d=n.dimen
     assert(d.y+d.h==pos[amount].y+amount:getSize().h,'cover bottom not aligned')
     assert(math.abs(d.w*dims[2]-d.h*dims[1])<=dims[1]+dims[2],'cover distorted')
     local contentw=size.width-paper.padding_left-paper.padding_right-paper.shadow_width
     assert(d.w<=math.floor(contentw*.35) and d.x+d.w==size.width-paper.padding_right-paper.shadow_width)
     if dims[1]==160 and dims[2]==220 then
      local base=math.min(Screen:getWidth(),Screen:getHeight()*.75)
      local old_scale=math.min(.65*1.25,math.floor(contentw*.275)/160,math.floor(base*(4/3)*.175*.65)/220)
      assert(d.h>math.floor(220*old_scale),'portrait cover did not enlarge')
     end
     for _,t in ipairs(fields)do if pos[t] and pos[t].y>=pos[goal].y and pos[t].y<d.y+d.h then
      assert(pos[t].x+t.width<d.x,'goal overlaps cover')
     end end
    end end)
    assert(images==1);local book=assert(find(fields,ui.doc_props.title));assert(book.lines_per_page==2 and book.line_with_ellipsis==2)
    assert(find(fields,'作者') and size.height<Screen:getHeight())
    if dims[1]==160 or dims[1]==300 then
     local bb=BB.new(size.width,size.height,BB.TYPE_BB8);bb:fill(BB.COLOR_WHITE);paper:paintTo(bb,0,0)
     bb:writePNG(root..'checks/cover-'..dims[1]..'x'..dims[2]..'-'..id..'-'..Screen:getWidth()..'x'..Screen:getHeight()..'.png');bb:free()
    end
    paper:free()
   end
  end)
  ui.bookinfo.getCoverImage=original_cover;ui.doc_props.title,ui.doc_props.authors=title,author;assert(ok,e)
 end)
 check(id..' cover disabled or unavailable gives goal full width without an image placeholder',function()
  choose(id);local cover=settings:readSetting(S.cover);local original=ui.bookinfo.getCoverImage
  local ok,e=pcall(function()
   for _,enabled in ipairs({false,true})do
    settings:saveSetting(S.cover,enabled);ui.bookinfo.getCoverImage=function()return nil end
    local paper,fields,size=render();local pos=positions(paper,size);local title=assert(find(fields,'本月阅读目标'));local percent=assert(find(fields,'166%'))
    local images=0;walk(paper,function(n)if getmetatable(n)==require('ui/widget/imagewidget')then images=images+1 end end)
    assert(images==0 and pos[title].x==paper.padding_left and pos[percent].x==paper.padding_left)
    assert(pos[percent].y>=pos[title].y+title:getSize().h)
    local amount;for _,t in ipairs(fields)do if t.text:find('15.0万字',1,true)then amount=t end end
    assert(pos[amount].x+amount.width==size.width-paper.padding_right-paper.shadow_width);paper:free()
   end
  end)
  settings:saveSetting(S.cover,cover);ui.bookinfo.getCoverImage=original;assert(ok,e)
 end)
end
for _,id in ipairs({'classic','pixel','swiss'})do
 check(id..' book title grows ten percent and cycle titles remain four characters',function()
  choose(id);local before=settings:readSetting(S.summary)
  local ok,e=pcall(function()
   assert(ink.uiStyle().type.book.size==55)
   settings:saveSetting(S.summary,{'global_week','global_month'})
   local paper,fields,size=render();local week=assert(find(fields,'本周阅读'));local month=assert(find(fields,'本月阅读'));local pos=positions(paper,size)
   assert(not find(fields,'本周') and not find(fields,'本月'))
   assert(week.face==month.face and week.bold==month.bold and week.width==month.width)
   assert(week:getAllLineCount()==1 and month:getAllLineCount()==1 and pos[week].baseline==pos[month].baseline)
   local diag=ink.diagnosticContextText();assert(diag:find('摘要组合：本周阅读、本月阅读',1,true));paper:free()
  end)
  settings:saveSetting(S.summary,before);assert(ok,e)
 end)
end
check('already built surfaces retain their own style after a later selection',function()
 choose('pixel');local paper=render();choose('swiss');assert(paper.theme.id=='pixel')
 local bb=BB.new(paper:getSize().w,paper:getSize().h,BB.TYPE_BB8);bb:fill(BB.COLOR_WHITE);paper:paintTo(bb,0,0);bb:free();paper:free()
end)
for _,id in ipairs({'classic','pixel','swiss'})do for _,background in ipairs({'black','white'})do
 check('native full-screen preview '..id..' '..background,function()
  choose(id);local appearance={width=.84,font=1,scale=.72,background=background}
  local widget,valid=api.build(ui,ui.view.state,appearance);assert(valid)
  local bb=BB.new(Screen:getWidth(),Screen:getHeight(),BB.TYPE_BB8);bb:fill(background=='black' and BB.COLOR_BLACK or BB.COLOR_WHITE);widget:paintTo(bb,0,0)
  bb:writePNG(root..'checks/preview-'..id..'-'..background..'-'..Screen:getWidth()..'x'..Screen:getHeight()..'.png')
  bb:free();widget:free()
 end)
end end
check('rendering and previews never advance monthly rotation or start network work',function()
 assert(functionState()==data_before and savedSettings()==settings_before)
end)
for _,id in ipairs({'classic','pixel','swiss'})do
 check('native appearance editor previews '..id..' without changing saved choices',function()
  choose(id);settings:saveSetting(S.width,.84);settings:saveSetting(S.font,1);settings:saveSetting(S.scale,.65);settings:saveSetting(S.background,'black')
  local before=savedSettings();local editor=api.editor:new{ui=ui};assert(editor.valid)
  editor:change('font',1.05);editor:refreshPreview();assert(editor.valid and ink.uiStyle().id==id)
  editor:onCloseWidget();assert(savedSettings()==before)
 end)
end
local function paintEditor(editor,name)
 local bb=BB.new(Screen:getWidth(),Screen:getHeight(),BB.TYPE_BB8);bb:fill(BB.COLOR_WHITE)
 editor:paintTo(bb,0,0);assert(editor:getSize().w<=Screen:getWidth() and editor:getSize().h<=Screen:getHeight())
 bb:writePNG(root..'checks/'..name..'-'..Screen:getWidth()..'x'..Screen:getHeight()..'.png');bb:free()
end
for _,spec in ipairs(ink.APPEARANCE_NUMBERS)do
 check('manual '..spec.key..' validates exact range and fractional percentages',function()
  assert(ink.parseAppearanceNumber(tostring(spec.min),spec)==spec.min/100)
  assert(ink.parseAppearanceNumber(tostring(spec.max),spec)==spec.max/100)
  assert(ink.parseAppearanceNumber(tostring(spec.min+.5),spec)==(spec.min+.5)/100)
  for _,invalid in ipairs({'', 'abc','nan','1e2','80.55','80%','-1',tostring(spec.min-1),tostring(spec.max+.1)})do
   local value,reason=ink.parseAppearanceNumber(invalid,spec);assert(value==nil and reason)
  end
 end)
end
check('percentage display preserves one decimal instead of rounding away manual input',function()
 assert(ink.appearancePercent(.845)=='84.5%' and ink.appearancePercent(.8)=='80%')
end)
settings:saveSetting('virtual_keyboard_enabled',true)
for _,id in ipairs({'classic','pixel','swiss'})do
 check('appearance switching previews all skins and cancel discards all changes from '..id,function()
  choose(id);local before=encoded(settings.data);local data=functionState();local editor=api.editor:new{ui=ui};UI:show(editor)
  for _,target in ipairs({'classic','pixel','swiss'})do
   assert(editor:selectStyle(target));assert(editor.valid and editor.draft.ui_style==target and ink.uiStyle().id==id)
   paintEditor(editor,'appearance-'..target)
  end
  assert(functionState()==data and encoded(settings.data)==before)
  editor:onCancel();assert(editor.closed and encoded(settings.data)==before)
 end)
 for _,spec in ipairs(ink.APPEARANCE_NUMBERS)do
  check(id..' native manual '..spec.key..' applies to preview only',function()
   choose(id);local editor=api.editor:new{ui=ui};UI:show(editor);local before=savedSettings()..tostring(settings:readSetting(S.ui_style))
   editor:editNumber(spec);local dialog=assert(editor.number_dialog)
   local ei,di;for i,entry in ipairs(UI._window_stack)do if entry.widget==editor then ei=i end;if entry.widget==dialog then di=i end end
   assert(ei and di and di>ei,'input dialog must be above the modal appearance editor')
   assert(dialog.title==spec.label..'（%）' and dialog:getInputText()==ink.appearancePercent(editor.draft[spec.key]):gsub('%%$',''))
   -- Keep dimensions inside the verified layout while testing fractional input.
   if id=='pixel' and spec.key=='width' then
    local bb=BB.new(Screen:getWidth(),Screen:getHeight(),BB.TYPE_BB8);bb:fill(BB.COLOR_WHITE)
    for i,entry in ipairs(UI._window_stack)do
     entry.widget:paintTo(bb,entry.x,entry.y)
    end
    bb:writePNG(root..'checks/number-input-'..Screen:getWidth()..'x'..Screen:getHeight()..'.png');bb:free()
   end
   local number=spec.key=='width' and '84.5' or spec.key=='font' and '100.5' or '65.5'
   dialog:setInputText(number);dialog.buttons[1][2].callback()
   assert(editor.number_dialog==nil and editor.draft[spec.key]==tonumber(number)/100 and editor.valid)
   assert(savedSettings()..tostring(settings:readSetting(S.ui_style))==before)
   if spec.key=='width' then paintEditor(editor,'appearance-manual-'..id)end
   editor:onCancel();assert(editor.closed and savedSettings()..tostring(settings:readSetting(S.ui_style))==before)
  end)
 end
end
check('invalid manual input keeps editor and dialog open without changing the draft',function()
 local editor=api.editor:new{ui=ui};UI:show(editor);local before=encoded(editor.draft)
 editor:editNumber(ink.APPEARANCE_NUMBERS[1]);local dialog=editor.number_dialog
 local message=ink.message;local reason;ink.message=function(text)reason=text end
 dialog:setInputText('900');dialog.buttons[1][2].callback();ink.message=message
 assert(reason and editor.number_dialog==dialog and encoded(editor.draft)==before)
 dialog.buttons[1][1].callback();assert(not editor.number_dialog and not editor.closed)
 editor:onCancel()
end)
check('missing preview font rejects the selected style without a fallback',function()
 choose('swiss');local editor=api.editor:new{ui=ui};local before=encoded(editor.draft)
 local native,message=Font.getFace,ink.message;local reason
 Font.getFace=function(self,name,...)if name=='fusion-pixel-12px-proportional-zh_hans.otf'then return nil end;return native(self,name,...)end
 ink.message=function(text)reason=text end
 local ok,result=pcall(editor.selectStyle,editor,'pixel');Font.getFace=native;ink.message=message
 assert(ok and not result and reason and encoded(editor.draft)==before and ink.uiStyle().id=='swiss')
 editor:onCloseWidget()
end)
check('saving commits style and appearance together and survives reopening settings',function()
 choose('classic');local editor=api.editor:new{ui=ui};UI:show(editor)
 assert(editor:selectStyle('pixel'));editor:change('width',.845);editor:change('font',1.005);editor:change('scale',.655);editor:change('background','white');editor:refreshPreview()
 assert(editor.valid);editor:save();assert(editor.closed)
 local saved=require('luasettings'):open(os.getenv('KO_HOME')..'/settings.reader.lua')
 assert(saved:readSetting(S.ui_style)=='pixel' and saved:readSetting(S.width)==.845 and saved:readSetting(S.font)==1.005 and saved:readSetting(S.scale)==.655 and saved:readSetting(S.background)=='white' and saved:readSetting(S.auto_fit)==false)
end)
check('failed appearance persistence restores every setting without a partial style change',function()
 local before=encoded(settings.data);local native=settings.flush;settings.flush=function()error('write denied')end
 local ok=pcall(ink.persistSettings,{[S.ui_style]='swiss',[S.width]=.8,[S.font]=1.1,[S.auto_fit]=true})
 settings.flush=native;assert(not ok and encoded(settings.data)==before)
end)
check('suspend closes the numeric keyboard and returns without saving drafts',function()
 local before=encoded(settings.data);local editor=api.editor:new{ui=ui};UI:show(editor)
 editor:editNumber(ink.APPEARANCE_NUMBERS[1]);local dialog=editor.number_dialog
 assert(dialog);editor:onSuspend();assert(editor.closed and not editor.number_dialog and encoded(settings.data)==before)
end)
check('out-of-screen draft disables save without changing persisted settings',function()
 local before=encoded(settings.data);local editor=api.editor:new{ui=ui};UI:show(editor)
 editor:change('width',.9);editor:change('font',1.2);editor:change('scale',1.5);editor:refreshPreview()
 assert(not editor.valid);editor:save();assert(not editor.closed and encoded(settings.data)==before)
 editor:onCancel()
end)
check('numeric buttons use the same bounds as manual input at every endpoint',function()
 local editor=api.editor:new{ui=ui}
 for i,spec in ipairs(ink.APPEARANCE_NUMBERS)do
  for _,limit in ipairs({spec.min,spec.max})do
   editor.draft[spec.key]=limit/100;editor:refreshPreview()
   local row=editor.controls.buttons[i+1]
   assert(row[1].enabled==(limit>spec.min) and row[3].enabled==(limit<spec.max) and row[2].callback)
  end
  editor.draft[spec.key]=(spec.key=='width' and .84 or spec.key=='font' and 1 or .65)
 end
 editor:onCloseWidget()
end)
check('unexpected preview errors remain visible and invalidate the previous save state',function()
 local editor=api.editor:new{ui=ui};assert(editor.valid)
 local native=Font.getFace;Font.getFace=function()error('test rendering failure')end
 local ok=pcall(editor.refreshPreview,editor);Font.getFace=native
 assert(not ok and not editor.valid);editor:onCloseWidget()
end)
check('silent native write failure is detected by reading actual saved settings',function()
 local before=encoded(settings.data);local native=settings.flush;settings.flush=function()return settings end
 local ok,reason=pcall(ink.persistSettings,{[S.ui_style]='swiss',[S.width]=.7})
 settings.flush=native;assert(not ok and tostring(reason):find('保存',1,true) and encoded(settings.data)==before)
end)
check('About and changelog show the current public name and pending revision',function()
 local native=UI.show;local viewer
 UI.show=function(_,w)viewer=w end
 local ok,e=pcall(api.menu().sub_item_table[8].callback);UI.show=native;assert(ok,e)
 assert(viewer.title=='关于 InkFolio' and viewer.text:find('InkFolio',1,true) and not viewer.text:find('墨笺',1,true))
 assert(not viewer.text:find('扫码',1,true) and not viewer.text:find('二维码',1,true))
 local out=assert(io.open(root..'checks/about-preview.txt','w'));out:write(viewer.text);out:close()
 local bb=BB.new(Screen:getWidth(),Screen:getHeight(),BB.TYPE_BB8);bb:fill(BB.COLOR_WHITE)
 viewer:paintTo(bb,0,0);bb:writePNG(root..'checks/about-'..Screen:getWidth()..'x'..Screen:getHeight()..'.png');bb:free();viewer:free()
 UI.show=function(_,w)viewer=w end;ok,e=pcall(ink.showChangelog);UI.show=native;assert(ok,e)
 assert(viewer.title=='更新日志' and viewer.text:find('尚未发布',1,true) and not viewer.text:find('墨笺',1,true))
 out=assert(io.open(root..'checks/changelog-preview.txt','w'));out:write(viewer.text);out:close()
 bb=BB.new(Screen:getWidth(),Screen:getHeight(),BB.TYPE_BB8);bb:fill(BB.COLOR_WHITE)
 viewer:paintTo(bb,0,0);bb:writePNG(root..'checks/changelog-'..Screen:getWidth()..'x'..Screen:getHeight()..'.png');bb:free();viewer:free()
end)
for _,id in ipairs({'classic','pixel','swiss'})do
 check(id..' metric options are exclusive native radio choices',function()
  choose(id)
  local metric_before=ink.summaryMetric()
  local summary=api.menu().sub_item_table[2].sub_item_table[4].sub_item_table
  local options
  for _,row in ipairs(summary)do if row.text=='周期摘要指标' then options=row.sub_item_table end end
  assert(options and #options==2)
  for _,option in ipairs(options)do
   assert(option.radio);option.callback()
   local checked=0
   for _,candidate in ipairs(options)do if candidate.checked_func()then checked=checked+1 end end
   assert(checked==1 and option.checked_func())
  end
  settings:saveSetting(S.summary_metric,metric_before)
 end)
 check(id..' native appearance selection marks preview only and cancellation keeps settings',function()
  choose(id);local before=encoded(settings.data)
  local editor=api.editor:new{ui=ui};UI:show(editor)
  local function verify(row,selected)
   local count=0
   for i=2,4 do
    assert(row[i].checked_func and not row[i].text:find('[',1,true))
    if row[i].checked_func()then count=count+1;assert(row[i].text==selected)end
   end
   assert(count==1)
  end
  local controls=editor.controls
  verify(controls.buttons[1],ink.uiStyle().label)
  local target=id=='pixel' and 'swiss' or 'pixel'
  assert(editor:selectStyle(target));editor:change('background','white');editor:refreshPreview()
  controls=editor.controls
  verify(controls.buttons[1],target=='pixel' and '像素' or '现代')
  verify(controls.buttons[5],'白色')
  assert(encoded(settings.data)==before)
  editor:onCancel();assert(editor.closed and encoded(settings.data)==before)
 end)
end

for _,id in ipairs({'classic','pixel','swiss'})do
 for _,selection in ipairs({{true,false},{false,true},{true,true},{false,false}})do
  for _,show_date in ipairs({true,false})do
   check(id..' full receipt with independently selected forecast days '..tostring(selection[1])..tostring(selection[2])..tostring(show_date),function()
    choose(id);settings:saveSetting(S.weather,selection[1]);settings:saveSetting(S.weather_tomorrow,selection[2]);settings:saveSetting(S.date,show_date)
    local paper,fields,size=render({width=.84,font=1,scale=.65,background='white',measure_only=true})
    assert(size.width<=Screen:getWidth() and size.height<Screen:getHeight())
    positions(paper,size);paper:free()
    local full,valid=api.build(ui,ui.view.state,{width=.84,font=1,scale=.65,background='white'});assert(valid);full:free()
   end)
  end
 end
end
print('THEMES_PASS '..passed..' / FAIL '..failed);os.exit(failed==0 and 0 or 1)
