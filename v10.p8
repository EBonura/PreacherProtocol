pico-8 cartridge // http://www.pico-8.com
version 41
__lua__


-- Time spent in mission
-- check if we can load map


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


function copy_map_into_memory(map_string)
  local data = unhex(map_string)
  for i, byte in ipairs(data) do 
    poke(0x2000 + i - 1, byte) 
  end
end


function unhex(s)
  local t, j = {}, 1
  for i = 1, #s, 2 do 
    local sub_str = sub(s, j, j + 1)
    j += 1
    if sub_str[1] ~= "\n" and sub_str[2] ~= "\n" then
      add(t, '0x'..sub_str)
      j += 1
    end
  end
  return t
end

-- function hex_to_char(str)
--   local result = ""
--   for i = 1, #str, 2 do
--     local substr = sub(str, i, i + 1)
--     local char = tonum("0x"..substr)
--     if substr[0] == "\n" or substr[1] == "\n" then
--     else
--       result = result..chr(tonum("0x"..substr))
--     end
--   end
--   return result
-- end


function get_controlled_entity()
  for e in all(entities) do
    if e.controlled then return e end
  end
end


function check_entity_collision(x1, y1, w1, h1, x2, y2, w2, h2)
  return x1 < x2 + w2 and x2 < x1 + w1 and y1 < y2 + h2 and y2 < y1 + h1
end


function tile_check(x, y, flag)
  return fget(mget(flr(x / 8), flr(y / 8)), flag or 0)
end


function is_close_to(e1, e2, dist)
  return dist_trig(e1.x - e2.x, e1.y - e2.y) <= dist
end


function sign(x)
  return x < 0 and -1 or (x > 0 and 1 or 0)
end


function display_logo(x_preacher, x_protocol, y_preacher, y_protocol)
  spr(224, x_preacher, y_preacher, 1, 2)
  spr(225, x_preacher + 9, y_preacher, 1, 2)
  spr(233, x_preacher + 18, y_preacher, 7, 2)

  spr(224, x_protocol, 11, y_protocol + 1, 2)
  spr(225, x_protocol + 9, y_protocol + 11, 1, 2)
  spr(226, x_protocol + 18, y_protocol + 11, 7, 2)
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

  current_game_state = game_state.loadout_select
  intro_counter, intro_blink = 0, 0

  -- Mission Select
  selected_mission = 2
  level_select_args = stringToTable([[
    6,35,9,38,mission 1,1000|
    6,50,9,38,mission 2,2000|
    6,65,9,38,mission 3,3000|
    6,80,9,38,mission 4,4000]])
  level_select_text_panels = {}
  for level_select_arg in all(level_select_args) do
    add(level_select_text_panels, textpanel:new(unpack(level_select_arg)))
  end
  
-- attack speed 4,3,2,1

  entity_stats_list = {}
  for t in all(stringToTable(
    [[Player,bot,8,8,100,100,false,1,2,3,100|Dervish,bot,8,8,350,800,false,5,5,3.5,300|Vanguard,bot,8,8,750,800,false,7,4,2,400|Warden,bot,9,9,900,800,false,9,4,2,600|CyberSeer,preacher,14,14,1000,1000,true,1,2,1,1000|QuantumCleric,preacher,16,16,1200,800,true,1,1,1,1500]])) do
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
      attack_cooldown = t[9],
      accelleration = t[10],
      destroy_reward = t[11]
    }
  end
   

  local mission_1 = stringToTable([[
    64,48,true,Player|
    392,336,false,Dervish|
    272,408,false,Dervish|
    480,360,false,Dervish|
    464,208,false,Dervish|
    376,208,false,CyberSeer]])
  missions_entities_params = {
    mission_1,
    { -- Mission 2
      {68*8, 27*8, "true", "Player"},
      {82*8, 27*8  , false, "Dervish"},
      {83*8, 37*8  , false, "Dervish"},
      {100*8, 28*8 , false, "Vanguard"},
      {88*8, 52*8  , false, "Vanguard"},
      {74*8, 45*8  , false, "Dervish"},
      {85*8, 45*8  , false, "Dervish"},
      {67*8, 37*8  , false, "Warden"}, 

    -- {4*8, 25*8, false, "Dervish"},
    -- {15*8, 26*8, false, "Dervish"},
    -- {6*8, 43*8, false, "Vanguard"},
    -- {27*8, 45*8, false, "Dervish"},
    -- {35*8, 43*8, false, "Dervish"},
    -- {50, 155, false, "QuantumCleric"},
    {126*8, 1*8  , false, "Vanguard"},

    },
    { -- Mission 3
      {92, 34, true, "bot"},
      {105, 140, false, "bot"},
    },
    { -- Mission 4
      {110, 160, true, "bot"},
      {125, 180, false, "bot"},
    },
  }

  local_mission_1_2_laser_doors =  {
    {107*8, 29*8, 12},  -- mission 2
    {12*8, 39*8, 8},    --  mission 1
    {99*8, 42*8, 11},   -- mission 2
    {105*8, 29*8, 8},   -- mission 2
    {106*8, 29*8, 7},   -- mission 2
    {55*8, 49*8, 12},   -- mission 1
  }

  mission_laser_doors_params = {
    local_mission_1_2_laser_doors, 
    local_mission_1_2_laser_doors,
    { -- Mission 3

    },
    { -- Mission 4

    },
  }

  mission_interfaces_textlines = stringToTable([[
⬆️⬇️⬅️➡️ move. explore around   
,move away. then ❎ to shoot 
,try moving to the next room
,shoot barrels. clear the way
,welcome to preacher protocol
,some barrels release waste
,shooting consumes energy
,watch out for toxic waste 
,impact strike: slow/strong
,pulse strike: fast/weak
,🅾️ rotate ability
,regen: restores health
,use switch to open the way
,kill foes to end mission
,energy drains when outside|
mission2|
mission3|
mission4]])


  mission_briefings_params = {
    "Initiation ground \n\nLearn the basics:\n- movement\n- cycle skills\n- environment\n- engaging targets\n- interacting with \nobjects",
    "Infiltrate the \nNeo-Tokara Complex\n\nneutralize guards; \nactivate all \nswitchess",
    "Access Denied:\n\nmission not \navailable in beta",
    "Access Denied:\n\nmission not \navailable in beta",
  }

  -- "Destroy the \nCore Facility\n\nevade or \nneutralize guards; \ndestroy the energy \ncore",

  -- Mission Brief
  briefing_panel = textpanel:new(52, 36, 67, 74, "")
  local stats = stringToTable([[500, 570, 650, 730, 810, 880, 960, 1040, 1120, 1200| 
                                500, 550, 610, 660, 720, 770, 830, 880, 940, 1000|
                                50, 53, 56, 60, 63, 66, 70, 73, 76, 80|
                                10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20|
                                4, 4, 3, 3, 3, 2, 2, 1, 1, 0|
                                1, 2, 2, 3, 3, 4, 4, 5, 5, 6 |
                                100, 131, 164, 200, 240, 285, 336, 394, 460, 535 |
                                0,0,0,0,0,0,5,6,2,5,9,3,1,2,2,4 |
                                0,1,0,0,0,0,0,2,0,0,0,0,0,0,0,0 |
                                10, 20, 9, 26,health| 
                                10, 34, 9, 26,energy|
                                10, 48, 9, 22,range|
                                10, 62, 9, 38,atk force|
                                10, 76, 9, 34,atk rate|
                                10, 91, 9, 22,regen|
                                40, 106, 9, 54,begin mission|
                                38, 110, 9, 58,select mission]])

  selected_loadout = 1
  credits = 5000
  loadout_select_text_panels = {}
  for i = 10, 16 do
    add(loadout_select_text_panels, textpanel:new(unpack(stats[i])))
  end

  cost_table = stats[7]
  selected_debrief = 1
  loadout_select_sliders = {
    slider:new(66, 22, stats[1]), -- health
    slider:new(66, 36, stats[2]), -- energy
    slider:new(66, 50, stats[3]), -- range
    slider:new(66, 64, stats[4]), -- atk force
    slider:new(66, 78, stats[5]), -- atk rate
    slider:new(66, 92, stats[6]), -- regen
  }

  debrief_text_panels = {
    textpanel:new(30, 100, 9, 62, 'restart mission'),
    textpanel:new(31, 115, 9, 60, 'mission select')
  }

  cam = cam:new()
  door_effect = door_effect:new()
  player_hud = player_hud:new()
  view_radius = 50
  player_copy = nil
  swap_palette = stats[8]
  swap_palette_dark = stats[9]
  load_entities()
end


function _update()
  state_actions[current_game_state].update()
  door_effect:update()
  update_player_copy()
end


function update_player_copy() 
  local player = get_controlled_entity()
  if player then player_copy = player end
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
  map(88, 25, 0, 0, 128, 48)
  draw_shadow(128,128,0, swap_palette_dark)

  if sin(intro_blink)<.9 then
    circfill(63,64, 3, 2)
  end

  local x_preacher = min(15, -50 + intro_counter * 3)
  local x_protocol = max(45, 128 - intro_counter * 3)
 
  display_logo(x_preacher, x_protocol, 0, 0)

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
  if intro_counter == 0 then music(05) end
  
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

  display_logo(cam.x + 15, cam.x + 45, cam.y, cam.y)

  for i, panel in ipairs(level_select_text_panels) do
    panel.selected = (i == selected_mission)
    panel:draw()
  end

  briefing_panel.textline = mission_briefings_params[selected_mission]
  briefing_panel:draw()
  print(smallcaps("⬆️ ⬇️ Select mission"), cam.x + 25, cam.y + 115, 11)
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
  local current_slider = loadout_select_sliders[selected_loadout]

  if btnp(⬆️) then
    sfx(19)
    selected_loadout = ((selected_loadout - 2) % num_panels) + 1
  elseif btnp(⬇️) then
    sfx(19)
    selected_loadout = (selected_loadout % num_panels) + 1
  end

  if selected_loadout == 7 then
    if btnp(❎) then
      sfx(20)
      door_effect.closing = true
    end
  else
    if btnp(⬅️) then
      if current_slider.idx > 1 then
        credits += cost_table[current_slider.idx - 1]
        current_slider.idx -= 1
        sfx(09)
      else
        sfx(14)
      end
    elseif btnp(➡️) then
      if credits >= cost_table[current_slider.idx] and current_slider.idx < 10 then
        credits -= cost_table[current_slider.idx]
        current_slider.idx += 1
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
  if debrief_counter == 0 then music(2) end
  reset_palette_and_transparency(true)

  player = get_controlled_entity()
  if player then
    print("mission complete", cam.x + 30, cam.y + 10, 11)
  else
    print("mission failed", cam.x + 30, cam.y + 10, 8)
  end

  local ability_actions = player_copy.ability_actions

  local used_pulse_strike = ability_actions[1].max_ammo - ability_actions[1].current_ammo
  local used_impact_strike = ability_actions[2].max_ammo - ability_actions[2].current_ammo
  local used_regen = ability_actions[3].max_ammo - ability_actions[3].current_ammo

  local display_pulse_strike = -min(used_pulse_strike, flr((debrief_counter / 15) * used_pulse_strike)) * 3
  local display_impact_strike = -min(used_impact_strike, flr(((debrief_counter - 15)/ 15) * used_impact_strike)) * 30
  local display_regen = -min(used_regen, flr(((debrief_counter - 30)/ 15) * used_regen)) * 100
  local display_enemies_killed = min(enemies_killed, flr(((debrief_counter - 45)/ 15) * enemies_killed))
  local display_enemies_reward = min(enemies_reward, flr(((debrief_counter - 45)/ 15) * enemies_reward))
  local display_reward = player and level_select_args[selected_mission][6] or 0
  total = display_pulse_strike + display_impact_strike + display_regen + display_enemies_reward + display_reward
      
  local text_x_position = cam.x + 15
  if display_stage >= 1 then
    print(smallcaps("pulse strike:\t\t"..display_pulse_strike), text_x_position, cam.y + 30, 7)
  end
  if display_stage >= 2 then
    print(smallcaps("impact strike:\t\t"..display_impact_strike), text_x_position, cam.y + 40, 7)
  end
  if display_stage >= 3 then
    print(smallcaps("regen:\t\t\t\t"..display_regen), text_x_position, cam.y + 50, 7)
  end
  if display_stage >= 4 then
    print(smallcaps("enemies:\t\t\t+"..display_enemies_reward), text_x_position, cam.y + 60, 7)
  end
  if display_stage >= 5 then
    print(smallcaps("mission reward:\t+"..display_reward), text_x_position, cam.y + 70, 7)
  end
  if display_stage >= 6 then
    print("total:\t\t\t\t"..total, text_x_position, cam.y + 85, 7)
  end
  if display_stage >= 7 then
    for i, panel in ipairs(debrief_text_panels) do
      panel.selected = (i == selected_debrief)
      panel:draw()
    end
  end

  debrief_counter = min(debrief_counter + 1, 15*7) 
  if debrief_counter % 15 == 0 then display_stage += 1 end
end


function update_debrief()
  if display_stage >= 7 then
    local num_panels = #debrief_text_panels
    if btnp(⬆️) then
      sfx(19)
      selected_debrief = ((selected_debrief - 2) % num_panels) + 1
    elseif btnp(⬇️) then
      sfx(19)
      selected_debrief = (selected_debrief % num_panels) + 1
    end

    if btnp(❎) then
      credits += total
      if selected_debrief == 1 then
        door_effect.closing = true
      elseif selected_debrief == 2 then
        current_game_state = game_state.mission_select
      end
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
  self.idx = 1
  self.value = values[1]
  self.total_values = 10
  self.selected = false
  return self
end


function slider:draw()
  local total_width = 3 * self.idx - 1
  local start_x, start_y = self.x + cam.x, self.y + cam.y

  -- Draw each rectangle
  for i = 1, self.total_values do
    local color = self.selected and 6 or 5
    if i <= self.idx then
      color = 11
    end
    local rect_x = start_x + (i - 1) * 3
    rectfill(rect_x, start_y, rect_x + 1, start_y + 4, color)
  end
  if self.selected then
    print("⬅️        ➡️", start_x - 9, start_y, 5)
  end
  local color = self.selected and 6 or 5
  print("             "..tostr(self.values[self.idx]), start_x - 9, start_y, color)
end


function slider:update()
  self.value = self.values[self.idx]
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
  self.active = true
  self.x_offset = 0
  self.moving_left = false
  self.moving_right = false
  self.max_offset = width
  return self
end


function textpanel:draw()
  if self.active then
    local drawx = cam.x + self.x + self.x_offset - self.expand_counter
    local drawy = cam.y + self.y
    local adjusted_width = self.width + self.expand_counter * 2
    local drawx2 = drawx + adjusted_width - 2

    rectfill(drawx - 1, drawy - 1, drawx + 2, drawy + self.height + 1, 3)
    rectfill(drawx2, drawy - 1, drawx2 + 3, drawy + self.height + 1, 3)
    rectfill(drawx, drawy, drawx + adjusted_width, drawy + self.height, 0)

    local text_color = self.selected and 11 or 5
    print(smallcaps(self.textline), cam.x + self.x + self.x_offset + 2, drawy + 2, text_color)
  end
end


function textpanel:update()
  if self.selected then
    self.expand_counter = min(3, self.expand_counter + 1)
  else
    self.expand_counter = max(0, self.expand_counter - 1)
  end

  if self.moving_left then
    if self.x_offset > -self.max_offset then
      self.x_offset -= self.max_offset / 5
    else
      self.moving_left = false
      self.moving_right = true
    end
  elseif self.moving_right then
    if self.x_offset < 0 then
      self.x_offset += self.max_offset / 5
    else
      self.moving_right = false
    end
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

  local rect_y1, rect_y2 = cam.y, 128 + cam.y
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
  -- copy_map_into_memory(mission1)

  entities = {}
  for params in all(missions_entities_params[selected_mission]) do
    add(entities, entity:new(unpack(params)))
  end

  laser_doors = {}
  for params in all(mission_laser_doors_params[selected_mission]) do
    add(laser_doors, laser_door:new(unpack(params)))
  end

  update_player_copy()

  -- Apply stats to player
  player = get_controlled_entity()
  local health = loadout_select_sliders[1].value
  player.max_health, player.health = health, health
  
  local energy = loadout_select_sliders[2].value
  player.max_energy, player.energy = energy, energy

  player.view_radius = loadout_select_sliders[3].value
  
  local ability_actions, attack_force_slider, attack_rate_slider = player.ability_actions, loadout_select_sliders[4], loadout_select_sliders[5]
  ability_actions[1].damage = attack_force_slider.value
  ability_actions[2].damage = attack_force_slider.value * 5

  ability_actions[1].attack_cooldown = attack_rate_slider.value
  ability_actions[2].attack_cooldown = attack_rate_slider.value * 3
  
  local regen_count = loadout_select_sliders[6].value
  ability_actions[3].current_ammo = regen_count
  ability_actions[3].max_ammo = regen_count

  emitters, barrels, interfaces = {}, {}, {}
  interface_textline_idx = 1
  for map_y = 0, 127 do 
    for map_x = 0, 127 do
      local tile = mget(map_x, map_y)
      if fget(tile, 7) then
        add(emitters, emitter:new(map_x * 8 - 4, map_y * 8 + 2))
      elseif fget(tile, 6) then
        add(barrels, barrel:new(map_x * 8, map_y * 8))
      elseif fget(tile, 5) then
        local textline = mission_interfaces_textlines[selected_mission][interface_textline_idx]
        add(interfaces, interface:new(map_x * 8, map_y * 8, textline))
        interface_textline_idx += 1
      end
    end
  end

  projectiles = {}
  particles = {}
  view_radius = player.view_radius

  -- debrief
  debrief_counter = 0
  display_stage = 1
  total_enemies = #entities - 1
  enemies_killed = 0
  enemies_reward = 0
  music(0)
end


-- GAMEPLAY
------------------
function update_gameplay()
  printh(time())
  local all_entities = {
    entities, projectiles, particles, emitters, 
    laser_doors, barrels, interfaces, {cam, player_hud}
  }

  for group in all(all_entities) do
    foreach(group, function(e) e:update() end)
  end

  check_losing_condition()
  check_winning_condition()
end


function draw_gameplay()
  reset_palette_and_transparency(true)
  map(0, 0, 0, 0, 128, 56)

  foreach(entities, function(e) e:draw_underlay() end)

  local all_entities = {entities, projectiles, interfaces, emitters, barrels}
  for group in all(all_entities) do
    foreach(group, function(e) e:draw() end)
  end
  
  map(0, 0, 0, 0, 128, 56, 2)
  foreach(entities, function(e) e:draw_overlay() end)
  foreach(laser_doors, function(l) l:draw() end)
  foreach(particles, function(p) p:draw() end)
  draw_shadow(player_copy.x - cam.x + 5, player_copy.y - cam.y + 5, view_radius, swap_palette)
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
  if not get_controlled_entity() then
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
    
    add(particles, particle:new(self.x, self.y, p_vx, p_vy, 15 + rnd(10), 0))
  end
end


function projectile:check_entity_collision()
  local steps = max(abs(self.vx), abs(self.vy))
  local step_x, step_y = sgn(self.vx), sgn(self.vy)  
  for i = 1, steps do
    local check_x, check_y = self.x + (i * step_x), self.y + (i * step_y)
    for group in all({entities, barrels}) do
      for e in all(group) do
        if e != self.creator and 
            check_x < e.x + e.width and e.x < check_x + 1 and 
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
    if tile_check(self.x + (i * step_x), self.y + (i * step_y)) then
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
  patrol = "patrol",
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
  self.acceleration = entity_stats.accelleration
  self.destroy_reward = entity_stats.destroy_reward
  self.stopping_friction = 0.4
  self.mass = 1
  self.facing_angle = 0
  self.visibility_range = 55
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
  self.controlled = controlled == 'true' 

  self.idle_frames = {lr = {0, 1}, up = {32, 33}, down = {16, 17}, duration = .5}
  self.move_frames = {lr = {2, 3}, up = {34, 35}, down = {18, 19}, duration = .1}
  self.animation_frame = 1

  self.frame_counter = 0
  self.energy_recharge_rate = 2

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
      energy_cost = 20,
      radius = 1,
      damage = self.attack_power
    },
    {
      action = entity.shoot,
      description = "Impact Strike",
      current_ammo = 50,
      max_ammo = 50,
      current_cooldown = 0,
      attack_cooldown = self.attack_cooldown * 3,
      projectile_speed = 5,
      energy_cost = 150,
      radius = 2,
      damage = self.attack_power * 5
    },
    {
      action = entity.health_recharge,
      description = "Regen Field",
      current_ammo = 3,
      max_ammo = 3,
      regen = 200
    }
  }

  return self
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
    sfx(18)
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
    sfx(10)
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
  self:check_outside()
end


function entity:inflict_damage(damage)
  self.health, self.hit_flash_timer = max(0, self.health - damage), 1
  
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
  
  if self.damage_timer == 0 and tile_check(self.x, self.y, 2) then
    sfx(14,0)
    self:inflict_damage(2)
    self.damage_timer = 5
  end
end


function entity:check_outside()
  if tile_check(self.x, self.y, 3) and self.controlled then
    self.energy = max(self.energy - 7, 0)
    local p = particle:new(cam.x + rnd(128), cam.y + rnd(128), rnd(1), 1, rnd(128) , 0, 5)
    add(particles, p)
  end
end


function entity:process_death_conditions()
  if self.health == 0 then
    spawn_death_particles(self.x, self.y)
    del(entities, self)
    enemies_killed += 1
    if not self.controlled then enemies_reward += self.destroy_reward end
  end
end


function entity:player_target_enemy()
  self.target.x, self.target.y = self.x, self.y
  for e in all(entities) do
    if not e.controlled and self:can_see(e) then
      self.target.x, self.target.y = e.x + e.width / 2, e.y + e.height/2
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
  elseif self.frame_counter >= rnd(30) + 10 then
    self:move_target_randomly()
    self.frame_counter = 0
  else
    self:move_towards_target_unless_close(1)
    self.frame_counter += 1
  end
end


function entity:move_towards_target_unless_close(distance)
  if not is_close_to(self, self.target, distance) then
    local angle = atan2(self.target.x - self.x, self.target.y - self.y)
    self.ax, self.ay = cos(angle) * self.acceleration * 0.7, sin(angle) * self.acceleration * 0.7
  else
    self.ax, self.ay = 0, 0
  end

  if  self.current_state == enemy_state.alert and
      self.vx ~= 0 and self.vy ~= 0 and
      self.x == self.prev_x and self.y == self.prev_y then
      -- printh("Stuck | Pos: ("..tostr(self.x)..","..tostr(self.y)..") | Prev Pos: ("..tostr(self.prev_x)..","..tostr(self.prev_y)..") | Velocity: ("..tostr(self.vx)..","..tostr(self.vy)..") | New Accel: ("..tostr(self.ax)..","..tostr(self.ay)..")")
      self.ax, self.ay = cos(rnd(1)) * 3, sin(rnd(1)) * 3
  end

  self.prev_x, self.prev_y = self.x, self.y
end


function entity:alert_behavior(can_see_player)
  if can_see_player then
    if not is_close_to(self, self.target, 50) then
      self:move_towards_target_unless_close(0)
    else
      self.current_state = enemy_state.attack
    end
  else
    if is_close_to(self, self.target, 1) then 
      self.current_state = enemy_state.search
    end
    self:move_towards_target_unless_close(1)
  end
end


function entity:attack_behavior(can_see_player)
  if not can_see_player or not is_close_to(self, self.target, 50) then
    self.current_state = enemy_state.alert
  else
    self.ability_actions[self.current_ability_index].action(self)
    self:circle_player()
  end
end


function entity:circle_player()
  local angle_to_target = atan2(self.target.x - self.x, self.target.y - self.y)
  if self.circle_player_timer % 30 == 0 then
    self.circle_direction = rnd(1) < 0.5 and -0.25 or 0.25
  end

  local circle_angle = (angle_to_target + self.circle_direction) % 1
  self.ax, self.ay = sin(circle_angle), cos(circle_angle)
  self.circle_player_timer += 1
end


function entity:move_target_randomly()
  local new_x, new_y = self.x + rnd(17) - 8, self.y + rnd(17) - 8
  if not tile_check(new_x, new_y) then
    self.target.x, self.target.y = new_x, new_y
  end
end





function entity:can_see(target)
  if not target then return false end
  local corners = {
    {dx = 0, dy = 0}, -- Top-left corner
    {dx = self.width - 1, dy = 0}, -- Top-right corner
    {dx = 0, dy = self.height - 1}, -- Bottom-left corner
    {dx = self.width - 1, dy = self.height - 1} -- Bottom-right corner
  }

  for corner in all(corners) do
    local start_x, start_y = self.x + corner.dx, self.y + corner.dy
    local end_x, end_y = target.x + corner.dx, target.y + corner.dy
    local dx, dy = end_x - start_x, end_y - start_y

    if dist_trig(dx, dy) > self.visibility_range then
      return false
    end

    local max_steps = max(abs(dx), abs(dy))
    local step_x, step_y = dx / max_steps, dy / max_steps
    
    local check_x, check_y = start_x, start_y
    for i = 0, max_steps do
      if tile_check(check_x, check_y) then
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

  local max_velocity, threshold = 4, 0.1
  dist = dist_trig(self.vx, self.vy)
  if dist > max_velocity then
    self.vx, self.vy = self.vx * max_velocity / dist, self.vy * max_velocity / dist
  elseif abs(self.vx) < threshold and abs(self.vy) < threshold then
    self.vx, self.vy = 0, 0
  end

  local function apply_force(other)
    local force_x, force_y = self.vx / self.mass, self.vy / self.mass
    other.vx, other.vy = other.vx + force_x * other.mass, other.vy + force_y * other.mass
  end

  local function check_collision(next_x, next_y)
    -- Check map collision
    if tile_check(next_x, next_y) or
        tile_check(next_x + self.width - 1, next_y) or
        tile_check(next_x, next_y + self.height - 1) or
        tile_check(next_x + self.width - 1, next_y + self.height - 1) then
      return true
    end

    -- Check Laser Door collision
    for laser_door in all(laser_doors) do
      if laser_door.active then
        local collision = check_entity_collision(
          next_x, next_y, 
          self.width - 1, self.height - 1, 
          laser_door.x + 8, laser_door.y, 
          1, laser_door.end_y - laser_door.y
        )
        if collision then
          return true
        end
      end
    end
    return false
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
  
  local close_to_emitter, active_emitter = false, nil
  for emitter in all(emitters) do
    if emitter.current_height != emitter.max_height and
      is_close_to(self, emitter, emitter.attract_distance) then
      close_to_emitter = true
      active_emitter = emitter
      break
    end
  end

  local close_to_interface, active_interface = false, nil
  for interface in all(interfaces) do
    if is_close_to(self, interface, interface.attract_distance) then
      close_to_interface = true
      active_interface = interface
      active_interface.active = false
      break
    end
  end
  
  local gameplay_panel = player_hud.gameplay_panel
  gameplay_panel.active = close_to_emitter or close_to_interface
  gameplay_panel.selected = close_to_emitter or close_to_interface
  if close_to_emitter then
    gameplay_panel.textline = "❎ (hold) to operate "
  elseif close_to_interface then
    gameplay_panel.textline = "❎ to operate "
  end

  local width = #gameplay_panel.textline * 4
  gameplay_panel.width = width
  gameplay_panel.x = (128 - width)/2
  
  if btn(❎) then
    if close_to_emitter then
      active_emitter.current_height += active_emitter.rise_speed
    elseif close_to_interface then
      gameplay_panel.textline = active_interface.textline
      local width = #gameplay_panel.textline * 4
      gameplay_panel.width = width
      gameplay_panel.x = (128 - width)/2
      active_interface.active = true
    else
      self.ability_actions[self.current_ability_index].action(self)
    end
  end

  if btnp(🅾️) then
    self:cycle_ability()
  end
  self.ax, self.ay = ax, ay
end


function entity:cycle_ability()
  player_hud.ammo_panel.moving_left, player_hud.ability_panel.moving_left = true, true

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
  local frames = velocity_magnitude > 0.1 and self.move_frames or self.idle_frames
  frame_duration = frames["duration"]

  local cos_val, sin_val = cos(self.facing_angle), sin(self.facing_angle)
  
  current_frames = cos_val > 0 and frames["down"] or frames["up"]
  if abs(cos_val) < abs(sin_val) then current_frames = frames["lr"] end

  -- Update animation frame
  self.animation_timer += .0333
  if self.animation_timer >= frame_duration then
    self.animation_timer -= frame_duration
    self.animation_frame = (self.animation_frame % #current_frames) + 1
  end

  local frame, flip = current_frames[self.animation_frame], self.facing_angle < 0.5

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
  local x_offset, y_offset = 0, -8
  if self.base_class == "preacher" then
    x_offset, y_offset = 5, -23
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

    local x_offset, y_offset = 0, 10
    if self.base_class == "preacher" then
      x_offset, y_offset = 4, 16
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

    -- -- Draw the target indicator
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
    --     if tile_check(flr(check_x), flr(check_y)) then
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


-- Laser Door
--------------
laser_door = {}
laser_door.__index = laser_door
function laser_door:new(x, y, color)
  local self = setmetatable({}, laser_door)
  self.x, self.y, self.end_y = x, y, y + 16
  self.color = color
  self.active = true

  while not tile_check(self.x + 7, self.end_y) do self.end_y += 1 end
  return self
end


function laser_door:draw()
  spr(14, self.x, self.y, 2, 2)
  if self.active then
    for i = 0, 2 do
      line(
        self.x + 7 + i * 2, 
        self.y + 12 - i * 4, 
        self.x + 7 + i * 2, 
        self.end_y + 2 + i * 4, 
        self.color)
    end
  end
end


function laser_door:update()
end


-- Emitter
----------
emitter = {}
emitter.__index = emitter
function emitter:new(x, y)
  local self = setmetatable({}, emitter)
  self.x, self.y = x, y
  self.attract_distance = 30
  self.rise_speed = .25
  self.current_height = 5
  self.max_height = 15
  self.blink_timer = 0
  self.active = false
  return self
end


function emitter:update()
  self.active = self.current_height == self.max_height

  for i, emitter in ipairs(emitters) do
    if self == emitter then
      local laser_door = laser_doors[i]
      laser_door.active = not self.active
      self.color = laser_door.color
    end
  end
end


function emitter:draw()
  local visible_height = min(self.current_height, self.max_height)
  self.blink_timer += 1
  
  if self.current_height == self.max_height then
    local color = self.color
    pal(6, color)
    pal(7, color)

    local h, k = self.x + 4, self.y - 1
    local a = visible_height + 6 + sin(time()) * 1.3

    local b = a / 2
    local a_sq, b_sq = a^2, b^2
    for x = h - a, h + a do
      local x_minus_h_sq = (x - h)^2
      local y_range = sqrt((1 - x_minus_h_sq/a_sq) * b_sq)
      local y_min, y_max = flr(k - y_range) + 1, flr(k + y_range)

      for y = y_min, y_max do
        if pget(x, y) == 6 then
          pset(x, y, color)
        end
      end
    end
  end 
  sspr(80, 16, 8, visible_height, self.x, self.y - visible_height + 1)
  pset(self.x, self.y, 6)
  pset(self.x + 7, self.y, 6)
  reset_palette_and_transparency()
end


-- Interface
----------
interface = {}
interface.__index = interface
function interface:new(x, y, textline)
  local self = setmetatable({}, interface)
  self.x, self.y = x, y
  self.sprites = {50,51,52,53,53,53,54,55}
  self.attract_distance = 30
  self.textline = textline
  self.active = false
  return self
end


function interface:update()
end


function interface:draw()
  if is_close_to(self, player_copy, self.attract_distance) then
    local col = self.active and 8 or 12
    add(particles, particle:new(self.x + rnd(8), self.y + 4, 0, -1, rnd(10) + 20, 0, col))
  end

  local idx = flr(time() * 6 % #self.sprites) + 1
  local float_offset = sin(time()) * 2
  spr(self.sprites[idx], self.x, self.y - 4 + float_offset)
end

-- Barrel
----------
barrel = {}
barrel.__index = barrel
function barrel:new(x, y)
  local self = setmetatable({}, barrel)
  self.x, self.y = x, y
  self.poison = rnd() > .5
  self.height, self.width = 16, 8
  self.health, self.hit_flash_timer = rnd(100) + 50, 0
  return self
end


function barrel:draw()
  if self.hit_flash_timer > 0 then
    for i = 0, 3 do pal(i, 7) end
    self.hit_flash_timer -= 1
  end
  spr(self.poison and 100 or 122, self.x, self.y - 8)
  spr(116, self.x, self.y)
  reset_palette_and_transparency()
end


function barrel:inflict_damage(damage)
  self.health = max(0, self.health - damage)
  self.hit_flash_timer = 1
end


function barrel:update()
  if self.health == 0 then

    for e in all(entities) do
      if is_close_to(self, e,20) then
        e:inflict_damage(5)
      end
    end

    spawn_death_particles(self.x + 4, self.y)
    del(barrels, self)
    mset(self.x/8, self.y/8, self.poison and 10 or 26)
  end
end


function spawn_death_particles(x, y)
  local particle_count = 25
  for i=1, particle_count do
    local angle, speed = rnd(1), rnd(2) 
    local p_vx, p_vy = cos(angle) * speed, sin(angle) * speed / 2
    local size = flr(rnd(3))
    local p = particle:new(x, y, p_vx, p_vy, 30 + rnd(15), size)
    add(particles, p)
  end
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
  self.x += (player_copy.x - self.x - 64) * self.lerpfactor
  self.y += (player_copy.y - self.y - 64) * self.lerpfactor
  camera(self.x, self.y)
end


-- Player hud
---------------
player_hud = {}
player_hud.__index = player_hud
function player_hud.new()
  local self = setmetatable({}, player_hud)
  self.x, self.y = 2, 27
  self.bar_width, self.bar_height = 3, 50
  self.shake_timer = 0

  self.gameplay_panel = textpanel:new(31, 105, 9, 60, 'test gameplay panel')
  self.ability_panel = textpanel:new(6, 2, 9, 52, '')
  self.ammo_panel = textpanel:new(6, 15, 8, 37, '')

  self.ability_panel.selected = true
  self.ammo_panel.selected = true
  return self
end


function player_hud:draw()
  player = get_controlled_entity()
  if player then
    self.shake_timer = max(0, self.shake_timer - 1)

    local shake_x, shake_y = self.shake_timer > 0 and flr(rnd(3)) - 1 or 0, self.shake_timer > 0 and flr(rnd(3)) - 1 or 0
    local drawx, drawy = self.x + cam.x + shake_x, self.y + cam.y + shake_y
    local drawx_bar_width, drawy_bar_height = drawx + self.bar_width, drawy + self.bar_height

    local health_draw_y = drawy + flr(self.bar_height * (1 - player.health / player.max_health))
    local energy_draw_y = drawy + flr(self.bar_height * (1 - player.energy / player.max_health))
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
    local ability_panel = self.ability_panel
    ability_panel.textline = smallcaps(current_ability.description)
    ability_panel.width = #ability_panel.textline * 4 + 2
    ability_panel:draw()

    local ammo_panel = self.ammo_panel
    ammo_panel.textline = tostr(current_ability.current_ammo).."/"..tostr(current_ability.max_ammo)
    ammo_panel.width = #ammo_panel.textline * 4 + 2
    ammo_panel:draw()

    self.gameplay_panel:draw()
  end
end


function player_hud:update()
  self.gameplay_panel:update()
  self.ability_panel:update()
  self.ammo_panel:update()
end






__gfx__
eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee000000000000000000000000bbbbbbbbeeeedddd6667eeee6b6bb6b666b666666666666600000000eeeeeeeedd6667ee
eeeeeeeeee5777eeee5777eeee5777ee000000000000000000000000b7bbbbbbeeedd66666667eeeb7bb22bb66b666666b666bb600000000eeeeeeedd666667e
ee5777eee577cc7ee577cc7ee577cc7e000000000000000000000000bbbbb7bbeedddd66666667ee61bbb7b66bbbbb666bb66b6600000000eeeeeeed55ddd66e
e577cc7ee777cc7ee777cc7ee777cc7e000000000000000000000000bbb7bbbbeeddd665dddd66ee1bb7bbb26b66bbb6bbbbbb6600030000eeeee11d5d111d6e
e777cc7ee577777ee577777ee577777e000000000000000000000000bbbbbb7beeddd65d1111d6ee1bbbbb72666bbbbbbbbbb66603030000eeee11dd5d181d6e
e577777ee577777e05777770e577077e000000000000000000000000b7bbbbbbe1ddd65d1881d61eb7bbbb2b66bbb7bbb7bbbb6603030300eeee1dd55d111d6e
0577707e0e0ee0e00e0e0ee00eee0ee0000000000000000000000000bbbb7bbb11115d5d1881d611611b7226666bbbbbbbbbb7b600000000eeee1d55dddd6eee
0e0ee0e00e0ee0e0eeee0eee0eeeeee0000000000000000000000000bbbbbbbbe1ddd65d1111d61e66b6b66bb66bbbbbbbbbbbbb00000000eee11d5d111d6eee
eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee6666666666666666eeeeeeeeeeddd665dddd66ee66666666bbbbbbbbbbbbbbbb66666666eee11d5d181d6eee
eeeeeeeeee5777eeee5777eeee5777eee050660e7777777777777776e00000eeeeddd666666666ee666266666bbb7bbb7bbbb7bb66666666ee11dd5d111d6eee
ee5777eee57cc77ee57cc77ee57cc77ee05000007666666666666666e00800eeeeddd566616166ee61662266666bbbbbbbbbbbb666666666ee1dd5ddddd66eee
e57cc77ee77cc77ee77cc77ee77cc77ee050000e766655555555666de00800eeeed0d6606d6066ee166666626bbbbbbbbbbbbbbb66666666ee1d5d111d6eeeee
e77cc77ee577777ee5777770e577777eeeeeeeee766556666665566de00800eeee02d6000d0006ee166666626b6b66b7bbbbb66b66666666e11d5d181d6eeeee
e577777ee577777e05777770e577707ee050660e765566666666556de00000eeee02d000020006ee666666226b6bb6bbbbb6bb6b66666666e11d5d111d6eeeee
057770700e0ee0e00e0ee0ee0eeee0e0e0500000765666666666656de00800eeeee20001520101ee61166226666b66bbbbb6bb6666666666e11d65ddd66eeeee
0eeee0ee0eeee0eeeeeee0ee0eeeeeeee050000e765666666666656de00000eeeee211015222222e666666666666666bbb666b66666666661111d66666eeeeee
eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee765666666666656d11122222eee222225ee1ee2eee1111ee55555555555555550000000dd0000000dddddddd
eeeeeeeeee5772eeee5772eeee5772eeeeeeeeee765666666666656d11122222eeeeee0250eeee2ee111111e555555222255555500000dddddd00000dddddddd
ee5772eee577772ee577772ee577772e0e00000e765666666666656dd112222deeeee112e0ee112e1116611155555521125555550000dddddddd0000dddddddd
e577772ee777777ee777777ee777777e05666600765566666666556d1d1222d2e000010ee0ee1eee011111155555552112555555000dddddddddd000dddddddd
e777777ee577777ee5777770e577777e05000060766556666665566d11dddd22e0eee1eee0ee1eee00111155555555222255555500dddddddddddd00dddddddd
e577777ee577777e05777770e577707e05000000766655555555666d11122222e0eee1eee0ee1eee0700555555555521125555550dddddddddddddd0dddddddd
057770700e0ee0e00e0ee0ee0eeee0e00e00000e766666666666666d11122222eeeee1ee00ee1eee0700575555555521125555550dddddddddddddd0dddddddd
0eeee0ee0eeee0eeeeeee0ee0eeeeeeeeeeeeeee66dddddddddddddd01122220eeeee1ee0eee1eee070057555555552222555555dddddddddddddddddddddddd
eeeeeeeeeeeeeeeeeee00eeeeee00eeeeee00eeeeee00eeeeee00eeeeee00eeeeeeeeeeeeeeeeeee000055755211211255555555dddddddddddddddd66666666
eeeeeeeeeeeeeeeeee0000eeee0000eeee0000eeee0000eeee0000eeee0000eee00000eee00000ee0070555552222222555555550dddddddddddddd067777776
eeeeeeeeeeeeeeeeeecccceeeecccceeeecccceeeecccceeeecccceeeecccceee00a00eee0aaa0ee0700575555555555555555550dddddddddddddd067666666
eeeeeeeeeeeeeeeeeec77ceeee77cceeee7ccceeeecccceeeeccc7eeeecc77eee00a00eee000a0ee00705575555555555555555500dddddddddddd006766666d
eeeeeeeeeeeeeeeeeec7cceeee7ccceeeecccceeeecccceeeeccc7eeeecc7ceee00a00eee00aa0ee070055555555555555555555000dddddddddd0006766666d
ee5eeee5ee1111eeeecccceeeecccceeeecccceeeecccceeeecccceeeecccceee00000eee00000ee0000555555555555555555550000dddddddd00006766666d
eeeeeeeee111111eee0000eeee0000eeee0000eeee0000eeee0000eeee0000eee00a00eee00a00ee00005555555555555222222200000dddddd000006766666d
5eeee5eeee1111eeeee00eeeeee00eeeeee00eeeeee00eeeeee00eeeeee00eeee00000eee00000eee000555e55555555521121120000000dd0000000666ddddd
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
55555555555555531555555555555551eeeeeeee5555555511115555eeee1155eeee11555511eeee5511eeee5555555115555555661161266666666666666666
55555555553335335155555555555515eeddddee5555555511111155eeee1155eeee11555511eeee5511eeee5555551551555555661261166666666666dddd66
55555555333533355515555555555155edbbbbde55555555eeee1111eeee1155eeee11555511eeee5511eeee555551555515555566116112212121216d6666d6
55555555553555555551555555551555db7bbb7d15555555eeeee111eeee1155eeeee1155511eeee511eeeee55551555555155556612611111111111d666666d
55555555533555535555155555515555dbbbbbbd11155555eeeeeeeeeeee1155eeeee1155511eeee511eeeee555155555555155566116666666666661d6666d2
55555555555553335555566666655555dbb7bbbdee116666eeeeeeeeeeee1155eeeee1155511eeee511eeeee5515555555555155661121211212121261dddd26
555555555555335355555666666555551dbbbbd2eee11666eeeeeeeeeeee1155eeee11555511eeee5511eeee5155555555555515661111111111111166122266
55555555555555555555566ee665555511dbdb22eeeeeeeeeeeeeeeeeeee1155eeee11555511eeee5511eeee1555555555555551666666666666666666666666
55555355eeeeeeee5555566ee665555511122222eeeeeeeeeeeeeeeeeeee1155eeeeee115511eeeeeeddddee000000001dddddddddddddd16666666666666666
55555355ee2222ee555556666665555511122222eee11666eeeeeeeeeeee1155eeeeee115511eeeeedddddde00000000111dddddddddd1116676666666677766
53555353e222222e5555566666655555d112222dee116666eeeeeeeeeeee1155eeeeee115511eeeedddddddd000000005511dddddddd115567766666667f7776
53355333e122225e55551555555155551d1222d211155555eeeeeeeeeeee1155eeeeee115511eeeedddddd2d0000000055511dddddd115556007666666770706
55355553e111555e555155555555155511dddd2215555555eeeee111eeeee115eeeee111511eeeeedddd22dd00000000555511dddd1155556660766666777776
55353533e111555e55155555555551551112222255555555eeee1111eeeee111eeeee115111eeeee1ddd22d2000000005555511dd11555556666077666007076
53353535e111555e51555555555555151112222255555555ee111155eeeeee11eeee115511eeeeee11dddd220000000055555511115555556666670666600006
33333535ee1155ee1555555555555551611222265555555511115555eeeeee11eeee115511eeeeee111222220000000055555551155555556666606666666666
b7b78506f3d1d1d5f3f3f3f3f3f3f3d5d1d1d1f30695b40557256515054515453505451515655725156557254515156557253545155705c4750670c1d1f306a4
74b60606060606060606060606060606b6f3d1d1f3f3f3f3f3d1d5d1f3d6e65161d1d4f3e6e6e6e6e6e6e5d1d5d1f2b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7
b7b78606f3d1f6e5f3f3c60606b6f3d55161d1f306a675c6060706060606060706070606060606060606060606060606060607060606b6958506c1d1d1f306a4
b504040404040404040404040404043606f3d1d1f3f3f3f3f3d1d6e6f3d1d15262e6e5f3d1d1d1d1d1d1d1d1d5d1f2b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7
b7b78506f3d1d1d1f3f306263606f3d65262d1f306a68706f3f3f3f3f3f3f3f3f3f3f3f3f3f3f37272f3f3f3f3f3f3f3f3f3f347474706977416f3d1d1f306a5
b405050505050505050505050505c47406f3d1d1c60606b6f3d1d1d1f3d1d1d1d1d1d1f3d1d1d1f3f3f3d4e6e5f3f2b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7
00007416f3f3f3f3f3f306948606f3d1d1d1d1f306a58606f3d1d1d1d1d1d1d1d1d1d1d1f3f3f3f3f3f3f3d1d1d1d1d1d1d1d1d1d1f316967506f3d1d1f306a5
74c60606060606060606060606b6947406f3d1d106263606f3d1d1d1d1f3d1d1d1d1f3d1d1d1d1f3c60606060606c7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7
000085b6070706b6f3f306948606f3f3f3f3727206a58606f3d1d1d1f3f372f3f3d1d1d1f3c6060606b6f3d1d1f3f3f3f3f3f3d1d1f316968706f3d1d1f3b694
7406f3f3f3f3f3f3f3f3f3f3f306947406f3d1d106947406f3d1d1d1d4e5f3f3f3f3d1d1d4e6e6e606260404040444b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7
0000b52434243606f3f3069485b6070706070706c6a485b6f4f2f2f2f50606b6f3d1d1d1f306262436b6f3d1d1f3f3f3f3f3f3d1d1f306977506f3d1d1f30695
7406f3d1d1d1d1d1d1d15161f306947406f3d1d106947406f3d1d1d1d5d1d1d1d1d1d1d1d5d1d1f30694b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7
b4456567655737b2f3f30694b50434240434343424c5b544d3f2f2f2e3243606f3d1f6d1f316a4b77406f3d1d1f347d1d1d1f3d1d1f306a68716f3d1d1f306a6
7406f3d1d1d1d1d1d1d15262f306947406f3d1d106947406f3d1d1d1d5d1d1d1d1d1d1d1d5d1d1f30694b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7
75c60607060606c6f3f30627355705c4b7b7b7b7b7b7b7b7b7b7b7b7b7b77506f3d1d1d1f316a4b77406f3d1d1f34747d1d1f3d1d1f306978606f3d1d1f306a6
7406f3d1f3f3f3f3f3f3f3f3f306947406f3f3f306947406f3f3f3f3d5f3f3f3f3f3f3f3d5f3f3f30694b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7
85067272f3d5f3f3f3f3b6060706b695b7d0b7b7b7b7b7b7b7d0b7b7b7b7870672f3f3f3f316a4008416f3d1d1f3d1d1d1d1f3d1d1f306a5850672d1d1b006a5
7406f3d1f3c606060606060606c69474b6060606c69474b6060606060606b6f3f3c6060606060606c694b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7
8506f3d1d1d5d1d1f3f3f3f3f3f3f4e2b7b7b7d0b7b7b7b7b7b7b7b7b7b785b60607060606c6a5b78416f3d1d1f3f3f3f3f3f3d1d1f316968606f372b07006a4
7406f3d1f3062604040404040404c5b50404040404c5b50404040404043606f3f30626040404040404c5b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7
8606f3d1f6e5d1d1f3f3d1d1d1d1f2f2b7b7b7b7b7b7d0b7b7b7b7d0b7b7b504344454546424c5b77416f3d1d1d1d1d1d1d1d1d1d1f316968506f3d1b17006a4
7406f3d1f30694b40505050505050505050505050505000000b40505053706f3f306270505050505050505c4b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7
8506f3d1d1d1d1d1f3f3d1d1d1d1f2f2b7b7d0b7b7b7b7b7b7b7b7b7b7b717b7b7b7b7b7b7b7b7b7761647d1d1d1d1d1d1d1d1d1d1f306977416f3d1d1b106a5
7406f3d1f3069474c6060606060606060606060606060505c474c6060606c6f3f3b60606060606060606b694b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7
7416f3f3f3f3f3f3f3f3f3f3f3f3c7e3b7b7b7b7b7b7b7b7b40545655567572565151545052535c48506f347f347f3f3d1d1d1f3f34706a577b2e6e6e4f306a6
7406f3d1f306947406f3f3f3f3f3f3f3f3f3f3f3f3f306b6947406f3f3f3f3f3f3f3f3f3f3d5f3f3f3f30694b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7
85b6070706060606060706060607c6a5b7b7b7b7b7b7d0b775c6060606c30607060606070606b69574b60606060606f4f2f2f2f50607c6948516f3d1d5f306a5
7406f3d1f306947406f3d1d1d1d1d1d1d1d1d1d1d1d1f306947406f3d1d1d1d1d1d1d1d1d1d6e65161f30694b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7
b52434244464646656346466563456c5171717171717171785067070c1d5f3f3f3f3f3f3727206a5b5040404040444d3f2f2f2e3563456c58516f3d1d5f30697
7406f3d1f306947406f3f3f3f3f3f3f3f3f3f3f3f3f3f306947406f3d1d1d1d1d1d1d1d1d1d1f35262f30694b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7
0000000000d000000000b7b7b7b7b7b40545655555675725371670c1d1d5d1d1d1d1d1d1d1f306270505355705c4000000000000000000007706f3d1d6e6c2a5
7406f3d1f3069474b606b6f3f3c606060606b6f3f3c606c6947406f3f3f3f3f3f3f3f3f3f3f3f3f3f3f30694b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7
d0b7b7b7b7b7b7b7b7b7b7b7b7b7b775c6060606c306060706c6c1d1d1d5d1d1d1d1d1d1d1f3b60606060706b695000000000000000000008516f3d1d1f31696
7406f3d1f30694b5043606f3f3062604043606f3f3062604c57406f3f3c6060606060606060606060606c694b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7
b7b7d0b7b7b7d0b7b7d0b7b7b7d0b7770672f3f3d5f3f3f3f3f3f3d1d1d5d1d172d1d1d1d1f3f3f372f3f3f3f4e2b7b7b7b7b7b7b75557053706f3f3f3f316a5
7406f3d1f3062705053706f3f3062705c47406f3f3062705053706f3f30626040404040404040404040404c5b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7
b7b7b7d0b7b7b7b7b7b7b7b7b7b7b78416f35161d5d1d1d1d1d1d1d1d4e57272d1d1d1d1d1f3d1d1d1d1d1d1f2f2b7b7b7b7b7b7d2f5060606c6f3f3c606c694
7406f3d1f3b606060606c6f3f3b606b6947406f3f3b606060606c6f3f30694b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7
b7b7b7b7b7b7b7b7b7b7b7b7d0b7b77516f35262e5f3f3f3f3f3f3d1d5d1d1d1d1d1d1d1d1f3d1d1d1d1d1d1f2f2b7b7b7b7b7b7f2f2f3f3f3f3f3f3062604c5
7406f3d1f3f3f3f3f3f3f3f3f3f3f306947406f3f3f3f3f3f3f3f3f3f30694000000000000000000000000000000000000b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7
b7b7b7b7d0b7b7b7b7b7b7b7b7b7b77706f3d1d1d1f3c60606b6f3d1d5d1d1d1d1d1d1d1d1f3f3f3f3f3f3f3c7e3b7b7b7b7b7b7f2f2d1d1d1d1f3f30695b7b7
7406f3d1d1d1d1d1d1d1d1d1d1d1f306947406f3f3d1d1d1d1d1d1f3f30694000000000000000000000000000000000000b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7
b7d0b7b7b7b7b7b7d0b7b7b7b7d0b77606f3f3f3727206263606f3f3d5f3f3f3f3f3f3f3f3f3c60606060607c6a5b7b7b7b7b7b7f2f2f3f3f3f3f3f30696b7b7
7406f3f3f3f3f3f3f3f3f3f3f3f3f306947406f3f3f3f3f3f3f3f3f3f30694000000000000000000000000000000000000b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7
b7b7b7b7b7b7b7b7b7b7b7b7b7b7b785b60607070606c69485b60606b3060607070606060607c6260404563456c5b7b7b7b7b7b7d3d7060606070606c6a5b7b7
74b606060606060606060606060606c69474b606060606060606060606c694000000000000000000000000000000000000b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7
b7d0b7b7b7b7b7b7b7b7b7b7b7b7b7b524343404445604c5b52404546464545634044466563424c5b7b7b7b7b717171717171717176656045634245624c5b7b7
b5040404040404040404040404040404c5b5040404040404040404040404c5b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7
eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee3eeeeeeeeeeeeeeeeeeee
eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee33eeeeeeeeeeeeeeeeeeee
333333333333333333333333e33333333e33333333e33333333e33333333ee33eeeeeeee33333333e33eeeeeeee33333333e33eeee33e33333333e33333333ee
333333333333333333333333e33333333e33333333e33333333e33333333ee33eeeeeeee33333333e333eeeeeee33333333e33eeee33e33333333e33333333ee
eeeeee33eeeeee3333eeee33eeee33eeee33eeee33e33eeeeeee33eeee33ee33eeeeeeeeeeeeeeeee3333eeeeee33eeeeeee33eeee33eeeeeeeeeeeeeeee33ee
333333333333333333eeee33eeee33eeee33eeee33e33eeeeeee33eeee33ee33eeeeeeee33333333e33333eeeee33eeeeeee33333333e33333333e33333333ee
333333333333333333eeee33eeee33eeee33eeee33e33eeeeeee33eeee33ee33eeeeeeee33333333e33e333eeee33eeeeeee33333333e33333333e33333333ee
33eeeeee33e333ee33eeee33eeee33eeee33eeee33e33eeeeeee33eeee33ee33eeeeeeeeeeeeeeeee33ee333eee33eeeeeee33eeee33eeeeeeeeee33e333eeee
33eeeeee33ee333e33333333eeee33eeee33333333e33333333e33333333ee33333333ee33333333e33eee333ee33333333e33eeee33e33333333e33ee333eee
33eeeeee33eee33333333333eeee33eeee33333333e33333333e33333333ee33333333ee33333333e33eeee333e33333333e33eeee33e33333333e33eee333ee
33eeeeeeeeeeee33eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee33eeeeeeeeeeeeeeeeeeeeee33ee
3eeeeeeeeeeeeee3eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee3eeeeeeeeeeeeeeeeeeeeeeee3ee
__gff__
0000000000000004000004040400000000000000000101000000400404000000000000000001814100000001010808080000000000000000000000010108080002020202020202020202020202000001020202020202020202020202020000010101020201020202020202010100002101010202410202020202010801010000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__map__
4b5054565555767552565151545052534c7b7b7b004b50535054515156755253545175534c7b7b7b7b4b505053545175534c7b7b7b7b7b7b7b7b7b7b7b7b7b7b4b5050505050505050505050504c4b5050505050505050505050504c717171717171717171717171717171717171717171717171717171717171717171717171
576c6060603c60607060606070603c6b597b7b7b00476c60706060603c6060706060606b497b7b7b7b576c70706060606b597b7b7b7b7b7b7b7b7b7b7b7b7b7b476c606060606060606060606b59476c606060606060606060606b597b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b71
58603f3f3f5d3f3f3f3f3f3f3f3f6d2c5a7b7b7b0048603f3f3f3f3f5d3f3f3f3f3f3f60597b7b7b7b77603f3f3f5d3f606a7b7b7b7b7b7b7b7b7b7b7b7b7b7b47603f3f3f3f3f3f3f3f3f3f607273603f3f3f3f3f3f3f3f3f3f60797b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b71
48613f6f6e5e1d1d1d1d1d1d1d1d3f60725456757573613f6f6e6e6e5e1d1d1d1d1d3f61697b7b7b7b58613f1d1d5d3f605a7b7b7b7b7b7b7b7b7b7b7b7b7b7b47603f1d1d1d1d1d1d1d1d3f6b60606c3f1d1d1d1d1d1d1d1d3f4f2e7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b71
48613f1d1d1d1d1d1d1d1d1d6f4e3f6b6060606060606c3f1d1d1d1d1d1d1d1d1d1d3f60725456565073603f1d6f5e3f6072525252754c7b7b7b7b7b7b7b7b7b47603f1d1d1d1d1d1d1d1d3f3f3f3f3f3f1d1d1d1d1d1d1d1d1d2f2f7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b71
47613f1d1d1d1d1d1d1d1d1d1d5d3f3f3f3f3f3f3f3f3f3f1d1d1d1d1d1d1d1d1d1d3f6b606060603c606c3f1d1d1d3f6b606060606b72757551515675754c7b47603f1d1d1d1d1d1d1d1d3f3f3f3f3f3f1d1d1d1d1d1d1d1d1d2f2f7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b71
572b6e6e6e6e4e1d1d1d1d1d1d5d3f3f3f3f3f3f3f3f3f3f1d1d1d1d1d1d1d1d1d1d3f3f3f3f3f3f5d3f3f3f3f3f3f3f3f3f3f3f3f6b607070606070606b497b47603f1d1d1d1d1d1d1d1d3f6c60606b3f1d1d1d1d1d1d1d1d1d2f2f7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b71
77603f1d1d1d5d1d1d1d1d1d1d5d3f6c6060707070606b3f1d1d1d1d3f3f1d1d1d1d3f3f3f3f3f4d5e3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f743f60597b47603f1d1d1d1d1d1d1d1d3f606263603f1d1d1d1d1d1d1d1d3f7c3e7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b71
67613f1d1d1d6d6e6f1d1d1d1d6d6e2c624665434363603f1d1d1d1d3f3f1d1d1d1d3f6c6060603b606070606060606b3f3f3f3f3f3f3f3f3f3f743f3f606a7b47603f3f3f3f3f3f3f3f3f3f604947603f3f3f3f3f3f3f3f3f3f605a7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b71
67603f3f3f3f3f3f3f3f3f3f3f3f3f614a7b7b7b0057603f1d1d1d1d3f3f1d1d1d1d3f606244666641654342426563603f1d1d1d3f6c607060606b3f3f606a7b476b6060606b3f3f6c6060606c49476b6060606b3f3f6c6060606c497b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b71
586b606060606060707060606060706c4a7b7b7b0067603f1d1d1d1d1d1d1d1d1d1d3f61697b7b7b7b7b7b7b7b0057603f1d6f4e3f6062434063603f3f605a7b5b40404063603f3f60624040405c5b40404063603f3f60624040655c7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b71
5b4240444546464565434044666543425c7b7b7b0067613f1d1d1d1d1d1d1d1d1d1d3f60794b505053545175534c77603f1d1d6d6e2c59000057603f746b497b4b50505073603f3f60725050504c4b50505073603f3f60725050504c7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b71
7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b0077603f1d1d1d1d1d1d1d1d1d1d3f606a576c70706060606b5967603f3f3f3f3f605a000078603f3f60597b476c6060606c3f3f6b6060606b49476c6060606c3f3f6b6060606b497b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b71
4b535275567552755256515154755075525652754c68603f1d1d1d1d1d4d6e6e6e6f3f607977603f3f3f5d3f606a586b60707060606c49000068603f3f606a7b47603f3f3f3f3f3f3f3f3f3f604947603f3f3f3f3f3f3f3f3f3f60497b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b71
476c606060603c6070606060706060603c603c6b4977603f3f3f3f3f3f5d3f3f3f3f3f605a58613f1d1d5d3f605a5b424343404465405c000058603f3f606a7b47603f1d1d1d1d1d1d1d1d3f604947603f1d1d1d1d1d1d1d1d3f60497b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b71
57603f3f3f3f3f1d3f3f3f3f5d1d3f3f3f3f5d6059786b6070606060603b60607060606c5a77603f1d6f5e3f607250547552565151757575757360743f605a7b47603f1d1d1d1d1d1d1d1d3f607273603f1d1d1d1d1d1d1d1d3f60497b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b71
78603f1d1d1d3f1d3f1d1d1d5d1d3f1d1d1d5d61695b40434445454666664165434265425c58613f1d1d1d3f6b606060607060606070707070606c3f3f604a7b47603f1d1d1d1d1d1d1d1d3f6b60606c3f1d1d1d1d1d1d1d1d3f60497b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b71
48603f1d6f1d3f1d3f1d6f6e5e1d3f1d6f6e5e6169004b505053505151567552535451754c77603f3f3f3f3f3f3f3f3f3f27273f3f3f3f3f3f3f74743f604a7b47603f1d1d1d1d1d1d1d1d3f3f3f3f3f3f1d1d1d1d1d1d1d1d3f604900000000000000007b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b
57603f1d5d1d3f1d3f1d1d1d3f1d3f1d1d1d3f607252736c60607060606060607060606b5958613f3f3f3f3f3f3f273f3f3f3f3f3f273f3f3f3f3f3f74605a7b47603f15161d1d1d1d1d1d3f3f3f3f3f3f1d1d1d1d1d1d1d1d3f60494b542d2f2f2e754c7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b
78603f3f5d3f3f1d3f3f3f3f3f1d3f3f3f3f3f6b6060606c3f3f3f3f07070c3f3f7474607273603f3f6c606060707060606060606070607060606060706c497b47603f25261d1d1d1d1d1d3f6c60606b3f1d1d1d1d1d1d1d1d3f6049476c7c2f2f7d6b497b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b
57603f1d5d1d1d1d1d1d1d1d1d1d1d1d1d1d3f3f273f3f3f3f1d1d1d0707071d741d3f6b60606c3f3f6062446666434044464645654340404044666543405c7b47603f3f3f3f3f3f3f3f3f3f606263603f3f3f3f3f3f3f3f3f3f604947603f1d1d3f60497b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b
782b6e6e5e1d1d1d1d1d1d1d1d1d1d1d1d1d3f3f3f3f273f3f1d1d1d1b07070c1d1d3f3f3f3f3f3f3f60794b50505675525354504c4b5050505050535451534c476b606060606060606060606c49476b606060606060606060606c4947603f3f3f3f60497b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b
68603f1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d3f6c6060706b271d1d1d0b070c1d1d1d3f3f3f3f3f3f3f605a576c6060606070606b4a476c60603c707060606b595b4040404040404040404040405c5b4040404040404040404040405c476b6b3f3f6c6c497b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b
58603f3f3f3f3f1d1d1d1d1d1d1d1d1d1d1d3f60624363613f1d1d1d07071c1d1d1d3f6c60607060606c5a676027273f3f3f3f607273603f3f5d3f3f3f3f60594b5050505050505050504c7b7b7b7b4b50505050504c0000000000005b63603f3f60625c0000000000007b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b
68603f1d6f1d3f1d1d1d1d1d1d1d1d1d1d1d3f606a7147613f1d1d0b07071d1d1d1d3f606265434265425c58603f1d1d1d1d3f6b60606c3f1d5d1d1d1d3f606a476c606060606060606b497b7b7b7b476c6060606b494b50505050505073603f3f60725050505050504c7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b
58603f1d5d1d3f1d1d1d1d1d1d1d1d1d1d1d3f605a7157613f1d1d1d07071d1d1d1d3f60594b505353505073603f1d1d1d1d3f3f3f3f3f3f1d5d1d1d1d3f606a47603f3f3f3f1b072760497b7b7b7b47603f3f3f6049476c6060606060606c3f3f6b6060606060606b497b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b
47613f3f5d3f3f3f3f3f3f3f3f3f3f3f3f3f3f605a7167603f1d1d1d1b071d1d1d1d0b606a476c60606060606c3f1d1d1d1d1d1d1d1d1d1d1d6d6e6e4e3f605a47603f1d1d1d1d1b1c60497b7b7b7b47603f1d1d604947603f3f3f3f5d3f3f3f3f3f5d3f3f3f3f3f60497b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b
586b60703b60606b3f3f6c60606060606070606c49716760071d1d1d271d1d1d1d1d07606a57603f3f3f3f3f3f3f1d1d1d1d3f3f3f3f3f3f1d1d1d1d6d6e2c4947603f1d1d1d1d1d3f60497b7b7b7b47603f1d1d604947603f1d1d1d6d4e1d1d1d1d5d1d1d1d1d3f60497b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b
5b424043446663603f3f606245654466654342405c716761071c1d1d1d271d1d1d1d1b605a67603f1d1d1d1d1d1d1d1d1d1d3f6c60606b3f1d0b1d1d1d3f605947603f1d1d1d1d1d3f60725050505073603f1d1d604947603f1d1d1d1d5d1d1d1d1d5d1d1d1d1d3f60497b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b
7b7b4b50755273613f3f60725050505052505353504c67601c07073f3f3f3f3f3f7474605a58603f3f3f3f3f3f3f3f3f27273f606263603f0b07070c1d3f606a47603f1d1d1d1d1d3f6b6060606060606c3f1d1d604947606e6e4e1d1d5d3f3f3f3f5e1d1d1d1d3f607250505050547b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b
7b7b576c6070606c3f3f6b606060603c607070606b6a586b60607060606060606070606c49476b6060606060607060606060606c4a586b60606b07071d3f606a47603f1d1d1d1d1d3f3f74743f3f3f743f3f1d1d607273603f1d5d1d1d3f1d1d1d1d3f1d1d1d1d3f6b60606060604f7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b
7b7b58603f3f3f5d3f3f3f3f3f3f3f5d3f3f3f3f60595b424044434466654466654342405c5b40426665446665434040404040405c5b4240636007072727605a476074743f3f3f3f3f3f3f3f743f3f3f3f3f1d1d6b60606c3f1d5d1d3f5d1d1d1d1d1d3f1d1d1d3f3f3f5d3f5d3f2f7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b7b
__sfx__
151000000c0730000000000000000c013000000000000000266550d0000e625000000e615000000e615000000c0730000000000000000c013000000c07300000266550d0000e625000000e615000000e61500000
a5100000021450e14502115021450212502115021450e11502145021250211502145021250211502145021150f145031250311503145031250f1150314503115021450e1250211502145021250e1150214502115
c3100000027500e73002710027500272002710027500271002750027300271002750027200271002750027100f750037200371003750037200f7100374003710027500e7300271002750027200e7100275002710
a71000000c0730c0000c033000000c023000000c013000000c003000000000000000000000000000000000000c0730c0000c033000000c023000000c013000000000000000000000000000000000000000000000
151000000c0730000000000000000c013000000c0730c000266550d0000e625000000e625000000e615000000c0730000000000000000c013000000c07300000266550d0000e625000000e615000000e61528600
cd0e000008d500cd5010d5013d5017d5018d5017d5014d500ed5009d5005d5001d5005d5008d500dd5010d5008d500cd5010d5013d5017d5018d5017d5014d5010d500bd5009d5008d5007d5009d500dd500fd50
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
a5100000021450e14502115021450a12502115021450e1150214502125021150a145091250211502145021150f14503125031150a145031250f115031450b115021450a125021150a145021250a1150214502115
a30300002d1212212118121121210e121111030010000100001000010000100001000010000100001000010000100001000010000100001000010000100001000010000100001000010000100001000010000100
d7020000257571b757147570000000001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
d007000037650316502f65029650226501e65019650166501465012640106400e6400903005630036300262000620006200062000620016200162000620006100061000610006100061000610006100061000610
d50e000027d550cd5510d5513d5517d5518d5517d5514d550ed5509d5505d5501d5505d5508d550dd5510d5508d550cd5510d5513d5517d5518d5517d5514d5510d550bd5509d5508d5507d5509d550dd5513d55
cd0e00000cd550fd5513d550cd550fd5512d550cd550fd5510d550cd550fd5513d550cd550fd5514d5512d550cd550fd5513d550cd550fd5512d550cd550fd550ed550cd550fd5513d5516d5515d5514d5512d55
311000000675506755027550275502745027450273502735027250272502715027150271502715027150271507755077550275502755027450274502735027350272502725027150271502715027150271502715
c31000000f7550f755037550375503745037450373503735037250372503715037150975509755097450974501755017550275502755027450274502735027350272502725027150271502715027150271502715
c3100000027500e730027100275002720027100275002710027500273002710027500272002710027500271001750017200171001750017200171001740017100075000720007100075000720007100074000710
010e00000c0730000000000000000c013000000c07300003266550d0000d625000000e6150e6050c6150e6050c0730000000000000000c073000000000000000266550d0000d625000000e6150e6050c6150e600
__music__
01 00175144
00 00184344
00 00170144
00 04185844
00 00171144
00 02034344
02 19034344
03 1a154344
00 03164344
00 02424344

