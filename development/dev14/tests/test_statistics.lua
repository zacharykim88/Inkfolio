require('setupkoenv');G_defaults=require('luadefaults'):open()
G_reader_settings=require('luasettings'):open(os.getenv('KO_HOME')..'/settings.reader.lua')
local settings=G_reader_settings
local Device=require('device');require('document/canvascontext'):init(Device)
local Screen=Device.screen;local UI=require('ui/uimanager');local BB=require('ffi/blitbuffer')
local root=assert(arg[0]:match('^(.*)/tests/[^/]+$'))..'/'
local f=assert(io.open(root..'2-inkfolio.lua'));local source=f:read('*a');f:close()
local api=assert(loadstring(source..[[
return {ink=Inkfolio,S=S,summary=summaryItems,items=SUMMARY_ITEMS,render=renderReceipt,build=buildReceipt,menu=receiptSettingsMenu,
 home=homeReceiptContext,store=store,remember=rememberReceipt}
]]))()
local ink,S=api.ink,api.S
if os.getenv('INK_STYLE') then settings:saveSetting(S.ui_style,os.getenv('INK_STYLE')) end
local passed,failed=0,0
local function check(name,fn)local ok,e=pcall(fn);if ok then passed=passed+1;print('PASS',name)else failed=failed+1;print('FAIL',name,e)end end
local function item(id)for _,v in ipairs(api.items)do if v.id==id then return v end end;error(id)end
local function choose(ids,metric)settings:saveSetting(S.summary,ids);settings:saveSetting(S.charts,{});settings:saveSetting(S.stats,true);settings:saveSetting(S.summary_metric,metric or 'words');ink.setGoal('enabled',false)end
check('first installation has only global today and words',function()
 assert(#api.summary()==1 and api.summary()[1].id=='global_today' and ink.summaryMetric()=='words' and #ink.chartItems()==0)
end)
settings:saveSetting(S.online,false)
local now=os.time{year=2026,month=10,day=19,hour=12,min=0,sec=0}
local function stamp(month,day,hour,min)return os.time{year=2026,month=month,day=day,hour=hour or 12,min=min or 0,sec=0}end
local SQ=require('lua-ljsqlite3/init');local ds=require('datastorage')
local db=SQ.open(ds:getSettingsDir()..'/statistics.sqlite3')
db:exec('CREATE TABLE book(id INTEGER PRIMARY KEY,pages INTEGER);INSERT INTO book VALUES(1,100),(2,200),(3,100);')
db:exec('CREATE TABLE page_stat_data(id_book INTEGER,page INTEGER,start_time INTEGER,duration INTEGER,total_pages INTEGER);')
-- Native view rescales pages after a font/layout change; use the actual KOReader schema.
local nf=assert(io.open(assert(os.getenv('KOREADER_RUNTIME'))..'/plugins/statistics.koplugin/main.lua'));local ns=nf:read('*a');nf:close()
local schema=assert(ns:match('local STATISTICS_DB_PAGE_STAT_VIEW_SCHEMA = %[%[(.-)%]%]'));db:exec(schema)
local rows={{1,1,stamp(9,15),3600,100},{1,2,stamp(10,1),1200,100},{1,3,stamp(10,18,23,30),3600,100},
 {1,4,stamp(10,19,9),600,100},{2,1,stamp(10,19,10),1200,100},{1,4,stamp(10,19,11),300,100}}
for _,r in ipairs(rows)do db:exec(string.format('INSERT INTO page_stat_data VALUES(%d,%d,%d,%d,%d);',unpack(r)))end;db:close()
local flushes=0
local ui={document={file='stats.epub',getPageCount=function()return 100 end},doc_props={title='统计测试',authors='示例作者'},
 view={state={page=25}},doc_settings={data={doc_pages=100}},
 statistics={id_curr_book=1,avg_time=30,isEnabled=function()return true end,insertDB=function()flushes=flushes+1 end},
 toc={getTocTitleByPage=function()return '第一章'end}}
ink.wordState.tracking_since=stamp(10,12,0);ink.wordState.days={}
for day=12,19 do if day~=14 then ink.wordState.days[os.date('%Y-%m-%d',stamp(10,day))]={words=day==19 and 12345 or 1000,incomplete=day==12}end end
local function data(id,context)choose({id});return ink.summaryData(ink.statisticsSnapshot(context or ui,now),item(id))end
check('today summary uses global time including crossing midnight',function()local v=data('global_today');assert(v.time==3900 and v.amount==12345 and v.metric=='words')end)
check('weekly boundary starts Monday and agrees with daily today',function()local v=data('global_week');assert(v.time==3900 and v.amount==12345 and not v.incomplete)end)
check('monthly summary includes older native time but only recorded words',function()local v=data('global_month');assert(v.time==6900 and v.amount==18345 and v.incomplete)end)
check('book cumulative includes records before plugin installation',function()local v=data('book_total');assert(v.time==9300 and v.amount==4 and v.metric=='pages')end)
check('global cumulative preserves native page rescaling and deduplication',function()local v=data('global_total');assert(v.time==10500 and v.amount==6 and v.metric=='pages')end)
check('legacy book today remains scoped and page-based',function()local v=data('book_today');assert(v.time==2700 and v.amount==2 and v.metric=='pages')end)
check('period pages are optional and count overlapping records once',function()choose({'global_today'},'pages');local v=ink.summaryData(ink.statisticsSnapshot(ui,now),item('global_today'));assert(v.time==3900 and v.amount==4 and v.metric=='pages')end)
check('native statistics are flushed once for selected summaries charts and goal',function()
 choose({'global_today','global_month'});settings:saveSetting(S.charts,{'week','month'});ink.setGoal('period','month');ink.setGoal('metric','time');ink.setGoal('target',7200);ink.setGoal('enabled',true)
 local before=flushes;local snap=ink.statisticsSnapshot(ui,now)
 local day=ink.summaryData(snap,item('global_today'));local month=ink.summaryData(snap,item('global_month'))
 local curve=snap:time('month');local goal=ink.goalSnapshot(ui,now,snap)
 assert(day.time==3900 and month.time==curve.total and goal.amount==month.time and flushes==before+1)
 assert(snap:time('month')==curve)
end)
check('words are shared between summary chart and goal',function()
 choose({'global_month'});ink.setGoal('period','month');ink.setGoal('metric','words');ink.setGoal('target',20000);ink.setGoal('enabled',true)
 local snap=ink.statisticsSnapshot(ui,now);local v=ink.summaryData(snap,item('global_month'));local c=snap:words('month');local goal=ink.goalSnapshot(ui,now,snap)
 assert(v.amount==c.total and goal.amount==v.amount and goal.percent==91 and snap:words('month')==c)
end)
check('missing current book id does not suppress global data',function()
 choose({'book_total','global_today'});local context={statistics={isEnabled=function()return true end}}
 local snap=ink.statisticsSnapshot(context,now);local a=ink.summaryData(snap,item('book_total'));local b=ink.summaryData(snap,item('global_today'))
 assert(a.time==nil and a.amount==nil and b.time==3900 and b.amount==12345 and snap.statuses['本书累计'])
end)
check('disabled native statistics leave independent words visible',function()
 choose({'global_today'});local snap=ink.statisticsSnapshot({statistics={isEnabled=function()return false end}},now);local v=ink.summaryData(snap,item('global_today'))
 assert(v.time==nil and v.amount==12345 and snap.statuses['今日阅读时长']:find('开启'))
end)
check('empty book record is unknown instead of numeric zero',function()
 local context={statistics={id_curr_book=3,isEnabled=function()return true end}};local v=data('book_total',context);assert(v.time==nil and v.amount==nil)
end)
check('explicit native zero remains confirmed zero',function()
 local d=SQ.open(ds:getSettingsDir()..'/statistics.sqlite3');d:exec(string.format('INSERT INTO page_stat_data VALUES(3,1,%d,0,100);',stamp(10,19,11)));d:close()
 local context={statistics={id_curr_book=3,isEnabled=function()return true end}};local v=data('book_today',context);assert(v.time==0 and v.amount==1)
end)
check('empty word date is unknown and explicit word zero is preserved',function()
 local original=ink.wordState.days['2026-10-19'];ink.wordState.days['2026-10-19']=nil;local v=data('global_today');assert(v.amount==nil)
 ink.wordState.days['2026-10-19']={words=0};v=data('global_today');assert(v.amount==0);ink.wordState.days['2026-10-19']=original
end)
check('word storage failure is visible in settings without corrupting time',function()
 ink.wordState.storage_error='测试字数记录损坏';local v=data('global_today');assert(v.time==3900 and v.amount==nil)
 ink.wordState.storage_error=nil
end)
check('native query failure is recorded and never converted to zero',function()
 choose({'global_today'});local exec=SQ.open;SQ.open=function()return {exec=function()error('simulated sqlite error')end,close=function()end}end
 local snap=ink.statisticsSnapshot(ui,now);local ok,v=pcall(ink.summaryData,snap,item('global_today'));SQ.open=exec
 assert(ok and v.time==nil and v.amount==12345 and snap.statuses['今日阅读时长']:find('失败'))
end)
check('month and week boundaries handle leap dates',function()
 local t=os.time{year=2028,month=2,day=29,hour=12};local month=ink.periodDays('month',t);local week=ink.periodDays('week',t)
 assert(#month==29 and #week==7 and os.date('%w',week[1].start)=='1')
end)
check('days without records remain distinct from future dates and zero',function()
 local c=ink.readCurve(ui,'month',now);assert(c.days[2].seconds==nil and c.days[20].future and c.days[20].seconds==nil)
end)
check('old summary selection is preserved by initialization',function()
 settings:saveSetting(S.summary,{'book_today','global_total'});settings:saveSetting(S.summary_metric,'pages');ink.initializeDefaults(true)
 assert(#api.summary()==2 and api.summary()[1].id=='book_today' and ink.summaryMetric()=='pages')
end)
local function summaryMenu()return api.menu().sub_item_table[2].sub_item_table[4].sub_item_table end
local function find(rows,text)for _,r in ipairs(rows)do if r.text==text then return r end end end
local function summaryChoices()return assert(find(summaryMenu(),'摘要内容（最多2项）')).sub_item_table end
check('legacy book today can be removed and is then hidden',function()
 local row=assert(find(summaryChoices(),'本书今日（旧设置）'));row.callback();assert(not find(summaryChoices(),'本书今日（旧设置）') and #api.summary()==1)
end)
check('new selections stay limited to two independently of charts',function()
 choose({'global_today'});local rows=summaryMenu();local choices=summaryChoices();find(choices,'全局本周阅读').callback();assert(#api.summary()==2 and not find(choices,'全局本月阅读').enabled_func())
 find(choices,'全局本月阅读').callback();assert(#api.summary()==2)
 local trends=find(rows,'阅读图表（最多2项）').sub_item_table;trends[1].callback();trends[2].callback();trends[3].callback();assert(#ink.chartItems()==2 and #api.summary()==2)
end)
check('secondary metric is one explicit choice',function()
 choose({'global_today'});local rows=find(summaryMenu(),'周期摘要指标').sub_item_table
 assert(rows[1].checked_func() and not rows[2].checked_func());rows[2].callback();assert(not rows[1].checked_func() and rows[2].checked_func())
end)
check('statistics help centralizes methodology and legend',function()
 local text=ink.statisticsText();assert(text:find('安装前',1,true) and text:find('同次唤醒',1,true) and text:find('斜线',1,true) and text:find('日均',1,true))
end)
check('statistics help closes back to parent menu',function()
 local shown,show=UI.show;UI.show=function(_,v)shown=v end
 local updates=0;ink.showStatisticsHelp({updateItems=function()updates=updates+1 end});UI.show=show
 assert(shown.title=='统计说明');shown:onCloseWidget();assert(updates==1);shown:free()
end)
check('homepage snapshot retains book statistics and current global data',function()
 choose({'book_total','global_today'})
 local path=os.getenv('KO_HOME')..'/history.epub';local f=assert(io.open(path,'w'));f:write('fixture');f:close()
 local old=ui.document.file;ui.document.file=path;api.remember(ui);settings:saveSetting('lastfile',path)
 local home=assert(api.home());local before=flushes;local snap=ink.statisticsSnapshot(home,now)
 local a=ink.summaryData(snap,item('book_total'));local b=ink.summaryData(snap,item('global_today'))
 assert(a.time==9300 and a.amount==4 and b.time==3900 and b.amount==12345 and flushes==before)
 ui.document.file=old
end)
check('native save failure is reported while words remain independent',function()
 choose({'global_today'});local context={statistics={isEnabled=function()return true end,insertDB=function()error('write failed')end}}
 local snap=ink.statisticsSnapshot(context,now);local v=ink.summaryData(snap,item('global_today'))
 assert(v.time==nil and v.amount==12345 and snap.statuses['今日阅读时长']:find('保存失败',1,true))
end)
check('unavailable native database never becomes zero',function()
 choose({'global_today'});local path=ds:getSettingsDir()..'/statistics.sqlite3';assert(os.rename(path,path..'.hold'))
 local snap=ink.statisticsSnapshot(ui,now);local ok,v=pcall(ink.summaryData,snap,item('global_today'));assert(os.rename(path..'.hold',path))
 assert(ok and v.time==nil and v.amount==12345 and snap.statuses['今日阅读时长']:find('数据库',1,true))
end)
check('empty month has no recorded marker or invented totals',function()
 choose({'global_month'});local t=os.time{year=2026,month=8,day=19,hour=12}
 local v=ink.summaryData(ink.statisticsSnapshot(ui,t),item('global_month'));assert(v.time==nil and v.amount==nil and not v.incomplete)
end)
check('a page query failure leaves the time result intact',function()
 choose({'global_today'},'pages');local snap=ink.statisticsSnapshot(ui,now);assert(snap:time('day'))
 local native=SQ.open;SQ.open=function()return {rowexec=function()error('page query failure')end,close=function()end}end
 local ok,v=pcall(ink.summaryData,snap,item('global_today'));SQ.open=native
 assert(ok and v.time==3900 and v.amount==nil and snap.statuses['今日阅读页数']:find('失败',1,true))
end)
check('invalid secondary metric fails visibly',function()
 settings:saveSetting(S.summary_metric,'invalid');assert(not pcall(ink.summaryMetric));settings:saveSetting(S.summary_metric,'words')
end)
-- Render with fixed clock and real snapshot functions; avoid ReaderUI fake text observations.
local snapshot=ink.statisticsSnapshot;ink.statisticsSnapshot=function(context)return snapshot(context,now)end
settings:saveSetting(S.auto_fit,false);settings:saveSetting(S.cover,false);settings:saveSetting(S.intro,false)
settings:saveSetting(S.word_book,false);settings:saveSetting(S.word_session,false);settings:saveSetting(S.remain,true)
local Text=require('ui/widget/textboxwidget');local H=require('ui/widget/horizontalgroup')
local function render(options)
 local fields={};local native=Text.new;Text.new=function(self,args)local t=native(self,args);fields[#fields+1]=t;return t end
 local ok,w,valid,size=pcall(api.render,ui,ui.view.state,options or {width=.84,font=1,scale=.65,background='white',measure_only=true});Text.new=native
 assert(ok,w);assert(valid);return w,fields,size
end
local function text(fields,value)for _,v in ipairs(fields)do if v.text==value then return v end end end
local combos={{'global_today'},{'global_week','global_month'},{'book_total','global_month'},{'global_today','global_total'},{'book_today','global_today'}}
for _,ids in ipairs(combos)do check('native summary combination '..table.concat(ids,'+'),function()
 choose(ids);settings:saveSetting(S.charts,{'week','month_words'});local w,fs,size=render()
 assert(size.width<=Screen:getWidth() and size.height<Screen:getHeight());assert(text(fs,'2026.10.19'));assert(text(fs,'当前页码') and not text(fs,'已读页数'))
 for _,v in ipairs(fs)do assert(not v.text:find('短横：',1,true) and not v.text:find('无记录%d天') and not v.text:find('记录不完整',1,true))end
 local bb=BB.new(size.width,size.height,BB.TYPE_BB8);bb:fill(BB.COLOR_WHITE);w:paintTo(bb,0,0)
 if ids[1]=='global_week' then bb:writePNG(root..'checks/statistics-'..Screen:getWidth()..'x'..Screen:getHeight()..'-'..(os.getenv('INK_STYLE') or 'classic')..'.png')end
 bb:free();w:free()
end)end
check('new summary metrics have consistent fonts and equal columns',function()
 choose({'global_week','global_month'});local w,fs=render();assert(text(fs,'本周阅读').face==text(fs,'本月阅读').face and text(fs,'本周阅读').width==text(fs,'本月阅读').width)
 local fonts={};for _,v in ipairs(fs)do if v.text=='字数' or v.text=='时长' then fonts[#fonts+1]=v.face;assert(not v.bold)end end
 assert(#fonts==4);for _,face in ipairs(fonts)do assert(face==fonts[1])end;w:free()
end)
check('compact goal and unavailable values keep reasons in settings',function()
 choose({'global_today'});ink.setGoal('period','month');ink.setGoal('metric','words');ink.setGoal('target',20000);ink.setGoal('enabled',true)
 local w,fs=render();local found=false;for _,v in ipairs(fs)do if v.text:find('91%',1,true) then found=true end end;assert(found);for _,v in ipairs(fs)do assert(not v.text:find('记录不完整',1,true))end
 assert(ink.statisticsText():find('记录不完整',1,true));w:free()
end)
check('summary menu has five clear groups and explicit scope names',function()
 choose({'global_today'});local rows=summaryMenu();assert(#rows==5 and rows[1].text=='显示阅读摘要')
 local choices=summaryChoices();assert(find(choices,'全局今日阅读') and find(choices,'全局本周阅读') and find(choices,'全局本月阅读'))
 assert(find(rows,'摘要内容（最多2项）').help_text:find('取消',1,true))
 assert(find(rows,'周期摘要指标').text_func()=='周期摘要：时长＋字数')
 assert(find(rows,'周期摘要指标').sub_item_table[1].text=='时长＋字数')
 assert(find(rows,'阅读图表（最多2项）') and find(rows,'统计说明'))
end)
check('native grouped summary menu paints and returns to each parent',function()
 choose({'global_today'});local show=UI.show;local container;UI.show=function(_,v)container=v end
 local ok,e=pcall(ink.settings);UI.show=show;assert(ok,e);local menu=container[1]
 menu:onMenuSelect(find(menu.item_table,'显示内容'))
 menu:onMenuSelect(find(menu.item_table,'阅读摘要'))
 assert(#menu.item_table==5 and #menu.item_table_stack==2)
 local bb=BB.new(Screen:getWidth(),Screen:getHeight(),BB.TYPE_BB8);bb:fill(BB.COLOR_WHITE);container:paintTo(bb,0,0)
 bb:writePNG(root..'checks/summary-menu-'..Screen:getWidth()..'x'..Screen:getHeight()..'-'..(os.getenv('INK_STYLE') or 'classic')..'.png');bb:free()
 for _,name in ipairs({'摘要内容（最多2项）','周期摘要指标','阅读图表（最多2项）'})do
  menu:onMenuSelect(find(menu.item_table,name));assert(#menu.item_table_stack==3)
  if name=='周期摘要指标' then menu:onMenuSelect(menu.item_table[2]);assert(ink.summaryMetric()=='pages')end
  menu:backToUpperMenu(true);assert(#menu.item_table==5 and #menu.item_table_stack==2)
 end
 menu:backToUpperMenu(true);assert(find(menu.item_table,'阅读摘要'));container:free()
end)
-- Validate rendered coordinates, not only container construction.
local function firstText(node)
 if node and node.getBaseline and node.text then return node end
 if node and node[2] and node[2].text and node[1] and not node[1].text then return node[2] end
end
local function walk(node,fn)fn(node);for _,child in ipairs(node)do walk(child,fn)end end
local function paintPositions(w,size)
 local native=Text.paintTo;local positions={}
 Text.paintTo=function(self,bb,x,y)positions[self]={x=x,y=y,baseline=y+self:getBaseline()};return native(self,bb,x,y)end
 local bb=BB.new(size.width,size.height,BB.TYPE_BB8);bb:fill(BB.COLOR_WHITE)
 local ok,e=pcall(w.paintTo,w,bb,0,0);Text.paintTo=native;bb:free();assert(ok,e)
 return positions
end
for _,period in ipairs({'day','week','month'})do for _,metric in ipairs({'time','words'})do
 check('date at masthead and left-aligned goal below book '..period..' '..metric,function()
  choose({'global_today'});ink.setGoal('period',period);ink.setGoal('metric',metric);ink.setGoal('target',metric=='words' and 150000 or 7200);ink.setGoal('enabled',true)
  local w,fs,size=render();local label=({day='今日',week='本周',month='本月'})[period]..'阅读目标'
  local title=assert(text(fs,label));local percent=assert(text(fs,tostring(ink.goalSnapshot(ui,now).percent)..'%'));local amount
  for _,t in ipairs(fs)do if t.text:find(' / ',1,true) and not t.text:find(' 页',1,true)then amount=t end end
  assert(amount and amount:getAllLineCount()==1,'goal amount wrapped')
  local date=assert(text(fs,'2026.10.19'));local brand=assert(text(fs,'INKFOLIO'));local book=assert(text(fs,ui.doc_props.title))
  assert(percent.face.size==amount.face.size and date.face==title.face and date.face.size<amount.face.size)
  assert(percent.bold and not amount.bold and not date.bold and not text(fs,'日期'))
  local pos=paintPositions(w,size)
  assert(pos[date].baseline==pos[brand].baseline and pos[date].x+date.width==size.width-w.padding_right-w.shadow_width)
  assert(pos[title].x==w.padding_left and pos[title].y>pos[book].y+book:getSize().h)
  assert(pos[title].y+title:getSize().h<=pos[percent].y and pos[percent].baseline==pos[amount].baseline)
  assert(pos[title].x==pos[percent].x and pos[percent].x+percent.width<pos[amount].x)
  assert(pos[amount].y+amount:getSize().h<pos[assert(text(fs,'阅读进度'))].y)
  assert(not text(fs,({day='今日',week='本周',month='本月'})[period]..(metric=='words' and '字数目标' or '时长目标')))
  w:free()
 end)
end end
for _,font in ipairs({.8,1,1.2})do for _,width in ipairs({.55,.84,.90})do
 check('whole UI baseline and type hierarchy font='..font..' width='..width,function()
  choose({'global_today','global_month'});settings:saveSetting(S.charts,{'week','month_words'})
  ink.setGoal('period','month');ink.setGoal('metric','words');ink.setGoal('target',150000);ink.setGoal('enabled',true)
  local w,fs,size=render({width=width,font=font,scale=.65,background='white',measure_only=true})
  assert(size.width<=Screen:getWidth() and size.height<Screen:getHeight())
  local positions=paintPositions(w,size);local rows=0
  walk(w,function(node)
   if getmetatable(node)==H then
    local texts={};local valid=true
    for _,child in ipairs(node)do
     local t=firstText(child)
     if t then texts[#texts+1]=t elseif child[1] then valid=false end
    end
    if valid and #texts>=2 then
     for i=2,#texts do assert(positions[texts[i]].baseline==positions[texts[1]].baseline,'text baseline mismatch')end
     rows=rows+1
    end
   end
  end)
  assert(rows>=8)
  local date=assert(text(fs,'2026.10.19'));local goal=assert(text(fs,'本月阅读目标'));assert(goal.face.size==text(fs,'章节').face.size and not text(fs,'日期'))
  local percent=assert(text(fs,'12%'));local amount
  for _,t in ipairs(fs)do if t.text:find('15.0万字',1,true) then amount=t end end
  assert(amount and date.face==goal.face and date.face.size<=amount.face.size and percent.face.size==amount.face.size)
  assert(not date.bold and percent.bold and not amount.bold and amount:getAllLineCount()==1)
  assert(positions[date].baseline==positions[assert(text(fs,'INKFOLIO'))].baseline and positions[percent].baseline==positions[amount].baseline)
  local times={};for _,t in ipairs(fs)do if t.text=='时长' then times[#times+1]=positions[t] end end
  assert(#times==2 and times[1].baseline==times[2].baseline)
  w:free()
 end)
end end
check('paired summary rows stay aligned when only one duration wraps',function()
 choose({'global_today','global_month'});ink.setGoal('enabled',false)
 local original=ink.summaryData
 ink.summaryData=function(snapshot,item)return {time=item.id=='global_today' and 1000000000000000 or 60,metric='words',amount=1000}end
 local ok,w,fs,size=pcall(render,{width=.55,font=1.2,scale=.65,background='white',measure_only=true});ink.summaryData=original;assert(ok,w)
 local positions=paintPositions(w,size);local labels={};local durations={}
 for _,t in ipairs(fs)do
  if t.text=='字数' then labels[#labels+1]=t end
  if t.text=='277777777777时46分' or t.text=='1分钟'then durations[#durations+1]=t end
 end
 assert(#labels==2 and positions[labels[1]].baseline==positions[labels[2]].baseline)
 assert(#durations==2 and positions[durations[1]].baseline==positions[durations[2]].baseline)
 assert(text(fs,'277777777777时46分'):getAllLineCount()>1)
 w:free()
end)
check('no summary and no goal avoids native queries',function()
 settings:saveSetting(S.stats,false);ink.setGoal('enabled',false);local before=flushes;local w=render();assert(flushes==before);w:free()
end)
print('STATISTICS_PASS '..passed..' / FAIL '..failed);os.exit(failed==0 and 0 or 1)
