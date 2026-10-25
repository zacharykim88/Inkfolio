require('setupkoenv');G_defaults=require('luadefaults'):open()
G_reader_settings=require('luasettings'):open(os.getenv('KO_HOME')..'/settings.reader.lua')
G_reader_settings:saveSetting('read_receipt_v2_online',false)
local Device=require('device');require('document/canvascontext'):init(Device)
local Screen=Device.screen;local BB=require('ffi/blitbuffer');local UI=require('ui/uimanager')
local root=assert(arg[0]:match('^(.*)/tests/[^/]+$'))..'/'
local f=assert(io.open(root..'2-inkfolio.lua'));local src=f:read('*a');f:close()
local api=assert(loadstring(src..'\nreturn {ink=Inkfolio,S=S,build=buildReceipt,editor=AppearanceEditor}'))()
local Reader=require('apps/reader/readerui');local Cre=require('document/credocument')
local path=os.getenv('KO_HOME')..'/paper-native.fb2';f=assert(io.open(path,'w'))
f:write('<?xml version="1.0" encoding="UTF-8"?><FictionBook xmlns="http://www.gribuser.ru/xml/fictionbook/2.0"><description><title-info><genre>prose</genre><author><first-name>InkFolio</first-name></author><book-title>纸上，继续阅读</book-title><lang>zh</lang></title-info></description><body><section><title><p>第一章 · 继续前行</p></title>',
 string.rep('<p>每次翻开书页，都是一段新的旅程。阅读让时间慢下来，也让眼前的文字与心中的想象相遇。</p>',80),'</section></body></FictionBook>');f:close()
Reader:doShowReader(path,Reader:extendProvider(path,Cre))
for _=1,3 do UI:_checkTasks()end
local ui=assert(Reader.instance);assert(ui.document and ui.view)
G_reader_settings:saveSetting(api.S.ui_style,'paper');G_reader_settings:saveSetting(api.S.stats,false)
local scene,valid=api.build(ui,ui.view.state);assert(scene and valid and scene.background_style=='paper')
local expected=api.ink.readingBackdrop(ui);local rendered=BB.new(Screen:getWidth(),Screen:getHeight(),BB.TYPE_BB8);scene:paintTo(rendered,0,0)
local r=scene.card_rect
for y=0,Screen:getHeight()-1,17 do for x=0,Screen:getWidth()-1,17 do
 if x<r.x or x>=r.x+r.w or y<r.y or y>=r.y+r.h then assert(rendered:getPixel(x,y):getColor8().a==expected:getPixel(x,y):getColor8().a)end
end end
rendered:writePNG(assert(os.getenv('INK_OUTPUT'))..'/paper-native-'..Screen:getWidth()..'x'..Screen:getHeight()..'.png')
rendered:free();expected:free();scene:free()
api.ink.settings();UI:forceRePaint()
local e=api.editor:new{ui=ui};UI:show(e);assert(e.controls.buttons[1][6].enabled)
local page=api.ink.readingBackdrop(ui)
for y=0,Screen:getHeight()-1,17 do for x=0,Screen:getWidth()-1,17 do
 if x<r.x or x>=r.x+r.w or y<r.y or y>=r.y+r.h then assert(e.preview_canvas:getPixel(x,y):getColor8().a==page:getPixel(x,y):getColor8().a)end
end end
page:free();local editorbb=BB.new(Screen:getWidth(),Screen:getHeight(),BB.TYPE_BB8);e:paintTo(editorbb,0,0)
editorbb:writePNG(assert(os.getenv('INK_OUTPUT'))..'/paper-native-editor-'..Screen:getWidth()..'x'..Screen:getHeight()..'.png');editorbb:free()
e:onCancel()
local dark,good=api.build(ui,ui.view.state,{ui_style='paper',paper_card_background='black'});assert(good and dark.card_background=='black')
local db=BB.new(Screen:getWidth(),Screen:getHeight(),BB.TYPE_BB8);dark:paintTo(db,0,0)
db:writePNG(assert(os.getenv('INK_OUTPUT'))..'/paper-native-dark-'..Screen:getWidth()..'x'..Screen:getHeight()..'.png');db:free();dark:free()
print('PAPER_NATIVE_PASS 4 / FAIL 0');os.exit(0)
