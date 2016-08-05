chai = require "chai"
should = chai.should()
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
  before (done) ->
    fs.unlinkAsync testConfigFile
    .catch -> return true
    .finally ->
      samjs.reset()
      .plugins(samjsMongo,samjsAuth,samjsMongoAuth,samjsAuthMongo)
      .options({config:testConfigFile})
      .configs({name:"testConfig",read:"root",write:"root"})
      done()


  describe "auth-mongo", ->
    users = null
    describe "configs", ->
      it "should reject get", (done) ->
        samjs.configs.testConfig.get()
        .catch -> done()
      it "should reject set", (done) ->
        samjs.configs.testConfig.set()
        .catch -> done()
      it "should reject test", (done) ->
        samjs.configs.testConfig.test()
        .catch -> done()
    describe "models", ->
      it "should create users", ->
        samjs.models()
        should.exist samjs.models.users
    describe "startup", ->
      it "should configure", (done) ->
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
        .then -> done()
        .catch done
      it "should not install when false user is supplied", (done) ->
        client.install.onceInstall
        .then ->
          client.auth.createRoot {}
        .catch (e) ->
          e.message.should.equal "Username and password required"
          done()
      it "should install", (done) ->
        client.auth.createRoot {name:"root",pwd:"rootroot"}
        .then ->
          client.install.onceInstalled
        .then -> done()
        .catch done
      it "should be started up", (done) ->
        samjs.state.onceStarted
        .then -> done()
        .catch done
      it "should reject users.find", (done) ->
        users = new client.Mongo("users")
        users.find()
        .then (result) ->
          should.not.exist result
        .catch (e) ->
          done()
      it "should reject users.count", (done) ->
        users.count()
        .then (result) ->
          should.not.exist result
        .catch (e) ->
          done()
      it "should reject users.remove", (done) ->
        users.remove({name:"root"})
        .then (result) ->
          should.not.exist result
        .catch (e) ->
          done()
      it "should reject users.insert", (done) ->
        users.insert({name:"root",pwd:"newpwd"})
        .then (result) ->
          should.not.exist result
        .catch (e) ->
          done()
      it "should reject users.update", (done) ->
        users.update(cond:{group:"root"}, doc: {pwd:"newpwd"})
        .then (result) ->
          should.not.exist result
        .catch (e) ->
          done()
      it "should reject config.set", (done) ->
        client.config.set("testConfig","value")
        .catch -> done()
      it "should reject config.get", (done) ->
        client.config.get("testConfig")
        .catch -> done()
      it "should auth", (done) ->
        client.auth.login {name:"root",pwd:"rootroot"}
        .then (result) ->
          result.name.should.equal "root"
          result.group.should.equal "root"
          done()
        .catch done
      describe "once authenticated", ->
        it "should users.find", (done) ->
          users.find(find:{name:"root"})
          .then (result) ->
            result = result[0]
            should.exist result._id
            should.exist result.group
            result.group.should.equal "root"
            should.exist result.name
            result.name.should.equal "root"
            should.not.exist result.pwd
            done()
          .catch done
        it "should users.insert", (done) ->
          users.insert({name:"root2",pwd:"newpwd",group:"root"})
          .then (result) ->
            should.exist result._id
            done()
          .catch done
        it "should users.count", (done) ->
          users.count({group:"root"})
          .then (result) ->
            result.should.equal 2
            done()
          .catch done
        it "should users.update", (done) ->
          users.update(cond:{name:"root2"}, doc: {group:"all"})
          .then (result) ->
            result.length.should.equal 1
            users.find(find: result[0])
          .then (result) ->
            result[0].group.should.equal "all"
            done()
          .catch done
        it "should users.remove", (done) ->
          users.remove({name:"root2"})
          .then (result) ->
            result.length.should.equal 1
            done()
          .catch done
        it "should config.set", (done) ->
          client.config.set("testConfig","value")
          .then -> done()
          .catch done
        it "should config.get", (done) ->
          client.config.get("testConfig")
          .then (result) ->
            result.should.equal "value"
            done()
          .catch done

  after (done) ->
    if samjs.models.users?
      model = samjs.models.users.dbModel
      model.remove({})
      .then ->
        return samjs.shutdown() if samjs.shutdown?
      .then ->  done()
    else
      if samjs.shutdown?
        samjs.shutdown().then -> done()
      else
        done()
