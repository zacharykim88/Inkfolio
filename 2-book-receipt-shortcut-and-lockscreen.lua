-- 墨笺 · Inkfolio v1.0.0 / KOReader user patch
-- SPDX-License-Identifier: GPL-3.0-only
-- Based on Estela-Zelin84/KOReader_Book-Receipt (GNU GPL v3).
-- Upstream credits u/hundredpercentcocoa and omer-faruq/koreader-user-patches.
-- Modifications and design: zacharykim88, 2026-10-10. Developed with OpenAI Codex.
-- One receipt theme; asynchronous book-library metadata collection, permanent cache.
-- Network code must never turn Wi-Fi on automatically.
local Blitbuffer = require('ffi/blitbuffer')
local CenterContainer = require('ui/widget/container/centercontainer')
local Device = require('device')
local Dispatcher = require('dispatcher')
local Font = require('ui/font')
local FrameContainer = require('ui/widget/container/framecontainer')
local Geom = require('ui/geometry')
local GestureRange = require('ui/gesturerange')
local HorizontalGroup = require('ui/widget/horizontalgroup')
local HorizontalSpan = require('ui/widget/horizontalspan')
local ImageWidget = require('ui/widget/imagewidget')
local InputContainer = require('ui/widget/container/inputcontainer')
local ProgressWidget = require('ui/widget/progresswidget')
local ReaderUI = require('apps/reader/readerui')
local RenderImage = require('ui/renderimage')
local ScreenSaverWidget = require('ui/widget/screensaverwidget')
local TextWidget = require('ui/widget/textwidget')
local TextBoxWidget = require('ui/widget/textboxwidget')
local UIManager = require('ui/uimanager')
local VerticalGroup = require('ui/widget/verticalgroup')
local VerticalSpan = require('ui/widget/verticalspan')
local WidgetContainer = require('ui/widget/container/widgetcontainer')
local BookInfo = require('apps/filemanager/filemanagerbookinfo')
local DataStorage = require('datastorage')
local DocSettings = require('docsettings')
local DocRegistry = require('document/documentregistry')
local LuaSettings = require('luasettings')
local NetworkMgr = require('ui/network/manager')
local QRWidget = require('ui/widget/qrwidget')
local SQ3 = require('lua-ljsqlite3/init')
local socket_url = require('socket.url')
local lfs = require('libs/libkoreader-lfs')
local datetime = require('datetime')
local ffiUtil = require('ffi/util')
local logger = require('logger')
local util = require('util')
local _ = require('gettext')
local Screen = Device.screen
local VERSION = '1.0.0'
local RELEASE_DATE = '2026-10-10'

-- Cinzel Decorative has chisel-shaped Latin capitals inspired by Roman inscriptions.
-- Fonts are separate dependencies, installed in the KOReader data directory's fonts/.
-- Missing font is reported explicitly instead of silently substituting a different one.
local TITLE_FONT = 'CinzelDecorative-Bold.ttf'
local CHINESE_TITLE_FONT = 'Xiangcui-Dazijiti-main/香萃打字机体 W40.ttf'

local P = 'read_receipt_v2_'
local S = {
    online = P .. 'online', width = P .. 'width', font = P .. 'font',
    cover = P .. 'cover', chapter = P .. 'chapter', stats = P .. 'stats',
    intro = P .. 'intro', qr = P .. 'qr', score = P .. 'score',
    remain = P .. 'remain', background = P .. 'background',
    footer = P .. 'footer', weather_city = P .. 'weather_city',
    global_today = P .. 'global_today', global_total = P .. 'global_total',
    summary = P .. 'summary', progress = P .. 'progress', scale = P .. 'scale',
    library_root = P .. 'library_root',
}
local store = LuaSettings:open(DataStorage:getSettingsDir() .. '/read_receipt_v2_db.lua')
local CACHE = store:readSetting('books') or {}
local DAY = store:readSetting('day') or ''
local ROUNDS = tonumber(store:readSetting('auto_rounds')) or 0
local DAILY_DONE = store:readSetting('daily_done') == true
local WEATHER=store:readSetting('weather') or {records={}}
WEATHER.records=WEATHER.records or {}
local LIBRARY = store:readSetting('library_files') or {pending={}}
local nextLibraryScan = 0
local dailyCheck, weatherCheck, selectedWeatherCity
-- CMA/NMC station identifiers verified from /rest/province on 2026-10-09.
-- Mainland prefecture names: Administrative-divisions-of-China (NBS-derived pc.json).
-- Municipalities and special administrative regions are listed directly.
local WEATHER_REGIONS={
    {name="北京市",cities={
        {name="北京市",code="Wqsps"},
    }},
    {name="天津市",cities={
        {name="天津市",code="yqSjH"},
    }},
    {name="河北省",cities={
        {name="石家庄市",code="uJQqI"},
        {name="唐山市",code="aCRJR"},
        {name="秦皇岛市",code="SBrmr"},
        {name="邯郸市",code="AwDQd"},
        {name="邢台市",code="WgyJx"},
        {name="保定市",code="FaykR"},
        {name="张家口市",code="AXmqR"},
        {name="承德市",code="oWYwK"},
        {name="沧州市",code="mHkdW"},
        {name="廊坊市",code="gXmTp"},
        {name="衡水市",code="Jiheq"},
    }},
    {name="山西省",cities={
        {name="太原市",code="jmHMK"},
        {name="大同市",code="VZgct"},
        {name="阳泉市",code="rwUnO"},
        {name="长治市",code="dwSMC"},
        {name="晋城市",code="VKljS"},
        {name="朔州市",code="OtlfP"},
        {name="晋中市",code="ovSsu"},
        {name="运城市",code="AupnI"},
        {name="忻州市",code="twMEQ"},
        {name="临汾市",code="nhsiM"},
        {name="吕梁市",code="EQQRH"},
    }},
    {name="内蒙古自治区",cities={
        {name="呼和浩特市",code="IlyWx"},
        {name="包头市",code="wzspS"},
        {name="乌海市",code="HfJln"},
        {name="赤峰市",code="yiSxk"},
        {name="通辽市",code="LUAqU"},
        {name="鄂尔多斯市",code="cSBaZ"},
        {name="呼伦贝尔市",code="YUznP"},
        {name="巴彦淖尔市",code="TBQLP"},
        {name="乌兰察布市",code="MwkIG"},
        {name="兴安盟",code="wfaiF"},
        {name="锡林郭勒盟",code="euSxF"},
        {name="阿拉善盟",code="foHBa"},
    }},
    {name="辽宁省",cities={
        {name="沈阳市",code="xasvS"},
        {name="大连市",code="nGPyb"},
        {name="鞍山市",code="TopGN"},
        {name="抚顺市",code="shhKE"},
        {name="本溪市",code="fZXDt"},
        {name="丹东市",code="DlvsN"},
        {name="锦州市",code="LgDdn"},
        {name="营口市",code="veIOe"},
        {name="阜新市",code="uxzEA"},
        {name="辽阳市",code="kgqfX"},
        {name="盘锦市",code="ooWvQ"},
        {name="铁岭市",code="WDQHL"},
        {name="朝阳市",code="SSCPq"},
        {name="葫芦岛市",code="NIFaR"},
    }},
    {name="吉林省",cities={
        {name="长春市",code="mxFBj"},
        {name="吉林市",code="oQKCU"},
        {name="四平市",code="UIlgs"},
        {name="辽源市",code="pSYcD"},
        {name="通化市",code="LaBrf"},
        {name="白山市",code="nFNOH"},
        {name="松原市",code="jJpzl"},
        {name="白城市",code="ktvDN"},
        {name="延边朝鲜族自治州",code="QHZhm"},
    }},
    {name="黑龙江省",cities={
        {name="哈尔滨市",code="pzXOG"},
        {name="齐齐哈尔市",code="pMfJu"},
        {name="鸡西市",code="tsmWc"},
        {name="鹤岗市",code="pQrYF"},
        {name="双鸭山市",code="xYzrU"},
        {name="大庆市",code="uLCaf"},
        {name="伊春市",code="BAQLD"},
        {name="佳木斯市",code="IwveF"},
        {name="七台河市",code="olTln"},
        {name="牡丹江市",code="WhkSY"},
        {name="黑河市",code="xggDD"},
        {name="绥化市",code="ccdEO"},
        {name="大兴安岭地区",code="HIKCZ"},
    }},
    {name="上海市",cities={
        {name="上海市",code="WwcJd"},
    }},
    {name="江苏省",cities={
        {name="南京市",code="CxOWZ"},
        {name="无锡市",code="fvlMy"},
        {name="徐州市",code="bWGZQ"},
        {name="常州市",code="bmyrb"},
        {name="苏州市",code="lqYjK"},
        {name="南通市",code="VHAmf"},
        {name="连云港市",code="HPnPL"},
        {name="淮安市",code="wVmjo"},
        {name="盐城市",code="bUGRK"},
        {name="扬州市",code="lDhJo"},
        {name="镇江市",code="xKfDh"},
        {name="泰州市",code="kQswL"},
        {name="宿迁市",code="jVxXh"},
    }},
    {name="浙江省",cities={
        {name="杭州市",code="HIieJ"},
        {name="宁波市",code="XjZpe"},
        {name="温州市",code="qgMmM"},
        {name="嘉兴市",code="pxfeS"},
        {name="湖州市",code="quMLV"},
        {name="绍兴市",code="gxbHp"},
        {name="金华市",code="QMNma"},
        {name="衢州市",code="ydEbu"},
        {name="舟山市",code="KElec"},
        {name="台州市",code="zWIte"},
        {name="丽水市",code="nEoHv"},
    }},
    {name="安徽省",cities={
        {name="合肥市",code="xqcji"},
        {name="芜湖市",code="YCdBx"},
        {name="蚌埠市",code="xEdTH"},
        {name="淮南市",code="DUBio"},
        {name="马鞍山市",code="cdzPY"},
        {name="淮北市",code="npJUD"},
        {name="铜陵市",code="VAMvd"},
        {name="安庆市",code="bIpli"},
        {name="黄山市",code="dFIpc"},
        {name="滁州市",code="aqZIQ"},
        {name="阜阳市",code="JcXXt"},
        {name="宿州市",code="KZzYj"},
        {name="六安市",code="RLVWB"},
        {name="亳州市",code="bjqNC"},
        {name="池州市",code="XbuHL"},
        {name="宣城市",code="hhgTF"},
    }},
    {name="福建省",cities={
        {name="福州市",code="djeOy"},
        {name="厦门市",code="gDCDS"},
        {name="莆田市",code="XbBQN"},
        {name="三明市",code="CZiRH"},
        {name="泉州市",code="MGECZ"},
        {name="漳州市",code="SCyJf"},
        {name="南平市",code="CGyTI"},
        {name="龙岩市",code="AVWuS"},
        {name="宁德市",code="uKfig"},
    }},
    {name="江西省",cities={
        {name="南昌市",code="JmxCz"},
        {name="景德镇市",code="DriXU"},
        {name="萍乡市",code="yBDJf"},
        {name="九江市",code="kVOgS"},
        {name="新余市",code="IzuqH"},
        {name="鹰潭市",code="UWvkt"},
        {name="赣州市",code="uBtqa"},
        {name="吉安市",code="riQqz"},
        {name="宜春市",code="OqvoJ"},
        {name="抚州市",code="toCHD"},
        {name="上饶市",code="KpYAB"},
    }},
    {name="山东省",cities={
        {name="济南市",code="VITKz"},
        {name="青岛市",code="Jrsbf"},
        {name="淄博市",code="BGfNv"},
        {name="枣庄市",code="rXLkZ"},
        {name="东营市",code="CHtLx"},
        {name="烟台市",code="qRqdU"},
        {name="潍坊市",code="hQrpa"},
        {name="济宁市",code="Jmcsg"},
        {name="泰安市",code="zUeIF"},
        {name="威海市",code="KeEOQ"},
        {name="日照市",code="GoJQw"},
        {name="临沂市",code="aGpFP"},
        {name="德州市",code="polCM"},
        {name="聊城市",code="XXeBL"},
        {name="滨州市",code="penbZ"},
        {name="菏泽市",code="MGAnB"},
    }},
    {name="河南省",cities={
        {name="郑州市",code="YVItN"},
        {name="开封市",code="swtij"},
        {name="洛阳市",code="rYaxY"},
        {name="平顶山市",code="nRecJ"},
        {name="安阳市",code="hNkdK"},
        {name="鹤壁市",code="NYclC"},
        {name="新乡市",code="VLpOH"},
        {name="焦作市",code="ubXHV"},
        {name="濮阳市",code="XbbBI"},
        {name="许昌市",code="ZzMTA"},
        {name="漯河市",code="lncFZ"},
        {name="三门峡市",code="TjcXC"},
        {name="南阳市",code="vRweN"},
        {name="商丘市",code="aMsMR"},
        {name="信阳市",code="hdKHW"},
        {name="周口市",code="URskB"},
        {name="驻马店市",code="ZmGSj"},
    }},
    {name="湖北省",cities={
        {name="武汉市",code="bSpCz"},
        {name="黄石市",code="MTZwr"},
        {name="十堰市",code="BREJr"},
        {name="宜昌市",code="ekVpr"},
        {name="襄阳市",code="fTXja"},
        {name="鄂州市",code="Agzls"},
        {name="荆门市",code="vGwSN"},
        {name="孝感市",code="CQLZw"},
        {name="荆州市",code="xBZlA"},
        {name="黄冈市",code="sWCpi"},
        {name="咸宁市",code="BokVQ"},
        {name="随州市",code="VHSxv"},
        {name="恩施土家族苗族自治州",code="zKHUp"},
    }},
    {name="湖南省",cities={
        {name="长沙市",code="zOenJ"},
        {name="株洲市",code="siHjW"},
        {name="湘潭市",code="tWpqg"},
        {name="衡阳市",code="ObykY"},
        {name="邵阳市",code="KZYji"},
        {name="岳阳市",code="bwVav"},
        {name="常德市",code="NMRKc"},
        {name="张家界市",code="FOUZo"},
        {name="益阳市",code="OZhHG"},
        {name="郴州市",code="cYyyF"},
        {name="永州市",code="vXgNI"},
        {name="怀化市",code="pJrqw"},
        {name="娄底市",code="ZrEsO"},
        {name="湘西土家族苗族自治州",code="TaxlO"},
    }},
    {name="广东省",cities={
        {name="广州市",code="DwzZf"},
        {name="韶关市",code="fXufo"},
        {name="深圳市",code="AhpEU"},
        {name="珠海市",code="sdnjf"},
        {name="汕头市",code="KYhpn"},
        {name="佛山市",code="YOyIv"},
        {name="江门市",code="YtTxj"},
        {name="湛江市",code="OKhmr"},
        {name="茂名市",code="aELXI"},
        {name="肇庆市",code="SwPNZ"},
        {name="惠州市",code="VDZzQ"},
        {name="梅州市",code="lWavY"},
        {name="汕尾市",code="hlwPp"},
        {name="河源市",code="Fkjlf"},
        {name="阳江市",code="dCezB"},
        {name="清远市",code="WYryQ"},
        {name="东莞市",code="cqsJg"},
        {name="中山市",code="YIWau"},
        {name="潮州市",code="CSTxF"},
        {name="揭阳市",code="rUWdQ"},
        {name="云浮市",code="JMZwt"},
    }},
    {name="广西壮族自治区",cities={
        {name="南宁市",code="dvHfb"},
        {name="柳州市",code="hDSje"},
        {name="桂林市",code="qiegc"},
        {name="梧州市",code="EUqSO"},
        {name="北海市",code="lBdeM"},
        {name="防城港市",code="kXkLV"},
        {name="钦州市",code="jPyoz"},
        {name="贵港市",code="UzLca"},
        {name="玉林市",code="cFeHF"},
        {name="百色市",code="Cejmy"},
        {name="贺州市",code="SdWDF"},
        {name="河池市",code="GGGqW"},
        {name="来宾市",code="qxttW"},
        {name="崇左市",code="Pnyfc"},
    }},
    {name="海南省",cities={
        {name="海口市",code="vmEKa"},
        {name="三亚市",code="PtnWb"},
        {name="三沙市",code="iIkAm"},
        {name="儋州市",code="pFFlS"},
    }},
    {name="重庆市",cities={
        {name="重庆市",code="UkfaS"},
    }},
    {name="四川省",cities={
        {name="成都市",code="yGYHR"},
        {name="自贡市",code="MIIAp"},
        {name="攀枝花市",code="jrDgO"},
        {name="泸州市",code="nLWnl"},
        {name="德阳市",code="QFQLG"},
        {name="绵阳市",code="GcFwG"},
        {name="广元市",code="OwVIj"},
        {name="遂宁市",code="pcHfo"},
        {name="内江市",code="wNtyv"},
        {name="乐山市",code="YuAXe"},
        {name="南充市",code="vihpz"},
        {name="眉山市",code="zkdYW"},
        {name="宜宾市",code="wfNOD"},
        {name="广安市",code="zJhEo"},
        {name="达州市",code="uEFLb"},
        {name="雅安市",code="MfnxC"},
        {name="巴中市",code="UxUlc"},
        {name="资阳市",code="AVVPj"},
        {name="阿坝藏族羌族自治州",code="ujnor"},
        {name="甘孜藏族自治州",code="EvJZp"},
        {name="凉山彝族自治州",code="kSbRT"},
    }},
    {name="贵州省",cities={
        {name="贵阳市",code="SKMHP"},
        {name="六盘水市",code="neXJx"},
        {name="遵义市",code="mKDbo"},
        {name="安顺市",code="zYxtY"},
        {name="毕节市",code="QJFow"},
        {name="铜仁市",code="EaOOy"},
        {name="黔西南布依族苗族自治州",code="pYfUO"},
        {name="黔东南苗族侗族自治州",code="NwqhO"},
        {name="黔南布依族苗族自治州",code="ikFVR"},
    }},
    {name="云南省",cities={
        {name="昆明市",code="IayMy"},
        {name="曲靖市",code="rYbQI"},
        {name="玉溪市",code="eHman"},
        {name="保山市",code="DQgGy"},
        {name="昭通市",code="CMqgr"},
        {name="丽江市",code="AwEIF"},
        {name="普洱市",code="weSDX"},
        {name="临沧市",code="oiQQr"},
        {name="楚雄彝族自治州",code="xbekN"},
        {name="红河哈尼族彝族自治州",code="kLDAL"},
        {name="文山壮族苗族自治州",code="ZQEia"},
        {name="西双版纳傣族自治州",code="IhAco"},
        {name="大理白族自治州",code="MXvqt"},
        {name="德宏傣族景颇族自治州",code="YpfMn"},
        {name="怒江傈僳族自治州",code="MlVrp"},
        {name="迪庆藏族自治州",code="dghSe"},
    }},
    {name="西藏自治区",cities={
        {name="拉萨市",code="utJQK"},
        {name="日喀则市",code="wcnpZ"},
        {name="昌都市",code="FKHOa"},
        {name="林芝市",code="ulvCs"},
        {name="山南市",code="uuiXc"},
        {name="那曲市",code="aDeyn"},
        {name="阿里地区",code="DDraR"},
    }},
    {name="陕西省",cities={
        {name="西安市",code="RfjCI"},
        {name="铜川市",code="lZvra"},
        {name="宝鸡市",code="jrjXm"},
        {name="咸阳市",code="FXoMd"},
        {name="渭南市",code="fXkRh"},
        {name="延安市",code="gtpZu"},
        {name="汉中市",code="cASRq"},
        {name="榆林市",code="eEPbq"},
        {name="安康市",code="RprEI"},
        {name="商洛市",code="qbDbK"},
    }},
    {name="甘肃省",cities={
        {name="兰州市",code="ARkZA"},
        {name="嘉峪关市",code="WVCbx"},
        {name="金昌市",code="chtaw"},
        {name="白银市",code="soZAZ"},
        {name="天水市",code="tiBhu"},
        {name="武威市",code="LAPGD"},
        {name="张掖市",code="nvQbo"},
        {name="平凉市",code="Yekjp"},
        {name="酒泉市",code="vDJSl"},
        {name="庆阳市",code="Nvedf"},
        {name="定西市",code="rsMQP"},
        {name="陇南市",code="mdYJa"},
        {name="临夏回族自治州",code="orIIe"},
        {name="甘南藏族自治州",code="QyZJe"},
    }},
    {name="青海省",cities={
        {name="西宁市",code="SHRvr"},
        {name="海东市",code="CrGat"},
        {name="海北藏族自治州",code="biGag"},
        {name="黄南藏族自治州",code="pVcUC"},
        {name="海南藏族自治州",code="bwKfK"},
        {name="果洛藏族自治州",code="ycCXH"},
        {name="玉树藏族自治州",code="MDlNL"},
        {name="海西蒙古族藏族自治州",code="UpIIn"},
    }},
    {name="宁夏回族自治区",cities={
        {name="银川市",code="LqTRN"},
        {name="石嘴山市",code="jNMZg"},
        {name="吴忠市",code="VXPXK"},
        {name="固原市",code="muLnq"},
        {name="中卫市",code="mZrCd"},
    }},
    {name="新疆维吾尔自治区",cities={
        {name="乌鲁木齐市",code="lIPam"},
        {name="克拉玛依市",code="RHxwy"},
        {name="吐鲁番市",code="DGEdf"},
        {name="哈密市",code="LFhJu"},
        {name="昌吉回族自治州",code="bIfiH"},
        {name="博尔塔拉蒙古自治州",code="UnvYB"},
        {name="巴音郭楞蒙古自治州",code="QAgHw"},
        {name="阿克苏地区",code="wPpQt"},
        {name="克孜勒苏柯尔克孜自治州",code="QCRTj"},
        {name="喀什地区",code="aHjQA"},
        {name="和田地区",code="HDzeq"},
        {name="伊犁哈萨克自治州",code="kAFDB"},
        {name="塔城地区",code="qHPXG"},
        {name="阿勒泰地区",code="SnOYy"},
    }},
    {name="香港特别行政区",cities={
        {name="香港特别行政区",code="KnxKc"},
    }},
    {name="澳门特别行政区",cities={
        {name="澳门特别行政区",code="ZZhCJ"},
    }},
    {name="台湾省",cities={
        {name="台北市",code="VrMVF"},
        {name="新北市",code=""},
        {name="桃园市",code=""},
        {name="台中市",code="FYDSf"},
        {name="台南市",code=""},
        {name="高雄市",code="Urwjw"},
        {name="基隆市",code=""},
        {name="新竹市",code=""},
        {name="嘉义市",code=""},
    }},
}

local STATS_PATH = DataStorage:getSettingsDir() .. '/statistics.sqlite3'
local MAX_AUTO = 5
local RUN = { active = false, sleeping = false, token = 0, manual = false,
              queue = {}, index = 1, started = false, processed = 0,
              worker = nil, transport_broken = false, network_failures = 0, last_error = nil,
              failed = 0, last_book_error = nil }
RUN.cancelled_day = store:readSetting('cancelled_day')
local refreshQuicklook = nil
local MANUAL_CONNECT_PENDING = false
local startPoll -- declared before the cancellation path that may need to re-arm Wi-Fi polling

local function saveData()
    store:saveSetting('books', CACHE)
    store:saveSetting('day', DAY)
    store:saveSetting('auto_rounds', ROUNDS)
    store:saveSetting('daily_done', DAILY_DONE)
    store:flush()
end
local function enabled(key)
    return G_reader_settings:readSetting(key) ~= false
end
local function networkingEnabled() return enabled(S.online) end
local function localDate() return os.date('%Y-%m-%d') end
local function resetDay()
    local d = localDate()
    if DAY ~= d then
        DAY, ROUNDS, DAILY_DONE = d, 0, false
        RUN.transport_broken = false
        RUN.network_failures = 0
        saveData()
    end
end
local function connected()
    NetworkMgr:queryNetworkState()
    return NetworkMgr:isConnected() == true
end
local function shortText(txt, count)
    txt = tostring(txt or '')
    local pos, chars = 1, 0
    while pos <= #txt and chars < count do
        local c = txt:byte(pos)
        if c >= 240 then pos = pos + 4
        elseif c >= 224 then pos = pos + 3
        elseif c >= 192 then pos = pos + 2
        else pos = pos + 1 end
        chars = chars + 1
    end
    return txt:sub(1, pos - 1) .. (pos <= #txt and '…' or '')
end
local function normalize(txt)
    local s = tostring(txt or ''):lower()
    for _, c in ipairs({'《','》','【','】','（','）','·','•','：','，','。','-',' ', '[',']','(',')',':',',','.', '\n'}) do
        s = s:gsub(c:gsub('(%W)', '%%%1'), '')
    end
    -- gsub also returns its replacement count; never leak it into bookKey's table.
    return (s:gsub('%s+', ''))
end
local function htmlText(s)
    s = tostring(s or ''):gsub('<script.-</script>', ' '):gsub('<style.-</style>', ' ')
    s = s:gsub('<[^>]*>', ' ')
    local ok, v = pcall(util.htmlEntitiesToUtf8, s)
    if ok and v then s = v end
    return (s:gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', ''))
end
local function extractBook(props, path)
    props = props or {}
    local file_title = path and path:match('([^/]+)%.[^%.]+$') or ''
    local title=util.trim(props.display_title or '')
    if title=='' then title=util.trim(props.title or '') end
    if title=='' then title=util.trim(file_title or '') end
    return {
        title = title,
        authors = util.trim(props.authors or ''),
        publisher = util.trim(props.publisher or ''),
        isbn = tostring(props.isbn or ''):gsub('[^%dXx]', ''),
        description = htmlText(props.description or ''),
        path = path,
    }
end
local function bookKey(book)
    -- Same work is intentionally shared across editions. The publisher and ISBN
    -- are ranking criteria, not cache identity: metadata can differ between the
    -- file manager and reader, or be unavailable for never-opened books.
    return table.concat({normalize(book.title), normalize(book.authors)}, '|')
end
local function validURL(url)
    return type(url) == 'string' and url:match('^https://book%.douban%.com/subject/%d+/$') ~= nil
end
local function cached(book)
    local item = CACHE[bookKey(book)]
    local rating = type(item) == 'table' and tonumber(item.rating)
    return rating and rating > 0 and rating <= 10 and validURL(item.url) and item or nil
end
local function completed(book)
    local item = cached(book)
    return item and ((type(book.description) == 'string' and book.description ~= '') or
        (type(item.intro) == 'string' and item.intro ~= ''))
end

local SUMMARY_ITEMS = {
    {id='book_today',label='本书今日',today=true},
    {id='global_today',label='全局今日',today=true,global=true},
    {id='book_total',label='本书累计'},
    {id='global_total',label='全局累计',global=true},
}
local function summaryItems()
    local chosen = G_reader_settings:readSetting(S.summary)
    if chosen == nil then
        chosen = {
            G_reader_settings:readSetting(S.global_today)==true and 'global_today' or 'book_today',
            G_reader_settings:readSetting(S.global_total)==true and 'global_total' or 'book_total',
        }
        G_reader_settings:saveSetting(S.summary,chosen)
    end
    local result={}
    -- Today precedes total; within the same period, book precedes global.
    for _,item in ipairs(SUMMARY_ITEMS) do
        for _,id in ipairs(chosen) do
            if id==item.id then result[#result+1]=item;break end
        end
    end
    assert(#result==#chosen and #chosen<=2,'Invalid reading-summary selection')
    return result
end

-- Count each book/page pair once; different books may share the same page number.
local function readStatistics(ui)
    local stats = ui.statistics
    if not stats or (stats.isEnabled and not stats:isEnabled()) then return nil end
    if stats.insertDB and not pcall(stats.insertDB, stats) then return nil end
    local id = tonumber(stats.id_curr_book)
    if not id and stats.getIdBookDB then
        local ok, v = pcall(stats.getIdBookDB, stats)
        if ok then id = tonumber(v) end
    end
    local items=summaryItems()
    if #items==0 then return {} end
    for _,item in ipairs(items) do if not item.global and not id then return nil end end
    if lfs.attributes(STATS_PATH, 'mode') ~= 'file' then return nil end
    local ok, db = pcall(SQ3.open, STATS_PATH)
    if not ok or not db then return nil end
    local clock = os.date('*t')
    clock.hour, clock.min, clock.sec, clock.isdst = 0, 0, 0, nil
    local start = os.time(clock)
    local function query(global, today)
        local filters = {}
        if not global then filters[#filters+1] = string.format('id_book=%d', id) end
        if today then filters[#filters+1] = string.format('start_time>=%d', start) end
        local where = #filters > 0 and (' WHERE '..table.concat(filters, ' AND ')) or ''
        return db:rowexec('SELECT count(*), sum(seconds) FROM ('..
            'SELECT sum(duration) AS seconds FROM page_stat'..where..
            ' GROUP BY id_book, page);')
    end
    local result={}
    local success,reason=pcall(function()
        for _,item in ipairs(items) do
            local pages,seconds=query(item.global,item.today)
            result[item.id]={pages=tonumber(pages) or 0,time=tonumber(seconds) or 0}
        end
    end)
    db:close()
    if not success then logger.warn('READ RECEIPT: cannot read statistics',reason);return nil end
    return result
end
local function duration(value)
    if value == nil then return '—' end
    local n = math.max(0, math.floor(tonumber(value) or 0))
    local hours, minutes = math.floor(n/3600), math.floor(n%3600/60)
    if hours > 0 then return string.format('%d时%d分',hours,minutes) end
    return string.format('%d分钟', minutes)
end
local function scoreStars(score)
    local half = math.max(0, math.min(10, math.floor(score + 0.5))) -- /10 -> 0..10 half-stars
    local full = math.floor(half/2)
    return string.rep('★', full) .. (half%2 == 1 and '½' or '') .. string.rep('☆', 5-full-(half%2))
end

-- Only promote v1.1 records whose link AND rating were actually collected.
if store:readSetting('migrated_v11') ~= true then
    local old = G_reader_settings:readSetting('book_receipt_douban_cache_v11') or {}
    for key, row in pairs(old) do
        if type(key) == 'string' and type(row) == 'table'
           and validURL(row.url) and tonumber(row.rating) and tonumber(row.rating) > 0 then
            CACHE[key] = {rating = tonumber(row.rating), url = row.url,
                          intro = row.intro, rated_versions = row.rated_versions or 1}
        end
    end
    store:saveSetting('migrated_v11', true)
    saveData()
end

-- Earlier keys accidentally included gsub's replacement count: title|author|0.
-- Remove that extra numeric field; a current-key record takes precedence.
if store:readSetting('cache_schema') ~= 261 then
    local keys = {}
    for key in pairs(CACHE) do keys[#keys+1] = key end
    table.sort(keys)
    for _, key in ipairs(keys) do
        local current = key:match('^([^|]*|[^|]*)|%d+$')
        if current then
            if CACHE[current] == nil then CACHE[current] = CACHE[key] end
            CACHE[key] = nil
        end
    end
    store:saveSetting('cache_schema', 261)
    DAILY_DONE, ROUNDS = false, 0
    saveData()
end

-- Fixed-size native dialog: dirty only its own rectangle, at most once per five seconds.
local PROGRESS={active=false,hidden=false,phase='',scanning=true,total=0,done=0,book=''}
local progressTick, cancelFetch
local function progressText()
    local lines={PROGRESS.title or '获取信息'}
    if PROGRESS.scanning then
        lines[#lines+1]='正在扫描书库'
        if PROGRESS.scan_total then lines[#lines+1]=string.format('%d / %d 个文件',PROGRESS.scan_done or 0,PROGRESS.scan_total) end
    elseif not PROGRESS.weather_only then
        lines[#lines+1]=string.format('已处理 %d / %d 本',PROGRESS.done,PROGRESS.total)
        lines[#lines+1]=string.format('已更新 %d 本，未完整获取 %d 本',RUN.processed or 0,RUN.failed or 0)
    end
    if PROGRESS.book~='' then lines[#lines+1]=shortText(PROGRESS.book,38) end
    if not PROGRESS.scanning or PROGRESS.phase~='正在扫描书库' then lines[#lines+1]=PROGRESS.phase end
    return table.concat(lines,'\n')
end
local function progressClose()
    local popup=PROGRESS.popup
    PROGRESS.popup=nil
    if popup then UIManager:close(popup) end
    if progressTick then UIManager:unschedule(progressTick) end
end
local function progressIgnore()
    PROGRESS.hidden=true
    progressClose()
end
local function progressPaint(force)
    if not PROGRESS.active or PROGRESS.hidden or not enabled(S.progress) then return end
    local now=os.time()
    if not force and PROGRESS.last_paint and now-PROGRESS.last_paint<5 then return end
    local text=progressText()
    if PROGRESS.popup then
        if text~=PROGRESS.last_text then
            PROGRESS.popup.text_widget:setText(text)
            UIManager:setDirty(PROGRESS.popup,'ui',PROGRESS.popup.frame.dimen)
        end
    else
        local ButtonTable=require('ui/widget/buttontable')
        local Popup=InputContainer:extend{modal=true,name='read_receipt_progress'}
        function Popup:init()
            local width=math.floor(math.min(Screen:getWidth(),Screen:getHeight())*.8)
            local point_size=math.max(10,math.floor(20*math.min(1,Screen:getHeight()/Screen:scaleBySize(620))))
            local face=Font:getFace('infofont',point_size)
            self.text_widget=TextBoxWidget:new{
                text=text,face=face,width=width,justified=false,line_height=.3,
                height=math.floor(face.size*1.3+0.5)*7,height_adjust=false,
                height_overflow_show_ellipsis=true,
            }
            self.frame=FrameContainer:new{background=Blitbuffer.COLOR_WHITE,
                bordersize=Screen:scaleBySize(1),padding=Screen:scaleBySize(12),margin=0,
                VerticalGroup:new{
                    self.text_widget,
                    ButtonTable:new{width=width,buttons={{
                        {text='忽略',callback=progressIgnore},
                        {text='取消',callback=function() cancelFetch() end},
                    }}},
                },
            }
            self[1]=CenterContainer:new{dimen=Screen:getSize(),self.frame}
            if Device:hasKeys() then self.key_events.Ignore={{Device.input.group.Back}} end
        end
        function Popup:onShow()
            UIManager:setDirty(self,function() return 'ui',self.frame.dimen end)
            return true
        end
        function Popup:onIgnore() progressIgnore();return true end
        function Popup:onCloseWidget()
            UIManager:setDirty(nil,function() return 'ui',self.frame.dimen end)
            if PROGRESS.popup==self then
                PROGRESS.popup=nil;PROGRESS.hidden=true;UIManager:unschedule(progressTick)
            end
        end
        PROGRESS.popup=Popup:new{}
        UIManager:show(PROGRESS.popup,'ui')
    end
    PROGRESS.last_paint,PROGRESS.last_text=now,text
end
progressTick=function()
    if not PROGRESS.active or PROGRESS.hidden then return end
    progressPaint(false)
    UIManager:scheduleIn(5,progressTick)
end
local function progressBegin(manual,weather_only)
    progressClose()
    PROGRESS.active,PROGRESS.hidden,PROGRESS.scanning=true,not enabled(S.progress),not weather_only
    PROGRESS.weather_only=weather_only
    PROGRESS.title=weather_only and '获取天气信息' or (manual and '手动获取图书信息' or '自动获取图书信息')
    PROGRESS.total,PROGRESS.done,PROGRESS.book=0,0,''
    PROGRESS.phase=weather_only and '正在请求天气' or '正在扫描书库'
    PROGRESS.scan_done,PROGRESS.scan_total,PROGRESS.last_paint,PROGRESS.last_text=nil,nil,nil,nil
    progressPaint(true)
    if not PROGRESS.hidden then UIManager:scheduleIn(5,progressTick) end
end
local function progressStage(phase)
    if PROGRESS.active then PROGRESS.phase=phase end
end
local function progressEnd(message,silent)
    local visible=PROGRESS.active and not PROGRESS.hidden and enabled(S.progress)
    PROGRESS.active=false
    progressClose()
    if visible and not silent then
        UIManager:show(require('ui/widget/infomessage'):new{text=message,timeout=8})
    end
end

local function authorNames(value)
    local names = {}
    local s = tostring(value or ''):gsub('%b[]', ''):gsub('【.-】', '')
        :gsub('（.-）', ''):gsub('%b()', '')
        :gsub('，', ';'):gsub('；', ';'):gsub('[,;/\n]', ';')
    for name in s:gmatch('[^;]+') do
        name = util.trim(name)
        -- Explicit translator roles are contributors, not author identity.
        if not name:match('译$') and not name:match('译者') then
            name = name:gsub('著$', '')
            if normalize(name) ~= '' then names[#names+1] = name end
        end
    end
    return names
end

local function displayTitle(value)
    local title=util.trim(tostring(value or ''))
    -- Only balanced brackets are removed. Volume markers remain part of identity.
    local volume={['上']=true,['中']=true,['下']=true,['上册']=true,['中册']=true,
        ['下册']=true,['上卷']=true,['中卷']=true,['下卷']=true}
    local work=title:gsub('（','('):gsub('）',')'):gsub('【','['):gsub('】',']')
    local function bracket(part)
        local inside=util.trim(part:sub(2,-2))
        if volume[inside] or inside:match('^%d+$') or inside:match('^第.-册$') or inside:match('^第.-卷$') then return part end
        return ''
    end
    local clean=util.trim(work:gsub('%b()',bracket):gsub('%b[]',bracket))
    if clean=='' or normalize(clean)==normalize(title) then return title end
    return clean
end

local function searchTitle(value)
    local title=util.trim(tostring(value or ''))
    local clean=displayTitle(title)
    -- Collection counts are edition qualifiers, not title identity.
    local prefix,count=clean:match('^(.*)全(.-)册$')
    if count and count~='' then
        local digits=count:gsub('%d','')
        for _,word in ipairs({'一','二','三','四','五','六','七','八','九','十','百'}) do digits=digits:gsub(word,'') end
        if digits=='' then clean=util.trim(prefix) end
    end
    -- Preserve original punctuation when no qualifier was removed.
    if clean=='' or normalize(clean)==normalize(title) then return title end
    return clean
end

local function matchBook(book, title, details)
    local want, got = normalize(book.title), normalize(title)
    if want == '' or got == '' then return nil end
    local authors = authorNames(book.authors)
    local text = normalize(details)
    local main_match = normalize(searchTitle(book.title)) == normalize(searchTitle(title))
    -- Substring matching is only permitted when one string is not a tiny fragment.
    if want ~= got and (math.min(#want, #got) < 6 or
        not (want:find(got,1,true) or got:find(want,1,true))) then
        -- Differently qualified editions need exact main titles AND author evidence.
        if not main_match or #authors == 0 or text == '' then return nil end
    end
    local publisher = normalize(book.publisher)
    local score = want == got and 10 or 4
    for _, name in ipairs(authors) do
        local author = normalize(name)
        if text ~= '' and not text:find(author,1,true) then return nil end
        if text:find(author,1,true) then score = score + 4 end
    end
    if publisher ~= '' and text:find(publisher,1,true) then score = score + 5 end
    if book.isbn ~= '' and text:find(book.isbn,1,true) then score = score + 10 end
    return score
end
local function appendCandidate(out, book, id, title, details, rating)
    id = tostring(id or '')
    if not id:match('^%d+$') then return end
    local relevance = matchBook(book, title, details)
    if not relevance then return end
    local value = tonumber(rating)
    if value and (value <= 0 or value > 10) then value = nil end
    for _, item in ipairs(out) do if item.id == id then return end end
    out[#out+1] = { id = id, rating = value,
                    url = 'https://book.douban.com/subject/' .. id .. '/',
                    relevance = relevance, title = title, details = details }
end
local function parseDouban(html, book)
    local out = {}
    local ok, parser = pcall(require, 'htmlparser')
    if not ok then return out, '缺少 HTML 解析组件' end
    local parse_ok, root = pcall(parser.parse, html, 6000)
    if not parse_ok or not root then return out, '搜索页内容无法解析' end
    local yes, nodes = pcall(function() return root:select('div.result-list div.result') end)
    if not yes or not nodes then return out, '搜索结果字段解析失败' end
    for _, node in ipairs(nodes) do
        local function el(selector)
            local good, values = pcall(function() return node:select(selector) end)
            return good and values and values[1] or nil
        end
        local function getText(selector)
            local n = el(selector)
            if not n then return '' end
            local good, t = pcall(function() return n:gettext() end)
            return good and htmlText(t) or ''
        end
        local link = el('a.nbg')
        local attr = link and link.attributes or {}
        local id = (attr.href or ''):match('/subject/(%d+)')
            or (attr.onclick or ''):match('sid:%s*(%d+)')
        appendCandidate(out, book, id, getText('div.title h3 a'),
            getText('span.subject-cast'), getText('span.rating_nums'))
    end
    return out
end
local function parseBing(xml, book)
    local out = {}
    for item in tostring(xml or ''):gmatch('<item[^>]*>(.-)</item>') do
        local title = htmlText(item:match('<title[^>]*>(.-)</title>') or '')
        local details = htmlText(item:match('<description[^>]*>(.-)</description>') or '')
        local link = htmlText(item:match('<link[^>]*>(.-)</link>') or '')
        local id = link:match('^https?://book%.douban%.com/subject/(%d+)/?')
        local book_title = title:gsub('%s*%(%s*豆瓣%s*%).*$', '')
            :gsub('%s*（豆瓣）.*$', ''):gsub('%s*%-?%s*豆瓣.*$', '')
        -- Only use Bing for discovery; never treat Bing snippets as verified ratings.
        appendCandidate(out, book, id, book_title, details, nil)
    end
    return out
end
local function parseDetail(html)
    local ok, parser = pcall(require, 'htmlparser')
    if not ok then return nil, nil, '缺少 HTML 解析组件' end
    local good, root = pcall(parser.parse, tostring(html or ''), 6000)
    if not good or not root then return nil, nil, '详情页内容无法解析' end
    local parsed, rating, intro = pcall(function()
        local ratings = root:select('strong[property="v:average"]')
        local n = ratings[1] and tonumber(htmlText(ratings[1]:gettext()))
        if not n or n <= 0 or n > 10 then return nil end
        local descriptions = root:select('#link-report .intro')
        -- When collapsed and expanded copies coexist, the last is the full text.
        local node = descriptions[#descriptions]
        local text = node and htmlText(node:gettext()) or ''
        return n, text ~= '' and shortText(text, 240) or nil
    end)
    if not parsed then return nil, nil, '详情页字段解析失败' end
    if not rating then return nil, nil, '详情页没有有效评分，可能未评分或访问被限制' end
    if not intro then return rating, nil, '详情页没有可提取的内容简介' end
    return rating, intro
end
local function finalizeCandidates(candidates, verified_only)
    table.sort(candidates, function(a,b) return a.relevance > b.relevance end)
    local n, sum, accepted = 0, 0, 0
    for i = 1, math.min(8, #candidates) do
        local c = candidates[i]
        if c.rating and (not verified_only or c.checked_detail) then
            sum, n = sum + c.rating, n + 1
        end
    end
    if n == 0 then return nil end
    for i = 1, math.min(8,#candidates) do
        if candidates[i].rating then
            accepted = i
            break
        end
    end
    local preferred = candidates[accepted]
    if not preferred or not validURL(preferred.url) then return nil end
    return {rating = math.floor(sum / n * 10 + 0.5) / 10,
            rated_versions = n, url = preferred.url,
            intro = preferred.intro, updated_at = os.time()}
end

-- Kobo / KOReader may not initialize Turbo's UIManager.looper. Running httpclient
-- in that configuration throws "attempt to index field looper (a nil value)".
-- Use KOReader's supported POSIX subprocess runner. HTTPS runs outside the UI
-- process; the UI polls only process status and reads the completed result file.
-- Never fall back to synchronous HTTPS in the UI thread.
local HTTP_TIMEOUT = 25
local HTTP_MAX_BYTES = 512 * 1024
local HTTP_SEQ = 0

local function stopHTTP()
    local worker = RUN.worker
    if not worker then return end
    RUN.worker = nil
    if worker.pid and worker.pid ~= false then
        ffiUtil.terminateSubProcess(worker.pid)
        local pid = worker.pid
        local function reap()
            if not ffiUtil.isSubProcessDone(pid) then
                UIManager:scheduleIn(0.25, reap)
            elseif worker.path then
                os.remove(worker.path)
            end
        end
        reap()
    end
    if worker.path then os.remove(worker.path) end
end

local function markAttempt()
    if RUN.started then return end
    RUN.started = true
    if not RUN.manual and not RUN.new_books then
        resetDay()
        ROUNDS = math.min(MAX_AUTO, ROUNDS + 1)
        DAILY_DONE = true
        saveData()
    end
end

local function sendHTTP(url, token, cb, kind)
    if RUN.sleeping or not networkingEnabled() or not connected() or token ~= RUN.token then return false end
    if RUN.transport_broken and kind~='weather' then return false end
    if RUN.worker then
        RUN.last_error = 'HTTP worker already active'
        logger.warn('READ RECEIPT:', RUN.last_error)
        return false
    end
    if type(ffiUtil.runInSubProcess) ~= 'function' or
       type(ffiUtil.isSubProcessDone) ~= 'function' or
       type(ffiUtil.terminateSubProcess) ~= 'function' then
        RUN.last_error = 'KOReader subprocess API unavailable'
        RUN.transport_broken = true
        logger.warn('READ RECEIPT:', RUN.last_error)
        return false
    end

    HTTP_SEQ = HTTP_SEQ + 1
    -- The child writes its result to a unique path; the UI never reads a
    -- half-written response or a pipe that could block on an oversized page.
    local resultpath = DataStorage:getSettingsDir() .. '/read_receipt_http_' ..
                       tostring(os.time()) .. '_' .. tostring(HTTP_SEQ) .. '.tmp'
    os.remove(resultpath)
    local ok, pid, error_text = pcall(ffiUtil.runInSubProcess, function()
        local status, data = 'ERROR', 'unknown error'
        local good, why = pcall(function()
            local https = require('ssl.https')
            local socketutil = require('socketutil')
            -- Limit connection and entire receive time to avoid hung tasks.
            socketutil:set_timeout(6, 12)
            local chunks, bytes = {}, 0
            local sink = function(chunk)
                if chunk then
                    bytes = bytes + #chunk
                    if bytes > HTTP_MAX_BYTES then return nil, 'response too large' end
                    chunks[#chunks+1] = chunk
                end
                return 1
            end
            local request_ok, res, code = pcall(https.request, {
                url=url, method='GET', sink=sink,
                headers={ ['User-Agent']='Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Safari/537.36',
                          ['Accept-Encoding']='identity' },
            })
            socketutil:reset_timeout()
            if request_ok and tonumber(code) == 200 then
                status, data = 'OK', table.concat(chunks)
            elseif request_ok then
                status, data = 'HTTP', tostring(code or res)
            else
                status, data = 'ERROR', tostring(res)
            end
        end)
        if not good then status, data = 'ERROR', tostring(why) end
        local file = io.open(resultpath, 'wb')
        if file then
            file:write(status, '\n', data)
            file:close()
        end
    end)
    if not ok or type(pid) ~= 'number' or pid <= 0 then
        RUN.last_error = 'cannot start HTTP subprocess: ' .. tostring(ok and error_text or pid)
        RUN.transport_broken = true
        os.remove(resultpath)
        logger.warn('READ RECEIPT:', RUN.last_error)
        return false
    end

    if kind~='weather' then markAttempt() end
    RUN.worker = { pid=pid, path=resultpath, token=token, started=os.time(), kind=kind }
    local function checkResult()
        local worker = RUN.worker
        if not worker or worker.pid ~= pid then return end
        if token ~= RUN.token or RUN.sleeping or not networkingEnabled() then
            stopHTTP()
            return
        end
        if os.time() - worker.started > HTTP_TIMEOUT then
            local reason='HTTP subprocess timed out'
            if kind~='weather' then RUN.last_error=reason end
            logger.warn('READ RECEIPT:',reason)
            stopHTTP()
            cb('',reason)
            return
        end
        if not ffiUtil.isSubProcessDone(pid) then
            UIManager:scheduleIn(0.25, checkResult)
            return
        end
        RUN.worker = nil
        local f = io.open(resultpath,'rb')
        local result = f and f:read('*a') or nil
        if f then f:close() end
        os.remove(resultpath)
        local status, body
        if result then status, body = result:match('^([^\n]*)\n(.*)$') end
        if status ~= 'OK' then
            local reason = status and (status .. ': ' .. tostring(body):sub(1,160))
                or 'no HTTP subprocess response'
            logger.warn('READ RECEIPT network:', reason)
            if kind~='weather' then
                RUN.last_error=reason
                RUN.network_failures = RUN.network_failures + 1
                if RUN.network_failures >= 3 then
                    RUN.transport_broken = true
                    logger.warn('READ RECEIPT: stopped batch after three consecutive network errors')
                end
            end
            cb('',reason)
        else
            if kind~='weather' then RUN.network_failures = 0 end
            cb(body)
        end
    end
    UIManager:scheduleIn(0.25, checkResult)
    return true
end
local function isDiagnosticBook(book)
    local ui = ReaderUI.instance
    return RUN.manual and ui and ui.document and ui.doc_props and
        bookKey(extractBook(ui.doc_props, ui.document.file)) == bookKey(book)
end
local function diagnosticPath(stage)
    local extension = stage == 'bing' and '.xml' or '.html'
    return DataStorage:getSettingsDir() .. '/read_receipt_debug_' .. stage .. extension
end
local function captureResponse(book, stage, url, body)
    body = tostring(body or '')
    local title = htmlText(body:match('<title[^>]*>(.-)</title>') or '')
    logger.info('READ RECEIPT response:', stage, 'bytes:', #body,
                'page title:', shortText(title, 100), 'url:', url)
    if not isDiagnosticBook(book) or body == '' then return end
    local file, open_error = io.open(diagnosticPath(stage), 'wb')
    if not file then
        logger.warn('READ RECEIPT cannot save diagnostic:', stage, open_error)
        return
    end
    local written, write_error = file:write(body)
    local closed, close_error = file:close()
    if not written or not closed then
        os.remove(diagnosticPath(stage))
        logger.warn('READ RECEIPT cannot save diagnostic:', stage, write_error or close_error)
        return
    end
    logger.info('READ RECEIPT diagnostic saved:', stage, diagnosticPath(stage))
end
local function fetchBook(book, token, done)
    if isDiagnosticBook(book) then
        for _, stage in ipairs({'douban', 'bing', 'detail'}) do
            os.remove(diagnosticPath(stage))
        end
    end
    -- Search broadly enough to include multiple editions; use publisher/ISBN
    -- to rank the results, otherwise those terms hide other edition ratings.
    local query = searchTitle(book.title)
    local function enrich(record)
        if book.description ~= '' or (record.intro and record.intro ~= '') then
            done(record); return
        end
        progressStage('正在读取图书详情')
        if not sendHTTP(record.url, token, function(body, network_error)
            captureResponse(book, 'detail', record.url, body)
            local rating, intro, parse_error = parseDetail(body)
            if rating and intro then record.intro = intro end
            done(record, network_error or parse_error)
        end) then done(record, RUN.last_error or '详情请求未启动') end
    end
    -- A rating-only cache remains visible while its missing introduction is fetched.
    local existing = cached(book)
    if existing then
        local record = {}
        for key, value in pairs(existing) do record[key] = value end
        enrich(record)
        return
    end
    logger.info('Inkfolio query:', book.title, 'authors:', book.authors,
                'search:', query)
    local function verifiedBing(results)
        table.sort(results, function(a,b) return a.relevance > b.relevance end)
        local idx = 1
        local function step()
            if token ~= RUN.token then return end
            if idx > math.min(6, #results) then
                local record = finalizeCandidates(results, true)
                local reason = not record and '未找到书名和作者匹配、且评分可验证的图书'
                    or (not record.intro and '详情页没有可提取的内容简介') or nil
                done(record, reason)
                return
            end
            local c = results[idx]; idx = idx + 1
            progressStage('正在读取图书详情 '..tostring(idx-1)..' / '..tostring(math.min(6,#results)))
            if not sendHTTP(c.url, token, function(body)
                captureResponse(book, 'detail', c.url, body)
                local value, intro = parseDetail(body)
                c.rating, c.intro, c.checked_detail = value, intro, value ~= nil
                UIManager:scheduleIn(0.7, step)
            end) then done(nil) end
        end
        step()
    end
    local function fallback()
        local bingq = query .. ' 豆瓣评分 site:book.douban.com/subject/'
        local url = 'https://www.bing.com/search?format=rss&q=' .. socket_url.escape(bingq)
        progressStage('正在搜索图书（Bing）')
        if not sendHTTP(url, token, function(body)
            captureResponse(book, 'bing', url, body)
            verifiedBing(parseBing(body, book))
        end) then done(nil) end
    end
    local url = 'https://www.douban.com/search?cat=1001&q=' .. socket_url.escape(query)
    progressStage('正在搜索图书（豆瓣）')
    if not sendHTTP(url, token, function(body)
        captureResponse(book, 'douban', url, body)
        local candidates, parse_error = parseDouban(body, book)
        if parse_error then done(nil, parse_error); return end
        local result = finalizeCandidates(candidates, false)
        logger.info('READ RECEIPT matched candidates:', #candidates, 'book:', book.title)
        if result then enrich(result) else fallback() end
    end) then done(nil) end
end

local function rootPath()
    local selected=G_reader_settings:readSetting(S.library_root)
    if selected then
        if selected~='/' and lfs.attributes(selected,'mode')=='directory' then return selected end
        return nil -- A missing chosen directory must not redirect scans elsewhere.
    end
    local home = G_reader_settings:readSetting('home_dir') or Device.home_dir
    if home and home ~= '/' and lfs.attributes(home, 'mode') == 'directory' then
        return home
    end
    return nil
end
local SKIP_DIR = { ['.adds']=true, ['.kobo']=true, ['.sdr']=true,
    ['.adobe-digital-editions']=true, ['digital editions']=true,
    ['lost+found']=true, ['system volume information']=true }
local BOOK_EXT = {epub=true, pdf=true, mobi=true, azw=true, azw3=true, fb2=true,
    txt=true, rtf=true, djvu=true, cbz=true, cbr=true, html=true, htm=true,
    md=true, doc=true, docx=true, pdb=true, prc=true, xps=true, zip=true}
local function collectPaths()
    local root = rootPath()
    if not root then return nil end
    local out, failed = {}, false
    local function walk(dir, depth)
        if depth > 24 then
            failed=true
            RUN.last_error='书库目录层级超过24层，扫描未完成：'..dir
            logger.warn('Inkfolio:',RUN.last_error)
            return
        end
        local ok, iter, state = pcall(lfs.dir, dir)
        if not ok or not iter then
            logger.warn('READ RECEIPT: cannot scan directory', dir)
            failed = true
            RUN.last_error='无法读取书库目录：'..dir
            return
        end
        for filename in iter, state do
            if filename ~= '.' and filename ~= '..' and filename:sub(1,1) ~= '.' then
                local path = dir .. '/' .. filename
                local mode = lfs.symlinkattributes(path, 'mode')
                if not mode then
                    failed=true
                    RUN.last_error='无法读取书库文件属性：'..path
                    logger.warn('Inkfolio:',RUN.last_error)
                elseif mode == 'directory' and not SKIP_DIR[filename:lower()] and
                   not filename:lower():match('%.sdr$') then
                    walk(path, depth+1)
                elseif mode == 'file' and BOOK_EXT[(filename:match('%.([^%.]+)$') or ''):lower()]
                    and DocRegistry:hasProvider(path) then
                    out[#out+1] = path
                end
            end
        end
    end
    local ok,reason=pcall(walk,root,0)
    if not ok then
        failed=true
        RUN.last_error='书库扫描失败：'..tostring(reason)
        logger.warn('Inkfolio:',RUN.last_error)
    end
    if failed then return nil end
    table.sort(out)
    return out
end
local function observePaths(paths)
    local root=rootPath()
    if LIBRARY.root and LIBRARY.root~=root then LIBRARY.known=nil;LIBRARY.pending={} end
    local known, changed = {}, LIBRARY.known == nil or LIBRARY.root~=root
    LIBRARY.root=root
    for _,path in ipairs(paths) do
        known[path] = true
        if LIBRARY.known and not LIBRARY.known[path] then
            LIBRARY.pending[path] = ''
            changed = true
        end
    end
    for path in pairs(LIBRARY.known or {}) do
        if not known[path] then LIBRARY.pending[path] = nil; changed = true end
    end
    LIBRARY.known = known
    if changed then store:saveSetting('library_files', LIBRARY);store:flush() end
end
local function finishNewPaths(book, complete)
    local paths = (RUN.book_paths or {})[bookKey(book)]
    if not paths then return end
    for _,path in ipairs(paths) do
        if LIBRARY.pending[path] then
            -- Failed books get one new-book attempt per day, avoiding endless retries.
            if complete then LIBRARY.pending[path] = nil
            else LIBRARY.pending[path] = localDate() end
        end
    end
    store:saveSetting('library_files', LIBRARY);store:flush()
end
local function currentBook()
    local ui = ReaderUI.instance
    if ui and ui.document and ui.doc_props then
        return extractBook(ui.doc_props, ui.document.file)
    end
end
local function getBookFromFile(path)
    local ui = ReaderUI.instance
    if ui and ui.document and ui.document.file == path then
        return currentBook()
    end
    -- KOReader's own metadata reader supports books that have never been opened.
    local ok, props = pcall(BookInfo.getDocProps, {ui = {}}, path)
    if not ok then
        logger.warn('READ RECEIPT: cannot read metadata', path, props)
        return nil
    end
    -- BookInfo.extendProps keeps only KOReader's standard fields. When a
    -- previously opened book has richer sidecar metadata, merge real fields.
    if DocSettings:hasSidecarFile(path) then
        local ok_side, side = pcall(function()
            return DocSettings:open(path):readSetting('doc_props')
        end)
        if ok_side and type(side)=='table' then
            props.publisher = props.publisher or side.publisher
            props.isbn = props.isbn or side.isbn
        end
    end
    return extractBook(props, path)
end
local function abortRound(user_cancel)
    stopHTTP()
    if user_cancel then
        RUN.cancelled_day=localDate()
        store:saveSetting('cancelled_day', RUN.cancelled_day)
        DAILY_DONE=true
        WEATHER.pending=false
        WEATHER.error='天气获取已取消'
        store:saveSetting('weather',WEATHER)
        saveData()
    elseif RUN.active and RUN.started and not RUN.manual and not RUN.new_books then
        DAILY_DONE = false -- interrupted automatic scan must be retried on reconnection
        saveData()
    end
    RUN.token = RUN.token + 1
    RUN.active, RUN.started, RUN.manual = false, false, false
    RUN.queue = {}
    progressEnd(user_cancel and '已取消获取，已保存的图书信息保留。' or '获取已中断。',RUN.sleeping)
    if startPoll then startPoll() end
end
cancelFetch=function() abortRound(true) end
local function finishRound()
    local processed = RUN.processed
    RUN.active, RUN.manual, RUN.started = false, false, false
    RUN.queue = {}
    local text=string.format('获取结束：已处理 %d / %d 本，更新 %d 本，未完整获取 %d 本。',
        RUN.done or 0,RUN.total or 0,processed,RUN.failed)
    if RUN.weather_result then text=text..'\n'..RUN.weather_result end
    local reason=RUN.last_error or RUN.last_book_error
    if reason then text=text..'\n最近失败原因：'..tostring(reason):sub(1,140) end
    progressEnd(text)
    if startPoll then startPoll() end
end
local function nextItem()
    if not RUN.active then return end
    if RUN.transport_broken then finishRound(); return end
    if RUN.sleeping or not networkingEnabled() or not connected() then
        abortRound(); return
    end
    if weatherCheck and weatherCheck(true) then return end
    while RUN.index <= #RUN.queue and completed(RUN.queue[RUN.index]) do
        finishNewPaths(RUN.queue[RUN.index], true)
        RUN.done=RUN.done+1;PROGRESS.done=RUN.done
        RUN.index = RUN.index + 1
    end
    if RUN.index > #RUN.queue then finishRound(); return end
    local book = RUN.queue[RUN.index]
    RUN.index = RUN.index + 1
    local token = RUN.token
    PROGRESS.book=book.title
    fetchBook(book, token, function(record, reason)
        if token ~= RUN.token or not RUN.active then return end
        if reason or not record then
            RUN.failed = RUN.failed + 1
            RUN.last_book_error = reason or '未找到匹配且有评分的图书'
            logger.warn('READ RECEIPT book incomplete:', book.title, RUN.last_book_error)
        end
        if record and record.rating and validURL(record.url) then
            CACHE[bookKey(book)] = record
            RUN.processed = RUN.processed + 1
            saveData()
            if refreshQuicklook then refreshQuicklook(bookKey(book)) end
        end
        finishNewPaths(book, completed(book))
        RUN.done=RUN.done+1;PROGRESS.done=RUN.done
        UIManager:scheduleIn(0.8, nextItem)
    end)
end
local function beginRound(manual, priority, new_paths)
    resetDay()
    if RUN.active or RUN.worker or RUN.sleeping or not networkingEnabled() or not connected() then return false end
    if not new_paths and not rootPath() then
        if manual or not RUN.directory_error_shown then
            UIManager:show(require('ui/widget/infomessage'):new{
                text='书库目录不可用，请在“墨笺 → 信息获取 → 书库目录”选择可读取的文件夹。没有发起联网请求。'})
            RUN.directory_error_shown=true
        end
        return false
    end
    RUN.directory_error_shown=false
    if not manual and (RUN.cancelled_day==localDate() or RUN.transport_broken or
       (not new_paths and ROUNDS >= MAX_AUTO)) then return false end
    if manual then RUN.transport_broken = false; RUN.network_failures = 0 end
    RUN.active = true
    RUN.cancelled_day=nil
    store:saveSetting('cancelled_day',nil)
    store:flush()
    WEATHER.pending=selectedWeatherCity()~=nil
    RUN.weather_result=nil
    RUN.done,RUN.total=0,0
    progressBegin(manual)
    RUN.manual = manual
    RUN.new_books = new_paths ~= nil
    RUN.book_paths = {}
    RUN.started = false
    RUN.processed = 0
    RUN.failed = 0
    RUN.last_book_error = nil
    RUN.last_error = nil
    RUN.index = 1
    RUN.token = RUN.token + 1
    local token = RUN.token
    UIManager:scheduleIn(0.05,function()
        if token~=RUN.token or not RUN.active then return end
        local filepaths = new_paths or collectPaths()
        if not filepaths then
            finishRound()
            if manual then
                local InfoMessage = require('ui/widget/infomessage')
                UIManager:show(InfoMessage:new{ text = '书库目录不可用，请在“墨笺 → 信息获取 → 书库目录”选择可读取的文件夹。没有发起联网请求。' })
            end
            return false
        end
        if not new_paths then observePaths(filepaths) end
        PROGRESS.scan_total,PROGRESS.scan_done=#filepaths,0
        local seen = {}
        RUN.queue = {}
        local function add(book, path)
            if path and LIBRARY.pending[path] then
                if book and completed(book) then
                    LIBRARY.pending[path]=nil
                elseif book then
                    local key=bookKey(book)
                    RUN.book_paths[key]=RUN.book_paths[key] or {}
                    table.insert(RUN.book_paths[key],path)
                else
                    LIBRARY.pending[path]=localDate()
                end
            end
            if book and book.title ~= '' and not completed(book) then
                local key = bookKey(book)
                if not seen[key] then
                    seen[key] = true
                    RUN.queue[#RUN.queue+1] = book
                end
            end
        end
        -- Prioritize currently opened book without opening the same document twice.
        if not new_paths then add(priority or currentBook()) end
        local idx = 1
        local function scanStep()
            if token ~= RUN.token or not RUN.active then return end
            if RUN.sleeping or not networkingEnabled() then abortRound(); return end
            for _ = 1, 3 do
                if idx > #filepaths then
                    RUN.total=#RUN.queue
                    PROGRESS.total,PROGRESS.scanning=RUN.total,false
                    store:saveSetting('library_files',LIBRARY);store:flush()
                    if #RUN.queue==0 and not RUN.manual and not RUN.new_books then DAILY_DONE=true;saveData() end
                    nextItem()
                    return
                end
                add(getBookFromFile(filepaths[idx]),filepaths[idx])
                idx = idx + 1
                PROGRESS.scan_done=idx-1
            end
            UIManager:scheduleIn(0.03, scanStep)
        end
        scanStep()
    end)
    return true
end
selectedWeatherCity=function()
    local code=G_reader_settings:readSetting(S.weather_city)
    if not code then return nil end
    for _,region in ipairs(WEATHER_REGIONS) do
        for _,city in ipairs(region.cities) do
            if city.code~='' and city.code==code then return city end
        end
    end
end
local function weatherPending()
    return selectedWeatherCity()~=nil and WEATHER.pending==true
end
local function validTemperature(value)
    local n=tonumber(value)
    if n and n>=-90 and n<=65 then return n end
end
local function parseWeather(body,code,day)
    local ok,response=pcall(function() return require('rapidjson').decode(body) end)
    if not ok or type(response)~='table' or response.code~=0 or type(response.data)~='table' then return nil end
    local data=response.data
    local forecast=data.predict
    if type(forecast)~='table' or type(forecast.station)~='table' or forecast.station.code~=code then return nil end
    local entry
    for _,item in ipairs(type(forecast.detail)=='table' and forecast.detail or {}) do
        if type(item)=='table' and item.date==day then entry=item;break end
    end
    if not entry then return nil end
    local dw=type(entry.day)=='table' and entry.day.weather or nil
    local nw=type(entry.night)=='table' and entry.night.weather or nil
    dw=type(dw)=='table' and dw or {}; nw=type(nw)=='table' and nw or {}
    local high,low=validTemperature(dw.temperature),validTemperature(nw.temperature)
    -- The official daily chart supplies both extrema when the daytime forecast has expired.
    if not high or not low then
        for _,item in ipairs(type(data.tempchart)=='table' and data.tempchart or {}) do
            if type(item)=='table' and type(item.time)=='string' and item.time:gsub('/','-')==day then
                high,low=validTemperature(item.max_temp),validTemperature(item.min_temp)
                break
            end
        end
    end
    if not high or not low or high<low then return nil end
    local info=dw.info
    if not info or info=='' or info=='9999' then info=nw.info end
    if type(info)~='string' or info=='' or info=='9999' then return nil end
    if info=='阴' then info='阴天' end
    return info..' '..string.format('%.0f～%.0f°C',low,high)
end
local function cityLabel(city)
    return (city.name:gsub('市$',''))
end
local function weatherText()
    local city=selectedWeatherCity()
    if not city then return '未选择城市' end
    local name=cityLabel(city)
    if RUN.worker and RUN.worker.kind=='weather' and RUN.worker.city==city.code then return name..'　获取中…' end
    if WEATHER.error and WEATHER.attempt_city==city.code and WEATHER.attempt_day==localDate() then return name..'　'..WEATHER.error end
    local record=WEATHER.records[city.code]
    if record and record.day==localDate() and record.text then return name..'　'..record.text end
    if WEATHER.attempt_city==city.code and WEATHER.attempt_day==localDate() then return name..'　'..(WEATHER.error or '天气获取失败') end
    return name..'　待联网更新'
end
weatherCheck=function(allow_active)
    if RUN.sleeping or not networkingEnabled() or (RUN.active and not allow_active) or RUN.worker or not weatherPending() then return false end
    if not connected() then return false end
    local city,day,token=selectedWeatherCity(),localDate(),RUN.token
    local standalone=not RUN.active
    if standalone then
        RUN.processed,RUN.failed=0,0
        progressBegin(false,true)
    end
    progressStage('正在获取'..cityLabel(city)..'天气')
    local started=sendHTTP('https://www.nmc.cn/rest/weather?stationid='..socket_url.escape(city.code),token,function(body,error_text)
        if token~=RUN.token then return end
        local text=not error_text and parseWeather(body,city.code,day) or nil
        if text then
            WEATHER.records[city.code]={day=day,text=text,updated_at=os.time()}
            WEATHER.error=nil
        else
            WEATHER.error='天气获取失败'
            logger.warn('READ RECEIPT weather:',error_text or 'missing valid daily weather')
        end
        RUN.weather_result=cityLabel(city)..'：'..(text or '天气获取失败')
        store:saveSetting('weather',WEATHER);store:flush()
        UIManager:nextTick(function()
            if token~=RUN.token then return end
            if RUN.active then nextItem()
            elseif weatherPending() then weatherCheck()
            else progressEnd(RUN.weather_result);startPoll() end
        end)
    end,'weather')
    if started then
        WEATHER.pending=false
        WEATHER.attempt_day,WEATHER.attempt_city,WEATHER.error=day,city.code,'天气获取中断'
        RUN.worker.city=city.code
        store:saveSetting('weather',WEATHER);store:flush()
    else
        WEATHER.pending=false
        WEATHER.error='天气请求未启动'
        store:saveSetting('weather',WEATHER);store:flush()
        if standalone then progressEnd(WEATHER.error) end
    end
    return started
end

local function newBooksCheck(force)
    if RUN.sleeping or RUN.active or RUN.worker or not networkingEnabled() or
       RUN.cancelled_day==localDate() or RUN.transport_broken then return false end
    if not force and LIBRARY.known and not connected() then return false end
    if not force and os.time()<nextLibraryScan then return false end
    nextLibraryScan=os.time()+180
    local paths=collectPaths()
    if not paths then return false end
    observePaths(paths)
    local added={}
    for _,path in ipairs(paths) do
        if LIBRARY.pending[path] and LIBRARY.pending[path]~=localDate() then
            added[#added+1]=path
        end
    end
    if #added>0 and connected() then return beginRound(false,nil,added) end
    return false
end
dailyCheck=function(force_scan)
    resetDay()
    if RUN.cancelled_day==localDate() then return end
    if newBooksCheck(force_scan) then return end
    if weatherCheck() then return end
    if RUN.sleeping or not networkingEnabled() or DAILY_DONE or RUN.active or RUN.transport_broken or ROUNDS >= MAX_AUTO then return end
    if connected() then beginRound(false) end
end
local function currentCheck()
    resetDay()
    if newBooksCheck(true) then return end
    if RUN.cancelled_day==localDate() or RUN.active or RUN.worker or RUN.sleeping or not networkingEnabled() or RUN.transport_broken or ROUNDS >= MAX_AUTO then return end
    local b = currentBook()
    if b and not completed(b) and connected() then beginRound(false,b) end
end
local POLL_ENABLED = false
local function pollWifi()
    POLL_ENABLED = false
    if RUN.sleeping or not networkingEnabled() then return end
    dailyCheck() -- silently detects Wi-Fi connected, never enables it.
    if RUN.cancelled_day~=localDate() then
        POLL_ENABLED = true
        UIManager:scheduleIn(45, pollWifi)
    end
end
startPoll = function()
    if POLL_ENABLED or RUN.sleeping or not networkingEnabled() then return end
    resetDay()
    if RUN.cancelled_day~=localDate() then
        POLL_ENABLED = true
        UIManager:scheduleIn(45, pollWifi)
    end
end
local function updateManually()
    if not networkingEnabled() then
        local InfoMessage = require('ui/widget/infomessage')
        UIManager:show(InfoMessage:new{ text = '插件联网已关闭，请先开启联网开关。' })
        return
    end
    if RUN.active or RUN.worker then
        local InfoMessage = require('ui/widget/infomessage')
        UIManager:show(InfoMessage:new{ text = '已有查询正在进行，请稍后重试。' })
        return
    end
    if connected() then beginRound(true); return end
    if not Device:hasWifiToggle() then
        UIManager:show(require('ui/widget/infomessage'):new{
            text='当前网络不可用，请在设备系统设置中连接网络后重试。'})
        return
    end
    if NetworkMgr:isWifiOn() then
        local InfoMessage = require('ui/widget/infomessage')
        UIManager:show(InfoMessage:new{text='Wi-Fi 已开启，但尚未连接网络。请先连接后重试。'})
        return
    end
    local ConfirmBox = require('ui/widget/confirmbox')
    UIManager:show(ConfirmBox:new{
        text = '当前 Wi-Fi 未连接，需要开启 Wi-Fi 才能手动更新图书信息。',
        ok_text = '开启 Wi-Fi', cancel_text = '取消',
        ok_callback = function()
            if not networkingEnabled() then return end
            MANUAL_CONNECT_PENDING = true
            local ok = NetworkMgr:enableWifi(function()
                if not MANUAL_CONNECT_PENDING then return end
                MANUAL_CONNECT_PENDING = false
                if networkingEnabled() and connected() then beginRound(true) end
            end, true)
            if ok == false then MANUAL_CONNECT_PENDING = false end
            UIManager:scheduleIn(48, function()
                if MANUAL_CONNECT_PENDING then
                    MANUAL_CONNECT_PENDING = false
                    local InfoMessage = require('ui/widget/infomessage')
                    UIManager:show(InfoMessage:new{text='Wi-Fi 连接失败，未执行手动更新。'})
                end
            end)
        end,
    })
end
-- ---------- 纸质票根与机打排版 ----------
-- 融合了手撕票根的半圆齿孔、细纸边和真实收银小票的两端对齐明细。
-- 纸张和纹理只用内建画笔；票头使用上方指定的字体。
-- v2.5: 票纸边缘的磨蹭脏印。所有坐标都限制在纸张内侧留白区；
-- 固定整数散列产生可重复的深浅斑点，不使用随机数，也不加载图片。
-- 优先采用 paintRect（BlitBuffer 原生矩形填充），减少逐像素读写。
local function printEdgePatina(bb, x, y, w, h, top_pad, bottom_pad, left_pad, right_pad)
    -- 留出至少 6 像素的空白隔离带，避免碰到正文、封面或二维码。
    local max_depth = math.min(22, top_pad - 6, bottom_pad - 6,
                                    left_pad - 6, right_pad - 6)
    if max_depth < 4 then return end
    local function noise(a, b, side)
        return (a * 92821 + b * 68917 + side * 17041
             + (a * b) % 173 * 379) % 1009
    end
    -- edge: 1 上、2 下、3 左、4 右；沿边移动，深度逐步衰减。
    for edge = 1, 4 do
        local horizontal = edge <= 2
        local extent = horizontal and w or h
        for along = 3, extent - 12, 3 do
            local zone = noise(math.floor(along / 41), 17, edge)
            local dense_zone = zone % 7 < 2  -- 墨辊接触不均，形成稀疏的污渍区域。
            for depth = 2, max_depth, 2 do
                local r = noise(along, depth, edge)
                local chance = math.max(8, 135 - depth * 6)
                if dense_zone then chance = chance + 54 end
                if along < 85 or extent - along < 85 then chance = chance + 16 end
                if r < chance then
                    local shade = (r % 13 == 0) and Blitbuffer.COLOR_GRAY_5
                              or ((r % 3 == 0) and Blitbuffer.COLOR_GRAY_7
                              or Blitbuffer.COLOR_GRAY_9)
                    -- 斑点大小不一；极偶尔出现短而窄的擦痕。
                    local length = (r % 47 == 0 and depth < 8) and 7
                                 or ((r % 9 == 0) and 3 or 1)
                    local thickness = (r % 11 == 0) and 2 or 1
                    local rw = horizontal and length or thickness
                    local rh = horizontal and thickness or length
                    local px, py
                    if edge == 1 then
                        px, py = x + along, y + 2 + depth
                    elseif edge == 2 then
                        px, py = x + along, y + h - 3 - depth - rh + 1
                    elseif edge == 3 then
                        px, py = x + 2 + depth, y + along
                    else
                        px, py = x + w - 3 - depth - rw + 1, y + along
                    end
                    bb:paintRect(px, py, rw, rh, shade)
                end
            end
        end
    end
end

-- Transparent ink masks extracted from the three supplied JPEG stamps.
-- Existing clockwise tilt and missing ink are retained. No paper texture is painted.
local STAMP_SIZE=240
local STAMPS={
    pending={"108:3,112:1,115:3","103:4,108:12,121:2,124:3","97:22,121:2,124:10","92:1,96:23,127:12","89:6,96:4,102:22,128:2,131:4,137:3,141:2,146:1,151:1","85:8,94:30,125:1,132:1,134:14","83:5,91:32,134:16","79:10,91:6,98:11,110:12,128:2,135:17,153:2","75:6,83:2,87:28,119:2,127:3,137:12,150:7","73:11,91:5,98:17,120:1,128:1,138:20","70:16,88:1,94:9,105:1,138:8,147:14","68:4,74:4,79:7,94:2,137:5,143:10,154:8","68:17,88:1,138:2,142:21,164:1","64:15,81:4,144:12,157:1,159:3,163:3","63:22,111:1,145:22","62:13,77:1,79:3,83:1,101:3,106:12,121:3,150:20","60:12,73:5,97:8,106:16,135:1,152:19","57:4,62:2,65:6,73:3,94:15,120:2,126:2,132:1,134:4,156:3,160:13","56:12,69:2,90:5,96:3,132:3,136:7,157:2,161:13","54:14,70:1,85:2,88:1,90:4,138:7,146:1,160:8,169:3,174:1","53:17,83:5,140:9,161:12,174:4","52:16,80:2,83:5,144:3,148:2,162:1,164:15","50:7,58:3,62:3,77:9,149:3,164:17","48:12,62:2,76:5,150:6,170:12","47:4,52:10,72:2,75:4,152:2,156:1,171:12","46:14,71:5,157:1,171:14","45:9,57:2,68:2,71:4,158:4,171:15","43:5,49:5,55:1,57:1,67:4,159:4,174:13","41:7,49:6,67:3,160:2,163:2,175:13","41:14,64:1,67:2,161:6,175:13","40:10,52:2,62:3,66:2,164:3,177:12","38:3,42:3,47:5,60:5,165:3,179:4,185:2,188:4","37:14,60:4,167:4,179:13","36:6,43:4,57:3,61:2,169:4,180:3,184:7","36:11,57:1,170:4,184:2,187:6","35:1,40:2,43:4,55:4,171:4,184:10","34:1,38:1,42:4,55:3,172:1,174:2,184:12","39:1,52:2,56:2,175:1,184:14","51:3,176:3,185:14","31:2,52:1,177:2,187:11","30:3,48:2,52:1,177:4,190:7,198:1","29:3,48:4,178:4,189:8,198:2","29:4,47:4,180:3,190:8,200:1","27:2,30:2,37:1,181:3,191:3,195:4,200:1","27:4,37:1,182:2,192:1,194:9","26:5,45:2,182:3,194:10","25:6,183:1,193:6,200:4","25:10,42:1,187:1,194:11","23:4,28:4,187:2,196:9","22:2,25:7,33:1,42:2,187:3,196:10","21:3,27:4,188:1,196:12","21:3,26:2,40:1,188:4,197:11","21:3,25:3,37:1,189:3,199:10","25:2,28:1,37:1,39:1,190:3,199:10","25:5,36:4,191:2,199:10","19:1,25:4,35:4,191:4,200:10","28:1,35:3,192:1,194:1,200:2,203:8","194:2,202:9","17:8,33:3,194:2,202:4,208:4","16:3,20:5,32:3,194:3,203:9","15:3,20:5,32:3,195:2,203:9","15:3,21:4,31:4,196:1,204:7,212:1","15:4,20:5,31:1,33:1,197:2,204:6,212:1","15:8,31:1,197:3,205:10","13:9,30:2,64:3,198:2,205:4,210:6","12:11,29:3,64:3,198:3,206:4,211:5","12:10,29:2,63:5,199:3,207:10","12:4,17:5,28:3,63:7,199:2,207:10","11:7,19:2,28:1,62:9,200:3,208:8","11:10,28:1,61:11,201:2,209:4,214:3","11:10,26:2,61:12,201:2,209:5,215:3","10:10,26:1,60:13,202:2,209:2,212:2,216:3","10:6,17:1,25:3,59:7,68:8,202:3,210:9","9:9,25:3,58:18,204:2,211:9","8:10,24:3,57:8,66:10,87:3,203:2,213:2,216:4","9:2,12:2,15:4,24:3,56:20,87:4,203:2,213:8","9:3,13:5,24:2,54:2,58:17,87:6,204:1,212:9","11:4,16:1,24:1,53:3,57:15,87:8,205:2,212:9","8:1,11:4,16:1,52:18,87:2,90:7,205:2,212:4,217:4","7:9,50:9,60:4,65:3,86:7,95:4,213:9","6:10,23:1,49:10,60:7,86:14,213:9","6:10,23:1,48:17,86:14,206:2,214:8","6:10,21:1,47:1,49:4,54:8,72:3,85:16,207:2,214:4,219:2","6:3,11:4,21:1,45:8,55:7,72:5,85:16,207:2,214:1,216:2,222:1","5:10,20:3,44:8,54:4,60:3,72:7,85:5,91:3,95:5,207:2,215:2","5:7,13:1,20:3,44:3,49:7,60:4,73:9,85:13,207:3,215:3,220:1,222:1","5:9,19:3,44:3,50:2,58:7,72:25,208:3,215:2,220:4","5:9,19:3,58:2,61:5,72:25,208:3,220:4","5:8,19:2,59:4,64:3,72:25,208:3,220:3","5:9,19:2,59:4,64:3,72:8,81:7,89:7,104:3,209:2,220:2","5:8,19:2,55:13,76:20,102:5,210:1,219:1","4:9,19:2,54:3,58:11,79:12,93:5,101:7,210:1,218:2","4:8,53:16,82:5,88:2,91:1,93:2,96:7,104:5,210:1,217:2,225:1","4:6,11:1,17:3,52:18,82:5,88:2,91:4,96:7,104:5,136:3,210:2,217:2","3:6,17:3,52:18,82:16,99:11,135:6,210:2,217:3,224:1","3:5,17:3,51:14,66:3,82:21,104:6,134:9,210:2,217:3,224:2","3:5,17:2,49:16,66:3,81:18,100:3,104:7,135:10,211:2,218:3,224:2","2:5,17:2,46:17,65:6,81:12,95:7,103:8,136:10,211:2,219:2,225:1","2:9,17:1,46:16,65:9,81:7,89:3,99:13,137:10,211:2,218:1,220:1,225:2","3:2,7:1,9:2,16:2,45:15,65:12,81:11,101:11,137:8,146:2,211:3,218:1,220:1","7:1,9:2,16:2,43:16,65:14,80:12,104:8,138:7,146:2,211:1,213:1,218:3","8:2,16:2,42:18,65:27,107:5,138:12,212:1,219:3,226:1","2:1,7:1,10:1,16:2,41:20,66:25,109:2,138:12,171:1,219:7","16:2,41:20,70:21,138:6,145:5,170:3,219:7","17:1,38:1,41:11,55:6,73:18,104:3,138:1,140:10,170:7,219:8","2:1,17:1,35:2,38:5,44:5,50:2,54:7,76:7,84:10,103:5,137:13,170:7,219:9","2:1,15:1,34:3,39:21,78:3,82:1,85:2,88:9,101:8,137:12,169:13,219:8","1:2,15:1,32:4,45:1,47:11,81:5,88:22,139:10,169:14,212:1,219:6,226:2","6:1,15:2,31:5,40:2,43:1,47:10,83:27,138:10,154:5,169:14,212:1,220:8","15:3,33:2,37:1,40:1,46:11,61:2,86:25,138:10,153:8,169:4,174:9,221:8","16:1,33:2,46:12,60:4,87:24,140:6,153:12,169:14,222:7","16:1,33:2,46:11,60:6,86:26,154:13,168:10,179:2,222:6","45:12,60:9,86:8,96:16,153:16,171:9,213:1,221:7","1:3,45:12,60:10,86:9,99:12,112:1,153:16,172:8,213:1,221:7","1:3,16:1,45:11,60:14,85:12,101:13,124:3,136:3,155:24,220:8","15:2,44:3,48:8,61:16,85:13,104:9,123:7,135:5,160:5,166:13,222:7","1:1,15:2,44:12,63:6,70:3,74:6,85:14,107:6,123:18,162:19,190:4,223:6","1:1,5:1,16:1,44:4,49:6,65:4,70:12,85:14,110:3,123:18,165:19,189:5,223:6","0:2,15:2,45:2,49:6,64:4,69:30,103:1,125:6,132:10,149:2,165:21,187:8,223:5","0:2,14:3,44:1,48:7,63:5,72:17,90:7,102:3,123:20,148:5,165:30,213:1,222:6","3:1,8:1,14:3,43:2,48:7,63:7,74:14,89:7,100:6,123:7,131:13,148:6,165:6,172:24,213:1,222:7","7:2,14:1,42:3,48:6,63:8,77:19,99:7,124:1,126:19,148:5,154:5,164:13,179:18,212:3,220:9","1:3,5:4,42:12,64:7,80:6,88:19,126:2,130:15,149:12,164:13,180:17,213:3,222:6","1:9,14:1,42:10,53:1,64:6,71:2,82:10,93:5,99:8,131:10,142:3,148:22,171:6,182:16,213:2,223:6","1:9,16:1,42:1,45:9,64:10,83:8,94:14,130:15,148:6,155:21,185:13,214:2,222:8","1:8,15:2,43:1,46:8,64:10,82:8,92:1,94:14,130:9,140:4,150:18,169:7,189:9,214:2,220:9","1:3,5:3,14:3,41:1,46:7,64:3,68:7,82:10,93:16,130:7,138:3,156:12,169:6,190:7,213:2,221:1,223:6","1:2,5:3,15:2,41:2,44:9,64:11,82:20,103:6,129:8,138:3,158:17,195:2,213:2,220:2,224:2,227:2","1:7,9:1,15:2,40:10,51:1,64:3,68:7,81:13,97:12,129:12,154:3,160:18,188:2,213:1,220:1,224:5","1:2,6:4,15:1,40:12,64:10,81:12,99:10,129:5,135:6,153:5,163:6,170:11,186:5,213:2,219:2,225:1,227:2","3:1,6:3,16:1,40:1,42:10,66:8,81:10,102:7,128:13,153:7,165:4,170:13,185:6,213:2,219:2,224:4","3:7,16:1,42:5,48:4,64:10,81:12,104:5,128:12,153:8,168:24,213:2,219:9","2:8,16:1,42:4,47:5,65:8,80:13,107:1,128:12,154:9,171:3,176:16,219:2,222:6","2:8,15:2,38:3,43:3,47:4,66:6,80:13,129:7,137:3,146:2,154:2,158:6,166:3,174:19,212:2,223:5","1:9,16:2,38:8,47:4,68:2,79:10,90:2,127:6,135:1,137:2,145:4,155:3,159:5,166:5,176:18,212:3,223:5","1:9,16:2,38:13,79:13,126:3,130:3,135:2,145:7,156:8,166:8,179:15,212:3,223:5","1:9,16:2,38:8,49:1,66:1,80:12,126:6,134:4,145:8,156:8,166:9,182:13,212:2,219:1,222:6","2:9,15:3,38:9,66:2,69:3,79:12,126:6,133:1,135:3,146:8,155:10,166:12,183:13,212:2,219:8","3:8,16:3,37:2,41:8,67:5,78:13,126:5,133:1,135:3,147:8,156:8,165:14,182:15,206:1,212:2,219:8","3:8,16:3,37:6,46:3,69:6,78:13,126:10,147:4,152:11,165:14,181:16,212:2,219:9","2:9,16:3,40:4,47:2,68:10,79:9,89:1,126:6,135:2,147:9,157:5,164:15,181:16,211:2,218:9","2:6,10:2,17:2,45:4,68:3,73:13,87:1,89:1,125:8,135:1,147:9,164:14,180:16,211:3,218:9","3:9,17:2,47:1,69:2,74:13,88:1,124:8,133:2,148:9,164:12,179:17,218:5,224:3","3:9,17:1,19:1,71:1,73:2,76:13,124:4,129:7,147:10,163:13,179:10,210:1,218:1,220:6","3:10,18:2,71:18,124:4,129:7,140:3,147:9,163:13,179:8,210:1,217:2,221:5","4:2,8:4,18:2,72:17,123:12,140:5,149:7,162:14,180:3,210:2,217:5","4:3,8:4,18:1,20:1,72:5,78:2,82:6,123:12,140:7,149:6,162:13,210:2,217:5,224:2","6:6,18:3,72:8,83:5,123:12,141:10,162:7,170:5,209:3,217:7","4:1,6:5,12:1,18:3,72:8,83:5,122:13,142:8,151:3,164:5,172:2,209:2,217:8","5:8,18:3,72:8,84:3,122:12,145:10,162:1,165:1,167:6,210:2,218:7","5:9,19:3,71:9,82:3,86:1,122:1,124:2,127:6,138:20,165:8,210:1,216:9","5:9,72:7,82:2,121:18,140:13,154:9,166:7,216:9","5:9,20:2,73:7,83:2,118:22,141:1,144:3,149:15,167:5,208:3,215:10","6:9,20:2,32:2,79:1,84:1,118:7,126:16,147:7,155:4,160:5,167:3,207:3,215:9","6:10,20:3,32:1,117:25,150:8,160:1,163:1,169:2,181:4,207:3,215:9","6:5,12:4,22:1,117:23,153:5,160:3,165:1,169:3,180:5,207:2,214:10","6:10,22:2,118:20,155:9,166:8,178:8,207:2,214:5,220:4","6:4,11:5,22:2,119:18,153:16,170:16,206:3,214:9","7:9,22:1,119:17,152:17,170:4,175:11,207:1,214:1,216:7","8:9,38:1,118:12,134:1,152:9,162:7,170:17,205:3,213:1,216:6","8:9,23:2,120:12,150:14,167:20,205:3,213:9","8:6,16:2,23:3,120:10,149:16,170:18,204:3,212:9","9:9,25:1,120:9,147:18,172:17,204:3,211:3,215:7","9:9,120:8,145:10,156:1,158:9,175:15,203:2,211:10","9:6,17:1,26:1,121:4,140:15,156:12,179:11,203:1,211:10","9:9,121:4,138:9,148:11,162:8,180:9,203:1,205:1,210:6,217:4","10:1,14:2,17:3,26:2,122:2,136:21,158:1,163:9,183:6,202:3,211:5,218:2","11:1,15:3,19:1,26:3,129:9,140:19,164:10,186:3,201:4,210:6,218:1","12:1,14:4,26:3,129:8,140:16,164:11,201:3,209:7,217:2","12:7,20:1,27:3,129:9,139:13,165:11,201:3,209:10","12:7,20:1,27:3,130:4,135:14,165:2,168:10,200:3,210:3,216:2","12:6,20:2,28:2,135:3,140:2,166:12,199:3,207:4,216:2","12:5,20:2,28:1,166:13,199:1,201:1,207:6,216:1","14:3,18:1,22:2,167:13,198:2,206:7,215:1","15:9,31:1,167:13,198:3,206:9","15:9,31:2,168:13,197:3,205:10","15:7,23:1,31:3,168:5,174:7,196:4,205:7,213:2","16:6,23:2,31:2,168:14,196:3,205:1,207:5,213:1","16:6,24:1,169:12,195:2,204:7,212:1","17:1,19:1,25:1,169:2,172:9,194:4,203:7,211:2","16:3,23:1,35:2,168:13,195:2,202:8,211:1","17:2,20:3,25:3,34:3,169:11,193:3,201:11","21:7,36:1,168:12,192:2,201:11","19:7,27:1,37:2,170:8,192:2,200:11","20:8,37:2,171:6,191:3,199:12","21:2,24:2,27:2,37:1,172:4,190:2,199:12","21:5,29:2,189:1,198:7,206:3","21:3,26:6,39:3,188:2,198:11","23:1,26:2,29:3,40:3,187:4,198:10","23:8,42:1,187:3,198:9","24:10,186:3,195:4,200:7","24:4,29:2,32:4,44:1,185:2,194:4,200:6","27:9,43:3,183:4,194:12","27:9,44:3,183:3,194:11","27:4,32:5,44:4,182:1,184:1,194:4,200:4","27:5,34:3,45:4,181:3,191:1,193:4,200:3","27:7,36:1,48:2,180:4,190:7,199:2","28:7,38:3,48:3,178:3,182:1,189:8,199:1","29:3,34:3,39:2,48:4,177:4,188:11","31:1,33:10,49:5,179:1,187:12","31:5,37:3,41:3,53:2,187:12","32:7,41:4,173:2,188:6,195:2","33:12,175:1,186:3,190:4,195:1","35:1,37:9,183:12","36:5,42:5,184:1,187:1,189:5","36:12,169:1,187:1,190:3","37:7,45:3,61:1,167:2,185:1,187:1,190:2","38:8,165:5,187:1,190:1","39:7,51:2,64:2,164:5,177:2,184:1,186:1","40:7,51:2,64:3,162:5,175:4,184:3","41:6,51:1,64:6,160:5,185:2","42:6,51:1,53:1,55:2,66:5,158:3,162:1,176:1,184:2","44:3,52:1,54:4,67:3,71:2,157:5","44:1,52:2,55:2,69:1,71:4,154:6,169:2","51:3,55:2,60:1,72:4,153:4,167:4","51:6,58:1,60:2,73:7,150:7,167:4","51:11,76:7,147:7,164:7","50:8,60:2,64:3,77:7,143:7,162:13","50:6,57:1,60:2,63:5,79:4,84:5,141:8,159:4,164:8,173:3","52:6,60:8,83:7,136:2,139:8,158:13,173:3","53:4,60:4,65:3,70:3,85:11,133:4,138:1,140:3,155:5,161:10","55:3,60:9,70:5,88:3,92:10,128:6,135:3,155:17","59:2,62:3,66:7,75:3,93:4,98:13,117:2,121:4,126:4,133:4,151:4,157:5,163:8","59:6,66:8,75:4,97:1,100:1,102:4,107:3,112:1,114:1,118:2,124:7,151:4,157:13","60:5,66:8,75:8,103:3,108:1,113:2,117:4,145:22","62:3,67:1,69:16,143:6,150:10,162:4","63:1,65:2,68:3,72:9,82:8,138:1,141:13,155:5,161:4","67:14,82:14,133:2,138:2,141:21","68:32,131:17,149:12","72:20,93:3,98:6,114:4,119:3,123:3,130:6,137:13,152:5","73:19,94:10,108:3,113:11,125:1,132:12,145:2,148:8","75:9,85:20,109:2,113:11,133:1,135:2,138:2,141:6,148:3","79:27,107:17,133:3,138:2,141:9","80:14,95:22,118:5,134:2,138:8","86:37,133:3,138:3,142:2","91:7,100:4,105:19,126:1,132:3,136:3","92:2,95:3,99:15,115:3,119:6,126:2","103:24","107:1,115:3",""},
    reading={"113:3,120:3","107:4,113:6,120:5,126:2,130:3","101:3,105:19,127:1,129:11","96:1,100:24,133:3,137:9","93:6,101:4,106:21,128:2,134:1,137:4,143:6","89:8,98:31,137:2,140:15","87:5,94:35,140:16","82:11,95:7,103:11,115:12,134:2,141:17,160:1","79:6,86:2,91:29,124:3,133:3,143:15,159:5","76:11,95:6,102:18,125:2,134:1,144:21","73:17,92:1,98:3,102:6,109:2,144:8,153:15","71:5,77:4,82:8,98:2,143:5,149:20","71:5,77:12,92:1,144:2,148:22,172:1","67:16,84:5,150:13,164:1,166:3,170:4","66:23,113:1,116:1,152:23","65:14,80:2,83:3,87:1,106:3,111:12,127:2,130:1,157:14,172:5","62:13,77:5,101:8,111:17,141:1,159:20","59:5,65:2,68:6,77:3,99:15,125:3,132:1,138:1,140:4,163:3,167:14","58:13,72:2,94:6,101:2,138:3,142:8,164:2,168:13","56:15,73:1,89:2,92:1,94:4,145:6,168:8,177:3","55:18,86:5,146:10,168:13,182:4","54:18,83:3,87:5,150:4,155:1,169:1,171:16","53:7,61:2,65:3,81:9,156:3,172:17","50:4,55:7,65:2,80:5,156:7,176:1,178:12","49:4,55:7,63:2,76:1,78:5,159:2,163:1,176:1,179:11","48:14,74:5,164:1,178:15","47:10,59:3,72:1,75:3,165:5,179:16","45:11,57:4,70:4,76:1,166:5,181:14","43:7,51:7,70:3,167:2,171:1,182:14","43:14,67:1,70:2,168:6,183:14","42:10,54:2,64:3,70:1,171:3,184:13","40:3,44:4,49:6,63:5,172:3,186:5,193:3,197:3","39:8,48:5,62:4,175:4,187:9,197:3","38:6,45:4,51:1,60:2,63:3,176:4,188:3,192:8","37:12,59:2,177:5,192:10","37:1,42:2,45:4,58:4,179:4,192:11","36:1,44:4,57:4,180:1,182:1,193:11","40:2,43:1,54:2,59:1,183:1,193:13","54:2,183:4,194:14","32:3,54:2,184:3,196:11","31:4,51:1,54:1,185:4,198:8","31:3,50:4,186:4,198:8,207:2","30:3,34:1,49:4,188:3,198:9","29:1,31:2,189:4,199:8,209:1","28:4,190:3,200:2,203:9","27:6,47:1,191:2,203:10","26:7,191:2,202:11","26:10,43:2,195:1,202:12","24:5,30:3,195:2,204:10","23:10,35:1,42:1,44:2,195:3,204:11","22:3,29:3,197:1,205:12","22:4,27:3,42:1,197:3,206:11","22:3,26:4,39:1,197:4,208:10","26:3,38:2,41:1,198:1,200:1,208:11","26:5,38:3,200:2,208:11","20:1,26:5,37:4,200:3,209:10","29:1,37:3,201:1,203:1,209:12","203:1,211:10","18:8,35:2,202:3,211:4,217:5","16:4,21:5,34:3,203:3,211:11","16:10,33:4,204:2,212:10","16:3,21:6,33:3,205:1,213:7,222:1","15:5,21:5,32:1,34:1,205:3,213:7,222:1","16:8,34:1,206:3,214:8,223:1","14:9,31:2,207:3,214:4,219:6","13:11,30:3,207:3,216:3,220:6","13:10,30:3,81:2,208:3,216:10","12:5,18:5,29:1,31:1,81:3,208:2,217:10","12:7,20:2,29:1,80:5,209:1,211:1,217:9","11:11,29:2,80:6,210:2,218:4,224:3","11:11,27:3,79:3,83:6,210:2,218:6,225:3","11:10,27:1,53:2,78:5,84:6,211:2,218:2,221:3,225:4","10:9,26:3,53:6,78:13,211:3,219:1,221:8","9:10,26:3,53:8,77:15,212:1,214:1,221:8","9:10,25:4,52:10,63:2,76:18,212:3,222:2,225:5","9:3,13:2,16:3,25:3,51:8,60:1,62:5,75:6,82:1,85:9,213:1,222:9","10:9,25:3,51:9,63:3,67:2,74:13,88:6,213:1,222:4,227:3","9:1,11:7,26:1,51:9,61:5,67:2,70:24,215:1,221:9","12:3,51:12,64:2,67:1,71:10,82:5,88:3,214:3,222:3,227:4","8:9,52:7,62:1,65:2,71:10,82:5,88:2,216:1,222:10","7:10,24:2,55:3,60:3,64:25,222:10","6:10,24:1,59:4,64:4,69:19,216:2,223:9","6:4,11:5,24:1,64:14,79:9,216:3,223:5,229:2","6:3,11:5,22:1,66:8,75:13,216:3,223:2,226:1","5:6,12:4,21:3,66:17,84:4,91:3,216:3,225:2","5:8,14:1,21:3,65:12,78:4,85:3,90:3,94:3,217:2,225:3,230:1,232:1","5:10,20:3,64:4,69:2,73:13,88:5,96:4,217:3,225:1,230:4","6:9,20:3,63:20,86:4,91:2,94:9,117:1,217:3,225:1,229:5","6:1,8:6,20:2,63:5,69:11,81:4,86:7,94:2,97:2,101:4,116:5,217:3,229:4","5:9,20:2,62:5,69:10,83:2,86:4,91:17,115:6,146:1,218:3,229:3","5:9,20:2,60:2,63:5,69:9,86:4,92:12,105:7,114:7,145:3,219:2,229:1","4:10,20:2,58:2,63:14,90:7,98:23,144:4,228:1","4:9,57:3,62:12,92:8,102:6,110:12,144:7,219:2,226:3,235:1","4:7,18:3,56:9,66:8,90:1,94:12,107:15,145:9,219:3,226:3","4:5,18:3,56:16,89:3,97:1,99:3,104:19,147:7,219:3,227:3,234:1","3:5,18:3,54:17,88:6,100:9,110:13,145:10,219:2,227:3,234:2","3:5,17:3,53:7,61:10,88:8,104:20,145:11,220:3,227:4,233:3","2:6,18:2,51:8,60:10,88:9,107:17,146:7,154:3,220:3,229:2,235:2","2:6,9:2,17:2,49:9,60:6,88:14,109:1,111:14,146:12,220:3,227:1,230:1,236:1","3:2,7:2,10:2,17:2,48:18,87:16,113:9,123:2,146:12,220:3,227:2,230:1","7:1,10:1,17:2,46:17,64:3,87:12,100:3,115:9,146:12,178:3,221:2,228:3","8:3,17:2,45:22,87:6,95:8,117:7,146:6,153:5,178:7,221:1,229:3,236:1","2:1,7:1,10:1,17:2,44:5,50:16,86:6,94:8,121:3,145:13,178:8,189:1,221:1,228:8","17:2,43:23,86:11,99:1,145:13,178:7,187:4,228:8","16:3,40:1,43:13,59:7,85:15,145:12,163:1,177:14,229:9","2:1,37:2,40:6,47:6,54:2,58:3,62:4,71:1,85:13,146:10,162:4,177:4,183:8,229:9","2:1,16:1,36:3,41:18,62:2,69:4,85:7,93:5,146:9,162:6,177:5,183:8,229:8","1:2,16:1,33:5,48:1,51:6,58:2,61:2,69:6,84:15,148:6,161:12,177:4,182:9,222:1,229:6,236:2","7:1,16:2,33:5,43:1,50:11,62:1,69:9,84:15,162:5,169:5,176:10,187:2,222:1,230:9","16:2,34:3,39:1,49:14,69:7,77:4,84:6,91:7,161:8,170:18,231:8","17:1,34:3,49:14,71:27,161:16,180:8,232:7","17:1,34:3,49:14,68:30,132:2,144:2,163:5,169:8,178:10,232:7","48:8,57:6,68:13,82:4,88:10,131:6,142:5,167:6,175:12,231:7","1:3,48:14,71:4,76:11,88:5,94:3,105:2,131:7,140:7,169:4,174:5,180:8,199:4,222:2,231:7","1:3,17:1,48:14,76:8,85:11,104:4,131:6,138:5,145:3,173:21,198:4,230:8","15:3,48:2,52:9,77:21,102:7,132:16,156:2,173:10,184:11,196:7,224:1,232:7","16:2,47:4,52:2,55:6,81:28,131:7,139:10,155:4,173:31,233:6","1:1,5:1,17:1,48:3,52:9,80:17,98:11,130:8,140:8,155:6,173:7,181:6,188:16,233:6","0:2,16:1,48:3,52:8,80:13,95:11,107:3,130:6,137:14,155:7,172:14,187:18,233:5","0:2,15:3,47:1,52:8,80:6,88:5,94:17,133:19,155:6,162:5,172:13,188:18,223:1,232:6","8:2,15:3,46:2,52:8,80:17,99:12,137:15,156:14,172:13,190:9,200:6,222:2,232:7","7:2,15:1,46:2,51:8,79:12,92:1,96:16,137:11,149:3,154:24,179:6,192:1,194:13,222:2,230:9","1:3,5:5,45:14,79:9,89:4,98:5,104:7,136:15,156:5,163:22,198:8,223:2,232:6","1:9,15:1,45:11,57:1,78:10,89:4,100:11,136:14,158:15,174:1,177:7,199:7,223:2,232:7","1:9,17:1,45:1,48:9,78:15,103:8,135:9,145:1,147:1,163:2,166:2,169:7,177:6,204:1,224:1,233:7","1:9,16:2,46:1,49:9,78:2,81:12,106:5,135:8,144:3,162:1,167:10,178:6,197:2,224:2,230:10","1:3,5:4,15:3,44:1,47:1,49:4,54:4,77:15,135:12,161:3,168:21,195:4,223:2,231:1,233:6","1:2,5:3,16:2,44:2,47:10,78:14,135:6,142:5,160:6,172:5,178:12,193:7,222:3,230:1,234:2,238:1","1:4,6:2,9:1,16:2,43:10,55:2,78:5,84:7,134:13,164:1,166:2,174:26,222:2,234:5","1:2,6:4,16:2,43:11,55:1,76:4,81:10,134:5,140:6,161:8,178:23,222:3,229:2,235:1,237:2","3:1,6:1,8:2,17:1,43:1,45:11,76:15,134:12,161:10,174:2,181:1,184:17,222:3,229:2,234:5","3:8,17:1,45:5,51:5,76:14,135:11,153:2,162:1,166:5,174:4,183:19,223:1,229:10","2:9,17:1,44:5,50:6,75:14,133:9,144:1,152:4,162:3,166:6,174:6,186:7,194:9,223:1,229:2,232:6","2:9,16:2,41:3,46:3,50:5,57:2,75:4,80:9,132:3,136:4,141:2,151:3,155:4,163:9,173:9,188:12,201:3,222:2,233:5","1:10,16:3,41:14,57:6,75:3,80:6,87:1,131:4,136:2,141:4,152:8,162:10,173:13,191:13,221:3,233:5","1:9,17:2,41:14,57:7,74:9,84:4,132:6,139:5,155:6,162:10,173:14,190:15,221:3,233:5","1:9,16:3,41:8,52:2,56:6,64:4,74:7,82:6,132:5,139:1,141:1,143:1,153:18,173:14,190:16,221:3,229:1,232:6","2:9,16:3,40:11,56:8,65:3,74:6,82:6,132:2,135:7,153:5,159:11,172:15,189:17,221:3,228:9","3:8,17:3,40:2,43:4,48:3,52:1,56:28,85:3,132:7,140:3,154:9,165:3,171:6,178:2,181:6,188:3,192:13,215:1,222:1,228:9","3:8,17:3,40:2,43:3,49:3,56:21,79:3,83:4,130:9,141:1,154:10,171:14,187:17,222:1,228:10","2:9,17:3,43:3,50:2,56:10,67:8,77:6,86:1,130:9,141:1,154:9,171:13,186:11,221:2,228:9","2:7,11:2,18:2,48:4,59:6,67:7,79:5,85:1,129:9,139:3,154:9,170:14,188:8,221:2,228:9","3:9,18:2,63:3,67:4,72:1,77:1,80:6,100:1,129:5,135:7,146:3,154:9,169:15,188:4,228:5,234:3","3:10,18:1,20:1,65:15,82:6,100:4,129:12,146:6,155:7,169:14,220:1,227:2,230:6","3:6,10:3,19:1,67:13,84:8,98:6,129:3,133:8,146:7,156:5,169:13,219:2,227:2,231:3,235:1","4:3,8:5,19:2,69:10,81:1,86:3,90:4,97:7,128:13,147:10,170:7,178:4,219:3,227:5","4:3,8:5,19:3,74:4,82:2,86:4,92:12,128:7,136:5,148:8,158:2,172:4,178:1,180:2,219:3,227:5,233:3","6:7,19:3,75:2,82:2,87:3,91:13,128:13,149:1,151:6,158:5,169:1,172:1,174:2,177:3,219:2,227:7","5:8,19:3,82:2,88:17,127:12,145:3,149:16,166:2,172:9,218:3,227:1,229:6","5:9,19:3,87:4,93:8,102:4,127:4,132:28,161:9,174:6,219:2,228:8","5:9,20:3,86:5,93:13,125:2,128:18,147:1,151:3,156:15,174:6,219:1,226:9","6:8,20:1,86:21,123:7,132:16,154:7,162:4,167:3,171:1,175:3,189:4,225:10","6:9,21:2,90:8,99:8,123:7,131:17,156:9,170:1,176:1,188:5,217:3,225:5,231:3","6:10,21:2,34:1,93:15,123:23,160:5,167:2,170:1,176:2,187:7,217:3,225:9","6:10,21:3,94:1,96:13,123:7,131:11,143:2,162:9,173:11,186:8,216:3,226:8","6:5,12:4,23:2,97:7,105:3,124:20,160:16,177:17,216:3,224:10","6:10,23:2,99:1,101:7,124:18,159:17,178:4,183:12,216:3,224:5,230:3","7:3,11:5,23:2,104:3,124:12,137:1,139:2,158:18,178:17,216:2,224:9","8:8,23:1,124:12,137:1,157:15,175:21,216:1,224:1,226:7","8:9,40:1,125:11,155:17,178:18,214:3,223:1,226:6","9:7,17:1,24:3,125:10,154:18,181:17,214:3,222:9","9:5,17:2,24:3,125:9,152:10,163:1,165:10,184:14,214:3,221:10","9:10,26:1,126:5,148:13,163:13,187:11,213:3,221:11","9:10,126:4,145:23,169:9,188:9,213:1,220:11","10:6,17:2,27:1,126:4,142:22,165:1,170:10,192:5,212:1,220:11","10:3,14:5,37:1,135:3,139:5,145:20,171:10,195:2,212:1,214:1,220:6,227:4","10:2,15:2,18:3,27:2,135:8,146:17,171:12,211:3,220:6,228:2","15:4,20:1,27:3,135:8,145:1,148:11,172:3,176:8,210:4,219:7,227:1","12:7,27:3,135:9,145:11,172:13,210:3,219:7,227:2","13:7,21:1,28:3,135:4,140:9,150:2,154:1,173:4,178:8,210:3,219:1,221:8","12:6,19:1,21:1,29:3,174:13,209:3,219:4,226:2","12:6,21:2,29:3,174:13,208:3,216:4,225:2","13:5,21:2,29:2,174:14,208:1,210:1,216:2,219:3,225:2","13:5,19:1,23:2,32:1,175:14,207:2,215:7,224:1","15:3,19:6,175:6,182:6,206:3,215:10","16:9,32:3,175:14,206:3,215:10","16:7,24:1,32:3,176:13,205:4,214:11","16:7,24:2,33:1,177:12,204:4,214:1,216:5,222:2","17:6,25:1,176:3,180:9,204:2,213:7,221:2","17:2,20:1,26:2,36:1,176:12,203:3,212:8,221:1","17:3,37:1,176:12,204:2,212:10","18:2,21:3,26:4,36:3,176:11,202:3,210:11","22:8,36:1,38:1,177:9,201:2,210:11","20:7,28:1,39:1,179:5,200:3,209:11","21:8,39:2,181:2,200:3,208:12","22:8,39:1,199:1,208:12","22:5,30:3,198:1,207:12","22:4,27:6,41:3,197:2,207:11","24:1,27:2,30:4,42:2,196:3,206:12","24:6,31:2,44:1,195:4,206:10","25:11,194:4,204:4,209:7","25:4,31:1,33:4,46:1,193:2,203:4,209:7","28:9,45:3,192:4,202:13","28:10,45:4,191:4,203:11","28:4,33:6,46:4,190:1,192:2,203:3,209:4","28:5,35:4,47:4,189:4,199:1,202:4,209:3","29:5,35:1,38:1,51:1,188:4,198:8,208:2","30:6,40:3,51:3,186:3,190:1,197:7,205:1,208:1","30:3,35:4,40:3,51:4,185:4,196:11","32:1,35:9,52:4,187:1,195:12","33:5,39:3,43:3,56:1,195:12","34:7,43:4,181:2,196:6,204:2","34:13,56:1,183:1,194:4,199:3","36:2,39:9,56:1,191:4,196:8","37:1,39:3,44:5,177:1,192:1,195:2,198:5","37:14,176:2,196:1,198:4","38:8,47:3,64:1,175:2,193:4,199:2","40:8,173:4,195:1,199:1","41:7,54:1,67:2,172:4,184:3,192:1,194:2","42:7,54:2,67:3,169:5,183:4,192:3","43:6,67:6,167:5,194:2","44:6,53:1,56:4,69:5,165:3,169:1,184:1,192:2","46:3,55:5,71:2,74:3,162:1,164:5","46:1,54:6,72:6,161:7,176:3","54:3,58:1,63:1,76:3,159:5,175:4","54:5,60:5,76:7,156:8,174:4","53:12,79:7,153:7,172:6","52:7,60:1,62:2,67:3,81:7,150:7,169:14","53:6,60:1,62:3,66:5,82:5,88:5,148:8,167:12,180:4","54:5,60:1,63:8,87:7,142:2,146:8,165:13,181:3","56:3,63:4,68:3,73:4,89:11,139:4,144:6,162:6,169:9","58:2,63:9,73:5,92:3,96:11,133:7,141:3,162:17","61:7,69:8,78:4,97:5,103:13,122:3,126:5,132:4,138:5,158:4,164:15","62:6,69:8,78:5,102:1,104:2,107:4,112:3,117:1,119:1,123:2,130:6,157:5,164:13","63:5,70:7,78:9,108:2,113:1,118:3,122:5,151:23","65:3,70:1,72:5,78:11,149:6,157:10,169:5","68:2,71:3,75:10,86:8,144:2,147:20,168:4","70:14,85:15,138:3,144:2,147:22","71:33,137:4,142:26","75:21,97:3,102:7,114:1,119:4,124:3,128:4,136:3,140:2,143:14,159:5","77:20,99:10,113:3,118:11,130:2,137:14,152:1,155:8","78:9,89:20,114:2,118:10,129:1,138:2,141:2,144:9,155:3","83:28,112:11,124:5,138:4,144:3,148:8","84:14,99:30,140:2,144:8","90:39,139:3,145:1,149:1","95:8,104:4,109:21,131:1,138:6","96:2,100:2,104:15,120:4,125:5,132:2","107:17,125:7","112:1,120:3",""},
    finished={"110:1,115:3","103:4,108:12,121:2,124:3","97:22,121:2,124:5,130:4","92:1,96:23,127:3,131:8","89:6,96:4,102:22,128:2,131:4,137:3,141:2,146:1,151:1","85:8,94:30,125:1,132:16","83:5,90:33,134:16","79:10,91:6,98:11,110:12,128:2,135:17,153:1","75:6,83:2,87:28,119:2,127:3,136:21","73:11,90:7,98:17,120:1,128:1,138:20","70:16,88:1,94:12,138:8,147:14","68:4,74:4,79:7,94:2,137:5,143:19","68:5,74:11,88:1,138:2,141:22,164:1","64:15,81:4,144:12,157:1,159:7","63:22,111:1,145:22","62:13,77:1,79:3,83:1,101:3,106:12,121:2,150:19","61:11,73:6,97:8,106:16,152:19","57:4,62:2,65:6,73:3,94:15,120:2,126:2,132:6,156:3,160:13","56:12,69:2,90:5,96:3,132:11,157:1,161:13","54:14,70:1,85:2,88:6,138:7,160:8,169:4","53:17,83:5,91:1,140:9,161:12,174:2","52:17,80:2,83:5,144:3,148:2,162:1,164:15","50:7,58:3,62:3,77:9,149:3,164:17","48:11,62:2,76:5,150:6,166:1,170:11","47:4,52:10,72:2,75:4,152:2,155:2,171:12","46:14,71:5,157:1,171:4,176:8","45:7,53:1,57:2,69:1,71:4,158:1,160:2,171:15","43:11,55:1,57:1,67:4,159:4,173:14","41:7,49:6,67:3,160:2,163:1,175:13","41:14,64:1,67:2,161:6,175:13","40:10,52:2,62:3,66:2,164:3,176:13","38:3,42:4,47:5,61:4,165:3,179:4,185:2,188:3","37:14,60:4,167:4,179:8,188:4","36:6,43:4,58:2,61:2,168:4,180:3,184:8","36:11,57:1,169:5,184:2,187:6","35:1,40:7,55:4,171:4,184:10","34:1,38:1,42:4,55:4,172:1,174:1,184:11","39:1,52:2,56:2,175:1,184:14","51:3,175:4,185:14","31:2,51:2,176:3,187:11","30:3,49:1,52:1,177:4,190:7","29:4,48:4,178:4,189:7,198:2","29:4,47:4,180:3,190:8","28:1,30:2,37:1,181:3,191:7,200:1","27:4,37:1,182:2,192:1,194:9","26:5,45:2,182:3,194:10","25:6,183:1,185:1,193:10","25:10,42:1,187:1,194:10","23:4,28:4,187:2,195:10","22:10,33:1,41:1,43:1,187:3,196:10","21:3,27:4,32:1,188:2,196:12","21:3,26:2,40:1,188:4,197:11","21:3,25:4,189:3,199:10","25:2,37:1,39:1,189:4,199:10","25:5,36:4,191:2,199:10","25:5,35:4,191:4,200:10","28:1,35:3,192:1,194:1,200:11","194:2,201:10","17:8,34:2,194:2,202:4,207:5","16:3,20:5,33:2,194:3,202:10","15:4,20:5,32:3,195:2,203:9","15:3,20:5,32:3,196:1,204:7,212:1","15:4,20:5,31:1,33:1,196:3,204:6,212:1","15:8,31:1,197:3,205:7,213:1","13:9,30:2,198:2,205:4,210:5","13:10,29:3,55:2,198:3,206:4,211:5","12:10,29:3,54:4,199:3,207:10","12:2,15:1,17:5,28:3,53:5,199:3,207:10","11:7,19:2,28:1,53:8,200:1,202:1,208:8","11:10,28:1,53:5,59:4,201:2,208:5,214:3","11:10,26:2,54:10,201:2,209:5,215:3","11:9,26:1,54:6,61:4,202:2,209:2,212:2,215:4","10:6,17:1,25:3,54:5,61:5,202:2,209:2,212:7","9:9,25:3,55:12,204:2,211:8","8:10,24:3,55:12,89:3,203:2,212:3,216:4","9:2,12:2,15:4,24:3,55:4,60:8,89:6,203:2,213:2,216:5","9:3,13:5,24:2,55:3,60:8,89:8,204:1,212:4,217:4","11:6,24:2,55:14,89:10,205:2,212:9","8:1,11:4,16:1,55:5,61:5,67:1,89:13,205:2,212:4,217:4","7:9,55:5,62:6,74:1,88:14,213:9","6:10,23:1,55:12,73:4,88:14,213:9","6:10,23:1,55:9,65:2,73:7,88:4,93:9,206:2,213:9","6:10,23:1,55:10,72:12,87:5,93:7,206:3,214:4,219:2","6:3,11:4,21:1,56:8,73:1,75:11,87:5,93:6,207:2,214:1,216:2,222:1","5:6,12:3,20:3,58:3,73:26,207:2,215:2","5:7,13:1,20:3,73:3,77:2,80:19,207:3,215:3,220:1,222:1","5:9,19:3,42:3,55:3,73:10,84:7,92:7,110:3,208:2,215:2,220:4","5:9,19:3,42:6,54:5,79:20,109:4,208:3,215:1,220:4","5:9,19:2,42:8,52:7,80:12,93:2,96:6,107:6,208:2,219:4","5:9,19:2,42:13,56:3,84:30,209:2,220:2","5:8,19:2,42:18,66:2,85:1,88:11,100:7,108:7,210:1,219:1","4:9,19:2,42:15,58:3,66:4,84:9,94:21,210:1,218:2","4:9,42:20,65:7,84:7,92:4,97:19,210:1,217:2,225:1","4:6,11:1,18:2,42:8,51:11,66:9,84:4,89:2,92:2,95:6,102:14,210:2,217:2","3:6,17:3,42:8,52:11,66:12,84:7,92:4,100:17,210:2,217:3,224:1","3:5,17:3,46:1,48:16,66:15,83:9,93:3,102:2,105:3,109:9,158:2,210:1,217:3,224:2","3:5,17:2,49:8,58:6,65:8,74:18,93:2,105:4,110:6,117:1,158:3,211:2,217:4,223:3","2:5,17:2,49:8,58:5,66:6,73:22,109:9,157:6,211:2,218:3,225:1","2:6,9:2,17:1,48:8,57:6,69:26,111:6,158:7,211:2,217:1,220:1,225:2","3:2,7:1,9:2,16:2,48:12,73:6,80:14,114:2,137:3,158:10,211:3,218:1,220:1,223:1","7:1,9:2,16:2,48:11,73:1,76:19,107:3,137:4,158:12,211:3,218:3","8:2,16:3,47:9,57:2,72:3,78:21,106:4,136:6,158:13,212:1,219:3,226:1","2:1,6:2,10:1,16:2,48:11,71:6,82:20,104:7,135:6,158:5,164:4,170:2,219:7","16:2,47:12,71:2,74:4,84:9,95:16,135:7,158:4,165:4,170:3,219:7","16:2,46:12,71:3,75:4,87:10,98:14,137:6,158:5,165:8,219:8","2:1,17:1,46:4,51:7,72:9,90:23,132:3,137:9,158:6,165:8,219:9","2:1,15:1,46:11,72:9,85:2,92:2,95:18,131:18,158:4,163:5,169:4,219:8","1:2,15:1,46:11,64:3,73:3,77:5,84:3,88:1,96:5,102:12,130:22,158:14,212:1,219:6,226:2","6:1,15:3,45:1,47:10,63:5,73:10,84:7,99:15,129:27,158:13,212:1,220:8","15:3,44:2,47:9,63:7,74:8,84:2,87:6,102:13,127:44,221:7","16:1,44:8,53:3,63:8,74:22,102:14,126:5,132:4,138:25,164:5,222:7","16:1,44:6,53:3,64:7,74:8,83:14,101:15,125:15,143:12,156:13,222:6","44:7,52:2,55:1,64:9,74:7,83:11,95:2,101:16,125:14,146:9,157:1,159:7,167:3,213:1,221:7","1:3,44:10,65:9,75:5,83:6,90:7,100:16,125:14,150:24,213:1,221:7","1:3,16:1,44:11,65:10,76:3,82:14,99:3,103:12,125:13,153:10,165:11,190:2,220:8","15:2,43:12,65:10,81:13,98:13,112:2,126:12,159:5,165:14,188:5,214:1,222:7","15:2,42:13,66:9,81:12,98:10,126:12,159:2,165:17,187:6,223:6","1:1,5:1,16:1,42:12,66:5,72:3,81:12,98:8,126:11,162:2,165:7,173:6,180:14,223:6","0:2,15:2,42:3,46:8,57:3,65:10,80:13,99:2,127:9,138:2,165:6,172:22,223:5","0:2,14:3,42:4,47:7,57:6,66:8,80:13,128:7,137:5,168:27,213:1,222:6","3:1,8:1,14:3,41:5,47:6,57:8,67:6,80:12,130:3,137:8,172:18,192:4,213:1,222:7","7:2,14:2,41:5,47:6,57:15,80:7,88:4,137:11,174:3,178:18,212:3,220:9","1:3,5:4,41:11,57:1,59:6,66:5,79:12,137:14,179:18,213:3,222:6","1:9,41:11,56:1,60:2,63:5,69:4,78:6,86:5,138:15,181:16,213:2,223:6","1:9,16:1,40:2,43:16,60:12,73:3,78:12,137:21,172:2,182:16,214:2,222:8","1:8,15:2,36:5,43:13,57:2,60:11,72:10,83:7,137:5,143:17,170:4,182:16,214:2,220:1,222:7","1:8,14:3,35:24,62:5,68:15,84:5,138:25,169:6,181:18,213:2,221:8","1:2,5:3,15:2,35:24,65:1,67:16,84:1,86:3,100:3,143:4,148:18,167:2,170:5,180:19,213:2,220:2,224:2,227:2","1:7,9:1,15:2,36:15,52:6,67:12,81:4,87:2,99:4,146:12,159:10,170:6,179:19,213:1,220:1,224:5","1:2,6:4,15:1,36:21,71:14,87:2,97:7,122:3,149:4,154:15,170:6,179:19,213:2,219:2,225:1,227:2","3:1,6:3,36:2,39:16,73:20,96:8,122:2,125:3,153:16,171:4,176:1,179:11,191:1,193:1,196:1,213:2,219:2,224:4","3:7,16:1,36:1,39:9,49:5,73:11,85:20,122:6,130:1,156:15,172:5,179:8,213:2,219:9","2:8,16:1,37:1,39:2,42:11,72:33,122:12,159:19,180:2,219:9","2:9,15:2,37:1,39:8,48:4,71:17,89:17,122:14,161:18,212:2,223:5","1:9,16:2,37:13,69:5,76:6,83:2,86:21,122:18,165:14,212:3,223:5","1:9,16:2,38:11,68:17,87:20,122:3,126:17,167:13,212:3,223:5","1:9,16:2,38:9,66:18,90:18,122:12,135:8,144:2,170:9,212:2,219:1,222:6","2:9,16:2,38:9,65:7,73:13,93:16,127:9,139:3,143:7,172:6,212:2,219:8","3:8,16:3,38:6,61:11,74:13,96:13,130:7,138:15,175:3,205:2,212:2,219:8","3:8,16:3,38:5,59:15,75:3,79:10,99:10,134:11,147:9,212:2,219:9","2:10,16:3,39:5,54:9,64:15,81:6,88:2,102:6,137:7,148:9,211:2,218:9","2:6,10:2,17:2,41:1,48:1,51:12,64:14,82:10,105:3,137:5,147:9,159:2,182:2,211:3,218:9","3:9,17:2,47:10,59:11,71:4,83:10,137:6,147:9,158:7,181:4,218:5,224:3","3:9,17:1,19:1,46:9,56:1,59:14,83:3,87:8,136:11,149:7,158:9,180:5,210:1,218:1,220:6","3:10,18:2,47:9,59:1,61:10,83:7,92:4,136:12,149:5,158:2,161:4,166:4,178:8,210:1,217:2,221:5","4:2,8:4,18:2,47:12,60:7,84:6,93:5,135:12,148:1,152:1,155:1,158:2,161:13,176:10,210:2,217:5","4:3,8:4,18:1,20:1,53:3,57:2,85:13,135:14,155:4,161:10,172:15,209:3,217:5,223:3","6:7,18:3,85:8,94:2,97:2,134:9,145:3,155:2,159:1,161:26,209:3,217:7","4:1,6:5,12:1,18:3,86:13,133:14,155:3,159:2,163:22,186:2,209:2,217:8","5:8,18:3,86:10,97:3,133:14,154:9,166:19,187:1,209:3,219:6","5:9,19:3,86:15,132:7,141:6,154:10,167:5,173:16,210:1,216:9","5:9,21:1,87:14,132:14,155:10,169:21,216:9","5:9,20:2,87:7,95:6,131:14,153:8,162:2,172:18,208:3,215:5,221:4","6:9,20:2,33:1,88:13,130:14,153:11,178:13,207:3,215:9","6:10,20:3,32:1,88:3,92:9,129:6,136:6,155:9,178:13,207:2,215:9","6:5,12:4,22:1,88:3,93:8,128:10,139:3,152:12,181:10,207:2,214:10","6:10,22:2,88:8,97:4,127:15,152:12,185:5,207:2,214:5,220:3","6:4,11:5,22:2,88:8,97:3,125:17,152:9,162:2,187:3,206:3,214:9","7:8,22:2,88:11,124:17,152:11,207:1,214:1,216:7","8:9,38:1,90:9,122:18,151:12,205:2,213:1,216:6","8:9,23:2,91:6,120:3,124:11,136:2,151:1,153:10,205:3,213:9","8:6,16:2,23:3,93:2,118:4,123:14,150:5,156:1,158:4,204:3,212:9","9:5,15:3,24:2,115:6,122:1,124:2,127:1,129:6,150:12,204:3,211:3,215:7","9:9,111:9,122:2,125:3,129:5,150:11,203:3,211:10","9:6,17:1,26:1,110:10,123:1,125:6,149:12,178:3,203:1,211:10","9:9,109:10,124:6,149:12,177:5,202:2,210:6,217:4","10:1,14:2,17:3,26:2,109:9,119:2,124:2,149:11,177:4,202:3,211:5,218:2","11:1,15:3,19:1,26:3,109:11,148:4,153:7,176:5,201:4,210:6,218:1","12:6,26:3,148:4,156:5,175:6,201:3,209:7,217:2","12:7,20:1,27:3,148:8,157:6,175:6,201:3,209:10","12:7,20:1,27:3,148:6,156:2,159:2,162:4,174:7,200:3,210:3,216:2","12:6,20:2,28:3,148:2,153:8,165:4,173:8,199:3,207:4,216:2","12:5,20:2,28:1,30:1,148:1,151:1,154:4,159:3,164:8,173:5,179:2,199:1,201:1,207:1,209:4,215:3","14:3,18:1,22:2,149:4,154:21,176:5,198:2,206:7,215:1","15:9,31:1,150:6,158:15,174:1,176:5,198:3,206:9","15:9,31:2,149:21,171:2,174:7,197:3,205:10","15:9,31:3,150:20,171:3,176:6,196:4,205:7,213:2","16:6,23:2,31:2,151:13,165:2,169:12,196:3,205:1,207:5,213:1","16:6,24:1,153:18,172:10,195:2,204:7,212:1","17:1,19:1,25:1,155:28,194:4,203:7,211:2","16:3,23:1,35:2,156:2,160:13,174:9,195:2,202:8,211:1","17:2,20:3,25:3,34:3,160:2,163:10,175:8,193:3,201:11","21:7,34:1,36:1,163:20,192:3,201:10","19:7,27:1,37:2,165:17,192:2,200:11","20:8,37:2,169:13,191:3,199:12","21:2,24:5,37:1,39:1,172:9,190:2,199:11","21:5,29:2,198:7,206:3","21:3,26:6,39:3,188:2,198:11","23:1,26:2,29:4,40:2,187:4,198:10","23:8,187:3,197:10","24:10,186:3,195:4,200:7","24:4,29:2,32:3,44:1,185:2,194:4,200:6","27:9,43:3,183:4,193:13","27:9,44:3,183:3,194:11","27:10,44:4,182:1,184:1,194:3,200:4","27:3,31:1,34:3,45:4,181:3,191:1,193:4,200:3","28:7,36:1,48:2,180:4,190:7,198:3","28:7,38:3,48:3,178:5,189:6,196:1,199:1","29:3,34:3,39:2,48:4,177:4,188:10","31:1,33:10,49:5,179:1,187:12","31:5,37:3,41:3,53:2,187:12","32:7,41:4,173:2,188:6,195:2","33:12,175:1,186:3,190:4,195:1","35:1,37:9,183:12","36:5,42:5,184:1,187:1,189:5","36:12,169:1,187:1,190:3","37:7,45:3,61:1,167:2,185:3,190:2","38:6,45:1,165:5,187:1,190:1","39:7,52:1,64:2,164:5,176:3,184:1,186:1","40:7,51:2,64:3,162:5,175:4,184:3","41:6,51:1,64:6,160:1,162:3,185:2","42:6,51:1,53:4,66:5,158:3,162:1,176:1,184:2","43:4,52:1,54:4,68:2,72:1,157:5","44:1,52:2,55:2,68:7,154:6,169:2","51:3,55:2,60:1,72:4,152:5,167:4","51:6,58:1,60:2,73:7,149:7,166:5","51:11,76:7,147:7,164:7","50:8,60:2,64:3,77:7,143:7,162:13","50:6,57:1,60:2,63:5,79:4,84:5,141:8,159:4,164:7,173:3","52:6,60:8,83:7,136:2,139:8,158:13,173:3","53:4,60:4,65:3,70:3,85:11,133:4,138:1,140:3,155:5,161:10","55:3,60:9,70:5,88:3,92:11,128:6,135:3,140:1,155:17","59:6,66:7,75:3,93:4,99:12,117:2,121:4,126:4,133:4,151:4,157:5,163:8","59:6,66:8,75:4,97:1,100:1,102:4,107:3,112:1,114:1,118:2,124:7,150:5,157:13","60:5,66:8,75:8,103:3,108:1,113:2,117:4,145:22","62:3,67:1,69:16,143:6,150:10,162:4","65:2,68:3,72:9,82:8,138:1,140:14,155:5,161:4","67:14,82:14,133:2,137:3,141:21","68:32,131:19,151:9","72:20,93:3,98:6,109:1,114:4,119:3,123:3,130:3,134:2,137:13,152:5","73:19,94:10,108:3,113:11,125:1,132:12,145:2,148:8","75:9,85:20,109:2,113:11,133:1,135:2,138:9,148:3","79:27,107:10,118:6,133:3,138:2,141:9","81:13,95:28,134:1,138:8","86:37,133:3,138:3,142:2","91:7,100:3,104:20,126:1,132:3,136:2","92:2,95:3,99:15,115:3,119:6,126:2","103:23","107:1,115:3",""},
}
local function stampState(percent)
    if percent<=1 then return 'pending' end
    if percent>=99 then return 'finished' end
    return 'reading'
end
local function paintStamp(bb,paper,x,y,w,h,radius,count,pitch,side_y,side_r)
    local rows=STAMPS[paper.stamp]
    if not rows then return end
    local size=paper.stamp_size
    local left,top=math.floor(x+w-size*.82),math.floor(y-size*.14)
    local function onPaper(px,py)
        if px<x or px>=x+w or py<y or py>=y+h then return false end
        -- Stamp ink is absent in the receipt's scalloped cutouts as well as beyond its edges.
        if py-y<radius or y+h-1-py<radius then
            for i=0,count-1 do
                local cx=math.floor(x+radius*1.5+i*pitch)
                local dy=py-y<radius and py-y or py-(y+h-1)
                if (px-cx)^2+dy^2<=radius^2 then return false end
            end
        end
        if (px-x)^2+(py-side_y)^2<=side_r^2 or (px-(x+w-1))^2+(py-side_y)^2<=side_r^2 then return false end
        return true
    end
    for row,runs in ipairs(rows) do
        local ya=top+math.floor((row-1)*size/STAMP_SIZE)
        local yb=top+math.floor(row*size/STAMP_SIZE)-1
        for start,length in runs:gmatch('(%d+):(%d+)') do
            local xa=left+math.floor(tonumber(start)*size/STAMP_SIZE)
            local xb=left+math.floor((tonumber(start)+tonumber(length))*size/STAMP_SIZE)-1
            for py=math.max(y,ya),math.min(y+h-1,yb) do
                local run_start
                for px=math.max(x,xa),math.min(x+w-1,xb) do
                    if onPaper(px,py) then run_start=run_start or px
                    elseif run_start then bb:paintRect(run_start,py,px-run_start,1,Blitbuffer.COLOR_BLACK);run_start=nil end
                end
                if run_start then bb:paintRect(run_start,py,math.min(x+w-1,xb)-run_start+1,1,Blitbuffer.COLOR_BLACK) end
            end
        end
    end
end

local ReceiptPaper = WidgetContainer:extend{
    padding_top = 28, padding_bottom = 30,
    padding_left = 28, padding_right = 28, shadow_width = 8,
}
function ReceiptPaper:getSize()
    local size = self[1]:getSize()
    return Geom:new{
        w = size.w + self.padding_left + self.padding_right + self.shadow_width,
        h = size.h + self.padding_top + self.padding_bottom,
    }
end
function ReceiptPaper:paintTo(bb, x, y)
    local sz = self:getSize()
    self.dimen = Geom:new{x=x,y=y,w=sz.w,h=sz.h}
    local ink, white = Blitbuffer.COLOR_GRAY_3, Blitbuffer.COLOR_WHITE
    local w, h = sz.w-self.shadow_width, sz.h
    local under=bb:copy()
    local function restoreRect(rx,ry,rw,rh)
        bb:blitFrom(under,rx,ry,rx,ry,rw,rh)
    end
    local function restoreCircle(cx,cy,r)
        for dy=-r,r do
            local half=math.floor(math.sqrt(r*r-dy*dy))
            restoreRect(cx-half,cy+dy,half*2+1,1)
        end
    end
    for i=0,self.shadow_width-1 do
        local shade=math.floor(95+145*i/math.max(1,self.shadow_width-1))
        bb:paintRect(x+w+i,y+3,1,h-3,Blitbuffer.Color8(shade))
    end
    local radius = math.max(8, math.floor(math.min(w / 22, 17)))
    local side_r = math.max(9, math.floor(radius * 1.2))
    bb:paintRect(x, y, w, h, white)
    bb:paintBorder(x, y, w, h, 1, ink, 0)
    -- 先渲染边缘脏印，再挖齿孔和侧面缺口：缺口内仍是干净的纸外背景。
    -- 最后才绘制正文，因此任何脏印都不会覆盖文字或二维码。
    printEdgePatina(bb, x, y, w, h,
        self.padding_top, self.padding_bottom, self.padding_left, self.padding_right)
    -- 一排连贯的半圆缺口。先挖洞再画弧线，只保留纸内侧半圆。
    local count = math.max(3, math.floor((w-radius*3) / (radius*2.9)))
    local pitch = (w-radius*3)/(count-1)
    for i=0,count-1 do
        local cx=math.floor(x+radius*1.5+i*pitch)
        for _,edge in ipairs({'top','bottom'}) do
            local cy=(edge=='top') and y or (y+h-1)
            restoreCircle(cx,cy,radius)
            bb:paintCircle(cx,cy,radius,ink,1)
            if edge=='top' then
                restoreRect(cx-radius-2,cy-radius-2,2*radius+4,radius+3)
            else
                restoreRect(cx-radius-2,cy+1,2*radius+4,radius+3)
            end
        end
    end
    -- 单对侧边内凹缺口，作为上下区块之间的视觉停顿。
    local side_y=math.floor(y+self.padding_top+self.stub_y)
    for _,edge in ipairs({'left','right'}) do
        local cx=(edge=='left') and x or (x+w-1)
        restoreCircle(cx,side_y,side_r)
        bb:paintCircle(cx,side_y,side_r,ink,1)
        if edge=='left' then
            restoreRect(cx-side_r-2,side_y-side_r-2,side_r+3,2*side_r+4)
        else
            restoreRect(cx+1,side_y-side_r-2,side_r+3,2*side_r+4)
        end
    end
    under:free()
    self[1]:paintTo(bb,x+self.padding_left,y+self.padding_top)
    paintStamp(bb,self,x,y,w,h,radius,count,pitch,side_y,side_r)
end

local PrintRule = WidgetContainer:extend{width=400, height=2, kind='dash', scale=1}
function PrintRule:getSize()
    if self.kind=='vertical' then return Geom:new{w=math.max(1,math.floor(self.scale+0.5)),h=self.height} end
    return Geom:new{w=self.width,h=self.height}
end
function PrintRule:paintTo(bb,x,y)
    local sz=self:getSize()
    self.dimen=Geom:new{x=x,y=y,w=sz.w,h=sz.h}
    if self.kind=='vertical' then
        bb:paintRect(x,y,sz.w,self.height,Blitbuffer.COLOR_GRAY_5)
    elseif self.kind=='solid' then
        bb:paintRect(x,y,self.width,self.height,Blitbuffer.COLOR_BLACK)
    else
        -- 印刷虚线：细短点划，阅读高对比墨水屏下不糊成整条。
        local mark,gap=math.max(1,math.floor(8*self.scale+0.5)),math.max(1,math.floor(7*self.scale+0.5))
        for i=0,self.width-1,mark+gap do
            bb:paintRect(x+i,y,math.min(mark,self.width-i),self.height,Blitbuffer.COLOR_GRAY_3)
        end
    end
end

-- ---------- 仿热敏纸印迹 ----------
-- 只处理文字组件本身的已印墨点，不覆盖白底、不处理封面与二维码。
-- 逐点按固定散列产生掉墨/浅印，跨次重绘一致，不会出现随机闪烁。
-- wrapper 的 getSize 与原组件相同：不改变 v2.3 的任何布局尺寸和位置。
local InkWear = WidgetContainer:extend{wear_level=1, wear_seed=1}
function InkWear:getSize()
    return self[1]:getSize()
end
local function wearInk(bb, x, y, width, height, level, seed)
    -- KOReader 的 BlitBuffer 支持像素读取及设置，RGB/灰阶均可转为 Color8。
    -- 所有点都限制在原组件的可视区域，避免修改周围文字与票根轮廓。
    local x0, y0 = math.max(0,math.floor(x)), math.max(0,math.floor(y))
    local x1 = math.min(bb:getWidth(),math.floor(x+width))
    local y1 = math.min(bb:getHeight(),math.floor(y+height))
    if x1<=x0 or y1<=y0 then return end
    local step = level==3 and 2 or (level==2 and 3 or 4)
    local density = level==3 and 215 or (level==2 and 145 or 78)
    local white, faded = Blitbuffer.COLOR_WHITE, Blitbuffer.COLOR_GRAY_9
    for py=y0,y1-1,step do
        local ly=py-y0
        for px=x0,x1-1,step do
            local lx=px-x0
            -- 加入低频的印刷压力变化，模拟滚轮下压不均；采用整数散列且不取随机数。
            local pressure = ((math.floor(lx/29)+math.floor(ly/11)+seed)%7<2) and 65 or 0
            local h=(lx*92821+ly*68917+((lx*ly)%251)*499+seed*131)%1009
            if h<density+pressure then
                local tone=bb:getPixel(px,py):getColor8().a
                -- 仅处理明显的深色墨点，亮底与抗锯齿边缘不受影响。
                if tone<160 then
                    local erase=h%5==0
                    bb:setPixel(px,py,erase and white or faded)
                    -- 大标题加入极少量横向缺墨，模仿热敏头的细小擦痕。
                    if erase and level==3 and h%3==0 and px+1<x1 then
                        local adjacent=bb:getPixel(px+1,py):getColor8().a
                        if adjacent<150 then bb:setPixel(px+1,py,white) end
                    end
                end
            end
        end
    end
end
function InkWear:paintTo(bb,x,y)
    self[1]:paintTo(bb,x,y)
    local size=self:getSize()
    wearInk(bb,x,y,size.w,size.h,self.wear_level,self.wear_seed)
end
local function inkSeed(value)
    local seed=37
    local str=tostring(value or '')
    for i=1,math.min(#str,128) do seed=(seed*33+str:byte(i))%65521 end
    return seed
end
local function inkText(widget, text, level)
    return InkWear:new{wear_level=level,wear_seed=inkSeed(text),widget}
end

local function buildReceipt(ui, state, appearance)
    if not ui or not ui.document then return nil end
    appearance=appearance or {}
    local factor=tonumber(appearance.width or G_reader_settings:readSetting(S.width)) or 0.72
    local scaler=tonumber(appearance.font or G_reader_settings:readSetting(S.font)) or 1
    local scale=tonumber(appearance.scale or G_reader_settings:readSetting(S.scale)) or 1
    local base_width=math.min(Screen:getWidth(),Screen:getHeight()*.75)
    local paper_w=math.floor(base_width*math.max(0.55,math.min(factor,0.90))*scale)
    local unit=paper_w/720
    local line_width=math.max(1,math.floor(scale+0.5))
    local function px(size) return math.max(1,math.floor(size*unit+0.5)) end
    local pad=px(25)
    local w=paper_w-2*pad
    -- Font:getFace scales its argument by DPI; widget dimensions are physical pixels.
    -- Express both in the same 720-pixel ticket design, independent of UI scaling.
    local font_unit=paper_w/Screen:scaleBySize(720)
    local function f(size) return math.max(1,math.floor(size*scaler*font_unit+0.5)) end
    local function missingTitleFont(name)
        return CenterContainer:new{
            dimen=Screen:getSize(),
            TextBoxWidget:new{
                text='小票标题字体无法加载：\n'..name..'\n请检查 KOReader 数据目录的 fonts 文件夹，再完全重启 KOReader。',
                face=Font:getFace('cfont',f(24)),
                width=math.floor(Screen:getWidth()*.78),
                alignment='center', justified=false,
            },
        }
    end
    -- Check at receipt build time: fonts added while KOReader is running need a restart.
    if not Font:getFace(TITLE_FONT,f(52)) then return missingTitleFont(TITLE_FONT) end
    if not Font:getFace(CHINESE_TITLE_FONT,f(36)) then return missingTitleFont(CHINESE_TITLE_FONT) end
    local function txt(value,size,bold,width,align,lines,is_heading)
        local fs=f(size)
        local face=Font:getFace(is_heading and CHINESE_TITLE_FONT or 'cfont',fs)
        local widget=TextBoxWidget:new{
            text=tostring(value or ''),
            face=face,
            bold=(not is_heading) and (bold or false),width=math.max(35,math.floor(width or w)),
            alignment=align or 'left',fgcolor=Blitbuffer.COLOR_BLACK,
            justified=false,
            line_height=0.3,
            height=lines and math.floor(face.size*1.3+0.5)*lines or nil,
            height_overflow_show_ellipsis=lines~=nil,
            height_adjust=lines~=nil,
        }
        -- 标题和主要数据加强缺墨；正文使用中等缺墨。
        local level=(is_heading or size>=26 or bold) and 3 or 2
        return inkText(widget,value,level)
    end
    local function heading(value,size,width,align,lines)
        return txt(value,size,false,width,align,lines,true)
    end
    local function vg(n) return VerticalSpan:new{width=n>0 and px(n) or 0} end
    local function hg(n) return HorizontalSpan:new{width=n>0 and px(n) or 0} end
    local function rule(kind) return PrintRule:new{width=w,height=kind=='solid' and px(1) or line_width,kind=kind or 'dash',scale=scale} end
    local function pair(l,r,lw,rw)
        return HorizontalGroup:new{l,HorizontalSpan:new{width=math.max(0,w-lw-rw)},r}
    end
    local elements={}
    local function add(widget,space)
        elements[#elements+1]=widget
        if space and space>0 then elements[#elements+1]=vg(space) end
    end
    local book=extractBook(ui.doc_props,ui.document.file)
    local cache=cached(book)
    local stats=enabled(S.stats) and readStatistics(ui) or nil
    local doc=(ui.doc_settings and ui.doc_settings.data) or {}
    local page=tonumber(state and state.page) or 1
    local total=math.max(1,tonumber(ui.file_cover and doc.doc_pages or ui.document:getPageCount()) or 1)
    page=math.max(1,math.min(page,total))
    if ui.pagemap and ui.pagemap.wantsPageLabels and ui.pagemap:wantsPageLabels() then
        local _,idx,count=ui.pagemap:getCurrentPageLabel(true)
        if idx and count and count>0 then page,total=idx,count end
    end
    local pct=math.floor(page*100/total+0.5)

    -- 1. 票头：碑铭风格的雕刻衬线标题。仅改标题字体，不影响其他正文。
    local titlew=math.floor(w*.76)
    local sidew=w-titlew-px(10)-1
    -- Keep both names on one left edge, leaving room for the reading-state stamp.
    local function fittedHeading()
        local min_size=f(24)
        for size=f(46),min_size,-1 do
            local face=Font:getFace(TITLE_FONT,size)
            if face then
                local widget=TextWidget:new{
                    text='INKFOLIO',face=face,fgcolor=Blitbuffer.COLOR_BLACK,
                    padding=0,bold=false,
                }
                if widget:getSize().w <= titlew then return widget end
            end
        end
        return nil
    end
    local engraved_heading=fittedHeading()
    if engraved_heading then
        engraved_heading=inkText(engraved_heading,'INKFOLIO',3)
    end
    if not engraved_heading then
        return CenterContainer:new{
            dimen=Screen:getSize(),
            TextBoxWidget:new{
                text='墨笺标题宽度不足，请调大小票宽度或文字大小',
                face=Font:getFace('cfont',f(22)),width=math.floor(Screen:getWidth()*.8),
                alignment='center',justified=false,
            },
        }
    end
    add(HorizontalGroup:new{
        VerticalGroup:new{
            align='left',
            heading('墨笺',30,titlew,'left',1),vg(5),
            engraved_heading,
        },
        hg(10),
        HorizontalSpan:new{width=sidew+1},
    },15)
    add(rule('dash'),10)

    local date_gap=px(9)+px(10)+1
    local dl=math.floor((w-date_gap)*.60)
    local dr=w-date_gap-dl
    add(HorizontalGroup:new{
        VerticalGroup:new{heading('日期',17,dl,'left',1),vg(3),txt(os.date('%Y.%m.%d'),28,true,dl,'left',1)},
        hg(9),PrintRule:new{kind='vertical',height=px(54),scale=scale},hg(10),
        VerticalGroup:new{heading('天气',17,dr,'left',1),vg(3),txt(weatherText(),20,true,dr,'left',2)},
    },12)
    add(rule('dash'),13)

    -- 2. 书目：书名像机打商品主项；元数据是附注，封面固定为窄幅辅助图。
    local cover,coverw
    if enabled(S.cover) and ui.bookinfo and ui.document then
        local cover_document=ui.document
        if ui.file_cover then cover_document=nil end
        local ok,bb=pcall(ui.bookinfo.getCoverImage,ui.bookinfo,
            cover_document,ui.file_cover and ui.document.file or nil)
        if ok and bb then
            local maxw=math.floor(w*.22)
            local maxh=math.floor(base_width*(4/3)*.14*scale)
            local sc=math.min(scale,maxw/bb:getWidth(),maxh/bb:getHeight())
            coverw=math.max(1,math.floor(bb:getWidth()*sc))
            local coverh=math.max(1,math.floor(bb:getHeight()*sc))
            if sc~=1 then bb=RenderImage:scaleBlitBuffer(bb,coverw,coverh,true) end
            cover=ImageWidget:new{image=bb,width=coverw,height=coverh}
        end
    end
    local detailw=w-(cover and (coverw+px(14)) or 0)
    local desc={heading(displayTitle(book.title),40,detailw,'left',2),vg(7)}
    local function metadata(label,value,size)
        local labelw=px(72)
        return HorizontalGroup:new{
            heading(label,size,labelw,'left',1),hg(7),
            txt(value,size,false,detailw-labelw-px(7),'left',2),
        }
    end
    if book.authors~='' then
        desc[#desc+1]=metadata('作者',shortText(book.authors,50),21)
        desc[#desc+1]=vg(4)
    end
    if book.publisher~='' then
        desc[#desc+1]=metadata('出版社',shortText(book.publisher,44),19)
        desc[#desc+1]=vg(4)
    end
    if enabled(S.score) then
        local mark=cache and (scoreStars(cache.rating)..'  '..string.format('%.1f/10',cache.rating)) or '暂无评分'
        desc[#desc+1]=txt(mark,cache and 25 or 18,cache~=nil,detailw,'left',1)
    end
    if cover then add(HorizontalGroup:new{VerticalGroup:new(desc),hg(14),cover},15)
    else add(VerticalGroup:new(desc),15) end
    add(rule('solid'),10)

    -- 3. 条目明细：固定列宽并右对齐数字，不用居中卡片或过多标题。
    local keyw=math.floor(w*.45)
    local valw=w-keyw
    local function row(key,value,k_size,v_size,heavy)
        return pair(heading(key,k_size or 21,keyw,'left',1),
            txt(value,v_size or 26,heavy~=false,valw,'right',1),keyw,valw)
    end
    add(row('阅读进度',tostring(pct)..'%',22,33,true),8)
    add(ProgressWidget:new{width=w,height=px(8),
        percentage=page/total,radius=0,bordersize=0,margin_v=0,margin_h=0,
        bgcolor=Blitbuffer.COLOR_GRAY_9,fillcolor=Blitbuffer.COLOR_BLACK},9)
    add(row('已读页数',string.format('%d / %d 页',page,total),20,25,true),7)
    if enabled(S.chapter) and ui.toc then
        local ok,chapter=pcall(ui.toc.getTocTitleByPage,ui.toc,tonumber(state and state.page) or 1)
        if ok and chapter and chapter~='' then
            local lw=math.floor(w*.24)
            add(pair(heading('章节',20,lw,'left',1),
                txt(shortText(chapter,60),23,true,w-lw,'right',2),lw,w-lw),7)
        end
    end
    if enabled(S.remain) and ui.statistics then
        local avg=tonumber(ui.statistics.avg_time)
        if avg and avg>0 then add(row('预计剩余',duration((total-page)*avg),20,23,false),7) end
    end

    -- Attach the side notches to the actual summary separator, including optional rows.
    local stub_y=0
    for _,widget in ipairs(elements) do stub_y=stub_y+widget:getSize().h end
    -- 4. 阅读摘要：最多两项；只有一项时居中显示。
    local summaries=summaryItems()
    if enabled(S.stats) and #summaries>0 then
        add(rule('dash'),13)
        add(heading('阅读摘要',26,w,'center',1),13)
        local summary_gap=px(10)+px(11)+line_width
        local half=math.floor((w-summary_gap)/2)
        local other=w-summary_gap-half
        local function statblock(label, pages, seconds, ww)
            local kw=math.floor(ww*.43)
            local rw=ww-kw
            return VerticalGroup:new{
                heading(label,22,ww,'center',1),vg(9),
                HorizontalGroup:new{
                    heading('页数',19,kw,'left',1),
                    txt(pages,25,true,rw,'right',1),
                },vg(8),
                HorizontalGroup:new{
                    heading('时长',19,kw,'left',1),
                    txt(seconds,23,true,rw,'right',1),
                },
            }
        end
        local function block(item,width)
            local values=stats and stats[item.id]
            return statblock(item.label,values and (values.pages..'页') or '—',
                values and duration(values.time) or '—',width)
        end
        if #summaries==1 then
            local single=block(summaries[1],half)
            add(CenterContainer:new{dimen=Geom:new{w=w,h=single:getSize().h},single},13)
        else
            add(HorizontalGroup:new{
                block(summaries[1],half),
                hg(10),PrintRule:new{kind='vertical',height=px(104),scale=scale},hg(11),
                block(summaries[2],other),
            },13)
        end
    end

    -- 5. 票根备注：左三行真实书籍简介，右可扫描的豆瓣详情二维码。
    local intro=enabled(S.intro) and (book.description~='' and book.description or (cache and cache.intro or '')) or ''
    local qr
    if enabled(S.qr) and cache and validURL(cache.url) then
        local size=math.floor(base_width*.105*scale)
        local ok,obj=pcall(function() return QRWidget:new{text=cache.url,width=size,height=size} end)
        if ok and obj and obj.image then
            qr=FrameContainer:new{bordersize=0,padding=math.max(1,math.floor(4*scale+0.5)),background=Blitbuffer.COLOR_WHITE,obj}
        end
    end
    if intro~='' or qr then
        add(rule('dash'),12)
        if intro~='' and qr then
            local qw=qr:getSize().w
            local tw=w-qw-px(13)
            add(HorizontalGroup:new{
                VerticalGroup:new{
                    heading('书籍简介',19,tw,'left',1),vg(6),
                    txt(intro,20,false,tw,'left',3),
                },hg(13),qr,
            },12)
        elseif intro~='' then
            add(heading('书籍简介',19,w,'left',1),6)
            add(txt(intro,20,false,w,'left',3),12)
        else
            add(CenterContainer:new{dimen=Geom:new{w=w,h=qr:getSize().h},qr},12)
        end
    end
    add(rule('solid'),9)
    -- 票尾小字，辅助信息保持低存在感。
    local battery=Device:hasBattery() and Device:getPowerDevice():getCapacity() or nil
    local clock=datetime.secondsToHour(os.time(),G_reader_settings:isTrue('twelve_hour_clock')) or ''
    local cw=math.floor(w*.22)
    local middle=w-2*cw
    local battery_labelw=px(40)
    local battery_widget=HorizontalGroup:new{
        heading('电量',18,battery_labelw,'left',1),hg(6),
        txt(battery and (tostring(battery)..'%') or '—',18,false,cw-battery_labelw-px(6),'left',1),
    }
    add(HorizontalGroup:new{battery_widget,
        txt(G_reader_settings:readSetting(S.footer) or '',16,false,middle,'center',1),
        txt(clock,18,false,cw,'right',1)},9)
    local paper=ReceiptPaper:new{
        padding_top=pad,padding_bottom=pad,padding_left=pad,padding_right=pad,
        stub_y=stub_y,shadow_width=px(8),
        stamp=stampState(pct),stamp_size=px(132),
        VerticalGroup:new(elements),
    }
    local size=paper:getSize()
    if size.w>Screen:getWidth() or size.h>Screen:getHeight()-px(24) then
        logger.warn('Read Receipt: layout exceeds screen',size.w,size.h)
        return CenterContainer:new{dimen=Screen:getSize(),TextBoxWidget:new{
            text='小票内容超出屏幕，请减小整体比例、字号或宽度。',
            face=Font:getFace('cfont',f(22)),width=w,
            alignment='center',justified=false,
        }}
    end
    return CenterContainer:new{dimen=Screen:getSize(),paper},true
end

-- Full-screen quicklook; same renderer and cached data as the suspend screen.
local function receiptBackground(appearance)
    local choice=appearance and appearance.background or G_reader_settings:readSetting(S.background) or 'white'
    if choice=='transparent' then return nil end
    return choice=='black' and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_WHITE
end

local Quicklook = InputContainer:extend{modal=true,name='quick_look_box',covers_fullscreen=true}
function Quicklook:init()
    self[1]=buildReceipt(self.ui,self.state)
        or CenterContainer:new{dimen=Screen:getSize(),TextWidget:new{text='无法获取阅读小票',face=Font:getFace('cfont',22)}}
    self[1]=FrameContainer:new{width=Screen:getWidth(),height=Screen:getHeight(),
        bordersize=0,padding=0,margin=0,background=receiptBackground(),self[1]}
    if Device:hasKeys() then self.key_events.AnyKeyPressed={{Device.input.group.Any}} end
    if Device:isTouchDevice() then
        for _,v in ipairs({'Tap','Swipe','MultiSwipe'}) do
            local ges=v=='Tap' and 'tap' or (v=='Swipe' and 'swipe' or 'multiswipe')
            self.ges_events[v]={GestureRange:new{ges=ges,range=function() return self.dimen end}}
        end
    end
end
function Quicklook:onTap() UIManager:close(self);refreshQuicklook=nil;return true end
Quicklook.onSwipe=Quicklook.onTap
Quicklook.onMultiSwipe=Quicklook.onTap
Quicklook.onAnyKeyPressed=Quicklook.onTap
function Quicklook:onCloseWidget() refreshQuicklook=nil end
function ReaderUI:onQuickLook()
    local ui=self
    UIManager:nextTick(function()
        if not ui.document then return end
        local box=Quicklook:new{ui=ui,state=ui.view and ui.view.state}
        refreshQuicklook=function(key)
            if not box or not ui.document then return end
            if key==bookKey(extractBook(ui.doc_props,ui.document.file)) then
                UIManager:close(box)
                box=Quicklook:new{ui=ui,state=ui.view and ui.view.state}
                UIManager:show(box)
            end
        end
        UIManager:show(box)
    end)
end
Dispatcher:registerAction('quicklookbox_action',{
    category='none',event='QuickLook',title='墨笺预览',reader=true,
})

-- Persist only values, never the ReaderUI or a document that will be closed.
local function rememberReceipt(ui)
    if not ui.document or not ui.doc_props then return end
    local state=ui.view and ui.view.state
    local page=tonumber(state and state.page)
    local total=tonumber(ui.document:getPageCount())
    if not page or not total or total<1 then return end
    local display_page,display_total=page,total
    if ui.pagemap and ui.pagemap.wantsPageLabels and ui.pagemap:wantsPageLabels() then
        local _,idx,count=ui.pagemap:getCurrentPageLabel(true)
        if idx and count and count>0 then display_page,display_total=idx,count end
    end
    local chapter=ui.toc and ui.toc:getTocTitleByPage(page) or nil
    local stats=ui.statistics
    local snapshot={file=ui.document.file,props=ui.doc_props,page=page,total=total,
        display_page=display_page,display_total=display_total,chapter=chapter,
        stats_enabled=stats~=nil and (not stats.isEnabled or stats:isEnabled()),
        stats_id=stats and stats.id_curr_book,avg_time=stats and stats.avg_time}
    store:saveSetting('last_receipt',snapshot)
    store:flush()
end

local function homeReceiptContext()
    local path=G_reader_settings:readSetting('lastfile')
    if not path then return nil,'尚未阅读书籍，打开一本书后即可显示墨笺。' end
    if lfs.attributes(path,'mode')~='file' then
        return nil,'最近阅读的书籍已移动或删除，请重新打开书籍。'
    end
    local saved=store:readSetting('last_receipt')
    if not saved or saved.file~=path then
        return nil,'最近阅读的书籍尚无墨笺记录，请打开该书并返回主页一次。'
    end
    local context={document={file=path},doc_props=saved.props,
        doc_settings={data={doc_pages=saved.total}},
        view={state={page=saved.page}},file_cover=true,
        bookinfo=BookInfo,
        pagemap={wantsPageLabels=function()return true end,
            getCurrentPageLabel=function()return nil,saved.display_page,saved.display_total end},
        toc={getTocTitleByPage=function()return saved.chapter end},
        statistics={id_curr_book=saved.stats_id,avg_time=saved.avg_time,
            isEnabled=function()return saved.stats_enabled end}}
    return context
end

-- Capture while the document and its modules are still alive.
local nativeReaderClose=ReaderUI.onClose
ReaderUI.onClose=function(self,...)
    rememberReceipt(self)
    return nativeReaderClose(self,...)
end

local Screensaver=require('ui/screensaver')
local nativeShow=Screensaver.show
Screensaver.show=function(self)
    if self.screensaver_type~='book_receipt' then return nativeShow(self) end
    if not Device:supportsScreensaver() then
        UIManager:show(require('ui/widget/infomessage'):new{text='此平台不支持 KOReader 休眠壁纸，可在阅读中打开小票预览。'})
        return
    end
    local ui=self.ui or ReaderUI.instance
    local unavailable
    if not ui or not ui.document then ui,unavailable=homeReceiptContext() end
    if self.screensaver_widget then
        UIManager:close(self.screensaver_widget)
        self.screensaver_widget=nil
    end
    Device.screen_saver_mode=true
    -- Preserve the reader's orientation, including the underlying transparent image.
    local state=ui and ui.view and ui.view.state
    local receipt=ui and buildReceipt(ui,state) or CenterContainer:new{
        dimen=Screen:getSize(),TextBoxWidget:new{
            text=unavailable,face=Font:getFace('cfont',22),
            width=math.floor(Screen:getWidth()*.8),alignment='center',justified=false}}
    self.screensaver_widget=ScreenSaverWidget:new{
        widget=receipt,background=receiptBackground(),covers_fullscreen=true,
    }
    self.screensaver_widget.modal=true
    self.screensaver_widget.dithered=true
    UIManager:show(self.screensaver_widget,'full')
end

-- Keep event wrappers deliberately shallow: preserve existing KOReader handlers.
local function hook(target, event, callback)
    if not target then return end
    local previous=target[event]
    target[event]=function(self,...)
        local result
        if previous then result=previous(self,...) end
        callback()
        return result
    end
end
local function awake()
    RUN.sleeping=false
    dailyCheck(true)
    startPoll()
end
local function doSleep()
    RUN.sleeping=true
    if RUN.active or RUN.worker then abortRound() end
    POLL_ENABLED=false
    UIManager:unschedule(pollWifi)
end
local function onlineEvent()
    if RUN.sleeping or not networkingEnabled() or MANUAL_CONNECT_PENDING then return end
    resetDay()
    dailyCheck()
    if DAILY_DONE then currentCheck() end
    startPoll()
end
local function bookOpened()
    UIManager:nextTick(function()
        if RUN.sleeping or not networkingEnabled() then return end
        dailyCheck(true)
        -- When an initial library job is running, the current book is already first.
        if DAILY_DONE then currentCheck() end
        startPoll()
    end)
end
hook(ReaderUI,'onResume',awake)
hook(ReaderUI,'onSuspend',doSleep)
hook(ReaderUI,'onNetworkConnected',onlineEvent)
hook(ReaderUI,'onReaderReady',bookOpened)
-- KOReader's file manager can remain active while reader events are not delivered.
local FMok,FM=pcall(require,'apps/filemanager/filemanager')
if FMok and FM then
    hook(FM,'onResume',awake)
    hook(FM,'onSuspend',doSleep)
    hook(FM,'onNetworkConnected',onlineEvent)
end
UIManager:scheduleIn(3,function() awake() end)

-- Render at the device resolution, then shrink the actual pixels for editing.
local AppearanceEditor=InputContainer:extend{modal=true,covers_fullscreen=true,name='inkfolio_appearance'}
function AppearanceEditor:init()
    self.draft={width=G_reader_settings:readSetting(S.width) or .72,
        font=G_reader_settings:readSetting(S.font) or 1,
        scale=G_reader_settings:readSetting(S.scale) or 1,
        background=G_reader_settings:readSetting(S.background) or 'white'}
    self.backdrop=Screen.bb:copy()
    -- Repaint the reading view without the settings menu for transparent previews.
    local live=ReaderUI.instance
    if live and live.document and live.view then live.view:paintTo(self.backdrop,0,0) end
    if (not live or not live.document) and FM and FM.instance then FM.instance:paintTo(self.backdrop,0,0) end
    self.refresh_callback=function()if not self.closed then self:refreshPreview() end end
    if Device:hasKeys() then self.key_events.Cancel={{Device.input.group.Back}} end
    self:refreshPreview()
end
function AppearanceEditor:change(key,value)
    self.draft[key]=value
    UIManager:unschedule(self.refresh_callback)
    self.pending=true
    UIManager:scheduleIn(.5,self.refresh_callback)
end
function AppearanceEditor:refreshPreview()
    UIManager:unschedule(self.refresh_callback)
    self.pending=false
    local sw,sh=Screen:getWidth(),Screen:getHeight()
    local pad=math.max(4,math.floor(math.min(sw,sh)*.02))
    local gap=math.max(3,math.floor(sh*.006))
    local rowh=math.max(20,math.floor(sh*.055))
    local fs=math.max(8,math.min(18,math.floor(rowh/Screen:scaleBySize(2.7))))
    local width=sw-2*pad
    local title=TextWidget:new{text='墨笺外观 · '..sw..'×'..sh,max_width=width,face=Font:getFace('infofont',fs+2)}
    local receipt,valid=buildReceipt(self.ui,self.ui.view and self.ui.view.state,self.draft)
    assert(receipt,'Inkfolio appearance: missing book context')
    self.valid=valid==true
    local status=TextWidget:new{text=self.valid and '停下操作后更新预览；保存后应用' or '无法显示，请减小设置或检查字体',
        max_width=width,face=Font:getFace('infofont',fs)}
    local rows={}
    local button_padding=require('ui/size').padding.buttontable
    local function button(text,callback,enabled,bw)
        return {text=text,callback=callback,enabled=enabled~=false,width=bw,height=math.max(1,rowh-2*button_padding),
            font_size=fs,font_face='infofont'}
    end
    local function numeric(label,key,step,minval,maxval)
        local current=self.draft[key]
        rows[#rows+1]={
            button('−',function()self:change(key,math.max(minval,math.floor(self.draft[key]*100-step+.5)/100))end,current>minval),
            button(label..' '..math.floor(current*100+.5)..'%',nil,false,math.floor(width*.5)),
            button('+',function()self:change(key,math.min(maxval,math.floor(self.draft[key]*100+step+.5)/100))end,current<maxval)}
    end
    numeric('宽度', 'width',1,.55,.9)
    numeric('字号', 'font',5,.8,1.2)
    numeric('比例', 'scale',5,.5,1.5)
    local background={button('背景',nil,false)}
    for _,item in ipairs({{'白色','white'},{'黑色','black'},{'透明','transparent'}}) do
        local label,key=item[1],item[2]
        background[#background+1]=button(self.draft.background==key and ('['..label..']') or label,
            function()self:change('background',key)end)
    end
    rows[#rows+1]=background
    rows[#rows+1]={button('取消',function()self:onCancel()end),
        button('保存',function()self:save()end,self.valid)}
    local controls=require('ui/widget/buttontable'):new{width=width,buttons=rows,show_parent=self,
        addVerticalSpan=function(table_widget)
            table.insert(table_widget.container,VerticalSpan:new{width=gap})
        end}
    local available=sh-2*pad-title:getSize().h-status:getSize().h-controls:getSize().h-3*gap
    assert(available>0,'Inkfolio appearance controls exceed screen')
    local zoom=math.min(width/sw,available/sh)
    local pw,ph=math.max(1,math.floor(sw*zoom)),math.max(1,math.floor(sh*zoom))
    local canvas=Blitbuffer.new(sw,sh,self.backdrop:getType())
    local background_color=receiptBackground(self.draft)
    if background_color then canvas:fill(background_color)
    else canvas:blitFrom(self.backdrop,0,0,0,0,sw,sh) end
    receipt:paintTo(canvas,0,0)
    receipt:free()
    local bitmap=RenderImage:scaleBlitBuffer(canvas,pw,ph,true)
    local preview=CenterContainer:new{dimen=Geom:new{w=width,h=available},
        ImageWidget:new{image=bitmap,width=pw,height=ph,image_disposable=true}}
    local old=self[1]
    self[1]=FrameContainer:new{width=sw,height=sh,bordersize=0,margin=0,padding=pad,
        background=Blitbuffer.COLOR_WHITE,VerticalGroup:new{align='center',title,
            VerticalSpan:new{width=gap},preview,VerticalSpan:new{width=gap},status,
            VerticalSpan:new{width=gap},controls}}
    if old then old:free() end
    UIManager:setDirty(self,'ui')
end
function AppearanceEditor:save()
    if self.pending then self:refreshPreview() end
    if not self.valid then return end
    for _,key in ipairs({'width','font','scale','background'}) do
        G_reader_settings:saveSetting(S[key],self.draft[key])
    end
    UIManager:close(self)
end
function AppearanceEditor:onCancel() UIManager:close(self);return true end
function AppearanceEditor:onSuspend() self:onCancel();return false end
AppearanceEditor.onSetRotationMode=AppearanceEditor.onSuspend
function AppearanceEditor:onCloseWidget()
    self.closed=true
    UIManager:unschedule(self.refresh_callback)
    if self.backdrop then self.backdrop:free();self.backdrop=nil end
    self:free()
    UIManager:setDirty(nil,'full')
end
local function editAppearance()
    local ui=ReaderUI.instance
    local reason
    if not ui or not ui.document then ui,reason=homeReceiptContext() end
    if not ui then
        UIManager:show(require('ui/widget/infomessage'):new{text=reason})
        return
    end
    UIManager:show(AppearanceEditor:new{ui=ui})
end

local function footerTextValid(text)
    if text:find('[\r\n]') then return false end
    local _,count=text:gsub('[^\128-\191]','')
    return count<=20
end
local function editFooter()
    local InputDialog=require('ui/widget/inputdialog')
    local dialog
    dialog=InputDialog:new{
        title='小票底部文字（最多20字）',
        input=G_reader_settings:readSetting(S.footer) or '',
        buttons={{
            {text='取消',callback=function() UIManager:close(dialog) end},
            {text='保存',is_enter_default=true,callback=function()
                local text=dialog:getInputText()
                if not footerTextValid(text) then
                    UIManager:show(require('ui/widget/infomessage'):new{text='请输入一行文字，最多20个字符。'})
                    return
                end
                G_reader_settings:saveSetting(S.footer,text)
                UIManager:close(dialog)
            end},
        }},
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

local function weatherCityMenu()
    local regions={{text='不设置城市',radio=true,keep_menu_open=true,
        checked_func=function()return G_reader_settings:readSetting(S.weather_city)==nil end,
        callback=function()
            G_reader_settings:delSetting(S.weather_city)
            WEATHER.pending=false;store:saveSetting('weather',WEATHER);store:flush()
        end}}
    for _,region in ipairs(WEATHER_REGIONS) do
        local rows={}
        for _,city in ipairs(region.cities) do
            rows[#rows+1]={
                radio=true,text=city.name..(city.code=='' and '（气象台暂无数据）' or ''),
                enabled=city.code~='',keep_menu_open=true,
                checked_func=function() return city.code~='' and G_reader_settings:readSetting(S.weather_city)==city.code end,
                callback=function()
                    if city.code=='' then return end
                    if G_reader_settings:readSetting(S.weather_city)==city.code then return end
                    G_reader_settings:saveSetting(S.weather_city,city.code)
                    WEATHER.pending=selectedWeatherCity()~=nil
                    store:saveSetting('weather',WEATHER);store:flush()
                    -- Wait for the current HTTP request, then fetch the newly selected city.
                    weatherCheck();startPoll()
                end,
            }
        end
        regions[#regions+1]={text=region.name,sub_item_table=rows}
    end
    return regions
end

local function summaryMenu()
    local rows={{text='显示摘要',keep_menu_open=true,
        checked_func=function() return enabled(S.stats) end,
        callback=function() G_reader_settings:saveSetting(S.stats,not enabled(S.stats)) end}}
    for _,item in ipairs(SUMMARY_ITEMS) do
        local function checked()
            for _,selected in ipairs(summaryItems()) do if selected.id==item.id then return true end end
            return false
        end
        local function available()
            return enabled(S.stats) and (checked() or #summaryItems()<2)
        end
        rows[#rows+1]={text=item.label,keep_menu_open=true,checked_func=checked,
            enabled_func=available,callback=function()
                if not available() then return end
                local chosen={}
                local was_checked=checked()
                for _,selected in ipairs(summaryItems()) do
                    if selected.id~=item.id then chosen[#chosen+1]=selected.id end
                end
                if not was_checked then chosen[#chosen+1]=item.id end
                G_reader_settings:saveSetting(S.summary,chosen)
            end}
    end
    return rows
end

local function chooseLibraryRoot()
    local PathChooser=require('ui/widget/pathchooser')
    UIManager:show(PathChooser:new{
        title='选择书库目录',select_directory=true,select_file=false,show_files=false,
        path=rootPath() or Device.home_dir or '/',
        onConfirm=function(path)
            if path=='/' or lfs.attributes(path,'mode')~='directory' then
                UIManager:show(require('ui/widget/infomessage'):new{text='请选择可读取的图书文件夹，不能选择系统根目录。'})
                return
            end
            if RUN.active or RUN.worker then abortRound() end
            G_reader_settings:saveSetting(S.library_root,path)
            nextLibraryScan=0
            dailyCheck(true);startPoll()
        end,
    })
end

local function openProjectLink(url)
    if not Device:openLink(url) then
        UIManager:show(require('ui/widget/textviewer'):new{
            title='此设备无法直接打开网页',text=url,justified=false,show_menu=false})
    end
end
local function showAbout()
    local text=table.concat({
        '墨笺 · Inkfolio',
        '版本：v'..VERSION,
        '更新日期：'..RELEASE_DATE,
        '二次开发与设计：zacharykim88',
        '开发辅助：OpenAI Codex',
        '',
        '本项目是 KOReader Lua 用户补丁，基于 Estela-Zelin84 维护的 KOReader_Book-Receipt 开源项目进行二次开发。',
        '功能：电影票根风格、图书封面与评分、三行简介与二维码、阅读进度与状态邮戳、阅读摘要、城市天气及底部自定义文字。',
        '外观页面提供实时预览，可调整宽度、字号、整体比例和背景。支持的设备可在阅读界面及主页休眠时显示墨笺，主页使用最近阅读书籍的记录。',
        '图书与天气信息通过联网任务获取；进度弹窗可关闭，支持后台继续及取消。阅读摘要依赖 KOReader 阅读统计插件。',
        '',
        '原项目注明，原创代码来自 Reddit 用户 u/hundredpercentcocoa；原始补丁收录于 omer-faruq/koreader-user-patches。感谢原作者及贡献者。',
        '',
        '开源许可：GNU General Public License v3.0（GPL-3.0）。保留原有版权与许可证声明，修改后的源代码随 Lua 补丁提供。软件按现状提供，不作任何担保。',
        '完整包附带香萃打字机体 W40 与 Cinzel Decorative Bold，字体按 SIL OFL 1.1 单独授权，来源与授权文件随包提供。安装时需同时合并包内 fonts 目录。',
        '',
        '兼容性：此前版本在 Kobo Sage / KOReader 2026.07.2 + SimpleUI 上经过真机测试。本版通过代码与模拟检查，实时外观编辑器及最终修改仍需真机验证，其他设备尚待反馈。休眠壁纸依赖设备能力；Android 提供预览与设置，不替换系统锁屏。Android F-Droid 版不执行用户补丁。',
        '',
        '设备：'..tostring(Device.model or '未知')..'，屏幕：'..Screen:getWidth()..'×'..Screen:getHeight(),
    },'\n')
    UIManager:show(require('ui/widget/textviewer'):new{
        title='关于墨笺',text=text,justified=false,show_menu=false,
        buttons_table={{
            {text='上游项目',callback=function() openProjectLink('https://github.com/Estela-Zelin84/KOReader_Book-Receipt') end},
            {text='原始补丁',callback=function() openProjectLink('https://github.com/omer-faruq/koreader-user-patches') end},
            {text='许可证',callback=function() openProjectLink('https://github.com/Estela-Zelin84/KOReader_Book-Receipt/blob/main/LICENSE') end},
        }},add_default_buttons=true,
    })
end

local function receiptSettingsMenu()
        local function toggle(label,key,action,default)
            local function checked()
                if default==false then return G_reader_settings:readSetting(key)==true end
                return enabled(key)
            end
            return {text=label,keep_menu_open=true,
                checked_func=checked,
                callback=function()
                    local nextval=not checked()
                    G_reader_settings:saveSetting(key,nextval)
                    if action then action(nextval) end
                end}
        end
        local menu={
            text='墨笺设置',
            sub_item_table={
                {text='信息获取',sub_item_table={
                    toggle('允许联网',S.online,function(now)
                        if not now then MANUAL_CONNECT_PENDING=false;abortRound() else dailyCheck();startPoll() end
                    end),
                    {text='立即更新',enabled_func=function()
                        return networkingEnabled() and not RUN.active and not RUN.worker
                    end,callback=updateManually},
                    toggle('获取进度弹窗',S.progress,function(now)
                        if not now then progressIgnore()
                        elseif PROGRESS.active then
                            PROGRESS.hidden=false;progressPaint(true)
                            UIManager:scheduleIn(5,progressTick)
                        end
                    end),

                    {text='天气城市',help_text='每次选择一个城市；选择“不设置城市”可清除选择。',sub_item_table=weatherCityMenu()},
                    {text='书库目录',callback=chooseLibraryRoot,help_text='选择内部存储或存储卡中的图书文件夹。更改目录后重新建立记录，现有图书可通过“立即更新”获取信息。'},
                }},
                {text='显示内容',sub_item_table={
                    toggle('封面',S.cover),
                    toggle('豆瓣评分',S.score),
                    toggle('当前章节',S.chapter),
                    toggle('剩余时间',S.remain),
                    toggle('书籍简介',S.intro),
                    toggle('豆瓣二维码',S.qr),
                    {text='底部文字',callback=editFooter},
                    {text='阅读摘要',sub_item_table=summaryMenu()},
                }},
                {text='外观',callback=editAppearance},
                {text='关于',callback=showAbout},
            },
        }
    return menu
end

-- Preserve the existing sleep-screen settings entry.
local previousDofile=dofile
_G.dofile=function(file)
    local result=previousDofile(file)
    if file and file:match('screensaver_menu%.lua$') and
       result and result[1] and result[1].sub_item_table then
        local tab=result[1].sub_item_table
        if Device:supportsScreensaver() then
            table.insert(tab,math.min(6,#tab+1),{
                text='墨笺',radio=true,
                checked_func=function() return G_reader_settings:readSetting('screensaver_type')=='book_receipt' end,
                callback=function() G_reader_settings:saveSetting('screensaver_type','book_receipt') end,
            })
        end
        table.insert(tab,math.min(7,#tab+1),receiptSettingsMenu())
    end
    return result
end

-- A native main-menu entry also exists on platforms without sleep-screen settings.
local receiptMenuWidget={name='read_receipt_settings'}
function receiptMenuWidget:addToMainMenu(items)
    items.read_receipt=receiptSettingsMenu()
    items.read_receipt.text='墨笺'
    table.insert(items.read_receipt.sub_item_table,2,{
        text=Device:supportsScreensaver() and '休眠显示' or '休眠显示（此平台不支持）',
        keep_menu_open=true,help_text='开启后使用墨笺作为休眠壁纸；关闭后保持屏幕原样。',
        enabled_func=function()return Device:supportsScreensaver()end,
        checked_func=function()return G_reader_settings:readSetting('screensaver_type')=='book_receipt'end,
        callback=function()
            if Device:supportsScreensaver() then
                local selected=G_reader_settings:readSetting('screensaver_type')=='book_receipt'
                G_reader_settings:saveSetting('screensaver_type',selected and 'disable' or 'book_receipt')
            end
        end,
    })
end
for _,module_name in ipairs({'apps/reader/modules/readermenu','apps/filemanager/filemanagermenu'}) do
    local Menu=require(module_name)
    local init=Menu.init
    assert(type(init)=='function' and type(Menu.registerToMainMenu)=='function',
        'READ RECEIPT: unsupported KOReader main-menu API')
    Menu.init=function(self,...)
        init(self,...)
        self:registerToMainMenu(receiptMenuWidget)
    end
end
