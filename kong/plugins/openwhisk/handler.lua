local BasePlugin    = require "kong.plugins.base_plugin"
local singletons    = require "kong.singletons"
local responses     = require "kong.tools.responses"
local constants     = require "kong.constants"
local get_post_args = require "kong.tools.public".get_body_args
local table_merge   = require "kong.tools.utils".table_merge
local meta          = require "kong.meta"
local http          = require "resty.http"
local cjson         = require "cjson.safe"
local multipart     = require "multipart"


local tostring      = tostring
local concat        = table.concat
local pairs         = pairs
local lower         = string.lower
local find          = string.find
local type          = type
local ngx           = ngx
local encode_base64 = ngx.encode_base64
local get_body_data = ngx.req.get_body_data
local get_uri_args  = ngx.req.get_uri_args
local read_body     = ngx.req.read_body
local ngx_log       = ngx.log
local var           = ngx.var


local server_header = meta._SERVER_TOKENS


local function log(...)
  ngx_log(ngx.ERR, "[openwhisk] ", ...)
end


local function retrieve_parameters()
  read_body()

  local content_type = var.content_type

  if content_type then
    content_type = lower(content_type)

    if find(content_type, "multipart/form-data", nil, true) then
      return table_merge(
        get_uri_args(),
        multipart(get_body_data(), content_type):get_all())
    end

    if find(content_type, "application/json", nil, true) then
      local json, err = cjson.decode(get_body_data())
      if err then
        return nil, err
      end
      return table_merge(get_uri_args(), json)
    end
  end

  return table_merge(get_uri_args(), get_post_args())
end


local function send(status, content, headers)
  ngx.status = status

  if type(headers) == "table" then
    for k, v in pairs(headers) do
      ngx.header[k] = v
    end
  end

  if not ngx.header["Content-Length"] then
    ngx.header["Content-Length"] = #content
  end

  if singletons.configuration.enabled_headers[constants.HEADERS.VIA] then
    ngx.header[constants.HEADERS.VIA] = server_header
  end

  ngx.print(content)

  return ngx.exit(status)
end


local function flush(ctx)
  ctx = ctx or ngx.ctx
  local response = ctx.delayed_response
  return send(response.status_code, response.content, response.headers)
end


local OpenWhisk = BasePlugin:extend()


OpenWhisk.PRIORITY = 1000


function OpenWhisk:new()
  OpenWhisk.super.new(self, "openwhisk")
end


function OpenWhisk:access(config)
  OpenWhisk.super.access(self)

  -- only allow POST
  if var.request_method ~= "POST" then
    return responses.send_HTTP_METHOD_NOT_ALLOWED()
  end

  -- get parameters
  local body, err = retrieve_parameters()
  if err then
    return responses.send_HTTP_BAD_REQUEST(err)
  end

  -- invoke action
  local basic_auth
  if config.service_token ~= nil then
    basic_auth = "Basic " .. encode_base64(config.service_token)
  end

  local client = http.new()

  client:set_timeout(config.timeout)

  local ok, err = client:connect(config.host, config.port)
  if not ok then
    log("could not connect to Openwhisk server: ", err)
    return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
  end

  if config.https then
    local ok, err = client:ssl_handshake(false, config.host, config.https_verify)
    if not ok then
      log("could not perform SSL handshake : ", err)
      return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
    end
  end

  local res, err = client:request {
    method  = "POST",
    path    = concat {          config.path,
      "/actions/",              config.action,
      "?blocking=true&result=", tostring(config.result),
      "&timeout=",              config.timeout
    },
    body    = cjson.encode(body),
    headers = {
      ["Content-Type"]  = "application/json",
      ["Authorization"] = basic_auth
    }
  }

  if not res then
    return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
  end

  local response_headers = res.headers
  local response_status  = res.status
  local response_content = res:read_body()

  ok, err = client:set_keepalive(config.keepalive)
  if not ok then
    log("could not keepalive connection: ", err)
  end

  local ctx = ngx.ctx
  if ctx.delay_response and not ctx.delayed_response then
    ctx.delayed_response = {
      status_code = response_status,
      content     = response_content,
      headers     = response_headers,
    }

    ctx.delayed_response_callback = flush

    return
  end

  return send(response_status, response_content, response_headers)
end


return OpenWhisk
