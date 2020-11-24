local typedefs = require "kong.db.schema.typedefs"

return {
  name = "openwhisk",
  fields = {
    { protocols = typedefs.protocols_http },
    { config = {
        type = "record",
        fields = {
          { timeout         = { type = "integer", default  = 60000 } },
          { keepalive       = { type = "integer", default  = 60000 } },
          { service_token   = { type = "string"                     } },
          { host            = typedefs.host({ required = true }), },
          { port            = typedefs.port({ required = true, default = 443 }), },
          { path            = { type = "string",  required = true   } },
          { action          = { type = "string",  required = true   } },
          { https           = { type = "boolean", default  = true   } },
          { https_verify    = { type = "boolean", default  = false  } },
          { raw_function    = { type = "boolean", default  = false  } },
          { result          = { type = "boolean", default  = true   } },
          { environment     = { type = "string",  default  = "{}"   } },
          { parameters      = { type = "string",  default  = "{}"   } },
          { methods         = {
              type = "array",
              default  = { "POST" },
              elements = {
                type = "string",
                one_of = { "HEAD", "GET", "POST", "PATCH", "PUT" }
              }
            }
          },
          { allowed_origins = {
              type = "array",
              default  = {},
              elements = {
                type = "string",
              }
            }
          },
        }
      }
    }
  }
}
