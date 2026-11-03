--[=[
MIT License

Copyright (c) 2026 patpatpatrick

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

Pinned classifier excerpt from Boot Mod Loader v0.13.4.
https://github.com/pat-pat-patrick/boot-mod-loader/blob/v0.13.4/src/boot_mod_loader.lua
No loader/game code is executed by this fixture.
]=]
local L = {}
L.for_chef = {}
-- The script's tokens, comments and strings left out: { kind, ... } where kind is the
-- word, the symbol, or "name"/"number"/"string". For the scope reading below.
local KEYWORD = {}
for w in string.gmatch("and break do else elseif end false for function if in local nil not or repeat return then true until while", "%a+") do KEYWORD[w] = true end

local function lua_tokens(src)
  local out, names, i, n = {}, {}, 1, #src
  local find, sub, byte = string.find, string.sub, string.byte
  local function long_close(at)
    -- a long bracket opening at at ([[, [=[, ...): the index after its close, or nil if none opens there
    local _, e, eq = find(src, "^%[(=*)%[", at)
    if not e then return nil end
    local _, close = find(src, "]" .. eq .. "]", e + 1, true)
    return (close or n) + 1
  end
  while i <= n do
    local s0 = find(src, "[^%s]", i)
    if not s0 then break end
    i = s0
    local c = sub(src, i, i)
    if c == "-" and sub(src, i + 1, i + 1) == "-" then
      i = long_close(i + 2) or ((find(src, "\n", i + 2, true) or n) + 1)
    elseif c == '"' or c == "'" then
      local j = i + 1
      while true do
        local k = find(src, "[\\" .. c .. "\n]", j)
        if not k then j = n + 1 break end
        local ch = sub(src, k, k)
        if ch == "\\" then j = k + 2 else j = k + 1 break end
      end
      out[#out + 1] = "string"
      i = j
    elseif c == "[" and find(src, "^%[=*%[", i) then
      out[#out + 1] = "string"
      i = long_close(i)
    elseif find(c, "[%a_]") then
      local _, e = find(src, "^[%w_]+", i)
      local word = sub(src, i, e)
      if KEYWORD[word] then out[#out + 1] = word else out[#out + 1] = "name" names[#out] = word end
      i = e + 1
    elseif find(c, "%d") or (c == "." and find(src, "^%.%d", i)) then
      local _, e = find(src, "^[%w%.]+", i)
      if find(sub(src, e, e), "[eE]") and find(src, "^[%+%-]%d", e + 1) then _, e = find(src, "^[%+%-]%d+", e + 1) end
      out[#out + 1] = "number"
      i = e + 1
    elseif find(src, "^%.%.%.", i) then out[#out + 1] = "..." i = i + 3
    elseif find(src, "^[=~<>]=", i) or find(src, "^%.%.", i) then out[#out + 1] = sub(src, i, i + 1) i = i + 2
    else out[#out + 1] = c i = i + 1
    end
  end
  return out, names
end

-- local chef = ... at the script's top, then chef.x / chef:x with that chef never tested (if
-- chef, not chef, chef and, type(chef), chef == ...). Scopes are followed: a chef a function or
-- block declares for itself (a parameter, a local) is another variable, and its tests say
-- nothing of the script's (0.13.3: HUDdle 0.4.9's modules test their own chef, and it failed
-- here with "attempt to index local 'chef' (a nil value)").
local function chef_untested(src)
  local t, names = lua_tokens(src)
  local function is_chef(k) return t[k] == "name" and names[k] == "chef" end
  local shadows, depth = { false }, 1
  local takes, used, tested = false, false, false
  local i = 1
  while i <= #t do
    local kind = t[i]
    if kind == "function" then
      local own, k = false, i + 1
      while k <= #t and t[k] ~= "(" do k = k + 1 end
      k = k + 1
      while k <= #t and t[k] ~= ")" do if is_chef(k) then own = true end k = k + 1 end
      depth = depth + 1 shadows[depth] = own
    elseif kind == "do" or kind == "if" or kind == "repeat" then
      depth = depth + 1 shadows[depth] = false
    elseif kind == "end" or kind == "until" then
      if depth > 1 then shadows[depth] = nil depth = depth - 1 end
    elseif kind == "local" then
      if t[i + 1] == "function" then
        if is_chef(i + 2) then shadows[depth] = true end
      else
        local k, has, count = i + 1, false, 0
        while t[k] == "name" do
          count = count + 1
          if names[k] == "chef" then has = true end
          k = k + 1
          if t[k] == "," then k = k + 1 else break end
        end
        if has then
          if not takes and depth == 1 and count == 1 and t[k] == "=" and t[k + 1] == "..." then takes = true
          else shadows[depth] = true end
          i = k - 1
        end
      end
    elseif takes and is_chef(i) then
      local free = true
      for d = 1, depth do if shadows[d] then free = false break end end
      local prev, nxt = t[i - 1], t[i + 1]
      if free and prev ~= "." and prev ~= ":" then
        if nxt == "." or nxt == ":" or nxt == "[" then used = true
        elseif prev == "if" or prev == "not" or prev == "and" or prev == "or" or prev == "==" or prev == "~=" or prev == "elseif" or prev == "while"
            or nxt == "and" or nxt == "or" or nxt == "then" or nxt == "==" or nxt == "~="
            or (prev == "(" and nxt == ")" and t[i - 2] == "name" and names[i - 2] == "type") then
          tested = true
        end
      end
    end
    i = i + 1
  end
  return takes and used and not tested
end

local function for_chef(source)
  local head = string.sub(source, 1, 1200)
  if string.find(head, "\n%-%- HD2%-Requires: chef%-shared%-loader") or string.find(head, "\n%-%- HD2%-Requires: chef%-loader") then
    return true
  end
  if not (string.find(source, "^local%s+chef%s*=%s*%.%.%.") or string.find(source, "\nlocal%s+chef%s*=%s*%.%.%.")) then return false end
  -- chef tested nowhere in the text: the quick answer. A test somewhere may be of another chef (a
  -- function's own), so only then is the script read with its scopes
  local tested_somewhere = false
  for _, test in ipairs({ "if%s+chef%s", "if%s+not%s+chef[%s%)]", "not%s+chef%s+then", "type%(%s*chef%s*%)",
                          "[%s%(=,]chef%s+and%s", "[%s%(=,]chef%s+or%s", "chef%s*[=~]=" }) do
    if string.find(source, test) then tested_somewhere = true break end
  end
  if not tested_somewhere then return string.find(source, "chef[%.:]") ~= nil end
  local ok, chef_only = pcall(chef_untested, source)
  return ok and chef_only
end


return for_chef

