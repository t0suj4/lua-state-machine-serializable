package = "statemachine-es"
version = "2.0.1-1"
source = {
  url = "https://github.com/t0suj4/lua-state-machine/archive/v2.0.1.tar.gz",
  dir = "lua-state-machine-2.0.1"
}
description = {
   summary = "A finite state machine micro framework with external state",
   detailed = [[
      This standalone module provides a finite state machine for your pleasure. 
      Extended for externally managed state.
   ]],
   homepage = "https://github.com/t0suj4/lua-state-machine",
   license = "MIT/X11"
}
dependencies = {
   "lua >= 5.1"
}
build = {
  type = "builtin",
  modules = {
    ["statemachine-es"] = "statemachine.lua"
  },
  copy_directories = {}
}

