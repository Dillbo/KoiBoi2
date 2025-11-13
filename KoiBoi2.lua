--              KoiBoi
--       A pond that is alive!
--           ><>       ><>
--         ><>  ><> ><>  ><>
--           ><> ~~~ ><>
--         ><>  ><> ><>  ><>
--           ><>       ><>
--     Any key then any knob


engine.name = 'PolyPerc'
local MusicUtil = require 'musicutil'

-- Global variables
local pond = {}
local koi = {}
local food = {}
local drone_buffer = {}
local menu = {}
local clock_id
local screen_refresh_id
local logo_path -- For the PNG logo path

-- MIDI variables
local midi_in_device
local midi_out_device

-- Constants (pre-calculate common values)
local SCREEN_WIDTH = 128
local SCREEN_HEIGHT = 64
local POND_CENTER_X = 64
local POND_CENTER_Y = 32
local POND_RADIUS = 30
local MAX_KOI = 8
local MAX_FOOD = 32
local DRONE_BUFFER_SIZE = 16
local FOOD_FADE_TIME = 8 -- seconds
local TWO_PI = 2 * math.pi
local COLLISION_THRESHOLD = 9 -- squared distance for faster collision detection
local GAME_TICK = 1/60
local SCREEN_TICK = 1/15

-- FIXED: Note mapping constants
local NOTE_RANGE_SEMITONES = 24 -- 2 octaves
local MIN_RADIUS = 1 -- Root note at 1 pixel from center
local MAX_RADIUS = POND_RADIUS - 1 -- Leave outermost pixel free
local RADIUS_RANGE = MAX_RADIUS - MIN_RADIUS -- 28 pixels for 24 semitones

-- Pre-allocate tables to avoid garbage collection
local temp_pos = {x = 0, y = 0}
local math_cos, math_sin = math.cos, math.sin -- local references for speed
local math_sqrt, math_floor = math.sqrt, math.floor
local math_random = math.random

-- Parameters
local params_initialized = false

-- State
local current_menu_page = -1 -- -1 = instructions, 0 = main screen
local selected_koi = 1
local selected_param = 1 -- For menu parameter selection
local playing = true
local show_instructions = true
local instruction_scroll = 0 -- Scroll offset for instructions

-- Scales
local scales = {
  'major', 'minor', 'dorian', 'phrygian', 'lydian', 'mixolydian', 'locrian',
  'minor pentatonic', 'major pentatonic', 'blues', 'chromatic'
}

-- Initialize parameters
local function init_params()
  if params_initialized then return end
  
  -- Scale & Tempo
  params:add_option("scale", "Scale", scales, 1)
  params:add_number("root_note", "Root Note", 0, 11, 0)
  params:add_number("octave", "Octave", 2, 6, 5) -- CHANGED: 4 → 5
  params:add_control("tempo", "Tempo", controlspec.new(60, 200, 'lin', 1, 120))
  
  -- PITCH MODE - for switching between modes
  params:add_option("pitch_mode", "Pitch Mode", {"Linear", "Scale"}, 2) -- Default to Scale mode
  
  -- Koi Behavior  
  params:add_number("num_koi", "Number of Koi", 1, MAX_KOI, 4) -- CHANGED: 2 → 4
  params:add_control("global_speed", "Global Speed", controlspec.new(0.1, 4.0, 'exp', 0.1, 1.0))
  
  -- PolyPerc Parameters
  params:add_control("cutoff", "Cutoff", controlspec.new(50, 5000, 'exp', 1, 800))
  params:add_control("release", "Release", controlspec.new(0.1, 5.0, 'exp', 0.01, 0.3)) -- CHANGED: 1.0 → 0.3
  params:add_control("amp", "Amplitude", controlspec.new(0.0, 1.0, 'lin', 0.01, 0.5)) -- CHANGED: 0.8 → 0.5
  
  -- Softcut Delay
  params:add_option("delay_division", "Delay Division", {
    "1/32", "1/16", "1/8", "1/8.", "1/4", "1/4.", "1/2", "1/2.", "1/1", "2/1", "4/1"
  }, 6) -- CHANGED: 5 (1/4 note) → 6 (1/4. dotted quarter note)
  params:add_control("delay_feedback", "Delay Feedback", controlspec.new(0.0, 0.95, 'lin', 0.01, 0.45)) -- CHANGED: 0.3 → 0.45
  params:add_control("delay_mix", "Delay Mix", controlspec.new(0.0, 1.0, 'lin', 0.01, 0.4)) -- CHANGED: 0.2 → 0.4
  
  -- Softcut Creative Parameters
  params:add_control("feedback_lfo_rate", "Feedback LFO Rate", controlspec.new(0.1, 2.0, 'exp', 0.01, 0.0)) -- CHANGED: 0.5 → 0.0
  params:add_control("feedback_lfo_depth", "Feedback LFO Depth", controlspec.new(0.0, 0.5, 'lin', 0.01, 0.2))
  params:add_control("delay_filter_cutoff", "Delay Filter Cutoff", controlspec.new(200, 8000, 'exp', 1, 2000))
  params:add_control("delay_filter_q", "Delay Filter Q", controlspec.new(0.1, 2.0, 'lin', 0.01, 0.5))
  params:add_option("delay_reverse", "Delay Reverse", {"Off", "On"}, 1)
  params:add_option("delay_overdub", "Delay Overdub", {"Off", "On"}, 2)
  
  -- Drone parameters
  params:add_control("drone_amp", "Drone Amplitude", controlspec.new(0.0, 0.3, 'lin', 0.01, 0.3)) -- CHANGED: 0.1 → 0.3
  params:add_control("drone_fade_chance", "Drone Fade Chance", controlspec.new(0.0, 1.0, 'lin', 0.01, 0.25))
  params:add_number("drone_buffer_bars", "Drone Buffer Bars", 1, 8, 2)
  params:add_number("drone_buffer_notes", "Drone Buffer Notes", 1, 16, 8)
  params:add_control("drone_cutoff", "Drone Cutoff", controlspec.new(50, 500, 'exp', 1, 200)) -- CHANGED: 150 → 200
  
  -- MIDI Parameters
  params:add_number("midi_in_device", "MIDI In Device", 1, 4, 1)
  params:add_number("midi_out_device", "MIDI Out Device", 1, 4, 1)
  params:add_number("midi_food_channel", "MIDI Food Channel", 1, 16, 1)
  params:add_number("midi_drone_channel", "MIDI Drone Channel", 1, 16, 2)
  params:add_option("midi_input_enable", "MIDI Input", {"Off", "On"}, 2)
  params:add_option("midi_output_enable", "MIDI Output", {"Off", "On"}, 1) -- CHANGED: 2 (On) → 1 (Off)
  
  params_initialized = true
end

-- FIXED: Proper note-to-radius conversion (2 octaves from center)
local function note_to_radius(note)
  local root_note = params:get("root_note")
  local octave = params:get("octave")
  local root_midi_note = root_note + (octave * 12)
  
  -- Calculate semitone offset from root note
  local semitone_offset = note - root_midi_note
  
  -- Clamp to 2-octave range (0-23 semitones)
  semitone_offset = util.clamp(semitone_offset, 0, NOTE_RANGE_SEMITONES - 1)
  
  -- Map linearly to radius: root note (0 semitones) = MIN_RADIUS, top note (23 semitones) = MAX_RADIUS
  local radius = MIN_RADIUS + (semitone_offset / (NOTE_RANGE_SEMITONES - 1)) * RADIUS_RANGE
  
  return radius
end

-- FIXED: Proper radius-to-note conversion (inverse of above)
local function radius_to_note(radius)
  local root_note = params:get("root_note")
  local octave = params:get("octave")
  local root_midi_note = root_note + (octave * 12)
  
  -- Clamp radius to valid range
  radius = util.clamp(radius, MIN_RADIUS, MAX_RADIUS)
  
  if params:get("pitch_mode") == 1 then
    -- Linear mode - direct mapping
    local norm_radius = (radius - MIN_RADIUS) / RADIUS_RANGE
    local semitone_offset = math_floor(norm_radius * (NOTE_RANGE_SEMITONES - 1) + 0.5) -- Round to nearest
    local note = root_midi_note + semitone_offset
    
    return note, radius / POND_RADIUS
  else
    -- Scale mode - quantize to scale
    local scale_name = scales[params:get("scale")]
    local scale_notes = MusicUtil.generate_scale(root_note, scale_name, 3) -- 3 octaves to cover range
    
    -- Map radius to scale position
    local norm_radius = (radius - MIN_RADIUS) / RADIUS_RANGE
    local scale_range = math.min(#scale_notes, NOTE_RANGE_SEMITONES) - 1
    local scale_position = norm_radius * scale_range
    local scale_degree = math_floor(scale_position + 0.5) + 1 -- Round to nearest scale degree
    scale_degree = util.clamp(scale_degree, 1, #scale_notes)
    
    local note = scale_notes[scale_degree] + (octave * 12)
    
    return note, radius / POND_RADIUS
  end
end

-- FIXED: Position to note conversion using proper radius calculation
local function pos_to_note(x, y)
  local dx = x - POND_CENTER_X
  local dy = y - POND_CENTER_Y
  local distance = math_sqrt(dx*dx + dy*dy)
  
  -- Convert distance to note using radius-to-note mapping
  return radius_to_note(distance)
end

-- FIXED: MIDI note to radius conversion using proper mapping
local function midi_note_to_radius(note)
  return note_to_radius(note)
end

-- Add MIDI food to pond - now uses proper radius mapping
local function add_midi_food(note, velocity)
  if #food < MAX_FOOD then
    -- Random angle for variety
    local angle = math_random() * TWO_PI
    
    -- Calculate radius based on MIDI note value using proper mapping
    local radius = midi_note_to_radius(note)
    
    -- Convert to x,y coordinates
    local x = POND_CENTER_X + radius * math_cos(angle)
    local y = POND_CENTER_Y + radius * math_sin(angle)
    
    -- Calculate normalized distance for visualization
    local distance = radius / POND_RADIUS
    
    -- Brightness based on velocity
    local brightness = math.max(5, math_floor(velocity / 127 * 15))
    
    table.insert(food, {
      x = x,
      y = y,
      note = note, -- Keep the original MIDI note
      distance = distance,
      age = 0,
      brightness = brightness,
      eaten = false,
      is_midi = true,
      velocity = velocity
    })
    
    -- Debug output
    local root_note = params:get("root_note")
    local octave = params:get("octave")
    local root_midi_note = root_note + (octave * 12)
    local semitone_offset = note - root_midi_note
    print(string.format("MIDI: %s (note %d, +%d semitones from root) -> radius %.1f", 
          MusicUtil.note_num_to_name(note), note, semitone_offset, radius))
  end
end

-- MIDI input callback
local function midi_note_on(note, velocity)
  if params:get("midi_input_enable") == 2 and velocity > 0 then
    add_midi_food(note, velocity)
  end
end

-- MIDI output functions
local function send_midi_note(note, velocity, channel)
  if params:get("midi_output_enable") ~= 2 then
    return
  end
  
  if not midi_out_device then
    print("No MIDI output device connected")
    return
  end
  
  if not note or not velocity or not channel then
    print("Invalid MIDI parameters: note=" .. tostring(note) .. " vel=" .. tostring(velocity) .. " ch=" .. tostring(channel))
    return
  end
  
  local safe_note = util.clamp(math_floor(tonumber(note) or 60), 0, 127)
  local safe_velocity = util.clamp(math_floor(tonumber(velocity) or 64), 1, 127)
  local safe_channel = util.clamp(math_floor(tonumber(channel) or 1), 1, 16)
  
  print("Sending MIDI: note=" .. safe_note .. " vel=" .. safe_velocity .. " ch=" .. safe_channel)
  
  local note_on_data = {0x90 | (safe_channel - 1), safe_note, safe_velocity}
  midi_out_device:send(note_on_data)
  
  clock.run(function()
    clock.sleep(0.1)
    if midi_out_device then
      local note_off_data = {0x80 | (safe_channel - 1), safe_note, 0}
      midi_out_device:send(note_off_data)
    end
  end)
end

-- Helper function to convert note divisions to seconds based on tempo
local function division_to_seconds(division_index)
  local tempo = params:get("tempo")
  local seconds_per_beat = 60 / tempo -- Quarter note duration
  
  local divisions = {
    1/8,     -- 1. 1/32 note (1/8 of quarter note)
    1/4,     -- 2. 1/16 note (1/4 of quarter note)
    1/2,     -- 3. 1/8 note (1/2 of quarter note)
    0.75,    -- 4. 1/8. dotted eighth note (1/2 * 1.5 = 0.75)
    1,       -- 5. 1/4 note (quarter note)
    1.5,     -- 6. 1/4. dotted quarter note (1 * 1.5)
    2,       -- 7. 1/2 note (half note)
    3,       -- 8. 1/2. dotted half note (2 * 1.5)
    4,       -- 9. 1/1 note (whole note)
    8,       -- 10. 2/1 note (double whole note)
    16       -- 11. 4/1 note (quadruple whole note)
  }
  
  return seconds_per_beat * divisions[division_index]
end

-- Get current delay time in seconds based on tempo and division
local function get_delay_time()
  return division_to_seconds(params:get("delay_division"))
end

-- Initialize MIDI
local function init_midi()
  print("Initializing MIDI...")
  
  if midi_in_device then
    midi_in_device.event = nil
  end
  midi_in_device = nil
  midi_out_device = nil
  
  local in_device_id = params:get("midi_in_device")
  print("Connecting MIDI input device: " .. tostring(in_device_id))
  if in_device_id and in_device_id > 0 then
    midi_in_device = midi.connect(in_device_id)
    if midi_in_device then
      midi_in_device.event = function(data)
        if data and #data >= 3 then
          local status = data[1]
          local note = data[2]
          local velocity = data[3]
          
          if (status & 0xF0) == 0x90 and velocity > 0 then
            midi_note_on(note, velocity)
          end
        end
      end
      print("MIDI input connected successfully")
    else
      print("Failed to connect MIDI input device")
    end
  end
  
  local out_device_id = params:get("midi_out_device")
  print("Connecting MIDI output device: " .. tostring(out_device_id))
  if out_device_id and out_device_id > 0 then
    midi_out_device = midi.connect(out_device_id)
    if midi_out_device then
      print("MIDI output connected successfully")
    else
      print("Failed to connect MIDI output device")
    end
  end
end

-- Initialize softcut
local function init_softcut()
  softcut.buffer_clear()
  softcut.enable(1, 1)
  softcut.buffer(1, 1)
  softcut.level(1, 1.0)
  softcut.level_input_cut(1, 1, 1.0)
  softcut.level_input_cut(2, 1, 1.0)
  softcut.pan(1, 0)
  softcut.play(1, 1)
  softcut.rec(1, 1)
  softcut.rec_level(1, 1.0)
  softcut.pre_level(1, 0.3)
  softcut.position(1, 1)
  softcut.loop(1, 1)
  softcut.loop_start(1, 1)
  
  -- Set initial delay time based on tempo and division
  local delay_time = get_delay_time()
  softcut.loop_end(1, 1 + delay_time)
  
  softcut.fade_time(1, 0.1)
  
  softcut.filter_dry(1, 1.0)
  softcut.filter_fc(1, params:get("delay_filter_cutoff"))
  softcut.filter_rq(1, params:get("delay_filter_q"))
  softcut.filter_fc_mod(1, 0.0)
  softcut.filter_lp(1, 1)
  softcut.rate(1, params:get("delay_reverse") == 2 and -1 or 1)
end

-- Initialize koi
local function init_koi()
  koi = {}
  local num_koi = params:get("num_koi")
  
  for i = 1, num_koi do
    local angle = math_random() * TWO_PI
    local radius = math_random() * (POND_RADIUS - 5) + 5
    
    koi[i] = {
      angle = angle,
      speed = 1.0,
      radius = radius,
      direction = math_random() > 0.5 and 1 or -1,
      active = true
    }
  end
end

-- Initialize drone buffer
local function init_drone_buffer()
  drone_buffer = {}
  local buffer_size = params:get("drone_buffer_notes")
  for i = 1, buffer_size do
    drone_buffer[i] = {
      note = nil,
      age = 0,
      active = false
    }
  end
  print("Drone buffer initialized with " .. buffer_size .. " slots")
end

-- LFO for feedback modulation
local feedback_lfo_phase = 0

-- Update feedback LFO
local function update_feedback_lfo(dt)
  local lfo_rate = params:get("feedback_lfo_rate")
  feedback_lfo_phase = feedback_lfo_phase + (dt * lfo_rate * TWO_PI)
  if feedback_lfo_phase > TWO_PI then
    feedback_lfo_phase = feedback_lfo_phase - TWO_PI
  end
  
  local lfo_value = math_sin(feedback_lfo_phase)
  local base_feedback = params:get("delay_feedback")
  local lfo_depth = params:get("feedback_lfo_depth")
  local modulated_feedback = util.clamp(base_feedback + (lfo_value * lfo_depth), 0.0, 0.95)
  
  softcut.pre_level(1, modulated_feedback)
end

-- Helper function to convert bars to seconds based on tempo
local function bars_to_seconds(bars)
  local tempo = params:get("tempo")
  local seconds_per_beat = 60 / tempo
  local seconds_per_bar = seconds_per_beat * 4
  return bars * seconds_per_bar
end

-- FIXED: Updated add_food function with proper pitch calculation
local function add_food()
  local num_pieces = math_random(4, 8)
  local food_count = #food
  
  for i = 1, num_pieces do
    if food_count < MAX_FOOD then
      local angle = math_random() * TWO_PI
      local radius = math_random() * (POND_RADIUS - 2)
      
      local x = POND_CENTER_X + radius * math_cos(angle)
      local y = POND_CENTER_Y + radius * math_sin(angle)
      
      -- Use the fixed position-to-note calculation
      local note, distance = pos_to_note(x, y)
      
      food_count = food_count + 1
      food[food_count] = {
        x = x,
        y = y,
        note = note,
        distance = distance,
        age = 0,
        brightness = 15,
        eaten = false,
        is_midi = false,
        velocity = 80
      }
    else
      break
    end
  end
end

-- Add note to drone buffer
local function add_to_drone_buffer(note)
  local fade_chance = params:get("drone_fade_chance")
  if math_random() < fade_chance then
    local buffer_size = params:get("drone_buffer_notes")
    
    local oldest_idx = 1
    local oldest_age = 0
    local found_empty = false
    
    for i = 1, buffer_size do
      if not drone_buffer[i] then
        drone_buffer[i] = {note = nil, age = 0, active = false}
      end
      
      if not drone_buffer[i].active then
        oldest_idx = i
        found_empty = true
        break
      elseif drone_buffer[i].age > oldest_age then
        oldest_age = drone_buffer[i].age
        oldest_idx = i
      end
    end
    
    drone_buffer[oldest_idx] = {
      note = note,
      age = 0,
      active = true
    }
    
    print("Added note " .. note .. " to drone buffer (chance: " .. fade_chance .. ")")
  end
end

-- Play drone note
local function play_drone_note(note)
  if not note or not tonumber(note) then
    return
  end
  
  local safe_note = tonumber(note)
  if safe_note < 0 or safe_note > 127 then
    return
  end
  
  engine.hz(MusicUtil.note_num_to_freq(safe_note))
  engine.cutoff(params:get("drone_cutoff"))
  engine.gain(params:get("drone_amp"))
  engine.release(4.0)
  
  if params:get("midi_output_enable") == 2 then
    send_midi_note(safe_note, 64, params:get("midi_drone_channel"))
  end
end

-- Update food (aging and fading)
local function update_food(dt)
  for i = #food, 1, -1 do
    local f = food[i]
    
    if not f.eaten then
      f.age = f.age + dt
      
      local fade_progress = f.age / FOOD_FADE_TIME
      f.brightness = math.max(1, 15 * (1 - fade_progress))
      
      if f.age >= FOOD_FADE_TIME then
        add_to_drone_buffer(f.note)
        table.remove(food, i)
      end
    else
      table.remove(food, i)
    end
  end
end

-- Update koi positions
local function update_koi(dt)
  local global_speed = params:get("global_speed")
  local speed_dt = dt * 0.5
  
  for i = 1, #koi do
    local k = koi[i]
    if k.active then
      local speed = k.speed * global_speed * k.direction * speed_dt
      k.angle = k.angle + speed
      
      if k.angle > TWO_PI then
        k.angle = k.angle - TWO_PI
      elseif k.angle < 0 then
        k.angle = k.angle + TWO_PI
      end
    end
  end
end

-- Check koi-food collisions
local function check_collisions()
  for ki = 1, #koi do
    local k = koi[ki]
    if k.active then
      local koi_x = POND_CENTER_X + k.radius * math_cos(k.angle)
      local koi_y = POND_CENTER_Y + k.radius * math_sin(k.angle)
      
      for fi = 1, #food do
        local f = food[fi]
        if not f.eaten then
          local dx = koi_x - f.x
          local dy = koi_y - f.y
          local distance_sq = dx*dx + dy*dy
          
          if distance_sq < COLLISION_THRESHOLD then
            local play_note = f.note
            
            if play_note and tonumber(play_note) then
              engine.hz(MusicUtil.note_num_to_freq(tonumber(play_note)))
              engine.cutoff(params:get("cutoff"))
              engine.gain(params:get("amp"))
              engine.release(params:get("release"))
            end
            
            if params:get("midi_output_enable") == 2 then
              local velocity = f.velocity or 80
              
              if play_note and tonumber(play_note) then
                local safe_note = tonumber(play_note)
                if safe_note >= 0 and safe_note <= 127 then
                  send_midi_note(safe_note, velocity, params:get("midi_food_channel"))
                  if f.is_midi then
                    print("MIDI food eaten: " .. MusicUtil.note_num_to_name(safe_note))
                  end
                end
              end
            end
            
            f.eaten = true
            break
          end
        end
      end
    end
  end
end

-- Update drone buffer
local function update_drone_buffer(dt)
  local buffer_size = params:get("drone_buffer_notes")
  local bar_length = bars_to_seconds(params:get("drone_buffer_bars"))
  
  for i = 1, buffer_size do
    if drone_buffer[i] and drone_buffer[i].active then
      drone_buffer[i].age = drone_buffer[i].age + dt
      
      if drone_buffer[i].age >= bar_length then
        play_drone_note(drone_buffer[i].note)
        drone_buffer[i].age = 0
        print("Playing drone note: " .. drone_buffer[i].note .. " (bar length: " .. string.format("%.2f", bar_length) .. "s)")
      end
    end
  end
end

-- DEBUG: Test note mapping function
local function test_note_mapping()
  print("Testing note-to-radius mapping (2 octaves)...")
  local root_note = params:get("root_note")
  local octave = params:get("octave")
  local root_midi_note = root_note + (octave * 12)
  
  print(string.format("Root: %s (MIDI %d) at radius %.1f", 
        MusicUtil.note_num_to_name(root_midi_note), root_midi_note, note_to_radius(root_midi_note)))
  
  -- Test chromatic scale through 2 octaves
  for i = 0, NOTE_RANGE_SEMITONES - 1 do
    local test_note = root_midi_note + i
    local radius = note_to_radius(test_note)
    print(string.format("+%02d: %s (MIDI %d) -> radius %.1f", 
          i, MusicUtil.note_num_to_name(test_note), test_note, radius))
  end
  
  print(string.format("Range: %.1f to %.1f pixels (total: %.1f pixels for %d semitones)", 
        MIN_RADIUS, MAX_RADIUS, RADIUS_RANGE, NOTE_RANGE_SEMITONES))
end

-- Main clock function
local function clock_update()
  while true do
    clock.sleep(GAME_TICK)
    
    if playing then
      update_food(GAME_TICK)
      update_koi(GAME_TICK)
      check_collisions()
      update_drone_buffer(GAME_TICK)
      update_feedback_lfo(GAME_TICK)
    end
  end
end

-- Screen refresh clock
local function screen_refresh()
  while true do
    clock.sleep(SCREEN_TICK)
    redraw()
  end
end

-- Draw koi sprite
local function draw_koi(x, y, angle, selected)
  local brightness = selected and 15 or 10
  
  if selected then
    screen.level(8)
    screen.circle(x, y, 6)
    screen.stroke()
  end
  
  screen.level(brightness)
  
  local cos_a = math_cos(angle)
  local sin_a = math_sin(angle)
  
  screen.pixel(x, y)
  screen.pixel(x + cos_a, y + sin_a)
  screen.pixel(x - cos_a, y - sin_a)
  screen.pixel(x, y + 1)
  screen.pixel(x, y - 1)
  
  local cos_2a = 2 * cos_a
  local sin_2a = 2 * sin_a
  screen.pixel(x - cos_a, y - sin_a)
  screen.pixel(x - cos_2a, y - sin_2a)
  
  local cos_3a = 3 * cos_a
  local sin_3a = 3 * sin_a
  local cos_4a = 4 * cos_a
  local sin_4a = 4 * sin_a
  
  screen.pixel(x - cos_3a, y - sin_3a)
  screen.pixel(x - cos_4a, y - sin_4a)
  screen.pixel(x - cos_3a + sin_a, y - sin_3a - cos_a)
  screen.pixel(x - cos_3a - sin_a, y - sin_3a + cos_a)
  
  screen.fill()
end

-- Draw pond
local function draw_pond()
  screen.level(4)
  screen.move(POND_CENTER_X + POND_RADIUS, POND_CENTER_Y)
  screen.circle(POND_CENTER_X, POND_CENTER_Y, POND_RADIUS)
  screen.stroke()
end

-- Draw food
local function draw_food()
  for i = 1, #food do
    local f = food[i]
    if not f.eaten then
      screen.level(math.floor(f.brightness))
      
      if f.is_midi then
        screen.rect(f.x - 1, f.y - 1, 2, 2)
        screen.fill()
      else
        screen.pixel(f.x, f.y)
        screen.fill()
      end
    end
  end
end

-- Draw koi
local function draw_koi_all()
  for i = 1, #koi do
    if koi[i].active then
      local x = POND_CENTER_X + koi[i].radius * math.cos(koi[i].angle)
      local y = POND_CENTER_Y + koi[i].radius * math.sin(koi[i].angle)
      draw_koi(x, y, koi[i].angle + math.pi/2, i == selected_koi)
    end
  end
end

-- Draw instructions page
local function draw_instructions()
  -- Draw PNG logo at the top (if it exists)
  local logo_y_offset = -instruction_scroll
  
  if logo_path and logo_y_offset > -60 and logo_y_offset < 64 then
    screen.display_png(logo_path, 0, logo_y_offset)
  end
  
  -- Instruction content with y positions (relative to scroll)
  -- Add 60 pixels offset to move text below the logo
  local content = {
    {y = 68, level = 15, text = "KOIBOI - A pond that is alive!"},
    {y = 80, level = 8, text = "By Dillbobo - August 2025"},
    
    {y = 95, level = 10, text = "BASIC CONTROLS:"},
    {y = 105, level = 8, text = "K1: Menu system"},
    {y = 113, level = 8, text = "K2: Play/Pause"},
    {y = 121, level = 8, text = "K3: Add food to pond"},
    
    {y = 135, level = 8, text = "E1: Select koi"},
    {y = 143, level = 8, text = "E2: Change koi radius"},
    {y = 151, level = 8, text = "E3: Change koi speed"},
    
    {y = 170, level = 10, text = "CONCEPT:"},
    {y = 180, level = 8, text = "Koi swim in circles"},
    {y = 188, level = 8, text = "They eat food to make notes"},
    {y = 196, level = 8, text = "Position = pitch"},
    {y = 204, level = 8, text = "Aged food = drones"},
    
    {y = 220, level = 10, text = "FEATURES:"},
    {y = 230, level = 8, text = "8-page menu system"},
    {y = 238, level = 8, text = "Scale/tempo controls"},
    {y = 246, level = 8, text = "Softcut delay effects"},
    {y = 254, level = 8, text = "MIDI input/output"},
    {y = 262, level = 8, text = "Drone layer with filter"},
    
    {y = 280, level = 10, text = "NAVIGATION:"},
    {y = 290, level = 8, text = "Use any encoder to scroll"},
    {y = 298, level = 8, text = "instructions up/down"},
    {y = 310, level = 6, text = "Press K1 or K2 to start!"}
  }
  
  -- Draw visible content based on scroll offset
  for _, item in ipairs(content) do
    local draw_y = item.y - instruction_scroll
    -- Only draw if item is visible on screen
    if draw_y >= 0 and draw_y <= 64 then
      screen.level(item.level)
      screen.move(2, draw_y)
      screen.text(item.text)
    end
  end
end

-- Draw menu
local function draw_menu()
  screen.level(15)
  
  if current_menu_page == 1 then
    screen.move(2, 10)
    screen.text("Scale & Tempo")
    
    if selected_param == 1 then
      screen.level(15)
      screen.rect(6, 20, 4, 4)
      screen.fill()
    end
    screen.level(selected_param == 1 and 15 or 10)
    screen.move(14, 25)
    screen.text("Scale: " .. scales[params:get("scale")])
    
    -- Root note parameter  
    if selected_param == 2 then
      screen.level(15)
      screen.rect(6, 30, 4, 4)
      screen.fill()
    end
    screen.level(selected_param == 2 and 15 or 10)
    screen.move(14, 35)
    screen.text("Root: " .. MusicUtil.note_num_to_name(params:get("root_note")))
    
    -- Octave parameter
    if selected_param == 3 then
      screen.level(15)
      screen.rect(6, 40, 4, 4)
      screen.fill()
    end
    screen.level(selected_param == 3 and 15 or 10)
    screen.move(14, 45)
    screen.text("Octave: " .. params:get("octave"))
    
    -- Tempo parameter
    if selected_param == 4 then
      screen.level(15)
      screen.rect(6, 50, 4, 4)
      screen.fill()
    end
    screen.level(selected_param == 4 and 15 or 10)
    screen.move(14, 55)
    screen.text("Tempo: " .. params:get("tempo"))
    
    -- Pitch Mode parameter
    if selected_param == 5 then
      screen.level(15)
      screen.rect(6, 58, 4, 4)
      screen.fill()
    end
    screen.level(selected_param == 5 and 15 or 10)
    screen.move(14, 62)
    local pitch_mode_text = params:get("pitch_mode") == 1 and "Linear" or "Scale"
    screen.text("Mode: " .. pitch_mode_text)
    
  elseif current_menu_page == 2 then
    screen.move(2, 10)
    screen.text("Koi Behavior")
    
    -- Num koi parameter
    if selected_param == 1 then
      screen.level(15)
      screen.rect(6, 20, 4, 4)
      screen.fill()
    end
    screen.level(selected_param == 1 and 15 or 10)
    screen.move(14, 25)
    screen.text("Koi: " .. params:get("num_koi"))
    
    -- Global speed parameter
    if selected_param == 2 then
      screen.level(15)
      screen.rect(6, 30, 4, 4)
      screen.fill()
    end
    screen.level(selected_param == 2 and 15 or 10)
    screen.move(14, 35)
    screen.text("Speed: " .. string.format("%.2f", params:get("global_speed")))
    
    -- Selected koi info
    screen.level(6)
    screen.move(14, 45)
    screen.text("Selected: " .. selected_koi)
    
    if koi[selected_koi] then
      screen.move(14, 55)
      local signed_speed = koi[selected_koi].speed * koi[selected_koi].direction
      local direction_text = koi[selected_koi].direction == 1 and "CW" or "CCW"
      screen.text("Speed: " .. string.format("%.1f", signed_speed) .. " (" .. direction_text .. ")")
    end
    
  elseif current_menu_page == 3 then
    screen.move(2, 10)
    screen.text("PolyPerc Synth")
    
    -- Cutoff parameter
    if selected_param == 1 then
      screen.level(15)
      screen.rect(6, 20, 4, 4)
      screen.fill()
    end
    screen.level(selected_param == 1 and 15 or 10)
    screen.move(14, 25)
    screen.text("Cutoff: " .. math_floor(params:get("cutoff")))
    
    -- Release parameter
    if selected_param == 2 then
      screen.level(15)
      screen.rect(6, 30, 4, 4)
      screen.fill()
    end
    screen.level(selected_param == 2 and 15 or 10)
    screen.move(14, 35)
    screen.text("Release: " .. string.format("%.2f", params:get("release")))
    
    -- Amp parameter
    if selected_param == 3 then
      screen.level(15)
      screen.rect(6, 40, 4, 4)
      screen.fill()
    end
    screen.level(selected_param == 3 and 15 or 10)
    screen.move(14, 45)
    screen.text("Amp: " .. string.format("%.2f", params:get("amp")))
    
  elseif current_menu_page == 4 then
    screen.move(2, 10)
    screen.text("Softcut Delay")
    
    -- Delay time parameter (now shows note value)
    if selected_param == 1 then
      screen.level(15)
      screen.rect(6, 20, 4, 4)
      screen.fill()
    end
    screen.level(selected_param == 1 and 15 or 10)
    screen.move(14, 25)
    local divisions = {"1/32", "1/16", "1/8", "1/8.", "1/4", "1/4.", "1/2", "1/2.", "1/1", "2/1", "4/1"}
    local current_division = divisions[params:get("delay_division")]
    screen.text("Division: " .. current_division)
    
    -- Feedback parameter
    if selected_param == 2 then
      screen.level(15)
      screen.rect(6, 30, 4, 4)
      screen.fill()
    end
    screen.level(selected_param == 2 and 15 or 10)
    screen.move(14, 35)
    screen.text("Feedback: " .. string.format("%.2f", params:get("delay_feedback")))
    
    -- Mix parameter
    if selected_param == 3 then
      screen.level(15)
      screen.rect(6, 40, 4, 4)
      screen.fill()
    end
    screen.level(selected_param == 3 and 15 or 10)
    screen.move(14, 45)
    screen.text("Mix: " .. string.format("%.2f", params:get("delay_mix")))
    
    -- LFO Rate parameter
    if selected_param == 4 then
      screen.level(15)
      screen.rect(6, 50, 4, 4)
      screen.fill()
    end
    screen.level(selected_param == 4 and 15 or 10)
    screen.move(14, 55)
    screen.text("LFO Rate: " .. string.format("%.2f", params:get("feedback_lfo_rate")))
    
  elseif current_menu_page == 5 then
    screen.move(2, 10)
    screen.text("Softcut Creative")
    
    -- LFO Depth parameter
    if selected_param == 1 then
      screen.level(15)
      screen.rect(6, 20, 4, 4)
      screen.fill()
    end
    screen.level(selected_param == 1 and 15 or 10)
    screen.move(14, 25)
    screen.text("LFO Depth: " .. string.format("%.2f", params:get("feedback_lfo_depth")))
    
    -- Filter Cutoff parameter
    if selected_param == 2 then
      screen.level(15)
      screen.rect(6, 30, 4, 4)
      screen.fill()
    end
    screen.level(selected_param == 2 and 15 or 10)
    screen.move(14, 35)
    screen.text("Filter: " .. math_floor(params:get("delay_filter_cutoff")))
    
    -- Reverse parameter
    if selected_param == 3 then
      screen.level(15)
      screen.rect(6, 40, 4, 4)
      screen.fill()
    end
    screen.level(selected_param == 3 and 15 or 10)
    screen.move(14, 45)
    local reverse_text = params:get("delay_reverse") == 2 and "On" or "Off"
    screen.text("Reverse: " .. reverse_text)
    
    -- Overdub parameter
    if selected_param == 4 then
      screen.level(15)
      screen.rect(6, 50, 4, 4)
      screen.fill()
    end
    screen.level(selected_param == 4 and 15 or 10)
    screen.move(14, 55)
    local overdub_text = params:get("delay_overdub") == 2 and "On" or "Off"
    screen.text("Overdub: " .. overdub_text)
    
  elseif current_menu_page == 6 then
    screen.move(2, 10)
    screen.text("Drone Layer")
    
    -- Buffer bars parameter
    if selected_param == 1 then
      screen.level(15)
      screen.rect(6, 20, 4, 4)
      screen.fill()
    end
    screen.level(selected_param == 1 and 15 or 10)
    screen.move(14, 25)
    screen.text("Bars: " .. params:get("drone_buffer_bars"))
    
    -- Buffer notes parameter
    if selected_param == 2 then
      screen.level(15)
      screen.rect(6, 30, 4, 4)
      screen.fill()
    end
    screen.level(selected_param == 2 and 15 or 10)
    screen.move(14, 35)
    screen.text("Notes: " .. params:get("drone_buffer_notes"))
    
    -- Fade chance parameter
    if selected_param == 3 then
      screen.level(15)
      screen.rect(6, 40, 4, 4)
      screen.fill()
    end
    screen.level(selected_param == 3 and 15 or 10)
    screen.move(14, 45)
    screen.text("Chance: " .. string.format("%.2f", params:get("drone_fade_chance")))
    
    -- Amplitude parameter
    if selected_param == 4 then
      screen.level(15)
      screen.rect(6, 50, 4, 4)
      screen.fill()
    end
    screen.level(selected_param == 4 and 15 or 10)
    screen.move(14, 55)
    screen.text("Amp: " .. string.format("%.2f", params:get("drone_amp")))
    
    -- Cutoff parameter
    if selected_param == 5 then
      screen.level(15)
      screen.rect(6, 58, 4, 4)
      screen.fill()
    end
    screen.level(selected_param == 5 and 15 or 10)
    screen.move(14, 62)
    screen.text("Cutoff: " .. math_floor(params:get("drone_cutoff")))
    
  elseif current_menu_page == 7 then
    screen.move(2, 10)
    screen.text("MIDI Settings")
    
    -- MIDI Input Enable
    if selected_param == 1 then
      screen.level(15)
      screen.rect(6, 20, 4, 4)
      screen.fill()
    end
    screen.level(selected_param == 1 and 15 or 10)
    screen.move(14, 25)
    local input_text = params:get("midi_input_enable") == 2 and "On" or "Off"
    screen.text("Input: " .. input_text)
    
    -- MIDI Output Enable
    if selected_param == 2 then
      screen.level(15)
      screen.rect(6, 30, 4, 4)
      screen.fill()
    end
    screen.level(selected_param == 2 and 15 or 10)
    screen.move(14, 35)
    local output_text = params:get("midi_output_enable") == 2 and "On" or "Off"
    screen.text("Output: " .. output_text)
    
    -- MIDI Input Device
    if selected_param == 3 then
      screen.level(15)
      screen.rect(6, 40, 4, 4)
      screen.fill()
    end
    screen.level(selected_param == 3 and 15 or 10)
    screen.move(14, 45)
    screen.text("In Dev: " .. params:get("midi_in_device"))
    
    -- MIDI Output Device
    if selected_param == 4 then
      screen.level(15)
      screen.rect(6, 50, 4, 4)
      screen.fill()
    end
    screen.level(selected_param == 4 and 15 or 10)
    screen.move(14, 55)
    screen.text("Out Dev: " .. params:get("midi_out_device"))
    
  elseif current_menu_page == 8 then
    screen.move(2, 10)
    screen.text("MIDI Channels")
    
    -- Food Channel
    if selected_param == 1 then
      screen.level(15)
      screen.rect(6, 20, 4, 4)
      screen.fill()
    end
    screen.level(selected_param == 1 and 15 or 10)
    screen.move(14, 25)
    screen.text("Food Ch: " .. params:get("midi_food_channel"))
    
    -- Drone Channel
    if selected_param == 2 then
      screen.level(15)
      screen.rect(6, 30, 4, 4)
      screen.fill()
    end
    screen.level(selected_param == 2 and 15 or 10)
    screen.move(14, 35)
    screen.text("Drone Ch: " .. params:get("midi_drone_channel"))
    
    -- Note Range Display (not selectable, just info)
    screen.level(6)
    screen.move(14, 45)
    local root_note = params:get("root_note")
    local octave = params:get("octave")
    local root_midi_note = root_note + (octave * 12)
    local top_note = root_midi_note + NOTE_RANGE_SEMITONES - 1
    screen.text("Range: " .. MusicUtil.note_num_to_name(root_midi_note) .. " - " .. MusicUtil.note_num_to_name(top_note))
    
    screen.move(14, 55)
    screen.text("(2 octaves: " .. NOTE_RANGE_SEMITONES .. " semitones)")
  end
  
  -- Page indicator
  screen.level(6)
  screen.move(120, 60)
  screen.text(current_menu_page)
end

-- Main redraw function
function redraw()
  screen.clear()
  
  if current_menu_page == -1 then
    -- Instructions screen
    draw_instructions()
    
  elseif current_menu_page == 0 then
    -- Main screen
    draw_pond()
    draw_food()
    draw_koi_all()
    
    -- Status
    screen.level(6)
    screen.move(2, 8)
    screen.text("Koi " .. selected_koi .. "/" .. params:get("num_koi"))
    screen.move(100, 8)
    screen.text(playing and "PLAY" or "PAUSE")
    
  else
    -- Menu screen
    draw_menu()
  end
  
  screen.update()
end

-- Key handlers
function key(n, z)
  if z == 1 then -- key press
    
    -- Instructions screen handling
    if current_menu_page == -1 then
      if n == 1 or n == 2 then
        -- K1 or K2: Exit instructions
        current_menu_page = 0
        show_instructions = false
        instruction_scroll = 0 -- Reset scroll for next time
      end
      redraw()
      return
    end
    
    if n == 1 then
      -- K1: enter/exit menu
      if current_menu_page == 0 then
        current_menu_page = 1
        selected_param = 1
      else
        current_menu_page = 0
      end
      
    elseif n == 2 then
      -- K2: global play/pause OR test note mapping in menu
      if current_menu_page == 0 then
        playing = not playing
      else
        -- DEBUG: Test note mapping when in menu
        test_note_mapping()
      end
      
    elseif n == 3 then
      -- K3: scatter food
      if current_menu_page == 0 then
        add_food()
      end
    end
  end
  
  redraw()
end

-- Encoder handlers
function enc(n, d)
  -- Instructions screen - ANY encoder scrolls
  if current_menu_page == -1 then
    if n == 1 or n == 2 or n == 3 then
      -- Any encoder: Scroll instructions up/down
      instruction_scroll = util.clamp(instruction_scroll + (d * 8), 0, 260)
    end
    redraw()
    return
  end
  
  if current_menu_page == 0 then
    -- Main screen
    if n == 1 then
      -- E1: select koi
      selected_koi = util.clamp(selected_koi + d, 1, params:get("num_koi"))
      
    elseif n == 2 then
      -- E2: change orbit radius
      if selected_koi <= params:get("num_koi") and koi[selected_koi] then
        koi[selected_koi].radius = util.clamp(koi[selected_koi].radius + d, 3, POND_RADIUS)
      end
      
    elseif n == 3 then
      -- E3: change speed
      if selected_koi <= params:get("num_koi") and koi[selected_koi] then
        local current_signed_speed = koi[selected_koi].speed * koi[selected_koi].direction
        local new_signed_speed = util.clamp(current_signed_speed + (d * 0.1), -3.0, 3.0)
        
        if new_signed_speed > 0 then
          koi[selected_koi].speed = new_signed_speed
          koi[selected_koi].direction = 1
        elseif new_signed_speed < 0 then
          koi[selected_koi].speed = -new_signed_speed
          koi[selected_koi].direction = -1
        else
          koi[selected_koi].speed = 0.1
          koi[selected_koi].direction = d > 0 and 1 or -1
        end
      end
    end
    
  else
    -- Menu screen
    if n == 1 then
      -- E1: change menu page
      current_menu_page = util.clamp(current_menu_page + d, 1, 8)
      selected_param = 1
      
    elseif n == 2 then
      -- E2: select parameter
      local max_params = 3
      if current_menu_page == 1 then max_params = 5 end -- Scale & Tempo has 5 params
      if current_menu_page == 2 then max_params = 2 end -- Koi Behavior has 2 selectable params
      if current_menu_page == 4 then max_params = 4 end -- Softcut Delay has 4 params
      if current_menu_page == 5 then max_params = 4 end -- Softcut Creative has 4 params
      if current_menu_page == 6 then max_params = 5 end -- Drone page has 5 params
      if current_menu_page == 7 then max_params = 4 end -- MIDI Settings has 4 params
      if current_menu_page == 8 then max_params = 2 end -- MIDI Channels has 2 params
      selected_param = util.clamp(selected_param + d, 1, max_params)
      
    elseif n == 3 then
      -- E3: adjust selected parameter
      if current_menu_page == 1 then
        -- Scale & Tempo
        if selected_param == 1 then
          params:delta("scale", d)
        elseif selected_param == 2 then
          params:delta("root_note", d)
        elseif selected_param == 3 then
          params:delta("octave", d)
        elseif selected_param == 4 then
          params:delta("tempo", d)
        elseif selected_param == 5 then
          params:delta("pitch_mode", d)
        end
        
      elseif current_menu_page == 2 then
        -- Koi Behavior
        if selected_param == 1 then
          params:delta("num_koi", d)
          init_koi()
          selected_koi = util.clamp(selected_koi, 1, params:get("num_koi"))
        elseif selected_param == 2 then
          params:delta("global_speed", d)
        end
        
      elseif current_menu_page == 3 then
        -- PolyPerc
        if selected_param == 1 then
          params:delta("cutoff", d)
        elseif selected_param == 2 then
          params:delta("release", d)
        elseif selected_param == 3 then
          params:delta("amp", d)
        end
        
      elseif current_menu_page == 4 then
        -- Softcut Delay
        if selected_param == 1 then
          params:delta("delay_division", d)
          -- Update softcut delay time when division changes
          local new_delay_time = get_delay_time()
          softcut.loop_end(1, 1 + new_delay_time)
          print("Delay division changed to: " .. ({"1/32", "1/16", "1/8", "1/8.", "1/4", "1/4.", "1/2", "1/2.", "1/1", "2/1", "4/1"})[params:get("delay_division")])
        elseif selected_param == 2 then
          params:delta("delay_feedback", d)
        elseif selected_param == 3 then
          params:delta("delay_mix", d)
        elseif selected_param == 4 then
          params:delta("feedback_lfo_rate", d)
        end
        
      elseif current_menu_page == 5 then
        -- Softcut Creative
        if selected_param == 1 then
          params:delta("feedback_lfo_depth", d)
        elseif selected_param == 2 then
          params:delta("delay_filter_cutoff", d)
          softcut.filter_fc(1, params:get("delay_filter_cutoff"))
        elseif selected_param == 3 then
          params:delta("delay_reverse", d)
          softcut.rate(1, params:get("delay_reverse") == 2 and -1 or 1)
        elseif selected_param == 4 then
          params:delta("delay_overdub", d)
          softcut.rec_level(1, params:get("delay_overdub") == 2 and 1.0 or 0.8)
        end
        
      elseif current_menu_page == 6 then
        -- Drone Layer
        if selected_param == 1 then
          params:delta("drone_buffer_bars", d)
        elseif selected_param == 2 then
          params:delta("drone_buffer_notes", d)
          init_drone_buffer()
        elseif selected_param == 3 then
          params:delta("drone_fade_chance", d)
        elseif selected_param == 4 then
          params:delta("drone_amp", d)
        elseif selected_param == 5 then
          params:delta("drone_cutoff", d)
        end
        
      elseif current_menu_page == 7 then
        -- MIDI Settings
        if selected_param == 1 then
          params:delta("midi_input_enable", d)
        elseif selected_param == 2 then
          params:delta("midi_output_enable", d)
        elseif selected_param == 3 then
          params:delta("midi_in_device", d)
          init_midi()
        elseif selected_param == 4 then
          params:delta("midi_out_device", d)
          init_midi()
        end
        
      elseif current_menu_page == 8 then
        -- MIDI Channels
        if selected_param == 1 then
          params:delta("midi_food_channel", d)
        elseif selected_param == 2 then
          params:delta("midi_drone_channel", d)
        end
      end
    end
  end
  
  redraw()
end

-- Parameter change callbacks
local function setup_param_callbacks()
  params:set_action("delay_mix", function(x)
    softcut.level(1, x)
  end)
  
  params:set_action("delay_division", function(x)
    local new_delay_time = get_delay_time()
    softcut.loop_end(1, 1 + new_delay_time)
  end)
  
  params:set_action("tempo", function(x)
    -- Update delay time when tempo changes
    local new_delay_time = get_delay_time()
    softcut.loop_end(1, 1 + new_delay_time)
    print("Tempo changed to " .. x .. " BPM, delay time now: " .. string.format("%.2fs", new_delay_time))
  end)
  
  params:set_action("delay_filter_cutoff", function(x)
    softcut.filter_fc(1, x)
  end)
  
  params:set_action("delay_filter_q", function(x)
    softcut.filter_rq(1, x)
  end)
  
  params:set_action("delay_reverse", function(x)
    softcut.rate(1, x == 2 and -1 or 1)
  end)
  
  params:set_action("delay_overdub", function(x)
    softcut.rec_level(1, x == 2 and 1.0 or 0.8)
  end)
  
  params:set_action("midi_in_device", function(x)
    init_midi()
  end)
  
  params:set_action("midi_out_device", function(x)
    init_midi()
  end)
  
  -- Set initial values
  softcut.level(1, params:get("delay_mix"))
  local initial_delay_time = get_delay_time()
  softcut.loop_end(1, 1 + initial_delay_time)
  softcut.filter_fc(1, params:get("delay_filter_cutoff"))
  softcut.filter_rq(1, params:get("delay_filter_q"))
  softcut.filter_lp(1, 1)
  softcut.rate(1, params:get("delay_reverse") == 2 and -1 or 1)
  softcut.rec_level(1, params:get("delay_overdub") == 2 and 1.0 or 0.8)
end

-- Main init function
function init()
  init_params()
  setup_param_callbacks()
  init_softcut()
  init_koi()
  init_drone_buffer()
  init_midi()
  
  -- Check for logo PNG
  local logo_file = norns.state.path .. "koi_logo.png"
  if util.file_exists(logo_file) then
    logo_path = logo_file
    print("Logo found: " .. logo_file)
  else
    logo_path = nil
    print("Logo not found at: " .. logo_file)
    print("Place 'koi_logo.png' in the script folder to display logo")
  end
  
  -- Start clocks
  clock_id = clock.run(clock_update)
  screen_refresh_id = clock.run(screen_refresh)
  
  -- Add some initial food
  add_food()
  
  print("Koi initialized with UPDATED PARAMETERS!")
  print("- Octave 5 (higher pitch range)")
  print("- 4 Koi swimming (more activity)")
  print("- Shorter note release (0.3s)")
  print("- Quieter food sounds (0.5 amp)")
  print("- Louder drone layer (0.3 amp)")
  print("- Higher drone cutoff (200 Hz)")
  print("- Dotted quarter note delay")
  print("- Higher feedback (0.45) and mix (0.4)")
  print("- LFO disabled (0.0 rate)")
  print("- MIDI output disabled by default")
  print("Press any key to start - instructions will be shown")
  
  -- Trigger initial screen draw
  redraw()
end

-- Cleanup
function cleanup()
  if clock_id then
    clock.cancel(clock_id)
  end
  if screen_refresh_id then
    clock.cancel(screen_refresh_id)
  end
end
