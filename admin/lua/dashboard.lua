-- Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
-- Copyright (c) 2023 bukale bukale2022@163.com

local config = require "config"
local cjson = require "cjson"
local user = require "user"
local time = require "time"
local sql = require "sql"
local utils = require "utils"
local constants = require "constants"

local ipairs = ipairs
local concat = table.concat
local ngxfind = ngx.re.find

local is_system_option_on = config.is_system_option_on

local _M = {}

local function getRequestTraffic()
    local hours = time.getHours()
    local dict = ngx.shared.dict_req_count
    local dataStr = '[["hour", "traffic","attack_traffic"],'
    for _, hour in ipairs(hours) do
        local count = dict:get(hour) or 0
        local attackCount = dict:get(constants.KEY_ATTACK_PREFIX .. hour) or 0
        dataStr = concat({ dataStr, '["', hour, '", ', count, ',', attackCount, '],' })
    end

    dataStr = string.sub(dataStr, 1, -2) .. ']'
    return dataStr
end

local function getAttackTypeTraffic()
    local dict = ngx.shared.dict_req_count
    local keys = dict:get_keys()
    local dataStr = ''

    if keys then
        local today = ngx.today()
        local prefix = constants.KEY_ATTACK_TYPE_PREFIX .. today

        for _, key in ipairs(keys) do
            local from = ngxfind(key, prefix)
            if from then
                local count = dict:get(key) or 0
                dataStr = concat({ dataStr, '{"name":"', key, '","value": ', count, '},' })
            end
        end
    end

    if #dataStr > 0 then
        dataStr = '[' .. string.sub(dataStr, 1, -2) .. ']'
    else
        dataStr = '[]'
    end

    return dataStr
end

function _M.doRequest()
    local response = {code = 200, data = {}, msg = ""}
    local uri = ngx.var.uri

    if user.checkAuthToken() == false then
        response.code = 401
        response.msg = 'User not logged in'
        ngx.status = 401
        ngx.say(cjson.encode(response))
        ngx.exit(401)
        return
    end

    if uri == "/dashboard" then
        local trafficDataStr = getRequestTraffic()
        local attackTypeDataStr = getAttackTypeTraffic()

        local data = {}
        data.trafficData = trafficDataStr
        data.attackTypeData = attackTypeDataStr

        local wafStatus = {}
        local world = {}
        local china = {}

        if is_system_option_on("mysql") then
            local res, err = sql.getTodayWafStatus()
            if res then
                wafStatus = res[1]
            else
                ngx.log(ngx.ERR, err)
            end

            res, err = sql.get30DaysWorldTrafficStats()
            if res then
                world = res
            else
                ngx.log(ngx.ERR, err)
            end

            res, err = sql.get30DaysChinaTrafficStats()
            if res then
                china = res
            else
                ngx.log(ngx.ERR, err)
            end
        else
            local dict = ngx.shared.dict_req_count

            local http4xx = utils.dictGet(dict, constants.KEY_HTTP_4XX)
            local http5xx = utils.dictGet(dict, constants.KEY_HTTP_5XX)
            local request_times = utils.dictGet(dict, constants.KEY_REQUEST_TIMES)
            local attack_times = utils.dictGet(dict, constants.KEY_ATTACK_TIMES)
            local block_times = utils.dictGet(dict, constants.KEY_BLOCK_TIMES)

            wafStatus = {http4xx = http4xx, http5xx = http5xx, request_times = request_times,
                        attack_times = attack_times, block_times = block_times}
        end

        data.sourceRegion = {world = world, china = china}
        data.wafStatus = wafStatus
        response.data = data
    end

    ngx.say(cjson.encode(response))
end

_M.doRequest()

return _M
