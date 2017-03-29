ceri = require "ce/wrapper"
module.exports = ceri
  mixins: [
    require "ce/structure"
    require "ce/class"
    require "ce/#model"
    require "ce/computed"
  ]
  structure: template 1, """
    <span class="card-title black-text">Create root user</span>
    <div class=row>
      <div class="input-field col s12">
        <ceri-icon class=prefix name="ma-person"></ceri-icon>
        <input
          #ref=nameInput 
          #model=name
          @keyup=onKeyupName
          @focus=onActiveName
          @blur=onActiveName
          />
        <label #ref=nameLabel style="pointer-events: none;">Username</label>
      </div>

      <div class="input-field col s12">
        <ceri-icon class=prefix name="ma-vpn_key"></ceri-icon>
        <input 
          #ref=pwInput 
          #model=pw
          @keyup=onKeyupPW
          type="password"
          @focus=onActivePW
          @blur=onActivePW
          />
        <label style="pointer-events: none;" #ref=pwLabel>Password</label>
      </div>
    </div>
  """

  data: ->
    name: ""
    pw: ""
  computed:
    isValid: -> @name && @pw.length >=8
    
  methods:
    next: -> @samjs.auth.createRoot {name:@name,pwd:@pw}
    onActiveName: ->
      if @nameInput != document.activeElement and @nameInput.value == ""
        @$class.setStr @nameLabel, ""
      else
        @$class.setStr @nameLabel, "active"
    onActivePW: ->
      if @pwInput != document.activeElement and @pwInput.value == ""
        @$class.setStr @pwLabel, ""
      else
        @$class.setStr @pwLabel, "active"
    onKeyupPW: (e) ->
      return if e.keyCode != 13
      @finished()
    onKeyupName: (e) ->
      return if e.keyCode != 13
      @pwInput.focus()
    
  connectedCallback: ->
    @samjs.plugins require "samjs-auth-client"
    @samjs.plugins require "samjs-auth-mongo-client"
