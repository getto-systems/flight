local cjson = require "cjson"

local script = "sudo /usr/local/openresty/nginx/conf/scripts/flight.sh"
local docker_host = os.getenv("DOCKER_HOST")
if docker_host == nil then
  docker_host = "unix:///var/run/docker.sock"
end
local path = ngx.var.uri

local query
if ngx.var.QUERY_STRING then
  query = ngx.decode_args(ngx.var.QUERY_STRING, 0)
else
  query = {}
end

local request_headers = ngx.req.get_headers()
local auth = request_headers["Authorization"]
if auth == nil then
  if query["token"] then
    auth = "Get " .. query["token"]
  end
end
if auth == nil then
  auth = "none"
end
auth = ngx.encode_base64(auth)

ngx.req.read_body()
local body = ngx.req.get_body_data()
if body == nil then
  body = cjson.encode(query)
end
body = ngx.encode_base64(body)

local command = script .. " " .. docker_host .. " " .. path .. " " .. auth .. " " .. body
local handle = assert(io.popen(command))
local result = handle:read("*a")
handle:close()

if true then
  local response = cjson.decode(result)

  if response["status"] then
    ngx.status = response["status"]
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
  if response["www-authenticate"] then
    ngx.header.WWW_Authenticate = response["www-authenticate"]
  end
  if response["access-control-allow-origin"] then
    ngx.header.Access_Control_Allow_Origin = response["access-control-allow-origin"]
    ngx.header.Access_Control_Allow_Methods = "POST, GET, OPTIONS"
    ngx.header.Access_Control_Allow_Headers = "Origin, Authorization"
  end

  ngx.say(ngx.decode_base64(response["body"]))
else
  ngx.say(command)
  ngx.say(result)
end
