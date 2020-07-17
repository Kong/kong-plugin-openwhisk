return {
  name = "openwhisk",
  fields = {
    {
      config = {
        type = "record",
        fields = {
          { timeout       = { type = "integer", default  = 60000 } },
          { keepalive     = { type = "integer", default  = 60000 } },
          { service_token = { type = "string"                     } },
          { host          = { type = "string",  required = true   } },
          { port          = { type = "integer", default  = 443   } },
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
