"""Run the delivered Lua goal functions with real temporary settings files.

Uses the system Lua 5.4 shared library; KOReader/LuaJIT device testing remains separate.
The settings double models LuaSettings.flush returning normally after a failed write.
"""
import ctypes
import ctypes.util
import os
from pathlib import Path
import tempfile
import unittest

SOURCE = Path(os.environ.get('INKFOLIO_SOURCE', str(Path(__file__).resolve().parents[1] / '2-inkfolio.lua')))


class Lua:
    def __init__(self):
        self.lib = ctypes.CDLL(ctypes.util.find_library('lua5.4'))
        self.lib.luaL_newstate.restype = ctypes.c_void_p
        self.lib.luaL_openlibs.argtypes = [ctypes.c_void_p]
        self.lib.luaL_loadbufferx.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_size_t, ctypes.c_char_p, ctypes.c_char_p]
        self.lib.lua_pcallk.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_ssize_t, ctypes.c_void_p]
        self.lib.lua_tolstring.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.POINTER(ctypes.c_size_t)]
        self.lib.lua_tolstring.restype = ctypes.c_char_p
        self.lib.lua_close.argtypes = [ctypes.c_void_p]
        self.state = self.lib.luaL_newstate()
        self.lib.luaL_openlibs(self.state)

    def run(self, text, execute=True):
        data = text.encode('utf-8')
        code = self.lib.luaL_loadbufferx(self.state, data, len(data), b'@goal-save-test', None)
        if not code and execute:
            code = self.lib.lua_pcallk(self.state, 0, 0, 0, 0, None)
        if code:
            raise AssertionError(self.lib.lua_tolstring(self.state, -1, None).decode('utf-8'))

    def close(self):
        self.lib.lua_close(self.state)


SETUP = r'''
Inkfolio = {}
local L = function(s) return s end
local S = {goal='reading_goal'}
local logger = {warn=function()end}
local messages = {}
function Inkfolio.message(text) messages[#messages+1]=text end
local refreshes = 0
local refreshQuicklook = function() refreshes=refreshes+1 end
local previous = {version=1,enabled=true,period='day',metric='time',values={day_time=600,week_words=2000}}
local desired = {version=1,enabled=true,period='week',metric='words',values={day_time=600,week_words=3000}}
local mode = 'write'
local disk_override
local function encode(value)
    if type(value)=='table' then
        local parts={}
        for key,item in pairs(value) do parts[#parts+1]='['..string.format('%q',key)..']='..encode(item) end
        return '{'..table.concat(parts,',')..'}'
    elseif type(value)=='string' then return string.format('%q',value)
    else return tostring(value) end
end
local function write(value)
    local file=assert(io.open(SETTINGS_PATH,'wb'))
    assert(file:write('return '..encode(value)))
    assert(file:close())
end
G_reader_settings={file=SETTINGS_PATH,data={reading_goal=previous}}
function G_reader_settings:readSetting(key) return self.data[key] end
function G_reader_settings:saveSetting(key,value) self.data[key]=value;return self end
function G_reader_settings:delSetting(key) self.data[key]=nil;return self end
function G_reader_settings:flush()
    if mode=='raise' then error('disk full') end
    if mode=='silent' then return self end
    if mode=='missing' then os.remove(self.file);return self end
    if mode=='malformed' then
        local file=assert(io.open(self.file,'wb'));file:write('return {');file:close();return self
    end
    write(disk_override or self.data)
    return self
end
write({reading_goal=previous})
local function failed(config)
    local ok,reason=Inkfolio.saveGoal(config or desired)
    assert(not ok,'save unexpectedly reported success')
    assert(type(reason)=='string' and reason~='','save failure has no reason')
    assert(G_reader_settings:readSetting(S.goal)==previous,'previous setting was not restored')
    assert(refreshes==0,'failed save refreshed the preview')
end
'''


class GoalSaveTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.lua = Lua()
        source = SOURCE.read_text()
        start = source.index('function Inkfolio.goalConfig(')
        end = source.index('function Inkfolio.parseGoalTarget(', start)
        path = str(Path(self.temp.name) / 'settings.lua')
        self.setup = 'local SETTINGS_PATH=' + repr(path) + '\n' + SETUP + source[start:end]

    def tearDown(self):
        self.lua.close()
        self.temp.cleanup()

    def check(self, body):
        self.lua.run(self.setup + '\n' + body)

    def test_full_patch_syntax(self):
        self.lua.run(SOURCE.read_text(), execute=False)

    def test_success_persists_all_targets_and_refreshes_once(self):
        self.check("assert(Inkfolio.saveGoal(desired));local saved=dofile(SETTINGS_PATH).reading_goal;assert(saved.period=='week' and saved.metric=='words' and saved.values.week_words==3000 and saved.values.day_time==600);assert(refreshes==1)")

    def test_silent_write_failure(self):
        self.check("mode='silent';failed()")

    def test_throwing_write_failure(self):
        self.check("mode='raise';failed()")

    def test_missing_output_file(self):
        self.check("mode='missing';failed()")

    def test_invalid_output_file(self):
        self.check("mode='malformed';failed()")

    def test_missing_goal_on_disk(self):
        self.check("disk_override={unrelated=true};failed()")

    def test_wrong_enabled_flag(self):
        self.check("disk_override={reading_goal={version=1,enabled=false,period='week',metric='words',values=desired.values}};failed()")

    def test_wrong_period(self):
        self.check("disk_override={reading_goal={version=1,enabled=true,period='day',metric='words',values={day_words=1000,day_time=600,week_words=3000}}};failed()")

    def test_wrong_metric(self):
        self.check("disk_override={reading_goal={version=1,enabled=false,period='week',metric='time',values=desired.values}};failed()")

    def test_missing_other_target(self):
        self.check("disk_override={reading_goal={version=1,enabled=true,period='week',metric='words',values={week_words=3000}}};failed()")

    def test_extra_stale_target(self):
        self.check("disk_override={reading_goal={version=1,enabled=true,period='week',metric='words',values={week_words=3000,day_time=600,month_time=1200}}};failed()")

    def test_invalid_saved_goal(self):
        self.check("disk_override={reading_goal={version=1,enabled=true,period='week',metric='words',values={week_words=0}}};failed()")

    def test_first_save_failure_removes_new_memory_setting(self):
        self.check("previous=nil;G_reader_settings.data.reading_goal=nil;write({});mode='silent';failed()")

    def test_unchanged_goal_is_successful_when_already_on_disk(self):
        self.check("mode='silent';assert(Inkfolio.saveGoal(previous));assert(refreshes==1)")

    def test_disabled_goal_with_no_targets(self):
        self.check("assert(Inkfolio.saveGoal({version=1,enabled=false,period='day',metric='time',values={}}));assert(refreshes==1)")

    def test_missing_settings_path_rolls_back(self):
        self.check("mode='silent';G_reader_settings.file=nil;failed()")

    def test_set_goal_changes_only_selected_target(self):
        self.check("assert(Inkfolio.setGoal('target',1200));local c=dofile(SETTINGS_PATH).reading_goal;assert(c.values.day_time==1200 and c.values.week_words==2000)")

    def test_switch_to_unconfigured_period_disables_goal(self):
        self.check("assert(Inkfolio.setGoal('period','month'));local c=dofile(SETTINGS_PATH).reading_goal;assert(c.period=='month' and not c.enabled and c.values.day_time==600)")

    def test_set_goal_failure_reports_error(self):
        self.check("mode='silent';assert(not Inkfolio.setGoal('target',1200));assert(#messages==1);assert(G_reader_settings.data.reading_goal==previous and refreshes==0)")

    def test_dialog_save_failure_keeps_input_open_then_retry_succeeds(self):
        source = SOURCE.read_text()
        start = source.index('function Inkfolio.editGoalTarget(')
        end = source.index('function Inkfolio.goalMenu(', start)
        dialog_setup = r'''
local dialog,closes
closes=0
local UIManager={show=function()end,close=function()closes=closes+1 end}
local input={new=function(self,options)
    dialog=options
    function dialog:onShowKeyboard()end
    function dialog:getInputText()return '20' end
    return dialog
end}
local require=function(name)assert(name=='ui/widget/inputdialog');return input end
function Inkfolio.refreshParentOnClose(widget)return widget end
function Inkfolio.language()return 'zh_CN' end
function Inkfolio.parseGoalTarget(text,metric)assert(text=='20' and metric=='time');return 1200 end
'''
        self.check(dialog_setup + source[start:end] + r'''
Inkfolio.editGoalTarget(nil)
mode='silent'
dialog.buttons[1][2].callback()
assert(closes==0 and #messages==1 and refreshes==0)
assert(G_reader_settings.data.reading_goal==previous)
mode='write'
dialog.buttons[1][2].callback()
assert(closes==1 and refreshes==1 and dofile(SETTINGS_PATH).reading_goal.values.day_time==1200)
''')


if __name__ == '__main__':
    unittest.main()
