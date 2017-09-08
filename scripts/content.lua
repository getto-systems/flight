local cjson = require "cjson"

local root = "/apps/getto/base"
local routes_json = root.."/routes.json"
local routes = root.."/routes"
local scripts = {
  auth = "sudo "..root.."/scripts/auth.sh",
  response = "sudo "..root.."/scripts/response.sh",
}

local function init_routes()
  local file = assert(io.open(routes_json))
  local content = file:read("*a")
  file:close()

  local json = cjson.decode(content)
  table.foreach(json, function(i,item)
    ngx.shared.routes:set(i, cjson.encode(item))
  end)

  ngx.shared.routes:set("init", true)
end

local function response(status,body,auth,response,content)
  ngx.status = status

  if auth then
    if auth["authenticate"] then
      ngx.header.WWW_Authenticate = auth["authenticate"]
    end
  end

  if response then
    if response["status"] then
      ngx.header.status = response["status"]
    end
    if response["content-type"] then
      ngx.header.Content_Type = response["content-type"]
    end
    if response["content-disposition"] then
      ngx.header.Content_Disposition = response["content-disposition"]
    end
    if response["location"] then
      ngx.header.Location = response["location"]
    end
  end

  if content then
    if content["origin"] then
      ngx.header.Access_Control_Allow_Origin = content["origin"]
      ngx.header.Access_Control_Allow_Methods = "POST, GET, OPTIONS"
      ngx.header.Access_Control_Allow_Headers = "Origin, Authorization, Content-Type"
    end
  end

  ngx.say(body)
  ngx.exit(ngx.OK)
end

local function command(script,args)
  local docker_host = os.getenv("DOCKER_HOST")
  if docker_host == nil or docker_host == "" then
    docker_host = "unix:///var/run/docker.sock"
  end

  local raw = script.." "..docker_host
  local command = script.." "..ngx.encode_base64(docker_host)

  table.foreach(args, function(i,arg)
    raw = raw.." "..arg
    command = command.." "..ngx.encode_base64(arg)
  end)

  local handle = assert(io.popen(command))
  local result = handle:read("*a")
  handle:close()

  result = cjson.decode(result)
  local data = result["result"]:gsub(" ","")
  data = ngx.decode_base64(data)

  local code = result["code"]

  if not (code == 0) then
    ngx.log(ngx.ERR, raw.."\n"..data)
  end

  return data, code
end

local function authenticate(content)
  local auth = content["auth"]
  local token
  if auth["method"] == "get" then
    local query
    if ngx.var.QUERY_STRING then
      query = ngx.decode_args(ngx.var.QUERY_STRING, 0)
      token = query["token"]
    end
  elseif auth["method"] == "header" then
    local request_headers = ngx.req.get_headers()
    local header = request_headers["Authorization"]
    local prefix = "Bearer "
    if string.sub(header,1,string.len(prefix)) == prefix then
      token = string.sub(header,string.len(prefix)+1)
    end
  end

  if token == nil then
    response(401, "unauthorized", {authenticate = prefix..'realm="token_required"'}, content["unauthorized"], content)
  end

  local data = cjson.encode({token = token})
  local result, code = command(scripts["auth"],{data,auth["image"],auth["key"],auth["expire"]})
  local credential = cjson.decode(data)

  if not (code == 0) then
    response(401, "unauthorized", {authenticate = prefix..'error="invalid_token"'}, content["unauthorized"], content)
  end

  if auth["roles"] then
    if not auth["roles"][credential["role"]] then
      response(403, "forbidden", {authenticate = prefix..'error="insufficient_role"'}, content["unauthorized"], content)
    end
  end

  return credential
end



-- MAIN ENTRY POINT

if not ngx.shared.routes:get("init") then
  init_routes()
end

local path = ngx.var.uri
local content = ngx.shared.routes:get(path)
if not content then
  response(404,"not found",nil,nil,nil)
end
content = cjson.decode(content)

if ngx.req.get_method() == "OPTIONS" then
  response(200,"ok",nil,nil,content)
end

local credential = {}
if content["auth"] then
  credential = authenticate(content)
end
credential = cjson.encode(credential)

ngx.req.read_body()
local data = ngx.req.get_body_data()
if data == nil then
  if ngx.var.QUERY_STRING then
    data = cjson.encode(ngx.decode_args(ngx.var.QUERY_STRING, 0))
  end
end

table.foreach(content["images"], function(i,line)
  local result, code = command(scripts["response"], {credential,data,line,routes..path.."/_env"})
  data = result

  if not (code == 0) then
    local status
    if code == 100 then
      status = 400
    elseif code == 104 then
      status = 404
    elseif code == 105 then
      status = 405
    elseif code == 109 then
      status = 409
    else
      status = 500
      data = "server error"
    end

    response(status, data, nil, content["not_found"], content)
  end
end)

response(200, data, nil, content["ok"], content)
