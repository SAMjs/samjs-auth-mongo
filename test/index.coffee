chai = require "chai"
should = chai.should()
chai.use require "chai-as-promised"
samjs = require "samjs"
samjsClient = require "samjs-client"
samjsMongo = require "samjs-mongo"
samjsMongoClient = require "samjs-mongo-client"
samjsMongoAuth = require "samjs-mongo-auth"
samjsAuth = require "samjs-auth"
samjsAuthClient = require "samjs-auth-client"
samjsAuthMongo = require("../src/main")
samjsAuthMongoClient = require "samjs-auth-mongo-client"

fs = samjs.Promise.promisifyAll(require("fs"))
port = 3060
url = "http://localhost:"+port+"/"
testConfigFile = "test/testConfig.json"
mongodb = "mongodb://localhost/test"

describe "samjs", ->
  client = null
  before ->
    fs.unlinkAsync testConfigFile
    .catch -> return true
    .finally ->
      samjs.reset()
      .plugins(samjsMongo,samjsAuth(),samjsMongoAuth,samjsAuthMongo)
      .options({config:testConfigFile})
      .configs({name:"testConfig",access: {read:"root",write:"root"}})


  describe "auth-mongo", ->
    users = null
    describe "configs", ->
      it "should reject get", ->
        samjs.configs.testConfig.get()
        .should.be.rejected
      it "should reject set", ->
        samjs.configs.testConfig.set()
        .should.be.rejected
      it "should reject test", ->
        samjs.configs.testConfig.test()
        .should.be.rejected
    describe "models", ->
      it "should create users", ->
        samjs.models()
        should.exist samjs.models.users
    describe "startup", ->
      it "should configure", ->
        samjs.startup().io.listen(port)
        client = samjsClient({
          url: url
          ioOpts:
            reconnection: false
            autoConnect: false
          })()
        client.plugins(samjsAuthClient,samjsMongoClient,samjsAuthMongoClient)
        client.install.onceConfigure
        .then ->
          client.install.set "mongoURI", mongodb
          client.install.onceConfigured

      it "should not install when false user is supplied",  ->
        client.install.onceInstall
        .then ->
          client.auth.createRoot {}
        .should.be.rejected
      it "should install", ->
        client.auth.createRoot {name:"root",pwd:"rootroot"}
        .then ->
          client.install.onceInstalled

      it "should be started up", ->
        samjs.state.onceStarted

      it "should reject users.find", ->
        users = client.getMongoModel("users")
        users.find().should.be.rejected
      it "should reject users.count", ->
        users.count().should.be.rejected
      it "should reject users.delete", ->
        users.delete({name:"root"}).should.be.rejected
      it "should reject users.insert", ->
        users.insert({name:"root",pwd:"newpwd"})
        .should.be.rejected
      it "should reject users.update", ->
        users.update(cond:{group:"root"}, doc: {pwd:"newpwd"})
        .should.be.rejected
      it "should reject config.set", ->
        client.config.set("testConfig","value")
        .should.be.rejected
      it "should reject config.get", ->
        client.config.get("testConfig")
        .should.be.rejected
      it "should auth", ->
        client.auth.login {name:"root",pwd:"rootroot"}
        .then (result) ->
          result.name.should.equal "root"
          result.group.should.equal "root"

      describe "once authenticated", ->
        it "should users.find",  ->
          users.find(find:{name:"root"})
          .then (result) ->
            result = result[0]
            should.exist result._id
            should.exist result.group
            result.group.should.equal "root"
            should.exist result.name
            result.name.should.equal "root"
            should.not.exist result.pwd

        it "should users.insert", ->
          users.insert({name:"root2",pwd:"newpwd",group:"root"})
          .then (result) ->
            should.exist result._id

        it "should users.count", ->
          users.count({group:"root"})
          .then (result) ->
            result.should.equal 2

        it "should users.update", ->
          users.update(cond:{name:"root2"}, doc: {group:"all"})
          .then (result) ->
            result.length.should.equal 1
            users.find(find: result[0])
          .then (result) ->
            result[0].group.should.equal "all"

        it "should users.delete", ->
          users.delete({name:"root2"})
          .then (result) ->
            result.length.should.equal 1

        it "should config.set", ->
          client.config.set("testConfig","value")

        it "should config.get",  ->
          client.config.get("testConfig")
          .then (result) ->
            result.should.equal "value"

  after ->
    if samjs.models.users?
      model = samjs.models.users.dbModel
      model.remove({})
      .then ->
        return samjs.shutdown() if samjs.shutdown?
    else if samjs.shutdown?
      samjs.shutdown()
