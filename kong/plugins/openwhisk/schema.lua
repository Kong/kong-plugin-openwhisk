return {
  fields = {
    timeout       = { type = "number",  default  = 60000 },
    keepalive     = { type = "number",  default  = 60000 },
    service_token = { type = "string"                    },
    host          = { type = "string",  required = true  },
    port          = { type = "number",  default  = 443   },
    path          = { type = "string",  required = true  },
    action        = { type = "string",  required = true  },
    https         = { type = "boolean", default  = true  },
    https_verify  = { type = "boolean", default  = false },
    result        = { type = "boolean", default  = true  },
  }
}
