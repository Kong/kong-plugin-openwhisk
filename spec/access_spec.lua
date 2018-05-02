local helpers = require "spec.helpers"
local cjson   = require "cjson"


--*****************************************************--
-- Setup to run the tests:
-- 1. Setup Openwhisk server and create a action
--    using include `action/hello.js`
-- 2. Set `config.host` and `config.service_token`
--*****************************************************--


local HOST          = "openwhisk_host"
local SERVICE_TOKEN = "openwhisk_auth_token"


describe("Plugin: openwhisk", function()
  local proxy
  setup(function()

    local api1 = assert(helpers.dao.apis:insert {
      name         = "test-openwhisk",
      hosts        = { "test.com" },
      upstream_url = "http://mockbin.com",
    })

    assert(helpers.dao.plugins:insert {
      api_id = api1.id,
      name   = "openwhisk",
      config = {
        host          = HOST,
        service_token = SERVICE_TOKEN,
        action        = "hello",
        path          = "/api/v1/namespaces/guest",
      }
    })

    assert(helpers.start_kong())

  end)

  teardown(function()
    helpers.stop_kong(nil, false)
  end)

  before_each(function()
    proxy = helpers.proxy_client()
  end)

  after_each(function()
    if proxy then proxy:close() end
  end)

  describe("invoke action hello", function()

    it("should allow POST", function()
      local res = assert(proxy:send {
        method  = "POST",
        path    = "/",
        body    = {},
        headers = {
          ["Host"] = "test.com"
        }
      })

      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.equal("Hello, World!", json.payload)
    end)

    it("should allow POST with querystring", function()
      local res = assert(proxy:send {
        method  = "POST",
        path    = "/?name=foo",
        body    = {},
        headers = {
          ["Host"] = "test.com"
        }
      })

      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.equal("Hello, foo!", json.payload)
    end)

    it("should allow POST with json body", function()
      local res = assert(proxy:send {
        method  = "POST",
        path    = "/",
        body    = { name = "foo" },
        headers = {
          ["Host"]         = "test.com",
          ["Content-Type"] = "application/json"
        }
      })

      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.equal("Hello, foo!", json.payload)
    end)

    it("should allow POST with form-encoded body", function()
      local res = assert(proxy:send {
        method  = "POST",
        path    = "/post",
        body    = {
          name  = "foo"
        },
        headers = {
          ["Host"]         = "test.com",
          ["Content-Type"] = "application/x-www-form-urlencoded"
        },

      })
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.equal("Hello, foo!", json.payload)
    end)

    it("should not allow GET", function()
      local res = assert(proxy:send {
        method  = "GET",
        path    = "/",
        body    = { name = "foo" },
        headers = {
          ["Host"]         = "test.com",
          ["Content-Type"] = "application/json"
        }
      })
      local body = assert.res_status(405, res)
      local json = cjson.decode(body)
      assert.equal("Method not allowed", json.message)
    end)

    it("should not allow DELETE", function()
      local res = assert(proxy:send {
        method  = "DELETE",
        path    = "/",
        body    = { name = "foo" },
        headers = {
          ["Host"]         = "test.com",
          ["Content-Type"] = "application/json"
        }
      })
      local body = assert.res_status(405, res)
      local json = cjson.decode(body)
      assert.equal("Method not allowed", json.message)
    end)
  end)
end)
