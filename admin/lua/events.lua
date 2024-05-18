-- Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
-- Copyright (c) 2024 bukale bukale2022@163.com

local cjson = require "cjson"
local user = require "user"
local pager = require "lib.pager"
local mysql = require "mysqlCli"


local tonumber = tonumber
local quote_sql_str = ngx.quote_sql_str

local _M = {}


local SQL_COUNT_IP_BLOCK_LOG = 'SELECT COUNT(*) AS total FROM attack_log '

local SQL_SELECT_IP_BLOCK_LOG = [[
    SELECT id, request_id, ip, ip_country_code, ip_country_cn, ip_country_en, ip_province_code, ip_province_cn, ip_province_en, ip_city_code, ip_city_cn, ip_city_en,
    ip_longitude, ip_latitude, http_method, server_name, user_agent, referer, request_protocol, request_uri,
    http_status, request_time, attack_type, hit_rule, action FROM attack_log
]]

local SQL_SELECT_IP_BLOCK_LOG_DETAIL = [[
    SELECT id, request_id, ip, ip_country_code, ip_country_cn, ip_country_en, ip_province_code, ip_province_cn, ip_province_en, ip_city_code, ip_city_cn, ip_city_en,
    ip_longitude, ip_latitude, http_method, server_name, user_agent, referer, request_protocol, request_uri,
    request_body, http_status, response_body, request_time, attack_type, hit_rule, action FROM attack_log
]]

-- 查询日志列表数据
local function listLogs()
    local response = {code = 200, data = {}, msg = ""}

    local args, err = ngx.req.get_uri_args()
    if args then
        local page = tonumber(args['page'])
        local limit = tonumber(args['limit'])
        local offset = pager.getBegin(page, limit)

        local serverName = args['serverName']
        local ip = args['ip']
        local action = args['action']

        local where = ' WHERE 1=1 '

        if serverName and #serverName > 0 then
            where = where .. ' AND server_name LIKE ' .. quote_sql_str('%' .. serverName .. '%')
        end

        if ip and #ip > 0 then
            where = where .. ' AND ip=' .. quote_sql_str(ip) .. ' '
        end

        if action and #action > 0 then
            where = where .. ' AND action=' .. quote_sql_str(action) .. ' '
        end

        local res, err = mysql.query(SQL_COUNT_IP_BLOCK_LOG .. where)

        if res and res[1] then
            ngx.log(ngx.ERR, cjson.encode(res))

            local total = tonumber(res[1].total)
            if total > 0 then
                res, err = mysql.query(SQL_SELECT_IP_BLOCK_LOG .. where .. ' ORDER BY id DESC LIMIT ' .. offset .. ',' .. limit)
                if res then
                    response.data = res
                else
                    response.code = 500
                    response.msg = 'query database error'
                    ngx.log(ngx.ERR, err)
                end
            end

            response.code = 0
            response.count = total
        else
            response.code = 500
            response.msg = 'query database error'
            ngx.log(ngx.ERR, err)
        end
    else
        response.code = 500
        response.msg = err
    end

    if response.code ~= 0 then
        ngx.log(ngx.ERR, response.msg)
    end

    return response
end

-- 根据id查询日志详情
local function getLog()
    local response = {code = 200, data = {}, msg = ""}

    local args, err = ngx.req.get_uri_args()
    if args and args['id'] then
        local id = tonumber(args['id'])

        local where = ' WHERE id=' .. id

        local res, err = mysql.query(SQL_SELECT_IP_BLOCK_LOG_DETAIL .. where)
        ngx.log(ngx.ERR, cjson.encode(res))

        if res then
            response.data = res[1]
        else
            response.code = 500
            response.msg = 'query database error'
            ngx.log(ngx.ERR, err)
        end
    else
        response.code = 500
        response.msg = err
        ngx.log(ngx.ERR, err)
    end

    return response
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

    if uri == "/events/list" then
        -- 查询事件数据列表
        response = listLogs()
    elseif uri == "/events/get" then
        -- 查询事件详情
        response = getLog()
    end

    ngx.say(cjson.encode(response))
end

_M.doRequest()

return _M
