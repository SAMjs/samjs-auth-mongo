# out: ../lib/main.js
path = require "path"
module.exports = (samjs) ->
  debug = samjs.debug("auth-mongo")
  throw new Error "samjs-mongo not found - must be loaded before samjs-auth-mongo" unless samjs.mongo
  throw new Error "samjs-auth not found - must be loaded before samjs-auth-mongo" unless samjs.auth
  throw new Error "samjs-mongo-auth not found - must be loaded before samjs-auth-mongo" unless samjs.mongoAuth

  usersModel = null
  samjs.auth.replaceUserHandler ((userName) ->
    usersModel ?= samjs.models.users
    if usersModel.authFind?
      find = usersModel.authFind(userName)
    else
      find = {}
      find[samjs.options.username] = userName
    query = usersModel.dbModel.findOne(find)
    populate = usersModel.populate
    if populate
      query.populate(populate)
    return query
    ), ((user) ->
      if user.toObject?
        return user.toObject(getters: true)
      else
        return samjs.helper.clone(user)
    )
  samjs.auth.addHook "afterLogin", (obj) ->
    socket = obj.socket.client.nsps["/"]
    socket.join(obj.user._id)
    socket.join(obj.user.group) if obj.user.group

    return obj
  samjs.auth.addHook "afterLogout", (obj) ->
    socket = obj.socket.client.nsps["/"]
    socket.leave(obj.user._id)
    socket.leave(obj.user.group) if obj.user.group
    return obj
  parsePermission = (permission) ->
    unless samjs.util.isArray(permission)
      if samjs.util.isString(permission)
        if samjs.options.hierarchical
          i = samjs.options.groups.indexOf(permission)
          return samjs.options.groups.slice i
      return [permission]
    return permission
  samjs.on "beforeConfigs", ->
    samjs.configs.addHook "afterProcess", (config) ->
      if (samjs.options.authOptions.permissionChecker == "inGroup" and not config.authOptions?.permissionChecker?) or
          (config.authOptions?.permissionChecker? and config.authOptions.permissionChecker == "inGroup")
        for mode in ["read","write"]
          if config[mode]?
            config[mode] = parsePermission(config[mode])
      return config
  samjs.mongo.addHook "afterProcess", (model) ->
    if (samjs.options.authOptions.permissionChecker == "inGroup" and not model.authOptions?.permissionChecker?) or
        (model.authOptions?.permissionChecker? and model.authOptions.permissionChecker == "inGroup")
      for key,val of model.schema.paths
        for mode in ["read","write"]
          if val.options[mode]?
            val.options[mode] = parsePermission(val.options[mode])
    return model

  samjs.auth.permissionCheckers.inGroup = (user, permission, options) ->
    if options.getIdentifier
      if user?
        return user[samjs.options.group]
      else
        return "__public"
    if permission == true
      if !options.authRequired or user?
        return true
    else
      if samjs.util.isString(permission)
        permission = parsePermission(permission)
      if samjs.util.isArray(permission)
        group = user[samjs.options.group]
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
    @access.read ?= [samjs.options.groupRoot]
    @access.write ?= [samjs.options.groupRoot]
    @installComp ?=
      paths: [path.resolve(__dirname, "./createUser")]
      icons: ["ma-person","ma-vpn_key"]
    @isRequired ?= true
    @test = (value) ->
      query = {}
      query[samjs.options.group] = samjs.options.groupRoot
      @dbModel.count query
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
            if @plugins.isOwner?
              id = samjs.mongo.mongoose.Types.ObjectId()
              request.content.owner = id
              request.content._id = id
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

    @addHook "beforeUpdate", (obj) ->
      if obj?.socket?.client? and obj?.query?.doc? and obj.query.cond?
        if obj.query.doc[samjs.options.password] and samjs.options.oldPassword
          return samjs.models.users.dbModel.findOne(obj.query.cond)
          .then (user) ->
            if user.equals(obj.socket.client.auth.user)
              unless obj.query.doc[samjs.options.oldPassword]
                throw new Error "no old password provided"
              samjs.auth.comparePassword user, obj.query.doc[samjs.options.oldPassword]
      return obj
    @addHook "afterCreate", (obj) ->
      properties = {}
      properties[samjs.options.username] ?= {
        type: String
        required: true
        index:
          unique: true
        read: options.read
        write: options.write
      }
      properties[samjs.options.password] ?= {
        type: String
        required: true
        read: false
        write: options.write
      }
      properties[samjs.options.group] ?= {
        type: String
        required: true
        read: options.read
        write: options.write
      }
      @schema.add(properties)
      @schema.pre "save", (next) ->
        samjs.auth.crypto.generateHashedPassword(@,next)
      return obj


  return new class AuthMongo
    name: "authMongo"

    options:
      hierarchical: true
      groupRoot: "root"
      group: "group"
      groups: ["root"]
      authOptions:
        permissionChecker: "inGroup"
      oldPassword: "oldPwd"

    models: [{
      name: "users"
      schema: {}
      db: "mongo"
      plugins:
        "users": null
    }]
