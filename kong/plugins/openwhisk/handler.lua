local BasePlugin    = require "kong.plugins.base_plugin"
local constants     = require "kong.constants"
local meta          = require "kong.meta"
local http          = require "resty.http"
local cjson         = require "cjson.safe"
local multipart     = require "multipart"


local kong          = kong
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
local get_headers   = ngx.req.get_headers
local read_body     = ngx.req.read_body
local ngx_log       = ngx.log
local var           = ngx.var
local header        = ngx.header


local server_header = meta._SERVER_TOKENS
local SERVER        = meta._NAME .. "/" .. meta._VERSION

local function log(...)
  ngx_log(ngx.ERR, "[openwhisk] ", ...)
end


local function retrieve_parameters()
  read_body()

  local content_type = var.content_type

  if content_type then
    content_type = lower(content_type)

    if find(content_type, "multipart/form-data", nil, true) or var.request_method == "GET" then
      return kong.table.merge(
        get_uri_args(),
        multipart(get_body_data(), content_type):get_all())
    end

    if find(content_type, "application/json", nil, true) then
      local json, err = cjson.decode(get_body_data())
      if err then
        return nil, err
      end
      return kong.table.merge(get_uri_args(), json)
    end
  end

  if var.request_method == "GET" then
    return get_uri_args()
  end

  return kong.table.merge(get_uri_args(), kong.request.get_body())
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

  if kong.configuration.enabled_headers[constants.HEADERS.VIA] then
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

  -- Check allowed methods
  local method = kong.request.get_method()
  local method_match = false
  for i = 1, #config.methods do
    if config.methods[i] == method then
      method_match = true
      break
    end
  end
  if not method_match then
    return kong.response.exit(405, { code = 405001, message = "The HTTP method used is not allowed in this endpoint." })
  end

  -- Get parameters
  local body, err = retrieve_parameters()
  if err then
    return kong.response.exit(400, { code = 400002, message = "Validation error", detail = { body = err } })
  end

  -- Append environment data
  body['_environment'] = config.environment

  -- Append extra data for the request
  body['_parameters'] = config.parameters

  -- Get x-auth-token
  local authorization_header = get_headers()["x-auth-token"]
  if authorization_header then
    body['token'] = authorization_header
  end

  -- Invoke action
  local basic_auth
  if config.service_token ~= nil then
    basic_auth = "Basic " .. encode_base64(config.service_token)
  end

  -- Blocking
  local blocking = (body['_blocking'] == nil)

  local client = http.new()

  client:set_timeout(config.timeout)

  local ok, err = client:connect(config.host, config.port)
  if not ok then
    kong.log.err(err)
    return kong.response.exit(503, { code = 503001, message = "It's not you, it's us, our service is down." })
  end

  if config.https then
    local ok, err = client:ssl_handshake(false, config.host, config.https_verify)
    if not ok then
      kong.log.err(err)
      return kong.response.exit(501, { code = 500001, message = "It's not you, it's us, we have experienced a error on our side." })
    end
  end

  local res, err = client:request {
    method  = "POST",
    path    = concat {          config.path,
      "/actions/",              config.action,
      "?blocking=",             tostring(blocking),
      "&result=",               tostring(config.result),
      "&timeout=",              config.timeout
    },
    body    = cjson.encode(body),
    headers = {
      ["Content-Type"]  = "application/json",
      ["Authorization"] = basic_auth
    }
  }

  if not res then
    kong.log.err(err)
    return kong.response.exit(501, { code = 500001, message = "It's not you, it's us, we have experienced a error on our side." })
  end

  local response_status  = res.status
  local response_content = res:read_body()

  ok, err = client:set_keepalive(config.keepalive)
  if not ok then
    log("could not keepalive connection: ", err)
  end

  -- Prepare response for downstream
  for key, value in pairs(res.headers) do
    header[key] = value
  end
  header.Server = SERVER

  local ctx = ngx.ctx
  if ctx.delay_response and not ctx.delayed_response then
    ctx.delayed_response = {
      status_code = response_status,
      content     = response_content,
      headers     = header,
    }

    ctx.delayed_response_callback = flush

    return
  end

  return send(response_status, response_content, header)
end


return OpenWhisk
