# out: ../lib/main.js
module.exports = (samjs) ->
  debug = samjs.debug("auth-mongo")
  throw new Error "samjs-mongo not found - must be loaded before samjs-auth-mongo" unless samjs.mongo
  throw new Error "samjs-auth not found - must be loaded before samjs-auth-mongo" unless samjs.auth
  throw new Error "samjs-mongo-auth not found - must be loaded before samjs-auth-mongo" unless samjs.mongoAuth

  parsePermission = (permission) ->
    unless samjs.util.isArray(permission)
      if samjs.util.isString(permission)
        if samjs.options.hierarchical
          if samjs.configs.groups.value?
            i = samjs.configs.groups.value.indexOf(permission)
            return samjs.configs.groups.value.slice i
      return [permission]
    return permission

  samjs.auth.permissionCheckers.inGroup = (permission, user) ->
    if permission == true
      return true
    else
      if samjs.util.isString(permission)
        permission = parsePermission(permission)
      if samjs.util.isArray(permission)
        group = user.group
        if samjs.util.isString(group)
          groups = [group]
        else if samjs.util.isArray(group)
          groups = group
        else
          groups = []
        for group in groups
          return true if permission.indexOf(group) > -1
    return false

  samjs.mongo.plugins users: (options) ->
    options ?= {}
    pc = @permissionChecker
    pc ?= samjs.options.permissionChecker
    if pc == "inGroup"
      options.read ?= samjs.options.groupRoot
      options.write ?= samjs.options.groupRoot
      options._read = parsePermission(options.read)
      options._write = parsePermission(options.write)
    else
      options.read ?= [samjs.options.rootUser]
      options.write ?= [samjs.options.rootUser]
    @test = (value) ->
      @dbModel.count {group:samjs.options.groupRoot}
      .then (data) ->
        if data == 0
          throw new Error "no #{samjs.options.groupRoot} found"
    @installInterface = (socket) ->
      socket.on "authMongo.getInstallationInfo", (request) ->
        if request.token?
          obj = success: true, content:
            groupRoot: samjs.options.groupRoot
            group: samjs.options.group
          socket.emit "authMongo.getInstallationInfo.#{request.token}", obj
      socket.on "authMongo.createRoot", (request) =>
        if request.token?
          if request?.content? and request.content[samjs.options.username]? and
              request.content[samjs.options.password]?
            @dbModel.create request.content
            .then (result) -> success:true, content:result
            .catch (e) -> success:false, content:e?.message
            .then (response) ->
              if response.success
                debug "user installed completely"
                samjs.state.checkInstalled()
              socket.emit "authMongo.createRoot." + request.token, response

          else
            socket.emit "authMongo.createRoot." + request.token,
              {success:false, content: "Username and password required"}
      return ->
        if socket?
          socket.removeAllListeners "authMongo.createRoot"
          socket.removeAllListeners "authMongo.getInstallationInfo"


    @addHook "afterCreate", ->
      properties = {}
      properties[samjs.options.username] = {
        type: String
        required: true
        index:
          unique: true
        read: options.read
        write: options.write
      }
      properties[samjs.options.password] = {
        type: String
        required: true
        write: options.write
      }
      properties[samjs.options.group] = {
        type: String
        required: true
        read: options.read
        write: options.write
      }
      @schema.add(properties)
      @schema.pre "save", (next) ->
        samjs.auth.crypto.generateHashedPassword(@,next)

  usersModel = null
  samjs.auth.replaceUserHandler (userName) ->
    usersModel ?= samjs.models.users.dbModel
    find = {}
    find[samjs.options.username] = userName
    return usersModel.findOne(find).then (response) ->
      response.toObject(versionKey: false)
  return new class AuthMongo
    name: "authMongo"

    options:
      hierarchical: true
      groupRoot: "root"
      group: "group"
      permissionChecker: "inGroup"

    configs: [{
      name: "groups"
      value: ["root"]
      test: (value) -> new samjs.Promise (resolve, reject) ->
        if samjs.util.isArray(value)
          resolve(data)
        else
          reject(data)
      hooks:
        afterCreate: (config) ->
          config.read ?= samjs.options.groupRoot
          config.write ?= samjs.options.groupRoot
        after_Set: (obj) ->
          for d,i in obj.data
            if obj.oldData[i] != d
              for name, config of samjs.configs
                config._read = null
                config._write = null
              for name, model of samjs.models
                model._read = null
                model._write = null
              break
          return obj
      }]

    models: [{
      name: "users"
      schema: {}
      db: "mongo"
      plugins:
        "users": null
      isRequired: true
    }]

    parsePermission: parsePermission
