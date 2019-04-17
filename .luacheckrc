std             = "ngx_lua"
unused_args     = false
redefined       = false
max_line_length = false


globals = {
    "kong",
}


files["specs/**/*.lua"] = {
    std = "ngx_lua+busted",
}
