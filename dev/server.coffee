samjs = require "samjs"
path = require "path"
fs = samjs.Promise.promisifyAll(require("fs"))
testConfigFile = "test/testConfig.json"
fs.unlinkAsync testConfigFile
.catch -> return true
.finally ->
  samjs
  .plugins([
    require("samjs-install")(),
    require("samjs-mongo"),
    require("samjs-auth"),
    require("samjs-mongo-auth"),
    require("../src/main.coffee")
    ])
  .options({config:testConfigFile})
  .configs()
  .models()
  .startup()
