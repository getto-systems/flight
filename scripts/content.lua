local cjson = require "cjson"

local root = "/apps/getto/base"
local routes_json = root.."/routes.json"
local routes = root.."/routes"
local scripts = {
  auth          = "sudo "..root.."/scripts/auth.sh",
  response      = "sudo "..root.."/scripts/response.sh",
  volume_create = "sudo "..root.."/scripts/volume-create.sh",
  volume_delete = "sudo "..root.."/scripts/volume-delete.sh",
  copy_files    = "sudo "..root.."/scripts/copy-files.sh",
}

local function load_routes(dir,project)
  local file = assert(io.open(root.."/"..dir.."/"..project.."/routes.json"))
  local content = file:read("*a")
  file:close()

  local json = cjson.decode(content)
  for path,item in pairs(json) do
    ngx.shared.routes:set(path, cjson.encode(item))
  end
end
local function init_routes()
  local file = assert(io.open(routes_json))
  local content = file:read("*a")
  file:close()

  local json = cjson.decode(content)
  local dir = json["root"]
  for i,project in ipairs(json["projects"]) do
    load_routes(dir,project)
  end

  ngx.shared.routes:set("init", true)
end

local function command(script,args)
  local docker_host = os.getenv("DOCKER_HOST")
  if docker_host == nil or docker_host == "" then
    docker_host = "unix:///var/run/docker.sock"
  end

  local raw = script.." "..docker_host
  local command = script.." "..ngx.encode_base64(docker_host)

  for i,arg in ipairs(args) do
    raw = raw.." '"..arg.."'"
    command = command.." "..ngx.encode_base64(arg)
  end

  local handle = assert(io.popen(command))
  local result = handle:read("*a")
  handle:close()

  result = cjson.decode(result)
  local data = result["result"]:gsub(" ","")
  data = ngx.decode_base64(data)

  local code = result["code"]

  if not (code == 0) then
    ngx.log(ngx.ERR, raw, data)
  end

  return data, code
end

local function response(status,body,auth,response,content,volume)
  if volume then
    command(scripts["volume_delete"],{volume})
  end

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

local function authenticate(content)
  local auth = content["auth"]
  local token
  local prefix = "Bearer "
  if auth["method"] == "get" then
    local query
    if ngx.var.QUERY_STRING then
      query = ngx.decode_args(ngx.var.QUERY_STRING, 0)
      token = query["token"]
    end
  elseif auth["method"] == "header" then
    local request_headers = ngx.req.get_headers()
    local header = request_headers["Authorization"]
    if header then
      if string.sub(header,1,string.len(prefix)) == prefix then
        token = string.sub(header,string.len(prefix)+1)
      end
    end
  end

  if token == nil then
    response(401, "unauthorized", {authenticate = prefix..'realm="token_required"'}, content["unauthorized"], content, nil)
  end

  local data = cjson.encode({token = token})
  local result, code = command(scripts["auth"],{data,cjson.encode(auth)})

  if not (code == 0) then
    response(401, result, {authenticate = prefix..'error="invalid_token"'}, content["unauthorized"], content, nil)
  end

  local credential = cjson.decode(result)

  if auth["roles"] then
    if not auth["roles"][credential["role"]] then
      response(403, "forbidden", {authenticate = prefix..'error="insufficient_role"'}, content["unauthorized"], content, nil)
    end
  end

  return credential
end

local function upload_data(res)
  local head
  local content

  for i,line in pairs(res) do
    if i == 1 then
      head = line
    elseif i == 2 then
      content = line
    end
  end
  if head == "Content-Disposition" and content then
    local info = {}
    for k,v in string.gmatch(content,'; ([^=]*)="([^"]*)"') do
      info[k] = v
    end
    return info
  end
  return nil
end

local function upload(info,content,volume,volume_dir)
  local upload = require "resty.upload"
  local data = {}

  local chunk = 8192
  local timeout = 1000

  local dir = volume_dir.."/"..info["dest"]
  os.execute("mkdir -p "..dir)

  local form, err = upload:new(chunk)
  if not form then
    ngx.log(ngx.ERR, "failed to upload: ", err)
    return data
  end

  form:set_timeout(timeout)

  local file
  local upload_info = {}
  local key
  local buffer = ""

  while true do
    local typ,res,err = form:read()

    if not typ then
      ngx.log(ngx.ERR, "failed to read: ", err)

    elseif typ == "header" then
      local upload_data = upload_data(res)
      if upload_data then
        if upload_data["filename"] then
          local file_name = upload_data["name"]
          if file_name then
            upload_info["name"] = file_name
            file = io.open(dir.."/"..file_name, "w+")
            if not file then
              ngx.log(ngx.ERR, "failed to write: ", dir.."/"..file_name)
            end
          end
        elseif upload_data["name"] then
          key = upload_data["name"]
          buffer = ""
        end
      end
    elseif typ == "body" then
      if file then
        file:write(res)
      else
        buffer = buffer..res
      end
    elseif typ == "part_end" then
      if file then
        file:close()
        file = nil
      elseif key then
        upload_info[key] = buffer
        key = nil
        buffer = ""
      end
    end

    if typ == "eof" then
      if upload_info then
        upload_info["bucket"] = info["bucket"]
        table.insert(data,upload_info)
        upload_info = nil
      end
      break
    end
  end

  return data
end



-- MAIN ENTRY POINT

if not ngx.shared.routes:get("init") then
  init_routes()
end

local path = ngx.var.uri
local content = ngx.shared.routes:get(path)
if not content then
  response(404,"not found",nil,nil,nil,nil)
end
content = cjson.decode(content)

if ngx.req.get_method() == "OPTIONS" then
  response(200,"ok",nil,nil,content,nil)
end

local volume
local credential = {}
local data

volume = command(scripts["volume_create"],{})
volume = string.gsub(volume,"\n","")

local volume_dir = "/work/volumes/"..volume
os.execute("mkdir -p "..volume_dir)

if content["auth"] then
  credential = authenticate(content)
end
credential = cjson.encode(credential)

if content["upload"] then
  data = upload(content["upload"],content,volume,volume_dir)
  data = cjson.encode(data)
else
  ngx.req.read_body()
  data = ngx.req.get_body_data()
  if data == nil then
    if ngx.var.QUERY_STRING then
      data = cjson.encode(ngx.decode_args(ngx.var.QUERY_STRING, 0))
    end
  end
  if data == nil then
    data = cjson.encode({})
  end
end

command(scripts["copy_files"],{volume})

if content["commands"] then
  for i,json in ipairs(content["commands"]) do
    local result, code = command(scripts["response"], {volume,credential,data,cjson.encode(json),routes..path.."/"..i..".env"})
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

      response(status, data, nil, content["not_found"], content, volume)
    end
  end
end

response(200, data, nil, content["ok"], content, volume)
