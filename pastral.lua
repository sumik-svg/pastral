-- pastoral v15.15
-- a semi-automatic generative pastoral piece for monome norns.
--
-- Voices: tone1 (a pluck synth, or your own samples), tone2
-- (a church bell), a fiddle with up to five harmony layers,
-- wind, and a granular cloud fed from the last 2.5 seconds
-- of the piece itself. The music is generated from a root +
-- scale with a selectable note-choice mode, so performances
-- can wander far from the default D-dorian meadow.
--
-- Controls (this script uses K1 as a hold modifier):
--   K1 + K2        play / stop (the script loads stopped)
--   K1 + E2 / E3   grain size / grain mix
--   K1 + K3        toggle rhythmic mode
--   K2             join the fiddle harmony
--   K3             strike the bell
--   E1 / E2 / E3   tone / wind / shimmer
--
-- tone1 can play .wav samples from the audio/ folder: one
-- selected file, or "sample rnd", which picks from a per-file
-- pool for every note (each note always rings out to its full
-- release). The audio input can also be recorded into the
-- pool from the params screen (T1 rec). A filename with a
-- trailing note tag (e.g. flute_D4.wav) sets the sample base
-- note automatically.
--
-- See README.md for installation, parameters, sample
-- credits and the changelog.

engine.name = 'Pastoral'

local MusicUtil = require 'musicutil'

local fps = 15
local timer_screen
local timer_ambient
local timer_fiddle
local timer_lfo
local lfo_phase = 0
local phase = 0

local scale_full = {38, 41, 43, 45, 48, 50, 52, 53, 55, 57, 59, 60, 62, 64, 65, 67, 69, 72, 74, 76, 77}
local guitar_notes = {50, 53, 55, 57, 60, 62, 65, 67, 69}
local fiddle_notes = {62, 65, 67, 69, 72, 74}
local bell_note = 50

-- parameters
local tone_val = 50
local wind_val = 35
local tone_eff_vis = 50 -- effective value after LFO (drives the background animation)
local wind_eff_vis = 35
local shimmer_val = 35
local grain_size_val = 35
local grain_mix_val = 0

-- fiddle / harmony voice management
local lead_fiddle_active = false
local lead_fiddle_note = 62
local lead_fiddle_timer = 0
local active_harmonies = {}

-- visual state
local ripples = {}
local wind_streaks = {}

for i = 1, 6 do
  wind_streaks[i] = {
    x = math.random(0, 128),
    y = math.random(8, 56),
    len = math.random(8, 24),
    speed = 1.0 + math.random() * 1.5,
    alpha = math.random(2, 6)
  }
end

-- shoreline sand pattern: irregular grains and waterline wobble,
-- prepared with a deterministic pseudo-random sequence
local sand_grains = {}
local shore_jit = {}
do
  local seed = 20261107
  local function rnd()
    seed = (seed * 1103515245 + 12345) % 2147483648
    return seed / 2147483648
  end
  for i = 1, 460 do
    sand_grains[i] = {
      x = math.floor(rnd() * 128),
      y = 8 + math.floor(rnd() * 56),
      thr = rnd() * 100,
      lvl = 1 + math.floor(rnd() * 3)
    }
  end
  local j = 0
  for x = 0, 128 do
    j = util.clamp(j + (rnd() - 0.5) * 1.6, -2.2, 2.2)
    shore_jit[x] = j
  end
end

-- waterline y: large swell + small swell + random-walk jaggedness
local function shore_y(x, base)
  return base
    + math.sin(x * 0.045 + phase * 0.35) * 3.0
    + math.sin(x * 0.013 - phase * 0.21) * 4.5
    + shore_jit[math.max(0, math.min(128, math.floor(x)))]
end

-- system
local k1_held = false
local playing = false
local sample_loaded = false
local rhythmic_mode = false
local pulse_clock_id = nil
local beat_indicator = 0
local rhythm_step = 0

-- samples
local audio_dir = ""
local sample_files = {}
local recording = false
local rec_name = nil
local last_rec_toggle = 0
local preload_done = false
local pool_ids = {}
local tone1_error_reported = false
local rec_clock = nil
local init_done = false

local NOTE_SEMI = { C = 0, D = 2, E = 4, F = 5, G = 7, A = 9, B = 11 }
local NOTE_NAMES = { "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B" }

local function note_name(midi)
  return NOTE_NAMES[(midi % 12) + 1] .. math.floor(midi / 12 - 1)
end

-- parse the trailing note tag of a filename (e.g. flute_D4.wav -> 62); nil if none
local function note_tag_from_filename(name)
  local letter, sharp, oct = name:match("_([A-Ga-g])(#?)(%d)%.[Ww][Aa][Vv]$")
  if not letter then return nil end
  local semi = NOTE_SEMI[letter:upper()] + (sharp == "#" and 1 or 0)
  return (tonumber(oct) + 1) * 12 + semi
end

local function scan_samples()
  local files = {}
  local entries = util.scandir(audio_dir)
  if entries then
    for _, name in ipairs(entries) do
      if name:lower():match("%.wav$") then table.insert(files, name) end
    end
    table.sort(files)
  end
  return files
end

local function load_sample_by_name(name)
  if name and name:lower():match("%.wav$") then
    sample_loaded = true
    local tag = note_tag_from_filename(name)
    if tag then params:set("tone1_base_note", tag) end
  end
end

-- load every file into the engine buffer pool, one slot per file
local function preload_all_samples()
  for i, name in ipairs(sample_files) do
    if name:lower():match("%.wav$") then
      local ok, err = pcall(engine.tone1_load_at, i - 1, audio_dir .. name)
      if not ok then print("pastoral: load failed for " .. name .. ": " .. tostring(err)) end
    end
  end
  preload_done = true
end

-- pool membership for random mode. Pool param ids are tied to
-- filenames (numbering would shift settings onto other files
-- when a recording extends the list). Files without a param
-- (just recorded) are in the pool by default.
local function pool_id_for(name)
  return "pool_" .. name:gsub("%.[Ww][Aa][Vv]$", ""):gsub("[^%w]", "_")
end

local function pool_on(i)
  local name = sample_files[i]
  if not name then return true end
  local id = pool_id_for(name)
  if not pool_ids[id] then return true end
  return params:get(id) == 2
end

local function pick_pool_file()
  local enabled = {}
  for i, name in ipairs(sample_files) do
    if name:lower():match("%.wav$") and pool_on(i) then table.insert(enabled, i) end
  end
  if #enabled == 0 then return params:get("tone1_sample_file") end
  return enabled[math.random(#enabled)]
end

-- rebuild the sample list, select the given file and load it (used after recording)
local function refresh_sample_list(select_name)
  sample_files = scan_samples()
  if #sample_files == 0 then sample_files = { "(no .wav in audio folder)" } end
  local p = params:lookup_param("tone1_sample_file")
  if p then
    p.options = sample_files
    if p.count ~= nil then p.count = #sample_files end
    local idx = 1
    if select_name then
      for i, n in ipairs(sample_files) do
        if n == select_name then idx = i break end
      end
    end
    p:set(idx)
  end
  preload_all_samples()
  if select_name then load_sample_by_name(select_name) end
end

local function stop_recording()
  if not recording then return end
  recording = false
  params:set("t1_rec_ctl", 1, true)
  if rec_clock then clock.cancel(rec_clock) rec_clock = nil end
  engine.rec_stop(audio_dir .. rec_name)
  print("pastoral: rec saved -> " .. rec_name)
  local name = rec_name
  clock.run(function()
    clock.sleep(1.0)
    local ok, err = pcall(refresh_sample_list, name)
    if not ok then print("pastoral: sample list refresh error: " .. tostring(err)) end
  end)
end

local function start_recording()
  local n = 0
  for _, f in ipairs(scan_samples()) do
    if f:match("^rec_") then n = n + 1 end
  end
  rec_name = string.format("rec_%02d_%s.wav", n + 1, note_name(params:get("tone1_base_note")))
  print("pastoral: rec start -> " .. rec_name)
  engine.rec_start()
  recording = true
  rec_clock = clock.run(function()
    clock.sleep(11.5)
    if recording then stop_recording() end
  end)
end


-- ============================================================
-- Music generation (mode / scale / root). The note tables are
-- built from root + scale; with the defaults (root=50, dorian)
-- they are exactly the original fixed tables.
-- ============================================================
local SCALE_INTERVALS = {
  {0, 2, 3, 5, 7, 9, 10},  -- dorian
  {0, 2, 4, 5, 7, 9, 11},  -- major
  {0, 2, 3, 5, 7, 8, 10},  -- minor
  {0, 2, 4, 7, 9},         -- maj penta
  {0, 3, 5, 7, 10},        -- min penta
  {0, 2, 4, 6, 7, 9, 11},  -- lydian
  {0, 2, 4, 5, 7, 9, 10},  -- mixolydian
  {0, 2, 3, 7, 8},         -- hirajoshi
  {0, 2, 4, 6, 8, 10},     -- whole tone
}
local walk_idx = 5
local turing_seq = nil
local turing_pos = 0
local motif_notes = nil
local motif_base = 1
local motif_pos = 0
local motif_cycle = 0
local MOTIF_TRANSPOSE = {0, 0, 2, -1, 4, -2, 1, 0}

local function build_tables()
  local root = math.floor(params:get("mus_root") + 0.5)
  local iv = SCALE_INTERVALS[params:get("mus_scale")]
  local function deg_index(note)
    local pc = (note - root) % 12
    for i, semi in ipairs(iv) do
      if semi == pc then return i - 1 end
    end
    return nil
  end
  local function tone_deg(d) return d == 0 or d == 2 or d == 3 or d == 4 or d == 6 end
  scale_full = {}
  for n = root - 12, root + 27 do
    if deg_index(n) then table.insert(scale_full, n) end
  end
  guitar_notes = {}
  for n = root, root + 19 do
    local d = deg_index(n)
    if d and tone_deg(d) then table.insert(guitar_notes, n) end
  end
  fiddle_notes = {}
  for n = root + 12, root + 24 do
    local d = deg_index(n)
    if d and tone_deg(d) then table.insert(fiddle_notes, n) end
  end
  bell_note = root
  if walk_idx > #guitar_notes then walk_idx = #guitar_notes end
  if turing_seq then
    for i = 1, #turing_seq do
      if turing_seq[i] > #guitar_notes then turing_seq[i] = #guitar_notes end
    end
  end
  if motif_base > #guitar_notes then motif_base = #guitar_notes end
end

local function reseed_music()
  walk_idx = math.floor(#guitar_notes / 2) + 1
  turing_seq = {}
  for i = 1, 12 do turing_seq[i] = math.random(#guitar_notes) end
  turing_pos = 0
  motif_base = math.floor(#guitar_notes / 2) + 1
  motif_notes = {0}
  local steps = {-2, -1, -1, 0, 1, 1, 2}
  for i = 2, 5 do
    motif_notes[i] = motif_notes[i - 1] + steps[math.random(#steps)]
  end
  motif_pos = 0
  motif_cycle = 0
end

local function pick_tone1_note()
  local n = #guitar_notes
  local mode = params:get("mus_mode")
  if mode == 2 then
    -- walk: drift by scale steps from the previous note, with occasional leaps
    local r = math.random(100)
    local step = 0
    if r <= 30 then step = -1
    elseif r <= 60 then step = 1
    elseif r <= 72 then step = -2
    elseif r <= 84 then step = 2
    elseif r <= 92 then step = 0
    else step = (math.random() < 0.5) and -4 or 4 end
    walk_idx = util.clamp(walk_idx + step, 1, n)
    return guitar_notes[walk_idx]
  elseif mode == 3 then
    -- turing: a 12-note loop that mutates with the given probability as it passes
    if not turing_seq then reseed_music() end
    turing_pos = (turing_pos % #turing_seq) + 1
    if math.random(100) <= params:get("turing_mutate") then
      turing_seq[turing_pos] = math.random(n)
    end
    return guitar_notes[turing_seq[turing_pos]]
  elseif mode == 4 then
    -- motif: a short phrase repeated with stepped transpositions (last note sometimes varies)
    if not motif_notes then reseed_music() end
    motif_pos = motif_pos + 1
    if motif_pos > #motif_notes then
      motif_pos = 1
      motif_cycle = motif_cycle + 1
      if math.random(100) <= 25 then
        motif_notes[#motif_notes] = motif_notes[#motif_notes] + ((math.random() < 0.5) and -1 or 1)
      end
    end
    local tr = MOTIF_TRANSPOSE[(motif_cycle % #MOTIF_TRANSPOSE) + 1]
    local idx = util.clamp(motif_base + tr + motif_notes[motif_pos], 1, n)
    return guitar_notes[idx]
  end
  -- meadow: the original free random choice
  return guitar_notes[math.random(n)]
end

local function strike_bell()
  local amp = params:get("bell_amp")
  local bright = params:get("bell_bright")
  local pan = 0.0

  if math.random(100) > 80 then
    pan = (math.random() > 0.5 and 1 or -1) * (0.3 + math.random() * 0.45)
  end

  engine.bell(MusicUtil.note_num_to_freq(bell_note), amp, pan, bright)

  local px = util.clamp(math.floor(64 + pan * 48), 16, 112)
  local py = 32

  table.insert(ripples, {x = px, y = py, r = 2, max_r = 75, dr = 1.6, alpha = 15, width = 2})
  table.insert(ripples, {x = px, y = py, r = 6, max_r = 85, dr = 1.3, alpha = 10, width = 1})
end

local function trigger_guitar(note, dyn)
  local amp = params:get("pluck_amp") * 1.7 * (dyn or 1.0)
  local pan = (math.random() * 1.8) - 0.9
  -- T1 random octave (applies to synth and sample notes alike)
  local oct = 0
  if math.random(100) <= params:get("t1_oct_chance") then
    local m = params:get("t1_oct_mode")
    if m == 1 then oct = 1
    elseif m == 2 then oct = math.random(1, 2)
    else oct = (math.random() < 0.5) and -1 or 1 end
  end
  local freq = MusicUtil.note_num_to_freq(note + 12 * oct)
  local src = params:get("tone1_source")
  local ok, err = pcall(function()
    if src == 2 and sample_loaded then
      -- single-sample mode: play the selected file from its slot
      engine.pluck_sample_at(freq, amp, pan, 12.0,
        MusicUtil.note_num_to_freq(params:get("tone1_base_note")),
        params:get("tone1_sample_file") - 1)
    elseif src == 3 and sample_loaded then
      -- random-sample mode: pick one file from the pool and play it
      -- from its slot. Each note is an independent synth, so the
      -- previous note rings out to its full release
      local idx = pick_pool_file()
      local base = note_tag_from_filename(sample_files[idx]) or params:get("tone1_base_note")
      engine.pluck_sample_at(freq, amp, pan, 12.0,
        MusicUtil.note_num_to_freq(base), idx - 1)
    else
      engine.pluck(freq, amp, pan, 2.8)
    end
  end)
  if not ok then
    -- never let the sample path kill tone1: print the error once
    -- and substitute the synth pluck for this note
    if not tone1_error_reported then
      tone1_error_reported = true
      print("pastoral: tone1 error (falling back to synth): " .. tostring(err))
    end
    pcall(engine.pluck, freq, amp, pan, 2.8)
  end

  local px = util.clamp(math.floor(64 + pan * 54), 10, 118)
  local py = math.random(8, 56)

  table.insert(ripples, {
    x = px,
    y = py,
    r = 1,
    max_r = 18 + math.floor((dyn or 1.0) * 8),
    dr = 2.4,
    alpha = 14,
    width = 1
  })
end

local function get_random_harmony_note(base_note)
  local idx = 13
  for i, n in ipairs(scale_full) do
    if n == base_note then idx = i break end
  end

  local possible_offsets = {2, -2, 4, -4, 7, -7}
  local valid_notes = {}
  for _, off in ipairs(possible_offsets) do
    local target_idx = idx + off
    if target_idx >= 1 and target_idx <= #scale_full then
      local candidate = scale_full[target_idx]
      local is_used = false
      for _, h in ipairs(active_harmonies) do
        if h.note == candidate then is_used = true break end
      end
      if not is_used then table.insert(valid_notes, candidate) end
    end
  end

  if #valid_notes > 0 then
    return valid_notes[math.random(#valid_notes)]
  else
    return scale_full[math.max(1, idx - 2)]
  end
end

local function start_lead_fiddle(custom_dur)
  local dur = custom_dur or (6.5 + math.random() * 3.5)
  local note = fiddle_notes[math.random(#fiddle_notes)]
  local pan = (math.random() > 0.5 and 1 or -1) * (0.3 + math.random() * 0.3)
  local base_amp = 0.35

  lead_fiddle_active = true
  lead_fiddle_note = note
  lead_fiddle_timer = dur
  active_harmonies = {}

  engine.fiddle(MusicUtil.note_num_to_freq(note), base_amp, pan, dur, 1.0)
end

local function join_harmony_layer()
  if not lead_fiddle_active then
    start_lead_fiddle(8.5)
    return
  end
  if #active_harmonies >= 5 then return end

  local remaining_time = lead_fiddle_timer
  if remaining_time < 2.0 then
    remaining_time = 4.0
    lead_fiddle_timer = remaining_time
  end

  local harm_note = get_random_harmony_note(lead_fiddle_note)
  local pan_offsets = {0.6, -0.6, 0.25, -0.25, 0.8}
  local harm_pan = pan_offsets[(#active_harmonies % #pan_offsets) + 1]
  local harm_amp = 0.28
  local harm_att = math.min(2.2, remaining_time * 0.45)

  engine.fiddle(MusicUtil.note_num_to_freq(harm_note), harm_amp, harm_pan, remaining_time, harm_att)

  table.insert(active_harmonies, {
    note = harm_note,
    timer = remaining_time,
    offset_idx = #active_harmonies + 1
  })
end

local function rhythm_loop()
  rhythm_step = 0
  while true do
    clock.sync(1/2)
    rhythm_step = rhythm_step + 1

    if playing then
      local intervals = {32, 16, 8, 4, 2}
      local bell_step = intervals[params:get("bell_rate")]

      if (rhythm_step - 1) % bell_step == 0 then
        strike_bell()
        beat_indicator = 1.0
      end

      if math.random(100) < (35 + wind_val * 0.5) then
        local is_down = ((rhythm_step % 2) == 1)
        local note = pick_tone1_note()
        trigger_guitar(note, is_down and 1.0 or 0.75)
      end
    end
  end
end

local function update_sound_params()
  -- while the LFO is on, use effective values wobbling slowly around the knob (base) values
  local tone_eff = tone_val
  local wind_eff = wind_val
  if params:get("lfo_on") == 2 then
    tone_eff = util.clamp(tone_val + math.sin(lfo_phase) * params:get("lfo_tone_depth"), 0, 100)
    wind_eff = util.clamp(wind_val + math.sin(lfo_phase * 0.83 + 1.7) * params:get("lfo_wind_depth"), 10, 100)
  end

  tone_eff_vis = tone_eff
  wind_eff_vis = wind_eff

  local cutoff_freq = 150 * math.exp((tone_eff / 100) * 4.7)
  engine.cutoff(cutoff_freq)
  engine.wind_speed(wind_eff)
  engine.wind_amp(params:get("wind_amp") * (wind_eff / 45) * (playing and 1 or 0))
  engine.shimmer(shimmer_val / 100)
  engine.grain_size(grain_size_val / 100)
  engine.grain_mix(grain_mix_val / 100)
end

function init()
  params:add_separator("PASTORAL LEVELS")
  params:add_control("pluck_amp", "T1 vol", controlspec.new(0.0, 1.0, 'lin', 0.01, 0.80))
  params:add_control("bell_amp", "T2 vol", controlspec.new(0.0, 0.4, 'lin', 0.01, 0.10))
  params:add_control("bell_bright", "T2 bright", controlspec.new(0.0, 1.0, 'lin', 0.01, 0.85))
  params:add_control("wind_amp", "Wind vol", controlspec.new(0.0, 0.6, 'lin', 0.01, 0.30))
  params:set_action("wind_amp", function() update_sound_params() end)

  params:add_separator("T1")
  params:add_option("tone1_source", "T1 source", {"synth", "sample", "sample rnd"}, 1)
  params:set_action("tone1_source", function(v)
    if (v == 2 or v == 3) and not preload_done then preload_all_samples() end
    if v == 3 then
      local n = 0
      for i, name in ipairs(sample_files) do
        if name:lower():match("%.wav$") and pool_on(i) then n = n + 1 end
      end
      print("pastoral: sample rnd mode, pool = " .. n .. " files")
    end
  end)
  -- list the .wav files in audio/ as options (the list is built at startup)
  audio_dir = _path.code .. "pastral/audio/"
  sample_files = scan_samples()
  if #sample_files == 0 then sample_files = {"(no .wav in audio folder)"} end
  params:add_option("tone1_sample_file", "T1 sample", sample_files, 1)
  params:set_action("tone1_sample_file", function()
    load_sample_by_name(sample_files[params:get("tone1_sample_file")])
  end)
  params:add_control("tone1_base_note", "T1 base note", controlspec.new(24, 96, 'lin', 1, 59, "note"))
  params:add_control("t1_oct_chance", "T1 oct rnd", controlspec.new(0, 100, 'lin', 1, 0, "%"))
  params:add_option("t1_oct_mode", "T1 oct mode", {"+1", "+1/+2", "-1/+1"}, 2)
  params:add_separator("T1 POOL")
  for i, name in ipairs(sample_files) do
    if name:lower():match("%.wav$") then
      local pid = pool_id_for(name)
      pool_ids[pid] = true
      params:add_option(pid, "pool " .. name:gsub("%.[Ww][Aa][Vv]$", ""), {"off", "on"}, 2)
    end
  end
  params:add_option("t1_rec_ctl", "T1 rec", {"ready", "REC"}, 1)
  params:set_action("t1_rec_ctl", function(v)
    if not init_done then return end
    local now = util.time()
    if now - last_rec_toggle < 0.75 then
      params:set("t1_rec_ctl", recording and 2 or 1, true)
      return
    end
    if v == 2 and not recording then
      last_rec_toggle = now
      start_recording()
    elseif v == 1 and recording then
      last_rec_toggle = now
      stop_recording()
    end
  end)

  params:add_separator("LFO")
  params:add_option("lfo_on", "LFO", {"off", "on"}, 2)
  params:set_action("lfo_on", function() update_sound_params() end)
  params:add_control("lfo_rate", "LFO rate", controlspec.new(0.01, 1.0, 'exp', 0.001, 0.07, "Hz"))
  params:add_control("lfo_tone_depth", "LFO>Tone", controlspec.new(0, 100, 'lin', 1, 30, "%"))
  params:set_action("lfo_tone_depth", function() update_sound_params() end)
  params:add_control("lfo_wind_depth", "LFO>Wind", controlspec.new(0, 100, 'lin', 1, 35, "%"))
  params:set_action("lfo_wind_depth", function() update_sound_params() end)

  params:add_separator("RHYTHM")
  params:add_option("bell_rate", "T2 rate", {"4 bars", "2 bars", "1 bar", "Half", "Quarter"}, 3)

  params:add_separator("MUSIC")
  params:add_option("mus_mode", "Mode", {"meadow", "walk", "turing", "motif"}, 1)
  params:add_option("mus_scale", "Scale", {"dorian", "major", "minor", "maj penta", "min penta", "lydian", "mixolydian", "hirajoshi", "whole tone"}, 1)
  params:set_action("mus_scale", function() build_tables() end)
  params:add_control("mus_root", "Root", controlspec.new(36, 72, 'lin', 1, 50, "note"))
  params:set_action("mus_root", function() build_tables() end)
  params:add_control("turing_mutate", "Turing mut", controlspec.new(0, 100, 'lin', 1, 12, "%"))
  params:add_trigger("mus_reseed", "Reseed")
  params:set_action("mus_reseed", function() if init_done then reseed_music() end end)

  params:bang()
  build_tables()
  reseed_music()
  if not preload_done then preload_all_samples() end
  update_sound_params()

  timer_lfo = metro.init()
  timer_lfo.time = 0.12
  timer_lfo.event = function()
    if params:get("lfo_on") == 2 then
      lfo_phase = lfo_phase + (params:get("lfo_rate") * 0.12 * 2 * math.pi)
      update_sound_params()
    end
  end
  timer_lfo:start()

  timer_ambient = metro.init()
  timer_ambient.time = 60 / (wind_val * 2.5)
  timer_ambient.event = function()
    if playing and not rhythmic_mode then
      if math.random(100) < (wind_val * 0.8) then
        local note = pick_tone1_note()
        trigger_guitar(note, 0.9)
      end
      timer_ambient.time = (60 / (wind_val * 2.5)) * (0.6 + math.random() * 0.8)
    end
  end
  timer_ambient:start()

  timer_fiddle = metro.init()
  timer_fiddle.time = 12.0
  timer_fiddle.event = function()
    if playing and not lead_fiddle_active then
      start_lead_fiddle()
    end
    timer_fiddle.time = 11.0 + math.random() * 8.0
  end
  timer_fiddle:start()

  timer_screen = metro.init()
  timer_screen.time = 1 / fps
  timer_screen.event = function()
    update_physics()
    redraw()
  end
  timer_screen:start()

  init_done = true
end

function update_physics()
  phase = phase + (wind_val * 0.003)

  if beat_indicator > 0 then
    beat_indicator = beat_indicator - 0.08
  end

  if lead_fiddle_timer > 0 then
    lead_fiddle_timer = lead_fiddle_timer - (1 / fps)
    if lead_fiddle_timer <= 0 then
      lead_fiddle_active = false
      active_harmonies = {}
    end
  end

  for i = #active_harmonies, 1, -1 do
    local h = active_harmonies[i]
    h.timer = h.timer - (1 / fps)
    if h.timer <= 0 or not lead_fiddle_active then
      table.remove(active_harmonies, i)
    end
  end

  local wind_speed_factor = 0.5 + (wind_eff_vis / 30)
  for _, s in ipairs(wind_streaks) do
    s.x = s.x + (s.speed * wind_speed_factor)
    if s.x > 128 then
      s.x = -s.len
      s.y = math.random(8, 56)
    end
  end

  for i = #ripples, 1, -1 do
    local r = ripples[i]
    r.r = r.r + r.dr
    r.alpha = r.alpha - (15 / (r.max_r / r.dr))
    if r.r >= r.max_r or r.alpha <= 0 then
      table.remove(ripples, i)
    end
  end
end

function enc(n, d)
  if k1_held then
    if n == 2 then
      grain_size_val = util.clamp(grain_size_val + d * 3, 0, 100)
      update_sound_params()
    elseif n == 3 then
      grain_mix_val = util.clamp(grain_mix_val + d * 3, 0, 100)
      update_sound_params()
    end
  else
    if n == 1 then
      tone_val = util.clamp(tone_val + d * 2, 0, 100)
      update_sound_params()
    elseif n == 2 then
      wind_val = util.clamp(wind_val + d * 2, 10, 100)
      update_sound_params()
    elseif n == 3 then
      shimmer_val = util.clamp(shimmer_val + d * 2, 0, 100)
      update_sound_params()
    end
  end
end

function key(n, z)
  if n == 1 then
    k1_held = (z == 1)
  elseif z == 1 then
    if k1_held and n == 2 then
      -- K1+K2: play / stop
      playing = not playing
      update_sound_params()
    elseif k1_held and n == 3 then
      rhythmic_mode = not rhythmic_mode
      if rhythmic_mode then
        pulse_clock_id = clock.run(rhythm_loop)
      else
        if pulse_clock_id then
          clock.cancel(pulse_clock_id)
          pulse_clock_id = nil
        end
      end
    elseif n == 2 then
      join_harmony_layer()
    elseif n == 3 then
      strike_bell()
    end
  end
end

function redraw()
  screen.clear()

  -- ========================================================
  -- 1. E1 (TONE): shoreline sand pattern. The waterline moves
  --    with the effective tone value (after LFO), as if waves
  --    were carrying the sand. Below it, irregularly scattered
  --    grains (dense at the edge, thinning with distance) and
  --    broken, unevenly spaced ripple-mark lines.
  -- ========================================================
  local shore_base = 16 + (tone_eff_vis / 100) * 38

  -- sand grains (visible only below the waterline)
  for _, g in ipairs(sand_grains) do
    local dist = g.y - shore_y(g.x, shore_base)
    if dist >= 0 and g.thr < (88 - dist * 1.15) then
      screen.level(g.lvl)
      screen.pixel(g.x, g.y)
    end
  end
  screen.stroke()

  -- ripple marks (wave traces left in the sand)
  local ripple_off = 0
  for k = 1, 6 do
    ripple_off = ripple_off + 3 + (k % 3)
    screen.level(util.clamp(6 - k, 1, 5))
    for fx = 0, 127, 2 do
      if ((fx * 31 + k * 57) % 100) < 78 then
        local ry = shore_y(fx, shore_base) + ripple_off
          + math.sin(fx * 0.09 + k * 1.7 + phase * 0.45) * 1.2
        local ryi = math.floor(ry + 0.5)
        if ryi >= 0 and ryi < 64 then screen.pixel(fx, ryi) end
      end
    end
  end
  screen.stroke()

  -- the waterline itself (brightest, slowly swelling)
  screen.level(9)
  for fx = 0, 127 do
    if ((fx * 17) % 100) < 94 then
      local sy = math.floor(shore_y(fx, shore_base) + 0.5)
      if sy >= 0 and sy < 64 then screen.pixel(fx, sy) end
    end
  end
  screen.stroke()

  -- ========================================================
  -- 2. wind: streamlines
  -- ========================================================
  for _, s in ipairs(wind_streaks) do
    local strk_lvl = util.clamp(math.floor(s.alpha * (0.6 + wind_val / 60)), 1, 10)
    screen.level(strk_lvl)
    screen.move(s.x, s.y)
    screen.line(s.x + s.len, s.y)
    screen.stroke()
  end

  -- ========================================================
  -- 3. fiddle: strings of light
  -- ========================================================
  if lead_fiddle_active then
    local vib_y = math.sin(phase * 4.0) * 0.8
    screen.level(12)
    screen.move(14, 32 + vib_y)
    screen.line(114, 32 + vib_y)
    screen.stroke()

    screen.level(8)
    screen.circle(14, 32 + vib_y, 1)
    screen.circle(114, 32 + vib_y, 1)
    screen.fill()

    for i, h in ipairs(active_harmonies) do
      local h_lvl = util.clamp(math.floor(7 + i * 1.5), 1, 14)
      screen.level(h_lvl)
      local y_offsets = { -8, 8, -14, 14, -20 }
      local hy = 32 + (y_offsets[i] or (i * 6)) + math.cos(phase * 3.5 + i) * 0.6

      screen.move(20, hy)
      screen.line(108, hy)
      screen.stroke()

      screen.level(math.floor(h_lvl * 0.7))
      screen.circle(20, hy, 1)
      screen.circle(108, hy, 1)
      screen.fill()
    end
  end

  -- ========================================================
  -- 4. attacks (bell & pluck): ripples
  -- ========================================================
  for _, r in ipairs(ripples) do
    local r_level = util.clamp(math.floor(r.alpha), 1, 15)
    screen.level(r_level)
    screen.circle(r.x, r.y, math.max(1, r.r))
    screen.stroke()
    if r.width > 1 and r.r > 4 then
      screen.circle(r.x, r.y, math.max(1, r.r - 3))
      screen.stroke()
    end
  end

  -- ========================================================
  -- 5. granular: mosaic grid
  -- ========================================================
  if grain_mix_val > 0 then
    local block_size = math.floor(3 + (grain_size_val / 100) * 9)
    local num_blocks = math.floor(5 + (grain_mix_val / 100) * 30)

    for b = 1, num_blocks do
      local bx = math.random(0, math.max(0, 128 - block_size))
      local by = math.random(0, math.max(0, 64 - block_size))
      local b_level = util.clamp(math.random(4, 15), 0, 15)

      screen.level(b_level)
      screen.rect(bx, by, block_size, block_size)
      if b % 3 == 0 then
        screen.fill()
      else
        screen.stroke()
      end
    end
  end

  -- ========================================================
  -- 6. minimal status line
  -- ========================================================
  if k1_held then
    screen.level(15)
    screen.move(4, 8)
    screen.text("[GRANULAR] SIZE:" .. grain_size_val .. "%  MIX:" .. grain_mix_val .. "%")
  else
    screen.level(tone_val < 35 and 6 or 3)
    screen.move(4, 8)
    if rhythmic_mode then
      screen.level(beat_indicator > 0.4 and 15 or 8)
      screen.text("SYNC " .. math.floor(clock.get_tempo()) .. " BPM")
    else
      screen.text("PASTORAL v15.15")
    end

    if recording then
      screen.level(15)
      screen.move(86, 8)
      screen.text("REC")
    elseif not playing then
      screen.level(15)
      screen.move(86, 8)
      screen.text("STOP")
    elseif lead_fiddle_active then
      local v_count = 1 + #active_harmonies
      screen.level(12)
      screen.move(86, 8)
      screen.text("STRINGS:" .. v_count .. "/6")
    elseif grain_mix_val > 0 then
      screen.level(8)
      screen.move(86, 8)
      screen.text("GRAIN:" .. grain_mix_val .. "%")
    end
  end

  screen.update()
end

function cleanup()
  if timer_screen then timer_screen:stop() end
  if timer_ambient then timer_ambient:stop() end
  if timer_fiddle then timer_fiddle:stop() end
  if timer_lfo then timer_lfo:stop() end
  if rec_clock then clock.cancel(rec_clock) end
  if pulse_clock_id then clock.cancel(pulse_clock_id) end
end