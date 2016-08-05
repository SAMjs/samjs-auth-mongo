# samjs-auth-mongo

Moves user management to mongodb. Adds groups.

Client: [samjs-auth-mongo-client](https://github.com/SAMjs/samjs-auth-mongo-client)

## Getting Started
```sh
npm install --save samjs-auth-mongo
npm install --save-dev samjs-auth-mongo-client
```

## Example
```js
samjs.plugins([
  // samjs-auth, samjs-mongo and samjs-mongo-authare needed before samjs-auth-mongo
  require("samjs-auth"),
  require("samjs-mongo"),
  require("samjs-mongo-auth"),
  require("samjs-auth-mongo")
])
.options()
.configs()
.models({
  name: "someModel",
  db: "mongo",
  plugins: {
    auth: null, // (optional) auth plugin will be enabled for all monog models by default
    // to disable auth
    noAuth: null
  },
  schema: {
    someProp: {
      type: String,
      read: true, // all can read
      write: ["root"] // only users in root group can write
    }
  },
  // add permissionChecker inGroup to samjs.auth as a new default
  // this is not required:
  permissionChecker: "inGroup"
}).startup(server)
```
## Options

name | value | description
---: | --- | ---
hierarchical | true | are groups hierarchical? when groups is: `["user","root"]`, `root` will be allowed everything what `user` can.
groupRoot | "root" | name of the root group
group | "group" | name of the group property in the mongodb
permissionChecker | "inGroup" | default permissionChecker, will overwrite permissionChecker set by `samjs-auth`

## Configs

This is the default config for user groups:
```js
{
  name: "groups",
  data: ["root"],
  read: "root",
  write: "root"
}
```
access like a normal config object:
```js
// server-side
samjs.configs.groups._get()
// client-side
samjs.config.set("groups",["user","root"]).then(function(){
  // successfully set
  })
```
## Users model

This is the default model for users:
```js
{
  name: "users",
  schema: {},
  db: "mongo",
  plugins:{
    "users": {
      read: "root", // (optional) root default
      write: "root" // (optional) root default
    }
  },
  isRequired: true
}
```
The `users` plugin adds the props `samjs.options.username` (default: "name"), `samjs.options.password` (default: "pwd") and `samjs.options.group` (default: "group") and a test / installInterface.

## startup
`samjs-mongo` needs you to set `mongoURI` in configuration.
`samjs-auth-mongo` needs you to set a user in `root` group in installation.
```js
samjs = require("samjs-client")()
samjs.plugins([
  require("samjs-auth-client"),
  require("samjs-mongo-client"),
  require("samjs-auth-mongoclient")
])
samjs.install.onceConfigure
.then(function(){
  client.install.set("mongoURI", "yourmongoURI")
}).then(function(){
  client.install.onceInstall
}).then(function(){
  client.auth.createRoot({name:"root",pwd:"rootroot"})
})

// server-side
samjs.state.onceStarted.then(function(){
  // startup finished
})
```
