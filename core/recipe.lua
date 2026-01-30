local util = require("core.util")

local M = {}

local function json_encode(value)
  if textutils and textutils.serializeJSON then
    return textutils.serializeJSON(value)
  end
  local t = type(value)
  if t == "nil" then
    return "null"
  elseif t == "number" then
    return tostring(value)
  elseif t == "boolean" then
    return value and "true" or "false"
  elseif t == "string" then
    local escaped = value:gsub("\\", "\\\\")
      :gsub("\"", "\\\"")
      :gsub("\n", "\\n")
      :gsub("\r", "\\r")
      :gsub("\t", "\\t")
    return "\"" .. escaped .. "\""
  elseif t == "table" then
    local is_array = true
    local max = 0
    for k, _ in pairs(value) do
      if type(k) ~= "number" then
        is_array = false
        break
      end
      if k > max then
        max = k
      end
    end
    if is_array then
      local parts = {}
      for i = 1, max do
        table.insert(parts, json_encode(value[i]))
      end
      return "[" .. table.concat(parts, ",") .. "]"
    else
      local parts = {}
      for k, v in pairs(value) do
        table.insert(parts, json_encode(tostring(k)) .. ":" .. json_encode(v))
      end
      return "{" .. table.concat(parts, ",") .. "}"
    end
  else
    error("json_encode unsupported type: " .. t)
  end
end

local function json_decode(text)
  if textutils and textutils.unserializeJSON then
    return textutils.unserializeJSON(text)
  end

  local i = 1
  local function skip_ws()
    while true do
      local c = text:sub(i, i)
      if c == " " or c == "\n" or c == "\r" or c == "\t" then
        i = i + 1
      else
        return
      end
    end
  end

  local function parse_value()
    skip_ws()
    local c = text:sub(i, i)
    if c == "\"" then
      i = i + 1
      local out = {}
      while i <= #text do
        local ch = text:sub(i, i)
        if ch == "\"" then
          i = i + 1
          return table.concat(out)
        elseif ch == "\\" then
          local nxt = text:sub(i + 1, i + 1)
          if nxt == "n" then
            table.insert(out, "\n")
          elseif nxt == "r" then
            table.insert(out, "\r")
          elseif nxt == "t" then
            table.insert(out, "\t")
          else
            table.insert(out, nxt)
          end
          i = i + 2
        else
          table.insert(out, ch)
          i = i + 1
        end
      end
      error("json_decode: unterminated string")
    elseif c == "{" then
      i = i + 1
      local obj = {}
      skip_ws()
      if text:sub(i, i) == "}" then
        i = i + 1
        return obj
      end
      while true do
        skip_ws()
        local key = parse_value()
        skip_ws()
        if text:sub(i, i) ~= ":" then
          error("json_decode: expected ':'")
        end
        i = i + 1
        local val = parse_value()
        obj[key] = val
        skip_ws()
        local sep = text:sub(i, i)
        if sep == "}" then
          i = i + 1
          break
        elseif sep == "," then
          i = i + 1
        else
          error("json_decode: expected ',' or '}'")
        end
      end
      return obj
    elseif c == "[" then
      i = i + 1
      local arr = {}
      skip_ws()
      if text:sub(i, i) == "]" then
        i = i + 1
        return arr
      end
      while true do
        local val = parse_value()
        table.insert(arr, val)
        skip_ws()
        local sep = text:sub(i, i)
        if sep == "]" then
          i = i + 1
          break
        elseif sep == "," then
          i = i + 1
        else
          error("json_decode: expected ',' or ']'")
        end
      end
      return arr
    elseif c == "t" and text:sub(i, i + 3) == "true" then
      i = i + 4
      return true
    elseif c == "f" and text:sub(i, i + 4) == "false" then
      i = i + 5
      return false
    elseif c == "n" and text:sub(i, i + 3) == "null" then
      i = i + 4
      return nil
    else
      local start = i
      while i <= #text do
        local ch = text:sub(i, i)
        if ch:match("[%d%.%-eE]") then
          i = i + 1
        else
          break
        end
      end
      local num = tonumber(text:sub(start, i - 1))
      if num == nil then
        error("json_decode: invalid number")
      end
      return num
    end
  end

  local value = parse_value()
  skip_ws()
  return value
end

local function read_file(path)
  if fs and fs.open then
    local handle = fs.open(path, "r")
    if not handle then
      return nil
    end
    local data = handle.readAll()
    handle.close()
    return data
  end
  local handle = io.open(path, "r")
  if not handle then
    return nil
  end
  local data = handle:read("*a")
  handle:close()
  return data
end

local function write_file(path, data)
  if fs and fs.open then
    local handle = fs.open(path, "w")
    if not handle then
      error("failed to open file for write: " .. tostring(path))
    end
    handle.write(data)
    handle.close()
    return true
  end
  local handle = io.open(path, "w")
  if not handle then
    error("failed to open file for write: " .. tostring(path))
  end
  handle:write(data)
  handle:close()
  return true
end

local function file_exists(path)
  if fs and fs.exists then
    return fs.exists(path)
  end
  local handle = io.open(path, "r")
  if handle then
    handle:close()
    return true
  end
  return false
end

function M.new_registry()
  return { recipes = {}, index = {} }
end

function M.add(registry, recipe)
  if not recipe.outputs or #recipe.outputs == 0 then
    error("recipe.outputs must not be empty: " .. tostring(recipe.id))
  end
  table.insert(registry.recipes, recipe)
end

function M.rebuild_index(registry)
  -- rebuilds and replaces registry.index, invalidates previous snapshots
  local index = {}
  for _, recipe in ipairs(registry.recipes) do
    local seen_outputs = {}
    for _, output in ipairs(recipe.outputs) do
      local key = util.normalize(output.item)
      if seen_outputs[key] then
        error("duplicate recipe output: " .. tostring(recipe.id) .. " -> " .. key)
      end
      seen_outputs[key] = true
      if not index[key] then index[key] = {} end
      table.insert(index[key], recipe)
    end
  end
  registry.index = index
  return index
end

function M.get_producers(registry, item_key)
  local key = util.normalize(item_key)
  local list = registry.index[key]
  if not list then return {} end
  local copy = {}
  for i, recipe in ipairs(list) do
    copy[i] = recipe
  end
  return copy
end

function M.save_registry(registry, path)
  assert(registry and registry.recipes, "invalid registry")
  assert(type(path) == "string" and path ~= "", "invalid path")
  local payload = { recipes = registry.recipes }
  local text = json_encode(payload)
  write_file(path, text)
  return true
end

function M.load_registry(path)
  assert(type(path) == "string" and path ~= "", "invalid path")
  if not file_exists(path) then
    return false, { code = "FILE_NOT_FOUND", path = path }
  end
  local text = read_file(path)
  if not text then
    return false, { code = "FILE_READ_FAILED", path = path }
  end
  local payload = json_decode(text)
  if type(payload) ~= "table" or type(payload.recipes) ~= "table" then
    return false, { code = "INVALID_RECIPE_FILE", path = path }
  end
  local registry = M.new_registry()
  for _, recipe in ipairs(payload.recipes) do
    M.add(registry, recipe)
  end
  M.rebuild_index(registry)
  return true, registry
end

function M.load_or_create(path, build_fn)
  assert(type(path) == "string" and path ~= "", "invalid path")
  if file_exists(path) then
    local ok, registry_or_err = M.load_registry(path)
    if ok then
      return true, registry_or_err
    end
  end
  if type(build_fn) ~= "function" then
    return false, { code = "NO_BUILDER", path = path }
  end
  local registry = build_fn(M.new_registry())
  M.save_registry(registry, path)
  return true, registry
end

return M

