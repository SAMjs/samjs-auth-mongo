(function() {
  var path;

  path = require("path");

  module.exports = function(samjs) {
    var AuthMongo, debug, parsePermission;
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
    parsePermission = function(permission) {
      var i;
      if (!samjs.util.isArray(permission)) {
        if (samjs.util.isString(permission)) {
          if (samjs.options.hierarchical) {
            if (samjs.configs.groups.value != null) {
              i = samjs.configs.groups.value.indexOf(permission);
              return samjs.configs.groups.value.slice(i);
            }
          }
        }
        return [permission];
      }
      return permission;
    };
    samjs.auth.permissionCheckers.inGroup = function(permission, user) {
      var group, groups, j, len;
      if (permission === true) {
        return true;
      } else {
        if (samjs.util.isString(permission)) {
          permission = parsePermission(permission);
        }
        if (samjs.util.isArray(permission)) {
          group = user.group;
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
        var pc;
        samjs.helper.initiateHooks(this, [], ["afterLogin", "afterLogout"]);
        this.addHook("afterLogin", function(obj) {
          console.log("joining " + obj.user._id);
          obj.socket.join(obj.user._id);
          return obj;
        });
        this.addHook("afterLogout", function(obj) {
          obj.socket.leave(obj.user._id);
          return obj;
        });
        if (options == null) {
          options = {};
        }
        if (this.installComp == null) {
          this.installComp = {
            paths: [path.resolve(__dirname, "./createUser")],
            icons: ["material-person", "material-vpn_key"]
          };
        }
        this.populate = options.populate;
        pc = this.permissionChecker;
        if (pc == null) {
          pc = samjs.options.permissionChecker;
        }
        if (options.read == null) {
          options.read = this.read;
        }
        if (options.write == null) {
          options.write = this.write;
        }
        if (pc === "inGroup") {
          if (options.read == null) {
            options.read = samjs.options.groupRoot;
          }
          if (options.write == null) {
            options.write = samjs.options.groupRoot;
          }
          options._read = parsePermission(options.read);
          options._write = parsePermission(options.write);
        } else {
          if (options.read == null) {
            options.read = [samjs.options.rootUser];
          }
          if (options.write == null) {
            options.write = [samjs.options.rootUser];
          }
        }
        if (this.isRequired == null) {
          this.isRequired = true;
        }
        this.test = function(value) {
          return this.dbModel.count({
            group: samjs.options.groupRoot
          }).then(function(data) {
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
        return this.addHook("afterCreate", function() {
          var name1, name2, name3, properties;
          properties = {};
          if (properties[name1 = samjs.options.username] == null) {
            properties[name1] = {
              type: String,
              required: true,
              index: {
                unique: true
              },
              read: options.read,
              write: options.write
            };
          }
          if (properties[name2 = samjs.options.password] == null) {
            properties[name2] = {
              type: String,
              required: true,
              read: false,
              write: options.write
            };
          }
          if (properties[name3 = samjs.options.group] == null) {
            properties[name3] = {
              type: String,
              required: true,
              read: options.read,
              write: options.write
            };
          }
          this.schema.add(properties);
          return this.schema.pre("save", function(next) {
            return samjs.auth.crypto.generateHashedPassword(this, next);
          });
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
        permissionChecker: "inGroup",
        oldPassword: "oldPwd"
      };

      AuthMongo.prototype.configs = [
        {
          name: "groups",
          value: ["root"],
          test: function(value) {
            return new samjs.Promise(function(resolve, reject) {
              if (samjs.util.isArray(value)) {
                return resolve(data);
              } else {
                return reject(data);
              }
            });
          },
          hooks: {
            afterCreate: function(config) {
              if (config.read == null) {
                config.read = samjs.options.groupRoot;
              }
              return config.write != null ? config.write : config.write = samjs.options.groupRoot;
            },
            after_Set: function(obj) {
              var config, d, i, j, len, model, name, ref, ref1, ref2;
              ref = obj.data;
              for (i = j = 0, len = ref.length; j < len; i = ++j) {
                d = ref[i];
                if (obj.oldData[i] !== d) {
                  ref1 = samjs.configs;
                  for (name in ref1) {
                    config = ref1[name];
                    config._read = null;
                    config._write = null;
                  }
                  ref2 = samjs.models;
                  for (name in ref2) {
                    model = ref2[name];
                    model._read = null;
                    model._write = null;
                  }
                  break;
                }
              }
              return obj;
            }
          }
        }
      ];

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

      AuthMongo.prototype.parsePermission = parsePermission;

      AuthMongo.prototype.startup = function() {
        var usersModel;
        usersModel = null;
        samjs.auth.replaceUserHandler((function(userName) {
          var find, query;
          if (usersModel == null) {
            usersModel = samjs.models.users.dbModel;
          }
          find = {};
          find[samjs.options.username] = userName;
          query = usersModel.findOne(find);
          if (samjs.models.users.populate) {
            query.populate(samjs.models.users.populate);
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
        return samjs.auth.replaceHooks(samjs.models.users);
      };

      return AuthMongo;

    })());
  };

}).call(this);
