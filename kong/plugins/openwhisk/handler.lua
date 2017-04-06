local BasePlugin = require "kong.plugins.base_plugin"
local meta = require "kong.meta"
local responses = require "kong.tools.responses"
local http = require "resty.http"
local cjson = require "cjson.safe"
local utils = require "kong.tools.utils"
local multipart = require "multipart"
local public_utils = require "kong.tools.public"

local string_find = string.find
local ngx_req_get_headers = ngx.req.get_headers
local ngx_req_read_body = ngx.req.read_body
local ngx_req_get_uri_args = ngx.req.get_uri_args
local ngx_req_get_body_data = ngx.req.get_body_data
local ngx_encode_base64 = ngx.encode_base64
local ngx_log = ngx.log
local ngx_print = ngx.print
local ngx_exit = ngx.exit
local format = string.format
local pairs = pairs

local ERR = ngx.ERR
local SERVER = meta._NAME .. "/" .. meta._VERSION


local function log(lvl, ...)
  ngx_log(lvl, "[openwhisk] ", ...)
end


local function retrieve_parameters()
  ngx_req_read_body()
  local body_parameters, err
  local content_type = ngx_req_get_headers()["content-type"]

  if content_type and string_find(content_type:lower(), "multipart/form-data", nil, true) then
    body_parameters = multipart(ngx_req_get_body_data(), content_type):get_all()
  elseif content_type and string_find(content_type:lower(), "application/json", nil, true) then
    body_parameters, err = cjson.decode(ngx_req_get_body_data())
  else
    body_parameters = public_utils.get_post_args()
  end

  if err then
    return nil, err
  end

  return utils.table_merge(ngx_req_get_uri_args(), body_parameters)

end


local OpenWhisk = BasePlugin:extend()
OpenWhisk.PRIORITY = 1000

function OpenWhisk:new()
  OpenWhisk.super.new(self, "openwhisk")
end


function OpenWhisk:access(config)
  OpenWhisk.super.access(self)

  -- only allow POST
  if ngx.var.request_method ~= "POST" then
    return responses.send_HTTP_METHOD_NOT_ALLOWED()
  end

  -- get parameters
  local body, err = retrieve_parameters()
  if err then
    return responses.send_HTTP_BAD_REQUEST(err)
  end
  local body_json = cjson.encode(body)

  -- invoke action
  local path = format("%s/actions/%s?blocking=true&result=%s&timeout=%s",
    config.path, config.action, config.result, config.timeout)

  local basic_auth
  if config.service_token ~= nil then
    basic_auth = "Basic "..ngx_encode_base64(config.service_token)
  end

  local client = http.new()
  client:set_timeout(config.timeout)

  local ok, err = client:connect(config.host, config.port)
  if not ok then
    log(ERR, "could not connect to Openwhisk server: ", err)
    return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
  else
    if config.https then
      local ok, err = client:ssl_handshake(false, config.host, config.https_verify)
      if not ok then
        log(ERR, "could not perform SSL handshake : ", err)
        return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
      end
    end
  end
  local res, err = client:request {
    method = "POST",
    path = path,
    body = body_json,
    headers = {
      ["Content-Type"] = "application/json",
      ["Authorization"] = basic_auth
    }
  }

  if not res then
    return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
  end

  local body = res:read_body()

  local ok, err = client:set_keepalive()
  if ok ~= 1 then
    log(ERR, "could not keepalive connection: ", err)
  end

  -- prepare response for downstream
  for k, v in pairs(res.headers) do
    ngx.header[k] = v
  end
  ngx.header["Server"] = SERVER
  ngx.status = res.status
  ngx_print(body)

  return ngx_exit(res.status)
end


return OpenWhisk
