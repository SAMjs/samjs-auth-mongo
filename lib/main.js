(function() {
  var path;

  path = require("path");

  module.exports = function(samjs) {
    var AuthMongo, debug, parsePermission, usersModel;
    debug = samjs.debug("auth-mongo");
    if (!samjs.mongo) {
      throw new Error("samjs-mongo not found - must be loaded before samjs-auth-mongo");
    }
    if (!samjs.auth) {
      throw new Error("samjs-auth not found - must be loaded before samjs-auth-mongo");
    }
    if (!samjs.mongoAuth) {
      throw new Error("samjs-mongo-auth not found - must be loaded before samjs-auth-mongo");
    }
    usersModel = null;
    samjs.auth.replaceUserHandler((function(userName) {
      var find, populate, query;
      if (usersModel == null) {
        usersModel = samjs.models.users;
      }
      if (usersModel.authFind != null) {
        find = usersModel.authFind(userName);
      } else {
        find = {};
        find[samjs.options.username] = userName;
      }
      query = usersModel.dbModel.findOne(find);
      populate = usersModel.populate;
      if (populate) {
        query.populate(populate);
      }
      return query;
    }), (function(user) {
      if (user.toObject != null) {
        return user.toObject({
          getters: true
        });
      } else {
        return samjs.helper.clone(user);
      }
    }));
    samjs.auth.addHook("afterLogin", function(obj) {
      obj.socket.join(obj.user._id);
      return obj;
    });
    samjs.auth.addHook("afterLogout", function(obj) {
      obj.socket.leave(obj.user._id);
      return obj;
    });
    parsePermission = function(permission) {
      var i;
      if (!samjs.util.isArray(permission)) {
        if (samjs.util.isString(permission)) {
          if (samjs.options.hierarchical) {
            i = samjs.options.groups.indexOf(permission);
            return samjs.options.groups.slice(i);
          }
        }
        return [permission];
      }
      return permission;
    };
    samjs.on("beforeConfigs", function() {
      return samjs.configs.addHook("afterProcess", function(config) {
        var j, len, mode, ref;
        if ((samjs.options.permissionChecker === "inGroup" && (config.permissionChecker == null)) || ((config.permissionChecker != null) && config.permissionChecker === "inGroup")) {
          ref = ["read", "write"];
          for (j = 0, len = ref.length; j < len; j++) {
            mode = ref[j];
            if (config[mode] != null) {
              config[mode] = parsePermission(config[mode]);
            }
          }
        }
        return config;
      });
    });
    samjs.mongo.addHook("afterProcess", function(model) {
      var j, key, len, mode, ref, ref1, val;
      if ((samjs.options.permissionChecker === "inGroup" && (model.permissionChecker == null)) || ((model.permissionChecker != null) && model.permissionChecker === "inGroup")) {
        ref = model.schema.paths;
        for (key in ref) {
          val = ref[key];
          ref1 = ["read", "write"];
          for (j = 0, len = ref1.length; j < len; j++) {
            mode = ref1[j];
            if (val.options[mode] != null) {
              val.options[mode] = parsePermission(val.options[mode]);
            }
          }
        }
      }
      return model;
    });
    samjs.auth.permissionCheckers.inGroup = function(permission, user, getIdentifier) {
      var group, groups, j, len;
      if (getIdentifier) {
        if (user != null) {
          return user[samjs.options.group];
        } else {
          return "__public";
        }
      }
      if (permission === true) {
        return true;
      } else {
        if (samjs.util.isString(permission)) {
          permission = parsePermission(permission);
        }
        if (samjs.util.isArray(permission)) {
          group = user[samjs.options.group];
          if (samjs.util.isString(group)) {
            groups = [group];
          } else if (samjs.util.isArray(group)) {
            groups = group;
          } else {
            groups = [];
          }
          for (j = 0, len = groups.length; j < len; j++) {
            group = groups[j];
            if (permission.indexOf(group) > -1) {
              return true;
            }
          }
        }
      }
      return false;
    };
    samjs.mongo.plugins({
      users: function(options) {
        var base, base1;
        if (options == null) {
          options = {};
        }
        if ((base = this.access).read == null) {
          base.read = [samjs.options.groupRoot];
        }
        if ((base1 = this.access).write == null) {
          base1.write = [samjs.options.groupRoot];
        }
        if (this.installComp == null) {
          this.installComp = {
            paths: [path.resolve(__dirname, "./createUser")],
            icons: ["material-person", "material-vpn_key"]
          };
        }
        if (this.isRequired == null) {
          this.isRequired = true;
        }
        this.test = function(value) {
          var query;
          query = {};
          query[samjs.options.group] = samjs.options.groupRoot;
          return this.dbModel.count(query).then(function(data) {
            if (data === 0) {
              throw new Error("no " + samjs.options.groupRoot + " found");
            }
          });
        };
        this.installInterface = function(socket) {
          socket.on("authMongo.getInstallationInfo", function(request) {
            var obj;
            if (request.token != null) {
              obj = {
                success: true,
                content: {
                  groupRoot: samjs.options.groupRoot,
                  group: samjs.options.group
                }
              };
              return socket.emit("authMongo.getInstallationInfo." + request.token, obj);
            }
          });
          socket.on("authMongo.createRoot", (function(_this) {
            return function(request) {
              var id;
              if (request.token != null) {
                if (((request != null ? request.content : void 0) != null) && (request.content[samjs.options.username] != null) && (request.content[samjs.options.password] != null)) {
                  if (_this.plugins.isOwner != null) {
                    id = samjs.mongo.mongoose.Types.ObjectId();
                    request.content.owner = id;
                    request.content._id = id;
                  }
                  return _this.dbModel.create(request.content).then(function(result) {
                    return {
                      success: true,
                      content: result
                    };
                  })["catch"](function(e) {
                    return {
                      success: false,
                      content: e != null ? e.message : void 0
                    };
                  }).then(function(response) {
                    if (response.success) {
                      debug("user installed completely");
                      samjs.state.checkInstalled();
                    }
                    return socket.emit("authMongo.createRoot." + request.token, response);
                  });
                } else {
                  return socket.emit("authMongo.createRoot." + request.token, {
                    success: false,
                    content: "Username and password required"
                  });
                }
              }
            };
          })(this));
          return function() {
            if (socket != null) {
              socket.removeAllListeners("authMongo.createRoot");
              return socket.removeAllListeners("authMongo.getInstallationInfo");
            }
          };
        };
        this.addHook("beforeUpdate", function(obj) {
          var ref, ref1;
          if (((obj != null ? (ref = obj.socket) != null ? ref.client : void 0 : void 0) != null) && ((obj != null ? (ref1 = obj.query) != null ? ref1.doc : void 0 : void 0) != null) && (obj.query.cond != null)) {
            if (obj.query.doc[samjs.options.password] && samjs.options.oldPassword) {
              return samjs.models.users.dbModel.findOne(obj.query.cond).then(function(user) {
                if (user.equals(obj.socket.client.auth.user)) {
                  if (!obj.query.doc[samjs.options.oldPassword]) {
                    throw new Error("no old password provided");
                  }
                  return samjs.auth.comparePassword(user, obj.query.doc[samjs.options.oldPassword]);
                }
              });
            }
          }
          return obj;
        });
        return this.addHook("afterCreate", function(obj) {
          var name, name1, name2, properties;
          properties = {};
          if (properties[name = samjs.options.username] == null) {
            properties[name] = {
              type: String,
              required: true,
              index: {
                unique: true
              },
              read: options.read,
              write: options.write
            };
          }
          if (properties[name1 = samjs.options.password] == null) {
            properties[name1] = {
              type: String,
              required: true,
              read: false,
              write: options.write
            };
          }
          if (properties[name2 = samjs.options.group] == null) {
            properties[name2] = {
              type: String,
              required: true,
              read: options.read,
              write: options.write
            };
          }
          this.schema.add(properties);
          this.schema.pre("save", function(next) {
            return samjs.auth.crypto.generateHashedPassword(this, next);
          });
          return obj;
        });
      }
    });
    return new (AuthMongo = (function() {
      function AuthMongo() {}

      AuthMongo.prototype.name = "authMongo";

      AuthMongo.prototype.options = {
        hierarchical: true,
        groupRoot: "root",
        group: "group",
        groups: ["root"],
        permissionChecker: "inGroup",
        oldPassword: "oldPwd"
      };

      AuthMongo.prototype.models = [
        {
          name: "users",
          schema: {},
          db: "mongo",
          plugins: {
            "users": null
          }
        }
      ];

      return AuthMongo;

    })());
  };

}).call(this);
