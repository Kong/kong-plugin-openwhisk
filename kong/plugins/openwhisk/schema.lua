local typedefs = require "kong.db.schema.typedefs"

return {
  name = "openwhisk",
  fields = {
    { protocols = typedefs.protocols_http },
    { config = {
        type = "record",
        fields = {
          { timeout       = { type = "integer", default  = 60000 } },
          { keepalive     = { type = "integer", default  = 60000 } },
          { service_token = { type = "string"                     } },
          { host          = typedefs.host({ required = true }), },
          { port          = typedefs.port({ required = true, default = 443 }), },
          { path          = { type = "string",  required = true   } },
          { action        = { type = "string",  required = true   } },
          { https         = { type = "boolean", default  = true   } },
          { https_verify  = { type = "boolean", default  = false  } },
          { result        = { type = "boolean", default  = true   } },
          { method        = {
              type = "array",
              default  = { "POST" },
              elements = {
                type = "string",
                one_of = { "HEAD", "GET", "POST", "PATCH", "PUT" }
              }
            }
          },
          { environment   = {
              type = "map",
              keys = { type = "string" },
              values = { type = "object" },
              default  = {}
            }
          },
          { parameters    = {
              type = "map",
              keys = { type = "string" },
              values = { type = "object" },
              default  = {}
            }
          },
        }
      }
    }
  }
}
