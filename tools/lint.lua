-- Lint the addon with luacheck's Lua API (works without LuaFileSystem, which the luacheck CLI needs).
-- Usage (repo root):  luajit tools/lint.lua [files...]      (needs: luarocks install luacheck)
local home = (os.getenv("USERPROFILE") or os.getenv("HOME") or ""):gsub("\\", "/")
package.path = home .. "/.luarocks/share/lua/5.1/?.lua;" .. home .. "/.luarocks/share/lua/5.1/?/init.lua;" .. package.path
package.preload.lfs = function()
    return { attributes = function() return nil end, currentdir = function() return "." end }
end
local luacheck = require("luacheck")

local env = {}
setfenv(assert(loadfile(".luacheckrc")), env)()
local opts = { std = "lua51", globals = env.globals, read_globals = env.read_globals,
               ignore = env.ignore, max_line_length = false }

local files = { ... }
if #files == 0 then
    files = { "Core.lua", "Training.lua", "BeastLore.lua", "Community.lua", "Debug.lua", "Finder.lua",
              "Minimap.lua", "Options.lua", "Data/Abilities.lua", "Data/Beasts.lua" }
end
local srcs = {}
for i, f in ipairs(files) do
    local h = assert(io.open(f, "rb"))
    srcs[i] = h:read("*a")
    h:close()
end

local total = 0
for i, fileReport in ipairs(luacheck.check_strings(srcs, opts)) do
    for _, ev in ipairs(fileReport) do
        total = total + 1
        print(("%s:%d:%d: (%s) %s"):format(files[i], ev.line, ev.column, ev.code, luacheck.get_message(ev)))
    end
end
print(("luacheck: %d file(s), %d warning(s)/error(s)"):format(#files, total))
os.exit(total == 0 and 0 or 1)
