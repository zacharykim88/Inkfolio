require('setupkoenv');G_defaults=require('luadefaults'):open()
G_reader_settings=require('luasettings'):open(os.getenv('KO_HOME')..'/settings.reader.lua')
local settings=G_reader_settings
settings:saveSetting('read_receipt_v2_online',false)
local Device=require('device');require('document/canvascontext'):init(Device)
local Screen=Device.screen;local BB=require('ffi/blitbuffer');local UI=require('ui/uimanager');local Font=require('ui/font')
local root=assert(arg[0]:match('^(.*)/tests/[^/]+$'))..'/'
local source=assert(io.open(root..'2-inkfolio.lua')):read('*a')
local api=assert(loadstring(source..[[
return {ink=Inkfolio,S=S,render=renderReceipt,bars=ReadingBars,paper=ReceiptPaper,themes=UI_THEMES,about=showAbout,weather=WEATHER}
]]))()
local ink,S=api.ink,api.S
local passed,failed=0,0
local function check(name,fn)local ok,e=pcall(fn);if ok then passed=passed+1;print('PASS',name)else failed=failed+1;print('FAIL',name,e)end end
local function stamp(y,m,d,h)return os.time{year=y,month=m,day=d,hour=h or 12,min=0,sec=0}end
local SQ=require('lua-ljsqlite3/init');local dbpath=require('datastorage'):getSettingsDir()..'/statistics.sqlite3'
local db=SQ.open(dbpath);db:exec('CREATE TABLE page_stat_data(id_book INTEGER,page INTEGER,start_time INTEGER,duration INTEGER);CREATE VIEW page_stat AS SELECT * FROM page_stat_data;')
local sunday,monday=stamp(2026,10,25),stamp(2026,10,26)
db:exec(string.format('INSERT INTO page_stat_data VALUES(1,1,%d,1800),(1,2,%d,3600);',sunday,monday));db:close()
local ui={document={file='english-book.epub',getPageCount=function()return 358 end},doc_props={title='Flowers for Algernon',authors='Daniel Keyes'},
 doc_settings={data={doc_pages=358}},view={state={page=123}},statistics={id_curr_book=1,isEnabled=function()return true end,insertDB=function()end,avg_time=45},
 toc={getTocTitleByPage=function()return 'Progress Report 9'end},bookinfo={getCoverImage=function()local b=BB.new(160,220,BB.TYPE_BB8);b:fill(BB.Color8(225));return b end}}
settings:saveSetting(S.auto_fit,false);settings:saveSetting(S.intro,false);settings:saveSetting(S.cover,false)
ink.setGoal('enabled',false)
check('English weekly chart loads Sunday from the database and keeps Monday summaries separate',function()
 ink.selectLanguage('en_US');settings:saveSetting(S.stats,true);settings:saveSetting(S.summary,{'global_week'});settings:saveSetting(S.charts,{'week','week_words'})
 local now=stamp(2026,10,28);ink.wordState.tracking_since=stamp(2026,10,1,0)
 ink.wordState.days={['2026-10-25']={words=100},['2026-10-26']={words=200}}
 local snapshot=ink.statisticsSnapshot(ui,now)
 local summary=snapshot:time('week');local chart=snapshot:time('week',nil,true)
 assert(summary.total==3600 and chart.total==5400)
 assert(os.date('%Y-%m-%d',chart.days[1].start)=='2026-10-25'and chart.days[1].seconds==1800 and chart.days[2].seconds==3600)
 assert(os.date('%Y-%m-%d',summary.days[1].start)=='2026-10-26')
 assert(snapshot:words('week').total==200 and snapshot:words('week',true).total==300)
 assert(snapshot:time('week')==summary and snapshot:time('week',nil,true)==chart)
end)
for _,date in ipairs({{2026,11,1},{2027,1,1},{2028,3,1},{2026,10,25},{2026,10,31}})do
 check('Sunday week spans dates correctly '..table.concat(date,'-'),function()
  local days=ink.periodDays('week',stamp(unpack(date)),true);assert(#days==7 and os.date('*t',days[1].start).wday==1)
  for i=1,7 do assert(os.date('*t',days[i].start).wday==i);if i>1 then assert(days[i-1].finish==days[i].start)end end
 end)
end
local Text=require('ui/widget/textboxwidget');local TextWidget=require('ui/widget/textwidget')
check('native chart labels describe their actual dates and move with the data',function()
 for _,language in ipairs({'zh_CN','en_US'})do
  ink.selectLanguage(language);local days=ink.periodDays('week',stamp(2026,10,28),language=='en_US')
  for i,day in ipairs(days)do if not day.future then day.words=i*1200 end end
  local bars=api.bars:new{width=Screen:getWidth()-100,height=math.floor(Screen:getHeight()*.15),data={days=days,metric='words'},theme=api.themes.swiss,font_size=14,scale=1,stroke=1}
  local labels={};local native=Text.new;Text.new=function(self,args)labels[#labels+1]=args.text;return native(self,args)end
  local bb=BB.new(Screen:getWidth(),Screen:getHeight(),BB.TYPE_BB8);bb:fill(BB.COLOR_WHITE);bars:paintTo(bb,40,20);Text.new=native
  local expected=language=='en_US'and {'S','M','T','W','T','F','S'}or {'一','二','三','四','五','六','日'}
  local offset=#labels-7;for i=1,7 do assert(labels[offset+i]==expected[i],table.concat(labels,','))end
  bb:writePNG((os.getenv('INK_OUTPUT')or root..'checks')..'/weekly-'..language..'-'..Screen:getWidth()..'x'..Screen:getHeight()..'.png');bb:free();bars:free()
 end
end)
check('fading preserves white, every antialias shade and the untouched source',function()
 for _,kind in ipairs({BB.TYPE_BB4,BB.TYPE_BB8,BB.TYPE_BBRGB16,BB.TYPE_BBRGB24,BB.TYPE_BBRGB32})do
  local b=BB.new(257,3,kind);b:fill(BB.COLOR_WHITE)
  for x=0,255 do b:setPixel(x,1,BB.Color8(x))end
  local original={};for x=0,255 do original[x]=b:getPixel(x,1):getColor8().a end
  local out=ink.fadeReadingBackdrop(b)
  local previous=0
  for x=0,255 do
   local value=b:getPixel(x,1):getColor8().a
   local faded=out:getPixel(x,1):getColor8().a
   assert(faded==187+math.floor(value*68/255+.5)and faded>=previous)
   assert(b:getPixel(x,1):getColor8().a==original[x]);previous=faded
   assert(out:getPixel(x,0):getColor8().a==255 and out:getPixel(x,2):getColor8().a==255,
    string.format('kind=%s x=%d blank source=%d/%d result=%d/%d',kind,x,b:getPixel(x,0):getColor8().a,b:getPixel(x,2):getColor8().a,out:getPixel(x,0):getColor8().a,out:getPixel(x,2):getColor8().a))
  end
  assert(out:getPixel(0,1):getColor8().a==187 and out:getPixel(256,1):getColor8().a==255)
  b:free();out:free()
 end
end)
check('fading respects all rotations and inverse source buffers',function()
 for rotation=0,3 do for inverse=0,1 do
  local b=BB.new(61,43,BB.TYPE_BB8);b:fill(BB.COLOR_WHITE);b:paintRect(10,15,20,9,BB.COLOR_BLACK)
  b:setRotation(rotation);b:setInverse(inverse)
  local a=ink.fadeReadingBackdrop(b)
  for y=0,b:getHeight()-1 do for x=0,b:getWidth()-1 do
   local value=b:getPixel(x,y):getColor8().a
   assert(a:getPixel(x,y):getColor8().a==187+math.floor(value*68/255+.5))
  end end
  a:free();b:free()
 end end
end)
check('full-resolution fading keeps exact stroke edges and one-pixel details',function()
 local b=BB.new(Screen:getWidth(),Screen:getHeight(),BB.TYPE_BB8);b:fill(BB.COLOR_WHITE)
 local x,y=math.floor(b:getWidth()/2),math.floor(b:getHeight()/2)
 b:paintRect(x,y,20,20,BB.COLOR_BLACK)
 b:paintRect(0,0,1,b:getHeight(),BB.COLOR_BLACK)
 b:paintRect(0,b:getHeight()-1,b:getWidth(),1,BB.Color8(100))
 local start=os.clock();local faded=ink.fadeReadingBackdrop(b)
 print(string.format('FADE_CPU_SECONDS %.4f',os.clock()-start))
 assert(faded:getWidth()==b:getWidth()and faded:getHeight()==b:getHeight())
 for yy=0,b:getHeight()-1 do for xx=0,b:getWidth()-1 do
  local value=b:getPixel(xx,yy):getColor8().a
  assert(faded:getPixel(xx,yy):getColor8().a==187+math.floor(value*68/255+.5))
  assert(value==((yy==b:getHeight()-1)and 100 or (xx==0 or (xx>=x and xx<x+20 and yy>=y and yy<y+20))and 0 or 255))
 end end
 b:free();faded:free()
end)
check('pixel keeps its black outline and clean white margins on every edge',function()
 local empty=require('ui/widget/verticalspan'):new{width=80}
 local paper=api.paper:new{theme=api.themes.pixel,padding_top=25,padding_bottom=25,padding_left=25,padding_right=25,outline_color=BB.COLOR_BLACK,outline_width=2,empty}
 local size=paper:getSize();local b=BB.new(size.w,size.h,BB.TYPE_BB8);paper:paintTo(b,0,0)
 for y=0,size.h-1 do for x=0,size.w-1 do assert(b:getPixel(x,y):getColor8().a==((x<2 or x>=size.w-2 or y<2 or y>=size.h-2)and 0 or 255))end end
 b:free();paper:free()
end)
check('English card titles use actual serif italics while authors, numbers and Chinese titles stay upright',function()
 ink.selectLanguage('en_US');settings:saveSetting(S.stats,false);settings:saveSetting(S.weather,false);settings:saveSetting(S.weather_tomorrow,false);settings:saveSetting(S.cover_weather,'off')
 local original=Text.new;local fields={};Text.new=function(self,args)fields[#fields+1]=args;return original(self,args)end
 local ok,w=pcall(api.render,ui,ui.view.state,{ui_style='cover',card_width=.6,card_background='white',measure_only=true});Text.new=original;assert(ok,w)
 local italic=assert(Font:getFace('NotoSerif-Italic.ttf',24)).realname
 local found=false
 for _,t in ipairs(fields)do if t.text==ui.doc_props.title then assert(t.face.realname==italic and not t.bold);found=true elseif t.text==ui.doc_props.authors or t.text=='34%'then assert(t.face.realname~=italic)end end
 assert(found);w:free()
 local title=ui.doc_props.title;ui.doc_props.title='献给阿尔吉侬的花束';fields={};Text.new=function(self,args)fields[#fields+1]=args;return original(self,args)end
 ok,w=pcall(api.render,ui,ui.view.state,{ui_style='cover',card_width=.6,measure_only=true});Text.new=original;assert(ok,w)
 for _,t in ipairs(fields)do if t.text==ui.doc_props.title then assert(t.face.realname~=italic)end end
 w:free();ui.doc_props.title=title
end)
check('English Find dialog and subsequent search results stay English with a Chinese host',function()
 local gettext=require('gettext');gettext.changeLang('zh_CN');ink.selectLanguage('en_US')
 local viewer=ink.textViewer{title='About InkFolio',text='InkFolio reading cards InkFolio',show_menu=false,add_default_buttons=true}
 local native=UI.show;local dialog;UI.show=function(_,w)if w.title=='Find in Text'then dialog=w end end
 local ok,e=pcall(viewer.findDialog,viewer);UI.show=native;assert(ok,e);assert(dialog.title=='Find in Text')
 for _,row in ipairs(dialog.buttons)do for _,b in ipairs(row)do assert(b.text=='Cancel'or b.text=='Find First'or b.text=='Find Next')end end
 dialog:onCloseKeyboard();dialog:free()
 viewer.search_value='InkFolio';viewer._find_next=false;viewer:findCallback();assert(viewer.button_table:getButtonById('find').text=='Find Next')
 viewer:findCallback();assert(viewer._find_next);viewer:findCallback();assert(not viewer._find_next and viewer.button_table:getButtonById('find').text=='Find')
 viewer:free();gettext.changeLang('C')
end)
check('About introduction is concise, keeps provenance and credits, and uses both languages',function()
 for _,language in ipairs({'zh_CN','en_US'})do
  ink.selectLanguage(language);local native=UI.show;local w;UI.show=function(_,widget)w=widget end;api.about();UI.show=native
  assert(w.text:find('KOReader Book Receipt',1,true)and w.text:find('Estela-Zelin84/KOReader_Book-Receipt',1,true)and w.text:find('GPL-3.0',1,true))
  assert(#w.text<1600);w:free()
 end
end)
print('DEVELOPMENT_PASS '..passed..' / FAIL '..failed);os.exit(failed==0 and 0 or 1)
