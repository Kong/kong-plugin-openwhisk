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
local read_body     = ngx.req.read_body
local ngx_log       = ngx.log
local var           = ngx.var


local server_header = meta._SERVER_TOKENS


local function log(...)
  return ngx_log(ngx.ERR, "[openwhisk] ", ...)
end


local function retrieve_parameters()
  read_body()

  local content_type = var.content_type

  if content_type then
    content_type = lower(content_type)

    if find(content_type, "multipart/form-data", nil, true) then
      return kong.table.merge(get_uri_args(), multipart(get_body_data(), content_type):get_all())
    end

    if find(content_type, "application/json", nil, true) then
      local json, err = cjson.decode(get_body_data())
      if err then
        return nil, err
      end
      return kong.table.merge(get_uri_args(), json)
    end
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


local OpenWhisk = {}
OpenWhisk.PRIORITY = 1000
OpenWhisk.VERSION = "1.0.0"


function OpenWhisk:access(config)

  -- only allow POST
  if var.request_method ~= "POST" then
    return kong.response.exit(405, { message = "Method not allowed" })
  end

  -- get parameters
  local body, err = retrieve_parameters()
  if err then
    return kong.response.exit(400, { message = err })
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
    kong.log.err(err)
    return kong.response.exit(500, { message = "An unexpected error happened" })
  end

  if config.https then
    local ok, err = client:ssl_handshake(false, config.host, config.https_verify)
    if not ok then
      kong.log.err(err)
      return kong.response.exit(500, { message = "An unexpected error happened" })
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
    kong.log.err(err)
    return kong.response.exit(500, { message = "An unexpected error occurred" })
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
