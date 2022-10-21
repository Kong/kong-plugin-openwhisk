local typedefs = require "kong.db.schema.typedefs"

-- kong-ee
-- encrypt apikey and clientid, if configured
-- https://docs.konghq.com/gateway/2.6.x/plan-and-deploy/security/db-encryption/
local ok, enabled = pcall(function() return kong.configuration.keyring_enabled end)
local ENCRYPTED = ok and enabled or nil
-- /kong-ee


return {
  name = "openwhisk",
  fields = {
    { protocols = typedefs.protocols_http },
    { config = {
        type = "record",
        fields = {
          { timeout       = { type = "integer", default  = 60000 } },
          { keepalive     = { type = "integer", default  = 60000 } },
          { service_token = { type = "string", encrypted = ENCRYPTED } },
          { host          = typedefs.host({ required = true }), },
          { port          = typedefs.port({ required = true, default = 443 }), },
          { path          = { type = "string",  required = true   } },
          { action        = { type = "string",  required = true   } },
          { https         = { type = "boolean", default  = true   } },
          { https_verify  = { type = "boolean", default  = false  } },
          { result        = { type = "boolean", default  = true   } },
        }
      }
    }
  }
}
