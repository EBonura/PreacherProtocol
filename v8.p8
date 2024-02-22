pico-8 cartridge // http://www.pico-8.com
version 41
__lua__


-- Should be possible to activate towers
-- Exploding barrels
-- Poison tiles

-- HELPER
------------------
function dist_trig(dx, dy)
  local ang = atan2(dx, dy)
  return dx * cos(ang) + dy * sin(ang)
end


function stringToTable(str)
  local tbl = {}
  for pair in all(split(str, "|", false)) do
    add(tbl, split(pair, ",", true))
  end
  return tbl
end


function smallcaps(s)
  local t=""
  for i=1,#s do
    local c=ord(s,i)
    t..=chr(c>96 and c<123 and c-32 or c)
  end
  return t
end


function reset_palette_and_transparency(_cls)
  if _cls then cls() end
  pal()
  palt(0, false)
  palt(14, true)
end


function draw_shadow(circle_x, circle_y, radius, swap_palette)
  -- calculate the top and bottom y of the circle
  local top_y = mid(0, flr(circle_y - radius), 127)
  local bottom_y = mid(0, flr(circle_y + radius), 127)

  for y = 0, top_y do
    local line_start_addr = 0x6000 + y * 64
    for i = 0, 63 do
      local current_byte = @(line_start_addr + i)
      poke(line_start_addr + i, (swap_palette[((current_byte & 0xf0) >> 4)+1] << 4) | swap_palette[(current_byte & 0x0f) + 1])
    end
  end

  for y = bottom_y, 127 do
    local line_start_addr = 0x6000 + y * 64
    for i = 0, 63 do
      local current_byte = @(line_start_addr + i)
      poke(line_start_addr + i, (swap_palette[((current_byte & 0xf0) >> 4)+1] << 4) | swap_palette[(current_byte & 0x0f) + 1])
    end
  end

  for y = top_y + 1, bottom_y - 1 do
    line_start_addr = 0x6000 + y * 64
    -- compute the intersection of the line with the circle
    local dy = y - circle_y
    local dx = sqrt(radius * radius - dy * dy)

    local start_x, end_x = mid(0, circle_x - dx, 127), mid(0, circle_x + dx, 127)
    local start_x_half, end_x_half = start_x >> 1, end_x >> 1

    -- modify the pixels before the circle
    for i = 0, start_x_half -1 do
      local current_byte = @(line_start_addr + i)
      poke(line_start_addr + i, (swap_palette[((current_byte & 0xf0) >> 4)+1] << 4) | swap_palette[(current_byte & 0x0f)+1])
    end

    -- modify the pixels after the circle
    for i = end_x_half + 1, 64 do
      local current_byte = @(line_start_addr + i)
      poke(line_start_addr + i, (swap_palette[((current_byte & 0xf0) >> 4)+1] << 4) | swap_palette[(current_byte & 0x0f)+1])
    end
  end
end


function copy_map_into_memory()
  local map_string = ""
  local start_address = 0x1000
  local data = unhex(map_string)
  
  for i, byte in ipairs(data) do
    poke(start_address + i - 1, byte)
  end
end


function unhex(s, n)
  local t = {}
  for i = 1, #s, 2 do
    add(t, '0x'..sub(s, i, i + 1))
  end
  return t
end


-- GAME
---------
function _init()
  -- Game State
  game_state = {
    intro = 1,
    mission_select = 2,
    loadout_select = 3,
    gameplay = 4,
    debrief = 5
  }

  state_actions = {
    [game_state.intro] = {update = update_intro, draw = draw_intro},
    [game_state.mission_select] = {update = update_mission_select, draw = draw_mission_select},
    [game_state.loadout_select] = {update = update_loadout_select, draw = draw_loadout_select},
    [game_state.gameplay] = {update = update_gameplay, draw = draw_gameplay},
    [game_state.debrief] = {update = update_debrief, draw = draw_debrief}
  }

  current_game_state = game_state.intro
  intro_counter, intro_blink = 0, 0

  -- Mission Select
  selected_mission = 1
  level_select_args = stringToTable("6,40,9,38,mission 1|6,55,9,38,mission 2|6,70,9,38,mission 3|6,85,9,38,mission 4")
  level_select_text_panels = {}
  for level_select_arg in all(level_select_args) do
    add(level_select_text_panels, textpanel:new(unpack(level_select_arg)))
  end

  entity_stats_list = {}
  for t in all(stringToTable([[Player,bot,8,8,100,100,false,1,2|Dervish,bot,7,7,80,40,false,1,5|Vanguard,bot,9,9,120,60,false,2,4|Warden,bot,9,9,120,60,false,3,3|CyberSeer,preacher,14,14,100,60,true,1,2|QuantumCleric,preacher,16,16,120,80,true,1,1]])) do
    local entity_name = t[1]
    local base_class = t[2]
    entity_stats_list[entity_name] = {
      base_class = base_class,
      width = t[3],
      height = t[4],
      max_health = t[5],
      max_energy = t[6],
      flying = t[7],
      attack_power = t[8],
      attack_cooldown = t[9]
    }
  end

  missions_entities_params = {
    { -- Mission 1
    {7*8, 36*8, true, "Player"},
    {4*8, 25*8, false, "Dervish"},
    {15*8, 26*8, false, "Dervish"},
    {17*8, 43*8, false, "Vanguard"},
    {50, 155, false, "QuantumCleric"},
    },
    { -- Mission 2
      {70, 80, true, "bot"},
      {85, 120, false, "bot"},
    },
    { -- Mission 3
      {90, 100, true, "bot"},
      {105, 140, false, "bot"},
    },
    { -- Mission 4
      {110, 160, true, "bot"},
      {125, 180, false, "bot"},
    },
  }

  mission_briefings_params = {
    "Infiltrate the \nNeo-Tokara Complex\n\nevade or \nneutralize guards; \nactivate the 3 \ndata transmission \ntowers",
    "Destroy the \nCore Facility\n\nevade or \nneutralize guards; \ndestroy the energy \ncore",
    "Briefing3",
    "Briefing4"
  }

  -- Mission Brief
  briefing_panel = textpanel:new(52, 40, 60, 74, "")
  -- 6614
  local stats = stringToTable([[50, 55, 60, 65, 70, 75, 80, 85, 90, 95, 100| 
                                50, 55, 60, 65, 70, 75, 80, 85, 90, 95, 100|
                                50, 55, 60, 65, 70, 75, 80, 85, 90, 95, 100|
                                50, 55, 60, 65, 70, 75, 80, 85, 90, 95, 100|
                                25, 30, 35, 40, 45, 50, 55, 60, 65, 70, 55 |
                                100, 131, 164, 200, 240, 285, 336, 394, 460, 535 |
                                0,0,0,0,0,0,5,6,2,5,9,3,1,2,2,4 |
                                0,1,0,0,0,0,0,2,0,0,0,0,0,0,0,0 |
                                4, 20, 9, 26,health| 
                                4, 34, 9, 26,energy|
                                4, 48, 9, 26,range|
                                4, 62, 9, 46,quick shoot|
                                4, 76, 9, 22,regen|
                                40, 96, 9, 54,begin mission|
                                38, 110, 9, 58,select mission]])

  selected_loadout = 1
  credits = 32000
  loadout_select_text_panels = {}
  for i = 9, 15 do
    add(loadout_select_text_panels, textpanel:new(unpack(stats[i])))
  end

  cost_table = stats[6]
  selected_debrief = 1
  loadout_select_sliders = {
    slider:new(72, 22, stats[1]), -- health
    slider:new(72, 36, stats[2]), -- energy
    slider:new(72, 50, stats[3]), -- range
    slider:new(72, 64, stats[4]), -- quick_shoot
    slider:new(72, 78, stats[5]), -- regen
  }

  debrief_text_panels = {
    textpanel:new(30, 90, 9, 62, 'restart mission'),
    textpanel:new(31, 105, 9, 60, 'mission select')
  }

  cam = cam:new()
  door_effect = door_effect:new()
  player_hud = player_hud:new()
  view_radius = 50
  player_position = {x = 0, y = 0}
  swap_palette = stats[7]
  swap_palette_dark = stats[8]
  load_entities()
end


function _update()
  state_actions[current_game_state].update()
  door_effect:update()
end


function _draw()
  state_actions[current_game_state].draw()
  door_effect:draw()
  printh("mem: "..tostr(stat(0)).." | cpu: "..tostr(stat(1)).." | fps: "..tostr(stat(7)))
end


-- INTRO
---------
function draw_intro()
  reset_palette_and_transparency(true)
  map(28, 18, 0, 0, 128, 48)
  draw_shadow(128,128,0, swap_palette_dark)

  if sin(intro_blink)<.9 then
    circfill(63,64, 3, 2)
  end

  local x_preacher = min(15, -50 + intro_counter * 3)
  local x_protocol = max(45, 128 - intro_counter * 3)

  spr(192, x_preacher, 0, 9, 2)
  spr(224, x_protocol, 11, 9, 2)

  if x_preacher == 10 and not sfx_played_preacher then
    sfx(20)
    sfx_played_preacher = true
  end
  if x_protocol == 40 and not sfx_played_protocol then
    sfx(20)
    sfx_played_protocol = true
  end

  if x_protocol == 45 then
    print(smallcaps("press ❎ to initiate"), 24, 110, 11)
  end
end


function update_intro()
  if intro_counter == 0 then
    music(05)
  end
  
  intro_counter += 1
  intro_blink += .02
  if btnp(❎) and intro_counter > 30 then
    sfx(19)
    intro_counter = 0
    current_game_state = game_state.mission_select
  end
end


-- MISSION SELECT
------------------
function draw_mission_select()
  reset_palette_and_transparency(true)
  map(0, 0, 0, 0, 128, 48)
  draw_shadow(-20,-20, 10, swap_palette_dark)

  spr(192, cam.x + 15, cam.y + 0, 9, 2)
  spr(224, cam.x + 45, cam.y + 11, 9, 2)

  for i, panel in ipairs(level_select_text_panels) do
    panel.selected = (i == selected_mission)
    panel:draw()
  end

  briefing_panel.textline = mission_briefings_params[selected_mission]
  briefing_panel:draw()
  print(smallcaps("⬆️ ⬇️ Select mission"), cam.x + 18, cam.y + 110, 11)
end


function update_mission_select()
  local num_panels = #level_select_text_panels

  if btnp(⬆️) then
    sfx(19)
    selected_mission = ((selected_mission - 2) % num_panels) + 1
  elseif btnp(⬇️)  then
    sfx(19)
    selected_mission = (selected_mission % num_panels) + 1
  elseif btnp(❎) then
    sfx(20)
    selected_loadout = 1
    current_game_state = game_state.loadout_select
  end
  foreach(level_select_text_panels, function(t) t:update() end)
end


-- LOADOUT SELECT
------------------
function draw_loadout_select()
  reset_palette_and_transparency(true)
  map(0, 0, 0, 0, 128, 48)
  draw_shadow(-20,-20, 10, swap_palette_dark)

  print(smallcaps("credits: "..tostr(credits)), cam.x + 70, cam.y + 4, 11)

  for i, panel in ipairs(loadout_select_text_panels) do
    panel.selected = (i == selected_loadout)
    panel:draw()
  end

  for panel in all(loadout_show_text_panels) do
    panel:draw()
  end
  
  for i, slider in ipairs(loadout_select_sliders) do
    slider.selected = (i == selected_loadout)
    slider:draw()
  end
end


function update_loadout_select()
  local num_panels = #loadout_select_text_panels
  local current_loadout = loadout_select_sliders[selected_loadout]

  if btnp(⬆️) then
    sfx(19)
    selected_loadout = ((selected_loadout - 2) % num_panels) + 1
  elseif btnp(⬇️) then
    sfx(19)
    selected_loadout = (selected_loadout % num_panels) + 1
  end


  if selected_loadout == 6 then
    if btnp(❎) then
      sfx(20)
      door_effect.closing = true
    end
  elseif selected_loadout == 7 then
    if btnp(❎) then
      sfx(19)
      current_game_state = game_state.mission_select
    end
  else
    if btnp(⬅️) then
      if current_loadout.value > 1 then
        credits += cost_table[current_loadout.value - 1]
        current_loadout.value -= 1
        sfx(09)
      else
        sfx(14)
      end
    elseif btnp(➡️) then
      if credits >= cost_table[current_loadout.value] and current_loadout.value < 10 then
        credits -= cost_table[current_loadout.value]
        current_loadout.value += 1
        sfx(09)
      else
        sfx(14)
      end
    end
  end

  foreach(loadout_select_text_panels, function(t) t:update() end)
  foreach(loadout_select_sliders, function(t) t:update() end)
end


-- DEBRIEF
-----------
function draw_debrief()
  reset_palette_and_transparency(true)
  player = get_controlled_entity()

  if player then
    print("mission complete", cam.x + 34, cam.y + 10, 11)
  else
    print("mission failed", cam.x + 34, cam.y + 10, 8)
  end

  for i, panel in ipairs(debrief_text_panels) do
    panel.selected = (i == selected_debrief)
    panel:draw()
  end
end


function update_debrief()
  local num_panels = #debrief_text_panels
  if btnp(⬆️) then
    sfx(19)
    selected_debrief = ((selected_debrief - 2) % num_panels) + 1
  elseif btnp(⬇️) then
    sfx(19)
    selected_debrief = (selected_debrief % num_panels) + 1
  end


  if btnp(❎) then
    if selected_debrief == 2 then
      current_game_state = game_state.mission_select
    elseif selected_debrief == 1 then
      door_effect.closing = true
    end
  end

  foreach(debrief_text_panels, function(t) t:update() end)
end



-- SLIDER
-------------
slider = {}
slider.__index = slider
function slider:new(x, y, values)
  local self = setmetatable({}, slider)
  self.x, self.y = x, y
  self.values = values
  self.value = 1
  self.total_values = 10
  self.selected = false
  return self
end


function slider:draw()
  local total_width = 3 * self.value - 1
  local start_x, start_y = self.x + cam.x, self.y + cam.y

  -- Draw each rectangle
  for i = 1, self.total_values do
    local color = self.selected and 6 or 5
    if i <= self.value then
      color = 11
    end
    local rect_x = start_x + (i - 1) * 3
    rectfill(rect_x, start_y, rect_x + 1, start_y + 4, color)
  end
  if self.selected then
    print("⬅️        ➡️", start_x - 9, start_y, 5)
  end
  local color = self.selected and 6 or 5
  print("             "..tostr(self.values[self.value]), start_x - 9, start_y, color)
end


function slider:update()
end


-- TEXT PANEL
-------------
textpanel = {}
textpanel.__index = textpanel
function textpanel:new(x, y, height, width, textline)
  local self = setmetatable({}, textpanel)
  self.x = x
  self.y = y
  self.height = height
  self.original_width = width
  self.width = width
  self.textline = textline
  self.selected = false
  self.expand_counter = 0
  return self
end


function textpanel:draw()
  local drawx = cam.x + self.x - self.expand_counter
  local drawy = cam.y + self.y
  local adjusted_width = self.width + self.expand_counter * 2
  local drawx2 = drawx + adjusted_width - 2

  rectfill(drawx - 1, drawy - 1, drawx + 2, drawy + self.height + 1, 3)
  rectfill(drawx2, drawy - 1, drawx2 + 3, drawy + self.height + 1, 3)
  rectfill(drawx, drawy, drawx + adjusted_width, drawy + self.height, 0)

  local text_color = self.selected and 11 or 5
  print(smallcaps(self.textline), cam.x + self.x + 2, drawy + 2, text_color)
end


function textpanel:update()
  if self.selected then
    self.expand_counter = min(3, self.expand_counter + 1)
  else
    self.expand_counter = max(0, self.expand_counter - 1)
  end
end


-- DOOR EFFECT
---------------
door_effect = {}
door_effect.__index = door_effect
function door_effect:new()
  self.opening = false
  self.closing = false
  self.close_wait = 5
  self.close_wait_timer = self.close_wait
  self.intro_counter = 0
  return self
end


function door_effect:draw()
  rect_x1 = cam.x - 1
  rect_x2 = self.intro_counter + cam.x - 1
  rect_x3 = 128 - self.intro_counter + cam.x
  rect_x4 = 128 + cam.x 

  rect_y1 = cam.y
  rect_y2 = 128 + cam.y

  rectfill(rect_x1, rect_y1, rect_x2, rect_y2, 0)
  rectfill(rect_x3, rect_y1, rect_x4, rect_y2, 0)
end


function door_effect:update()
  if self.closing then
    self.intro_counter = min(64, self.intro_counter + 2)
  elseif self.opening then
    self.intro_counter = max(0, self.intro_counter - 2)
  end

  if self.intro_counter == 64 then
    if current_game_state ~= game_state.gameplay then
      if self.close_wait_timer == 0 then
        self.closing = false
        self.opening = true
        self.close_wait_timer = self.close_wait
        current_game_state = game_state.gameplay
      elseif self.close_wait_timer == self.close_wait - 1 then
        load_entities()
        self.close_wait_timer = max(0, self.close_wait_timer - 1)
      else 
        self.close_wait_timer = max(0, self.close_wait_timer - 1)
      end
    else
      self.closing = false
      self.opening = true
      current_game_state = game_state.debrief
    end
  end
end


function load_entities()
  entities = {}
  for params in all(missions_entities_params[selected_mission]) do
    add(entities, entity:new(unpack(params)))
  end

  player = get_controlled_entity()
  local health = loadout_select_sliders[1].values[loadout_select_sliders[1].value]
  player.max_health, player.health = health, health
  local energy = loadout_select_sliders[2].values[loadout_select_sliders[2].value]
  player.max_energy, player.energy = energy, energy

  emitters = {}
  for map_y = 0, 127 do 
    for map_x = 0, 127 do
      local tile = mget(map_x, map_y)
      if fget(tile, 7) then
        add(emitters, emitter:new(map_x * 8 - 4, map_y * 8 + 2))
      end
    end
  end
  
  projectiles = {}
  particles = {}
  view_radius = 50
end


-- GAMEPLAY
------------------
function update_gameplay()
  foreach(entities, function(e) e:update() end)
  foreach(projectiles, function(e) e:update() end)
  foreach(particles, function(e) e:update() end)
  foreach(emitters, function(e) e:update() end)
  check_losing_condition()
  check_winning_condition()
  cam:update()
end


function draw_gameplay()
  reset_palette_and_transparency(true)
  map(0, 0, 0, 0, 128, 48)

  foreach(entities, function(e) e:draw_underlay() end)
  foreach(entities, function(e) e:draw() end)
  foreach(projectiles, function(p) p:draw() end)
  foreach(particles, function(p) p:draw() end)
  foreach(emitters, function(e) e:draw() end)
  foreach(entities, function(e) e:draw_overlay() end)

  player = get_controlled_entity()
  if player then
    player_position.x, player_position.y = player.x, player.y
  end
  draw_shadow(player_position.x - cam.x + 5, player_position.y - cam.y + 5, view_radius, swap_palette)
  
  map(0, 0, 0, 0, 128, 128, 2)
  player_hud:draw()
end


function check_winning_condition()
  for e in all(entities) do
    if not e.controlled then
      return
    end
  end
  if view_radius > 1 then
    view_radius -= .5
  else
    door_effect.closing = true
  end
end


function check_losing_condition()
  local player = get_controlled_entity()
  if not player then
    if view_radius > 1 then
      view_radius -= .5
    else
      door_effect.closing = true
    end
  end
end



-- PROJECTILE
--------------
projectile = {}
projectile.__index = projectile
function projectile:new(x, y, vx, vy, color, damage, radius, creator)
  local self = setmetatable({}, projectile)
  self.x, self.y = x, y
  self.vx, self.vy = vx, vy
  self.ax, self.ay = 0, 0
  self.color = color
  self.damage = damage
  self.radius = radius
  self.creator = creator
  return self
end


function projectile:update()
  local hit, entity = self:check_entity_collision()
  if hit then
    self:spawn_particles(3, false)
    entity:inflict_damage(self.damage)
    del(projectiles, self)
    return 
  end
  
  if self:check_wall_collision() then
    del(projectiles, self)
    self:spawn_particles(1, true)
    return
  end

  self.x += self.vx
  self.y += self.vy
end


function projectile:spawn_particles(count, bounce)
  for i=1, count do
    local variation = 0.5 
    local p_vx = self.vx * (0.5 + rnd(variation) - variation / 2)
    local p_vy = self.vy * (0.5 + rnd(variation) - variation / 2)

    if bounce then
      p_vx, p_vy = -p_vx, -p_vy
    end
    
    local p = particle:new(self.x, self.y, p_vx, p_vy, 15 + rnd(10), 0)
    add(particles, p)
  end
end


function projectile:check_entity_collision()
  local steps = max(abs(self.vx), abs(self.vy))
  local step_x, step_y = sgn(self.vx), sgn(self.vy)  
  for i = 1, steps do
    local check_x = self.x + (i * step_x)
    local check_y = self.y + (i * step_y)

    for e in all(entities) do
      if e != self.creator then
        if check_x < e.x + e.width and e.x < check_x + 1 and 
            check_y < e.y + e.height and e.y < check_y + 1 then
          return true, e
        end
      end
    end
  end

  return false, nil
end


function projectile:check_wall_collision()
  local steps = max(abs(self.vx), abs(self.vy))
  local step_x, step_y = sgn(self.vx), sgn(self.vy)

  for i = 1, steps do
    if wall_collide(self.x + (i * step_x), self.y + (i * step_y)) then
      return true
    end
  end

  return false
end


function projectile:draw()
  if self.radius == 1 then
    rectfill(self.x, self.y, self.x + self.radius, self.y + self.radius, 8)
  else
    rectfill(self.x - 1, self.y, self.x + self.radius + 1, self.y + self.radius, self.color)
    rectfill(self.x, self.y - 1, self.x + self.radius, self.y + self.radius + 1, self.color)
    rectfill(self.x, self.y, self.x + self.radius, self.y + self.radius, 7)
  end
end


-- PARTICLE
--------------
particle = {}
particle.__index = particle
function particle:new(x, y, vx, vy, lifespan, size, color)
  local self = setmetatable({}, particle)
  self.x, self.y = x, y
  self.vx, self.vy = vx, vy
  self.ax, self.ay = 0, 0
  self.color = color
  self.max_lifespan = lifespan
  self.lifespan = lifespan
  self.size = size
  return self
end


function particle:update()
  self.x += self.vx
  self.y += self.vy
  self.lifespan -= 1
  if self.lifespan < 0 then
    del(particles, self)
  end
end


function particle:draw()
  local color = self.color
  if not color then
    local color_sequence = {7, 10, 9, 8, 2, 5}
    local lifespan_per_color = self.max_lifespan / #color_sequence
    local color_index = flr((self.max_lifespan - self.lifespan) / lifespan_per_color) + 1
    color = color_sequence[color_index]
  end

  if self.size == 0 then
    pset(self.x, self.y, color)
  else
    circfill(self.x, self.y, self.size, color)
  end
end



-- ENTITY
----------
enemy_state = {
  idle = "idle",
  alert = "alert",
  attack = "attack",
  search = "search"
}
-- # A rapid, energy-based attack that targets a single enemy.
-- # A high-energy blast with wide-area effect, dealing substantial damage.
-- # Engages cloaking technology, making the player invisible for a short duration.
-- # Initiates a regeneration field, restoring health.
-- }

entity = {}
entity.__index = entity
function entity:new(x, y, controlled, entity_name)
  local self = setmetatable({}, entity)
  self.x, self.y = x, y
  self.original_x, self.original_y = x, y
  self.vx, self.vy = 0, 0
  self.ax, self.ay = 0, 0

  local entity_stats = entity_stats_list[entity_name]
  self.entity_name = entity_name
  self.base_class = entity_stats.base_class
  self.width = entity_stats.width
  self.height = entity_stats.height
  self.max_health = entity_stats.max_health
  self.health = entity_stats.max_health
  self.max_energy = entity_stats.max_energy
  self.energy = entity_stats.max_energy
  self.flying = entity_stats.flying
  self.attack_power = entity_stats.attack_power
  self.attack_cooldown = entity_stats.attack_cooldown
  self.acceleration = 3
  self.stopping_friction = 0.4
  self.mass = 1
  self.facing_angle = 0
  self.animation_timer = 0
  self.hoover_timer = 0
  self.hit_flash_timer = 0
  self.eye_blink_timer = 0
  self.state_icon_timer = 0
  self.chargeup_timer = 0
  self.circle_player_timer = 0
  self.damage_timer = 0
  self.heal_cooldown = 0
  self.rectangle_side = 40
  self.damage_texts = {}

  self.controlled = controlled

  self.idle_frames = {lr = {0, 1}, up = {32, 33}, down = {16, 17}, duration = .5}
  self.move_frames = {lr = {2, 3}, up = {34, 35}, down = {18, 19}, duration = .1}
  self.animation_frame = 1

  self.frame_counter = 0
  self.energy_recharge_rate = .5

  self.current_state = enemy_state.idle
  self.target = {x=self.x, y=self.y}
  self.state_actions = {
    [enemy_state.idle] = entity.idle_behavior,
    [enemy_state.alert] = entity.alert_behavior,
    [enemy_state.attack] = entity.attack_behavior,
    [enemy_state.search] = entity.search_behavior
  }

  self.current_ability_index = 1
  self.ability_actions = {
    {
      action = entity.shoot,
      description = "Pulse Strike",
      current_ammo = 1000,
      max_ammo = 1000,
      current_cooldown = 0,
      attack_cooldown = self.attack_cooldown,
      projectile_speed = 4,
      energy_cost = 2,
      radius = 1,
      damage = self.attack_power
    },
    {
      action = entity.shoot,
      description = "Impact Strike",
      current_ammo = 50,
      max_ammo = 50,
      current_cooldown = 0,
      attack_cooldown = 10,
      projectile_speed = 3,
      energy_cost = 15,
      radius = 2,
      damage = 10
    },
    -- {
    --   action = entity.invisible,
    --   description = "Stealth Mode"
    -- },
    {
      action = entity.health_recharge,
      description = "Regen Field",
      current_ammo = 3,
      max_ammo = 3,
      regen = 25
    }
  }

  return self
end


function get_controlled_entity()
  for e in all(entities) do
    if e.controlled then return e end
  end
end


function check_entity_collision(x1, y1, w1, h1, x2, y2, w2, h2)
  return x1 < x2 + w2 and x2 < x1 + w1 and y1 < y2 + h2 and y2 < y1 + h1
end


function wall_collide(x, y, flag)
  flag = flag or 0
  return fget(mget(flr(x / 8), flr(y / 8)), flag)
end


function entity:update_damage_text()
  for damage_text in all(self.damage_texts) do
    damage_text.y -= 1
    damage_text.timer -= 1
    if damage_text.timer <= 0 then
      del(self.damage_texts, damage_text)
    end
  end
end


function entity:draw_damage_text()
  for damage_text in all(self.damage_texts) do
    local damage_str = "-"..tostr(damage_text.damage)
    local rect_width = #tostr(abs(damage_text.damage)) == 1 and 7 or 12
    rectfill(damage_text.x - 1, damage_text.y - 1, damage_text.x + rect_width, damage_text.y + 5, 0)
    print(damage_str, damage_text.x, damage_text.y, 8)
  end
end


function entity:shoot()
  local current_ability = self.ability_actions[self.current_ability_index]

  local proj_vx = sin(self.facing_angle) * current_ability.projectile_speed
  local proj_vy = cos(self.facing_angle) * current_ability.projectile_speed
  
  local offset_x, offset_y = 3, 2
  if self.base_class == "preacher" then
    offset_x, offset_y = 5, - 7 + sin(self.hoover_timer) * 2 
    if self.facing_angle >= 0.5 then offset_x += 4 end
  end

  if abs(self.target.x - self.x) > 5 then
    local dx, dy = self.target.x - self.x - offset_x, self.target.y - self.y - offset_y
    local distance_to_target = dist_trig(dx, dy)

    local norm_dx, norm_dy = 0, 0
    if distance_to_target ~= 0 then
      norm_dx = dx / distance_to_target
      norm_dy = dy / distance_to_target
    end

    proj_vx, proj_vy = norm_dx * current_ability.projectile_speed, norm_dy * current_ability.projectile_speed
  end


  if self.energy > current_ability.energy_cost and current_ability.current_ammo > 0 and current_ability.current_cooldown == 0 then
    local proj = projectile:new(
      self.x + offset_x, 
      self.y + offset_y, 
      proj_vx, proj_vy, 
      8, 
      current_ability.damage, 
      current_ability.radius, 
      self
    )
    add(projectiles, proj)
    self.energy -= current_ability.energy_cost
    current_ability.current_ammo -= 1
    current_ability.current_cooldown = current_ability.attack_cooldown
  end
end


function entity:health_recharge()
  local current_ability = self.ability_actions[self.current_ability_index]

  if self.heal_cooldown == 0 and current_ability.current_ammo > 0  and self.health + current_ability.regen < self.max_health then
    self.health += current_ability.regen
    current_ability.current_ammo -= 1
    self.heal_cooldown = 40
    player_hud.shake_timer = current_ability.regen
  end
end


function entity:draw_health_recharge()
  if self.heal_cooldown > 0 then
    local radius = 40 - self.heal_cooldown
    local dx, dy = self.x + 4, self.y + 4
    local x0 = dx - radius
    local y0 = dy - (radius / 2)
    local x1 = dx + radius
    local y1 = dy + (radius / 2)
    oval(x0, y0, x1, y1, 11)
    self.heal_cooldown -= 2


    for i = 1, 10 do
      local angle = rnd(1)
      local p = particle:new(
        dx + radius * cos(angle), 
        dy - (radius / 2) * sin(angle), 
        0, -rnd(), 20, 0, 3
      )
      add(particles, p)
    end
  end
end


function entity:update()
  self:update_facing_direction()
  self:apply_physics()
  if self.controlled then
    self:handle_input()
    self:player_target_enemy()
  else
    self:ai_behavior()
  end
  self.energy = min(self.max_energy, self.energy + self.energy_recharge_rate)
  self:process_death_conditions()
  self:update_damage_text()

  local current_ability = self.ability_actions[self.current_ability_index]
  if current_ability.current_cooldown then
    current_ability.current_cooldown = max(0, current_ability.current_cooldown - 1)
  end

  self:check_poison_tile()
end


function entity:inflict_damage(damage)
  self.health = max(0, self.health - damage)
  self.hit_flash_timer = 1
  
  damage_text = {
    x = self.x + 4, 
    y = self.y - 4, 
    timer = 10, 
    damage = damage,
    color = self.eye_color
  }

  add(self.damage_texts, damage_text)
  if self.controlled then player_hud.shake_timer = damage + 1 end
end


function entity:check_poison_tile()
  self.damage_timer = max(0, self.damage_timer - 1)
  
  if self.damage_timer == 0 and wall_collide(self.x, self.y, 2) then
    sfx(14,0)
    self:inflict_damage(2)
    self.damage_timer = 5
  end
end


function entity:process_death_conditions()
  if self.health == 0 then
    local particle_count = 25
    for i=1, particle_count do
      local angle = rnd(1)
      local speed = rnd(2) 
      local p_vx = cos(angle) * speed
      local p_vy = sin(angle) * speed / 2
      local size = flr(rnd(3))
      local p = particle:new(self.x, self.y, p_vx, p_vy, 30 + rnd(15), size)
      add(particles, p)
    end
    del(entities, self)
  end
end


function entity:player_target_enemy()
  local min_distance = view_radius + 10
  local closest_enemy = nil
  
  self.target.x, self.target.y = self.x, self.y 

  for e in all(entities) do
    if not e.controlled then
      local distance = dist_trig(e.x - self.x, e.y - self.y)
      if distance < min_distance then
        if self:can_see(e) then
          min_distance = distance
          self.target.x, self.target.y = e.x + e.width / 2, e.y + e.height/2
        end
      end
    end
  end
end


function entity:update_facing_direction()
  if not self.controlled or self.x ~= self.target.x then
    self.facing_angle = atan2(self.target.y - self.y, self.target.x - self.x)
  elseif self.vx ~= 0 or self.vy ~= 0 then
    self.facing_angle = atan2(self.vy, self.vx)
  end
end


function entity:ai_behavior()
  local player = get_controlled_entity()
  local can_see_player = self:can_see(player)
  if can_see_player then self.target = {x = player.x, y = player.y} end
  self.state_actions[self.current_state](self, can_see_player)
end


function entity:idle_behavior(can_see_player)
  if can_see_player then
    self.current_state = enemy_state.alert
  end
end


function entity:search_behavior(can_see_player)
  if can_see_player then
    self.current_state = enemy_state.alert
  elseif self.frame_counter >= rnd(30)+10 then
    self:move_target_randomly()
    self.frame_counter = 0
  else
    self:move_towards_target_unless_close(1)
    self.frame_counter += 1
  end
end


function entity:move_towards_target_unless_close(distance)
  if not self:is_close_to_target(distance) then
    local angle = atan2(self.target.x - self.x, self.target.y - self.y)
    self.ax = cos(angle) * self.acceleration * 0.7
    self.ay = sin(angle) * self.acceleration * 0.7
  else
    self.ax, self.ay = 0, 0
  end

  if  self.current_state == enemy_state.alert and
      self.vx ~= 0 and self.vy ~= 0 and
      self.x == self.prev_x and self.y == self.prev_y then
      -- printh("Stuck | Pos: ("..tostr(self.x)..","..tostr(self.y)..") | Prev Pos: ("..tostr(self.prev_x)..","..tostr(self.prev_y)..") | Velocity: ("..tostr(self.vx)..","..tostr(self.vy)..") | New Accel: ("..tostr(self.ax)..","..tostr(self.ay)..")")
      local random_angle = rnd(1)
      self.ax, self.ay = cos(random_angle) * 3, sin(random_angle) * 3
  end

  self.prev_x, self.prev_y = self.x, self.y
end


function entity:alert_behavior(can_see_player)
  if can_see_player then
    if not self:is_close_to_target(50) then
      self:move_towards_target_unless_close(0)
    else
      self.current_state = enemy_state.attack
    end
  else
    if self:is_close_to_target(1) then 
      self.current_state = enemy_state.search
    end
    self:move_towards_target_unless_close(1)
  end
end


function entity:attack_behavior(can_see_player)
  if not can_see_player or not self:is_close_to_target(50) then
    self.current_state = enemy_state.alert
  else
    self.ability_actions[self.current_ability_index].action(self)
    self:circle_player()
  end
end


function entity:circle_player()
  local angle_to_target = atan2(self.target.x - self.x, self.target.y - self.y)

  -- Every 30 frames, randomly choose to add or subtract .25 to the angle
  if self.circle_player_timer % 30 == 0 then
    self.circle_direction = rnd(1) < 0.5 and -0.25 or 0.25
  end

  local circle_angle = (angle_to_target + self.circle_direction) % 1
  
  self.ax, self.ay = sin(circle_angle), cos(circle_angle)
  self.circle_player_timer += 1
end


function entity:move_target_randomly()
  local new_x, new_y = self.x + rnd(17) - 8, self.y + rnd(17) - 8
  if not wall_collide(new_x, new_y) then
    self.target.x, self.target.y = new_x, new_y
  end
end


function entity:is_close_to_target(dist)
  local distance_to_target = dist_trig(self.x - self.target.x, self.y - self.target.y)
  return distance_to_target <= dist
end


function entity:can_see(target)
  if not target then return false end

  local corners = {
    {dx = 0, dy = 0}, -- Top-left corner
    {dx = self.width-1, dy = 0}, -- Top-right corner
    {dx = 0, dy = self.height-1}, -- Bottom-left corner
    {dx = self.width-1, dy = self.height-1} -- Bottom-right corner
  }

  for corner in all(corners) do
    local start_x = self.x + corner.dx
    local start_y = self.y + corner.dy
    local end_x = target.x + corner.dx
    local end_y = target.y + corner.dy
    local dx = end_x - start_x
    local dy = end_y - start_y
    local max_steps = max(abs(dx), abs(dy))
    local step_x = dx / max_steps
    local step_y = dy / max_steps
    
    local check_x, check_y = start_x, start_y
    for i = 0, max_steps do
      if wall_collide(check_x, check_y) then
          return false
      end
      check_x += step_x
      check_y += step_y
    end
  end

  return true
end


function entity:apply_physics()
  local f = 1 - self.stopping_friction
  self.vx = (self.vx + self.ax / self.mass) * f
  self.vy = (self.vy + self.ay / self.mass) * f

  local max_velocity = 4
  local threshold = 0.1
  dist = dist_trig(self.vx, self.vy)
  if dist > max_velocity then
    local scale = max_velocity / dist
    self.vx, self.vy = self.vx * scale, self.vy * scale
  elseif abs(self.vx) < threshold and abs(self.vy) < threshold then
    self.vx, self.vy = 0, 0
  end

  local function apply_force(other)
    local force_x = self.vx / self.mass
    local force_y = self.vy / self.mass
    other.vx = other.vx + force_x * other.mass
    other.vy = other.vy + force_y * other.mass
  end

  local function check_collision(next_x, next_y)
    -- Check map collision
    if wall_collide(next_x, next_y) or
        wall_collide(next_x + self.width - 1, next_y) or
        wall_collide(next_x, next_y + self.height - 1) or
        wall_collide(next_x + self.width - 1, next_y + self.height - 1) then
      return true
    end

    -- Check collision with other entities
    if not self.flying then
      for other in all(entities) do
        if other ~= self and check_entity_collision(
            next_x, next_y, 
            self.width - 1, self.height - 1, 
            other.x, other.y, 
            other.width - 1, other.height - 1) then
            apply_force(other)
          return true
        end
      end
      return false
    end
  end

  function sign(x)
    return x < 0 and -1 or (x > 0 and 1 or 0)
  end

  local next_x = self.x
  for i = 1, abs(self.vx)  do
    local step_x = next_x + sign(self.vx)

    if check_collision(step_x, self.y) then
      break
    else
      next_x = step_x
    end
  end
  self.x = next_x

  -- For moving along the y-axis
  local next_y = self.y
  for i = 1, abs(self.vy) do
    local step_y = next_y + sign(self.vy)
    if check_collision(self.x, step_y) then
      break
    else
      next_y = step_y
    end
  end
  self.y = next_y
end


function entity:handle_input()
  local ax, ay = 0, 0
  if btn(⬅️) then ax -= self.acceleration end -- left
  if btn(➡️) then ax += self.acceleration end -- right
  if btn(⬆️) then ay -= self.acceleration end -- up
  if btn(⬇️) then ay += self.acceleration end -- down

  if btn(❎) then
    self.ability_actions[self.current_ability_index].action(self)
  elseif btnp(🅾️) then
    self:cycle_ability()
  end
  self.ax, self.ay = ax, ay
end


function entity:cycle_ability()
  self.current_ability_index += 1
  if self.current_ability_index > #self.ability_actions then
    self.current_ability_index = 1
  end
end


function entity:draw_underlay()
  if self.base_class == "bot" then
    ovalfill(self.x + 1, self.y + 6, self.x + 7, self.y + 8, 1)
  else
    ovalfill(self.x + 2, self.y + 10, self.x + 13, self.y + 14, 1)
  end
  self:draw_health_recharge()
end


function entity:draw()
  local velocity_magnitude = sqrt(self.vx * self.vx + self.vy * self.vy)
  local threshold = 0.1
  local frames = velocity_magnitude > threshold and self.move_frames or self.idle_frames
  frame_duration = frames["duration"]

  -- Direction
  local cos_val = cos(self.facing_angle)
  local sin_val = sin(self.facing_angle)
  
  if abs(cos_val) < abs(sin_val) then
    current_frames = frames["lr"]
  else
    current_frames = cos_val > 0 and frames["down"] or frames["up"]
  end

  -- Update animation frame
  self.animation_timer += .0333
  if self.animation_timer >= frame_duration then
    self.animation_timer -= frame_duration
    self.animation_frame = (self.animation_frame % #current_frames) + 1
  end

  local frame = current_frames[self.animation_frame]
  local flip = self.facing_angle < 0.5

  -- Palette swap
  local entity_eye_colors = {
    Dervish = 15,
    Vanguard = 13,
    Warden = 1,
    CyberSeer = 13,
    QuantumCleric = 0
  }
  
  if self.entity_name ~= "Player" then
    self.eye_blink_timer += rnd(1.5)
    base_color = self.base_class == "bot" and 7 or 13
    pal(base_color, entity_eye_colors[self.entity_name])
    pal(12, (self.eye_blink_timer % 20) < 10 and 8 or 5)
  end

  if self.hit_flash_timer > 0 then
    for i = 0, 15 do pal(i, 7) end
    self.hit_flash_timer -= 1
  end

  if self.base_class == "bot" then
    spr(frame, self.x, self.y, 1, 1, flip)
  else
    spr(8, self.x, self.y - 12 + sin(self.hoover_timer) * 2, 2, 3, flip)
    self.hoover_timer += .02
  end

  reset_palette_and_transparency()

  -- rect(self.x, self.y, self.x + self.width, self.y + self.height)

  -- Laser
  -- if self.laser then
  --   line(self.x, self.y, self.target.x, self.target.y, 8) -- Draw the laser line
  --   for i= 1, 2 do
  --     local variation_x = 0.5
  --     local p_vx = rnd(variation_x) - variation_x / 2
  --     local variation_y = 0.5
  --     local p_vy = -(0.5 + rnd(variation_y))
  --     local p = particle:new(self.target.x + p_vx, self.target.y, p_vx, p_vy, 8, 30) -- Adjusted to use p_vx for x-axis variance
  --     add(particles, p)
  --   end
  -- end
end


function entity:draw_overlay()
  local x_offset = 0
  local y_offset = -8
  if self.base_class == "preacher" then
    x_offset = 5
    y_offset = -23
  end
  
  if not self.controlled then
    if self.current_state == enemy_state.alert then
      spr(56, self.x + x_offset, self.y + y_offset)
    elseif self.current_state == enemy_state.search then
      self.state_icon_timer += 1
      if self.state_icon_timer % 40 < 30 then
        spr(57, self.x + x_offset, self.y + y_offset)
      end
    elseif self.current_state == enemy_state.attack then
      spr(23, self.x + x_offset, self.y + y_offset)
    end

    local x_offset = 0
    local y_offset = 10
    if self.base_class == "preacher" then
      x_offset = 4
      y_offset = 16
    end

    if self.health < self.max_health then
      local health_width = flr(8 * self.health / self.max_health)
      local bar_x, bar_y = self.x + x_offset, self.y + y_offset
      rectfill(bar_x, bar_y, bar_x + 8, bar_y, 0)
      rectfill(bar_x, bar_y, bar_x + health_width, bar_y, 8)
    end

    if self.energy < self.max_energy then
      local energy_width = flr(8 * self.energy / self.max_energy)
      local bar_x, bar_y = self.x + x_offset, self.y + 1 + y_offset
      rectfill(bar_x, bar_y, bar_x + 8, bar_y, 0)

      if energy_width != 0 then
        rectfill(bar_x, bar_y, bar_x + energy_width, bar_y, 12)
      end
    end
  end

  self:draw_damage_text()
  
  if self.controlled and self.target.x ~= self.x then
    self.rectangle_side = max(self.rectangle_side - 1, 20)
    draw_rotating_rect(self.target.x, self.target.y, self.rectangle_side, 3)
  else
    self.rectangle_side = 40
  end




  

    -- Draw the target indicator
    -- local corners = {
    --   {dx = 0, dy = 0}, -- Top-left corner
    --   {dx = self.width-1, dy = 0}, -- Top-right corner
    --   {dx = 0, dy = self.height-1}, -- Bottom-left corner
    --   {dx = self.width-1, dy = self.height-1} -- Bottom-right corner
    -- }

    -- for corner in all(corners) do
    --   local start_x = self.x + corner.dx
    --   local start_y = self.y + corner.dy
    --   local end_x = self.target.x + corner.dx
    --   local end_y = self.target.y + corner.dy
    --   local distance = dist_trig(start_x, start_y, end_x, end_y)
    --   local step_x, step_y = (end_x - start_x) / distance, (end_y - start_y) / distance

    --   local check_x, check_y = start_x, start_y
    --   for i = 0, distance do
    --     if wall_collide(flr(check_x), flr(check_y)) then
    --       pset(check_x, check_y, 8)
    --     else
    --       pset(check_x, check_y, 11)
    --     end
    --     check_x += step_x
    --     check_y += step_y
    --   end
    -- end
end


function draw_rotating_rect(x, y, side_length, color)
  local angle, corners, h = time()/2, {}, side_length / 2
  local c, s = cos(angle), sin(angle)

  for v in all({{-h, -h}, {h, -h}, {h, h}, {-h, h}}) do
    local dx, dy = unpack(v)
    add(corners, {dx * c - dy * s + x, dx * s + dy * c + y })
  end

  for i = 1, 4 do
    line(corners[i][1], corners[i][2], corners[i % 4 + 1][1], corners[i % 4 + 1][2], color)
  end
end



-- Emitter
----------
emitter = {}
emitter.__index = emitter
function emitter:new(x, y)
  local self = setmetatable({}, emitter)
  self.x, self.y = x, y
  self.attract_distance = 30
  self.is_near_bot = false
  self.rise_speed = .5
  self.resting_height = 5
  self.current_height = 0
  self.max_height = 15
  self.blink_timer = 0
  self.active = false
  return self
end


function emitter:update()
  if player and not self.active then
    local distance = dist_trig(player.x - self.x, player.y - self.y)
    self.is_near_bot = distance < self.attract_distance

    if self.is_near_bot then
      if self.current_height < self.max_height then
        self.current_height = min(self.current_height + self.rise_speed, self.max_height)
      else
        self.active = true
      end
    elseif not self.is_near_bot then
      self.current_height = max(self.current_height - self.rise_speed, self.resting_height)
    end
  end
end


function emitter:draw()
  local visible_height = min(self.current_height, self.max_height)
  self.blink_timer += 1
  
  if self.current_height == self.max_height then
    pal(6, 8)
    pal(7, 8)

    local h, k = self.x + 4, self.y - 1
    local a = visible_height + 6 + sin(time()) * 1.3

    local b = a / 2
    local a_sq, b_sq = a^2, b^2
    for x = h - a, h + a do
      local x_minus_h_sq = (x - h)^2
      local y_range = sqrt((1 - x_minus_h_sq/a_sq) * b_sq)

      local y_min = flr(k - y_range) + 1
      local y_max = flr(k + y_range)

      for y = y_min, y_max do
        if pget(x, y) == 6 then
          pset(x, y, 8)
        end
      end
    end
  end 
  sspr(80, 0, 8, visible_height, self.x, self.y - visible_height + 1)
  pset(self.x, self.y, 6)
  pset(self.x + 7, self.y, 6)

  reset_palette_and_transparency()
end


-- Camera
----------
cam = {}
cam.__index = cam
function cam.new(x, y)
  local self = setmetatable({}, cam)
  self.x, self.y, self.lerpfactor = 0, 0, .2
  return self
end


function cam:update()
  local controlled_entity = get_controlled_entity()
  if controlled_entity then
    self.x += (controlled_entity.x - self.x - 64) * self.lerpfactor
    self.y += (controlled_entity.y - self.y - 64) * self.lerpfactor
    camera(self.x, self.y)
  end
end


-- Player hud
---------------
player_hud = {}
player_hud.__index = player_hud
function player_hud.new()
  local self = setmetatable({}, player_hud)
  self.x, self.y = 2, 2
  self.bar_width, self.bar_height = 3, 50
  self.shake_timer = 0
  return self
end


function player_hud:draw()
  player = get_controlled_entity()
  if player then
    self.shake_timer = max(0, self.shake_timer - 1)

    local shake_x, shake_y = self.shake_timer > 0 and flr(rnd(3)) - 1 or 0, self.shake_timer > 0 and flr(rnd(3)) - 1 or 0
    local drawx, drawy = self.x + cam.x + shake_x, self.y + cam.y + shake_y
    local drawx_bar_width, drawy_bar_height = drawx + self.bar_width, drawy + self.bar_height

    local health_percentage = player.health / player.max_health
    local energy_percentage = player.energy / player.max_health

    local health_draw_y = drawy + flr(self.bar_height * (1 - health_percentage))
    local energy_draw_y = drawy + flr(self.bar_height * (1 - energy_percentage))
    rectfill(drawx, health_draw_y, drawx_bar_width, drawy_bar_height, 8)

    local energy_bar_x = drawx_bar_width + 7
    local energy_bar_x_width = energy_bar_x - self.bar_width
    rectfill(energy_bar_x, energy_draw_y, energy_bar_x_width, drawy_bar_height, 12)

    for x in all({drawx_bar_width, energy_bar_x}) do
      line(x, drawy, x, drawy_bar_height, 3)
      for y = drawy, drawy_bar_height, self.bar_height / 5 do
        line(x, y, x - 2, y, 3)
      end
    end

    local current_ability = player.ability_actions[player.current_ability_index]
    print_right_justified(smallcaps(current_ability.description), cam.x + 125, cam.y + 2)
    if current_ability.current_ammo then
      print_right_justified(tostr(current_ability.current_ammo).."/"..tostr(current_ability.max_ammo), cam.x + 125, cam.y + 9)
    end
  end
end


function print_right_justified(text, x, y)
  local text_width = #text * 4
  print(text, x - text_width, y, 3)
end




__gfx__
eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee00000000000000000000000000000000eeeedddd6667eeeeee1111ee66b666666666666600000000eeeeeeeedd6667ee
eeeeeeeeee5777eeee5777eeee5777ee00000000000000000000000000000000eeedd66666667eeee111111e66b666666b666bb600000000eeeeeeedd666667e
ee5777eee577cc7ee577cc7ee577cc7e00000000000000000000000000000000eedddd66666667ee111661116bbbbb666bb66b6600000000eeeeeeed55ddd66e
e577cc7ee777cc76e777cc7ee777cc7e00000000000000000000000000000000eeddd665dddd66ee011111156b66bbb6bbbbbb6600030000eeeee11d5d111d6e
e777cc7ee577777ee577777ee577777e00000000000000000000000000000000eeddd65d1111d6ee00111155666bbbbbbbbbb66603030000eeee11dd5d181d6e
e577777ee577777e05777770e577077e00000000000000000000000000000000e1ddd65d1881d61e0700555566bbb7bbb7bbbb6603030300eeee1dd55d111d6e
0577707e0e0ee0e00e0e0ee00eee0ee00000000000000000000000000000000011115d5d1881d61107005755666bbbbbbbbbb7b600000000eeee1d55dddd6eee
0e0ee0e00e0ee0e0eeee0eee0eeeeee000000000000000000000000000000000e1ddd65d1111d61e07005755b66bbbbbbbbbbbbb00000000eee11d5d111d6eee
eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee6666666666666666eeeeeeeeeeddd665dddd66ee00005575bbbbbbbbbbbbbbbb66666666eee11d5d181d6eee
eeeeeeeeee5777eeee5777eeee5777eee050660e7777777777777776e00000eeeeddd666666666ee007055556bbb7bbb7bbbb7bb66666666ee11dd5d111d6eee
ee5777eee57cc77ee57cc77ee57cc77ee05000007666666666666666e00800eeeeddd566616166ee07005755666bbbbbbbbbbbb666666666ee1dd5ddddd66eee
e57cc77ee77cc77ee77cc77ee77cc77ee050000e766655555555666de00800eeeed0d6606d6066ee007055756bbbbbbbbbbbbbbb66666666ee1d5d111d6eeeee
e77cc77ee577777ee5777770e577777eeeeeeeee766556666665566de00800eeee02d6000d0006ee070055556b6b66b7bbbbb66b66666666e11d5d181d6eeeee
e577777ee577777e05777770e577707ee050660e765566666666556de00000eeee02d000020006ee000055556b6bb6bbbbb6bb6b66666666e11d5d111d6eeeee
057770700e0ee0e00e0ee0ee0eeee0e0e0500000765666666666656de00800eeeee20001520101ee00005555666b66bbbbb6bb6666666666e11d65ddd66eeeee
0eeee0ee0eeee0eeeeeee0ee0eeeeeeee050000e765666666666656de00000eeeee211015222222eeeeeeeee6666666bbb666b66666666661111d66666eeeeee
eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee765666666666656d88eeee88eee222225ee1ee2ebbbbbbbb55555555555555550000000dd0000000dddddddd
eeeeeeeeee5772eeee5772eeee5772eeeeeeeeee765666666666656d8eeeeee8eeeeee0250eeee2eb7bbbbbb555555222255555500000dddddd00000dddddddd
ee5772eee577772ee577772ee577772e0e00000e765666666666656deeeeeeeeeeeee112e0ee112ebbbbb7bb55555521125555550000dddddddd0000dddddddd
e577772ee777777ee777777ee777777e05666600765566666666556deeeeeeeee000010ee0ee1eeebbb7bbbb5555552112555555000dddddddddd000dddddddd
e777777ee577777ee5777770e577777e05000060766556666665566deeeeeeeee0eee1eee0ee1eeebbbbbb7b555555222255555500dddddddddddd00dddddddd
e577777ee577777e05777770e577707e05000000766655555555666deeeeeeeee0eee1eee0ee1eeeb7bbbbbb55555521125555550dddddddddddddd0dddddddd
057770700e0ee0e00e0ee0ee0eeee0e00e00000e766666666666666d8eeeeee8eeeee1ee00ee1eeebbbb7bbb55555521125555550dddddddddddddd0dddddddd
0eeee0ee0eeee0eeeeeee0ee0eeeeeeeeeeeeeee66dddddddddddddd88eeee88eeeee1ee0eee1eeebbbbbbbb5555552222555555dddddddddddddddddddddddd
eeeeeeeeeeeeeeeeeee00eeeeee00eeeeee00eeeeee00eeeeee00eeeeee00eeeeeeeeeeeeeeeeeee55dddd555211211255555555dddddddddddddddd66666666
eeeeeeeeeeeeeeeeee0000eeee0000eeee0000eeee0000eeee0000eeee0000eee00000eee00000ee5dbbbbd552222222555555550dddddddddddddd067777776
eeeeeeeeeeeeeeeeeecccceeeecccceeeecccceeeecccceeeecccceeeecccceee00a00eee0aaa0eedb7bbb7d55555555555555550dddddddddddddd067666666
eeeeeeeeeeeeeeeeeec77ceeee77cceeee7ccceeeecccceeeeccc7eeeecc77eee00a00eee000a0eedbbbbbbd555555555555555500dddddddddddd006766666d
eeeeeeeeeeeeeeeeeec7cceeee7ccceeeecccceeeecccceeeeccc7eeeecc7ceee00a00eee00aa0eedbb7bbbd5555555555555555000dddddddddd0006766666d
ee5eeee5ee1111eeeecccceeeecccceeeecccceeeecccceeeecccceeeecccceee00000eee00000ee1dbbbbd255555555555555550000dddddddd00006766666d
eeeeeeeee111111eee0000eeee0000eeee0000eeee0000eeee0000eeee0000eee00a00eee00a00ee11dbdb22555555555222222200000dddddd000006766666d
5eeee5eeee1111eeeee00eeeeee00eeeeee00eeeeee00eeeeee00eeeeee00eeee00000eee00000ee11112b2255555555521121120000000dd0000000666ddddd
55555555111111115555555555355355555555515555555555555111e6655555e66555555555566e5555566eeeeeeeeeeeeeeeee666666666666666655555551
55555555111111115555555555335335555555115555555555551111e6655555333555555555566e55555333e66666666666666e666666666666666655555511
55555555eeeeeeee5555155555535535555551111111111111111eeee6655555e63335555555566e5553336ee66666666666666e66111111111111165555511d
55555555eeeeeeee55551555535355355555111e111111111111eeeee6655555e66555555555566e5555566ee66155555555166e6611121221212116555511dd
55555555eeeeeeee5555115553533535555111eeeeeeeeeeeeeeeeeee6655555366553335555566e3335566ee66515555551566e661266666666611655511ddd
66666666eeeeeeee666111666366333666111eeeeeeeeeeeeeeeeeeee6655555333353555555566e5535333ee66551555515566e66116111111162165511dddd
66666666eeeeeeee66111666633633666111eeeeeeeeeeeeeeeeeeeee6655555e36333355555566e53333633e66555155155566e6612611112116116511ddddd
eeeeeeeeeeeeeeeeeeeeeeeeeeeee3eeeeeeeeeeeeeeeeeeeeeeeeeee6655555e66555555555566e5555566ee66555511555566e661161266611621611dddddd
eeeeeeeeeeeeeeeeeeeeeeeeeee3333eeeeeeeeeeeeeeeeeeeeeeeeee6655555eeee11555555566e511eeeeee66555511555566e661161266611621615555555
66666666eeeeeeee66111666663366336611eeeeeeeeeeeeeeeeeeeee6115555eeee11555555116e5511eeeee66555155155566e661261166621611611555555
66666666eeeeeeee666111666633366366611eeeeeeeeeeeeeeeeeeee1115555eee115555555111e55511eeee66551555515566e6611612621116216d1155555
55555555eeeeeeee5555115553353553555111eeeeeeeeeeeeeeeeeee1111555eee115555551111e55511eeee66515555551566e6612611611116116dd115555
55555555eeeeeeee55551555535535535555111e111111111111eeeeeee11555e111155555511eee5551111ee66155555555166e6611612666666216ddd11555
55555555eeeeeeee5555155553553555555555111111111111111eeeeee11555e111555555511eee5555111ee66666666666666e6612611612121116dddd1155
55555555111111115555555553555555555555515555555555551111eeee1155e61155555511eeee5555116ee66666666666666e6611612611111116ddddd115
55555555111111115555555555555555555555555555555555555111eeee1155e66555555511eeee5555566eeeeeeeeeeeeeeeee6612611666666666dddddd11
5555555555555553155555555555555166dddd665555555511115555eeee1155eeee11555511eeee5511eeee5555555115555555661161266666666666666666
555555555533353351555555555555156dbbbbd65555555511111155eeee1155eeee11555511eeee5511eeee5555551551555555661261166666666666666666
55555555333533355515555555555155db7bbb7d55555555eeee1111eeee1155eeee11555511eeee5511eeee5555515555155555661161122121212166dddd66
55555555553555555551555555551555dbbbbbbd15555555eeeee111eeee1155eeeee1155511eeee511eeeee555515555551555566126111111111116d6666d6
55555555533555535555155555515555dbb7bbbd11155555eeeeeeeeeeee1155eeeee1155511eeee511eeeee55515555555515556611666666666666d666666d
555555555555533355555666666555551dbbbbd2ee116666eeeeeeeeeeee1155eeeee1155511eeee511eeeee551555555555515566112121121212121d6666d2
5555555555553353555556666665555511dbdb22eee11666eeeeeeeeeeee1155eeee11555511eeee5511eeee5155555555555515661111111111111161dddd26
55555555555555555555566ee6655555111b2222eeeeeeeeeeeeeeeeeeee1155eeee11555511eeee5511eeee1555555555555551666666666666666666122266
55555355eeeeeeee5555566ee665555511122222eeeeeeeeeeeeeeeeeeee1155eeeeee115511eeee66dddd66000000001dddddddddddddd16666666666666666
55555355ee2222ee5555566666655555d112222deee11666eeeeeeeeeeee1155eeeeee115511eeee6dddddd600000000111dddddddddd1116676666666677766
53555353e222222e55555666666555551d1222d2ee116666eeeeeeeeeeee1155eeeeee115511eeeedddddddd000000005511dddddddd115567766666667f7776
53355333e122225e555515555551555511dddd2211155555eeeeeeeeeeee1155eeeeee115511eeeedddddd2d0000000055511dddddd115556007666666770706
55355553e111555e55515555555515551112222215555555eeeee111eeeee115eeeee111511eeeeedddd22dd00000000555511dddd1155556660766666777776
55353533e111555e55155555555551551112222255555555eeee1111eeeee111eeeee115111eeeee1ddd22d2000000005555511dd11555556666077666007076
53353535e111555e51555555555555156112222655555555ee111155eeeeee11eeee115511eeeeee11dddd220000000055555511115555556666670666600006
33333535ee1155ee1555555555555551666666665555555511115555eeeeee11eeee115511eeeeee111222220000000055555551155555556666606666666666
8616f3f3f3d1d1d1f3f3f306a57406d1d1b1a206947406d1d1d1d1d1d1d1d1d1d5d1d1d1d4e5d1d1d1d1d1d1d1d1d1062757c47406d1d1000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
8716f3d1d1d1d1d1d1d1f306a47406d1d1d1b106947406d1d1d1d1d1d1d1d1d1d5d1d1d1d6e6e6e4d1d1d1d1d1d1d1b606b6947406d1d1000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
85b2e6e6e6e4d1d1d1d1f316a47406d1d1d1d106947406d1d1d1d1d1d1d1d1d1d5d1d1d1d1d1d1d5d1d1d1d1d1d1d1d1d106947406d1d1000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
8406f3d1d1d5d1d1d1d1f316a47406c0c0d1d106947406d1d1d1d1d1d1d1d1d1d5d1d1d1d1d1d1d5d1d1d1d1d1d1d1d1d106947406d1d1000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
8416f3d1d1d6e6e6e4d1f316957406a2c1d1d1069474b606b6d1d1d1d1d1c606b3b6d1d1d1d1c6b306b6d1d1d1d1d1c606c6947406d1d1000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
7516f3d1d1d1d1d1d6e6e6c29774b6f4f2f2f5c694b5043606d1d1d1d1d106263606d1d1d1d106263606d1d1d1d1d1062604c57406d1d1000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
76b2e6e6e4d1d1d1d1d1f316a6b544d3f2f2e356c5b4053706d1d1d1d1d106273706d1d1d1d106273706d1d1d1d1d1069400007406d100000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
7706f3d1d5d1d1d1d1d1f306a5b70000000000000074c606c6d1d1d1d1d1b60606c6d1d1d1d1b60606c6d1d1d1d1d1069400007406d1d1000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
7706f3f3d5f3f3f3f3f3f316a4b7000000000000007406d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1069400007406d1d1000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
85b60606b3070606060606c694b7000000000000007406d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1069400007406d1d1000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
b50404343444545464666656c500000000000000007406d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1069400007406d100000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1700000000000000000000000000000000000000007406d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1069400007406d100000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1700000000000000000000000000000000000000007406d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1069400007406d100000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1700000000000000000000000000000000000000007406d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1069400007400d100000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
17000000000000000000000000000000000000000074b606b60606b6b606b606b606b606b606b606b606b606b60606c694000074000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
171717171717171717171717171717171717171717b50404040404040404040404040404040404040404040404040404c5000074000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee00000000000000000000000000000000000000000000000000000000
eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee00000000000000000000000000000000000000000000000000000000
eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee00000000000000000000000000000000000000000000000000000000
eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee00000000000000000000000000000000000000000000000000000000
eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee3eeeeeeeeeeeeeeeeee00000000000000000000000000000000000000000000000000000000
eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee33eeeeeeeeeeeeeeeeee00000000000000000000000000000000000000000000000000000000
33333333e33333333e33333333e33eeeeeeee33333333e33eeee33e33333333e3333333300000000000000000000000000000000000000000000000000000000
33333333e33333333e33333333e333eeeeeee33333333e33eeee33e33333333e3333333300000000000000000000000000000000000000000000000000000000
eeeeee33eeeeeee33eeeeeeeeee3333eeeeee33eeeeeee33eeee33eeeeeeeeeeeeeeee3300000000000000000000000000000000000000000000000000000000
33333333e33333333e33333333e33333eeeee33eeeeeee33333333e33333333e3333333300000000000000000000000000000000000000000000000000000000
33333333e33333333e33333333e33e333eeee33eeeeeee33333333e33333333e3333333300000000000000000000000000000000000000000000000000000000
33eeeeeee33e333eeeeeeeeeeee33ee333eee33eeeeeee33eeee33eeeeeeeeee33e333ee00000000000000000000000000000000000000000000000000000000
33eeeeeee33ee333ee33333333e33eee333ee33333333e33eeee33e33333333e33ee333e00000000000000000000000000000000000000000000000000000000
33eeeeeee33eee333e33333333e33eeee333e33333333e33eeee33e33333333e33eee33300000000000000000000000000000000000000000000000000000000
33eeeeeeeeeeeee33eeeeeeeeeeeeeeeeeeeeeeeeeeeee33eeeeeeeeeeeeeeeeeeeeee3300000000000000000000000000000000000000000000000000000000
3eeeeeeeeeeeeeee3eeeeeeeeeeeeeeeeeeeeeeeeeeeee3eeeeeeeeeeeeeeeeeeeeeeee300000000000000000000000000000000000000000000000000000000
eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee00000000000000000000000000000000000000000000000000000000
eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee00000000000000000000000000000000000000000000000000000000
eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee00000000000000000000000000000000000000000000000000000000
eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee00000000000000000000000000000000000000000000000000000000
eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee00000000000000000000000000000000000000000000000000000000
eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee00000000000000000000000000000000000000000000000000000000
33333333e33333333e33333333e33333333e33333333e33333333e33333333ee33eeeeee00000000000000000000000000000000000000000000000000000000
33333333e33333333e33333333e33333333e33333333e33333333e33333333ee33eeeeee00000000000000000000000000000000000000000000000000000000
eeeeee33eeeeeee33e33eeee33eeee33eeee33eeee33e33eeeeeee33eeee33ee33eeeeee00000000000000000000000000000000000000000000000000000000
33333333e33333333e33eeee33eeee33eeee33eeee33e33eeeeeee33eeee33ee33eeeeee00000000000000000000000000000000000000000000000000000000
33333333e33333333e33eeee33eeee33eeee33eeee33e33eeeeeee33eeee33ee33eeeeee00000000000000000000000000000000000000000000000000000000
33eeeeeee33e333eee33eeee33eeee33eeee33eeee33e33eeeeeee33eeee33ee33eeeeee00000000000000000000000000000000000000000000000000000000
33eeeeeee33ee333ee33333333eeee33eeee33333333e33333333e33333333ee3333333300000000000000000000000000000000000000000000000000000000
33eeeeeee33eee333e33333333eeee33eeee33333333e33333333e33333333ee3333333300000000000000000000000000000000000000000000000000000000
33eeeeeeeeeeeee33eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee00000000000000000000000000000000000000000000000000000000
3eeeeeeeeeeeeeee3eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee00000000000000000000000000000000000000000000000000000000
__gff__
0000000000000000000000040400000000000000000000000000000404000000000000000000800000000401010808080000000000000000000001010108080802020202020202020202020202000001020202020202020202020202020000010101020201020202020202010100000001010202010202020202010001010000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__map__
7171717171717171714b5050505050505050505050505050505050505050505050505050504c000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
710000000000000000476c60606060606060606060606060606060606060606b606060606b49000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
71000000000000000057601d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d6049000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
7100000000000000002d5f1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d6049000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
7100000000000000002f2f1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d6049000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
7100000000000000003d7d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d6049000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
71000000000000000058601d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d6049000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
71000000000000000047601d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d6049000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
71000000000000000047601d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d6049000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
71000000000000000047601d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d6049000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
71000000000000000047601d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d60494b50505050504c4b50505050000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
71000000000000000047601d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d6049476c6060606b49476c606060000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
71000000000000000047601d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d604947601d1d1d604947601d1d1d000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
71000000000000000047601d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d4d6e6e2c7273601d1d1d60494760000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
71000000000000000047601d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d5d1d1d6b3c606c1d1d1d60727360000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
71000000000000000047601d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d5d1d1d1d5d1d1d1d1d1d6b3c606c000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
71000000000000000047601d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d5d1d1d4d5e1d1d1d1d1d1d5d1d1d1d1d1d1d1d1d1d1d1d1d1d00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
710000000000000000476b606060606060606060606060606b1d1d1d1d1d1d1d1d5d1d1d5d1d1d1d1d1d1d4d5e1d1d1d1d1d1d1d1d1d1d1d1d1d00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
7171717171717171715b4040404040404040404040404063601d1d1d1d1d1d1d1d6d4e1d5d1d1d1d1d1d1d5d1d1d1d1d1d1d1d1d1d1d1d1d1d0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000047601d1d1d1d1d1d1d1d1d5d1d5d1d1d1d1d1d1d5d1d1d1d1d1d1d1d1d1d1d1d1d1d0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
4b5053525354555575535352505050505050505050504c47601d1d1d1d1d1d1d1d1d5d1d5d1d1d1d4d6e6e5e1d1d1d1d1d1d1d1d1d1d1d1d1d0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
576c607070606060707060606060606060606060606b49472b6e6e6e6e6e4e1d1d1d5d1d5d1d1d1d5d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d00000000000000000000000000000000007b0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
67603f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f607273601d1d1d1d1d5d1d1d1d3f3f3f3f1d4d5e1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
67613f1d1d3f1d3f3f1d1d3f1d3f1d3f1d1d1d3f3f6b60606c1d1d1d1d1d5d1d1d3f1d1d1d1d3f5e1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
77603f3f3f3f1d3f3f3f3f3f1d3f3f3f3f3f3f3f1d3f3f3f3f1d1d1d1d1d6d6e3f1d1d1d1d1d1d3f1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
58603f1d1d3f1d3f3f1d1d3f1d3f1d3f1d1d1d3f1d3f3f3f3f1d1d1d1d1d1d1d3f1d1d15161d1d3f1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
67613f1d1d3f3f3f3f1d1d3f3f3f1d3f1d1d1d3f1d3f3f3f1d1d1d1d1d1d1d4d3f1d1d25261d1d3f6e4e1d1d1d1d1d1d1d1d1d1d1d1d1d00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
78603f3f3f3f4d6e6e4e3f3f1d3f3f3f3f3f3f3f3f3f3f3f1d1d1d1d1d1d1d5d3f1d1d1d1d1d1d3f1d5d1d1d1d1d1d1d1d1d1d1d1d1d0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
476b60606b3f5d1d6c3b606060606b0c1d1d1d6c6060606b1d1d1d1d1d4d6e5e1d3f1d1d1d1d3f1d1d6d6e4e1d1d1d6c60606060601d1d00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
5b446563603f5d3f606244666563601c1d1d1d60624063601d1d1d1d1d5d1d1d1d1d3f3f3f3f1d1d1d1d1d5d1d1d1d6062404063601d1d00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
4b5052732b6e5e1d607253754c47601d1d1d0b60494b732b6e6e6e6e6e5e1d1d1d1d5d1d1d5d1d1d1d1d1d6d6e6e6e2c49000047601d1d00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
486c60606c1d1d1d6b60606b5947601d1d0b2a6049476c6c1d1d1d1d1d1d1d1d4d6e5e1d1d5d1d1d1d1d1d1d1d1d1d6049000047601d1d00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__sfx__
151000000c0730000000000000000c013000000000000000266550d0000e625000000e615000000e615000000c0730000000000000000c013000000c07300000266550d0000e625000000e615000000e61500000
a5100000021450e14502115021450212502115021450e11502145021250211502145021250211502145021150f145031250311503145031250f1150314503115021450e1250211502145021250e1150214502115
c3100000027500e73002710027500272002710027500271002750027300271002750027200271002750027100f750037200371003750037200f7100374003710027500e7300271002750027200e7100275002710
a71000000c0730c0000c033000000c023000000c013000000c003000000000000000000000000000000000000c0730c0000c033000000c023000000c013000000000000000000000000000000000000000000000
150e00000c0730000000000000000c013000000c0730c000266550d0000e625000000e625000000e615000000c0730000000000000000c013000000c07300000266550d0000e625000000e615000000e61528600
3d0e000008d500cd5010d5013d5017d5018d5017d5014d500ed5009d5005d5001d5005d5008d500dd5010d5008d500cd5010d5013d5017d5018d5017d5014d5010d500bd5009d5008d5007d5009d500dd500fd50
47010000000000000000000000003706035060310600000000000000002506000000000000000000000160600000000000000000a060000000000000000000000000000000000000000000000000000000000000
47010000000000000009770097700a7700a7700a6700b7700c7700d7700f77011670117701377015770177701b6701b7701d77021770267702877000000000000000000000000000000000000000000000000000
93010000000000000009770097700a7700a7700a6700b7700c7700d7700f77011670117701377015770177701b6701b7701d77021770267702877000000000000000000000000000000000000000000000000000
cb0600000f5503c6002d6001f60000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000050000000
d5090000397702d67029770246701e77018670127700c6700a7500565005750056500475004650037500265001730016300073000630007200062000720006200071000610007100161001710016100171001610
a702000035453334532f4532b4532645325453234531e4531e4531945316453174531145310453104530d4530a453094530745302453034530045300000000000000000000000000000000000000000000000000
a702000000453024530445306453084530b4530e45311453164531a4531c4531e45320453224532445327453294532c4532f45332453344533745300000000000000000000000000000000000000000000000000
d1090000397702d67029770246701e77018670127700c6700a7400564005740056400474004640037400264001720016200072000620007100061000710006100000000000000000000000000000000000000000
170500003c6550b655036550000600000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1706000000453024530445306453084530b4530e45311453164531a4531c4531e45320453224532445327453294532c4532f45332453344533745300000000000000000000000000000000000000000000000000
170600003745337453354533345332453304532c4532945326453224531f4531c4531b4531945315453114530e4530c4530945307453044530245300000000000000000000000000000000000000000000000000
a4100000021450e14502115021450a12502115021450e1150214502125021150a145091250211502145021150f14503125031150a145031250f115031450b115021450a125021150a145021250a1150214502115
a30300002d4512245118451124510e451114030000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
d7020000257571b757147570000000001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
d007000037650316502f65029650226501e65019650166501465012640106400e6400903005630036300262000620006200062000620016200162000620006100061000610006100061000610006100061000610
__music__
01 00015144
03 00114344
00 04054344
00 41424344
00 02404344
03 02034344

