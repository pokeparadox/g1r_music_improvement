package.path = "./?.lua;" .. "./tests/?.lua;" .. package.path

local profiles = require("song_profiles")
local improve = require("improve")

local function fail(msg, extra)
  error((msg or "assertion failed") .. (extra and (": " .. extra) or ""), 2)
end

local function eq(actual, expected, msg)
  if actual ~= expected then fail(msg, tostring(actual) .. " ~= " .. tostring(expected)) end
end

local deepPath
local function deepEqual(a, b, path)
  path = path or "value"
  if type(a) ~= type(b) then deepPath = path .. " type"; return false end
  if type(a) ~= "table" then
    if a ~= b then deepPath = path .. " " .. tostring(a) .. "~=" .. tostring(b) end
    return a == b
  end
  local seen = {}
  for k, va in pairs(a) do
    seen[k] = true
    if not deepEqual(va, b[k], path .. "." .. tostring(k)) then return false end
  end
  for k in pairs(b) do
    if not seen[k] then deepPath = path .. "." .. tostring(k) .. " missing"; return false end
  end
  return true
end

local source = {
  tempo = 0x100,
  channels = {
    { hw = 1, program = { { pitch = 0, len = 2 }, { pitch = 2, len = 3 } } },
    { hw = 2, program = { { pitch = 5, len = 4 } } },
  },
}

local baseline = {
  left = { tempo = 256, channels = { { hw = 1, program = {
    { duty = 1 },
    { notetype = { volume = 12, fade = 1, speed = 12 } },
    { octave = 5 }, { pitch = 0, len = 2 },
    { octave = 6 }, { pitch = 2, len = 3 },
  } } } },
  right = { tempo = 256, channels = { { hw = 1, program = {
    { duty = 1 },
    { notetype = { volume = 12, fade = 1, speed = 12 } },
    { octave = 3 }, { pitch = 0, len = 2 },
    { octave = 2 }, { pitch = 2, len = 3 },
  } } } },
  center = { tempo = 256, channels = { { hw = 1, program = {
    { duty = 2 },
    { notetype = { volume = 12, fade = 1, speed = 12 } },
    { pitch = 7, len = 2 },
    { pitch = 9, len = 3 },
  } } } },
  bassDown = { tempo = 256, channels = { { hw = 1, program = {
    { duty = 1 },
    { notetype = { volume = 9, fade = 1, speed = 12 } },
    { octave = 3 }, { pitch = 5, len = 4 },
  } } } },
}

eq(profiles.validate(), true, "profiles.validate()")
eq(profiles.forLabel("Music_ThisSongDoesNotExist"), nil, "unknown label")
eq(profiles.forLabel("Music_Pokecenter").id, "pokecenter", "known label")
eq(profiles.forLabel("Music_Credits").key, nil, "shared conflicting label has no key override")

local noProfile = improve.extra(source, { dynamicIntensity = false })
if not deepEqual(noProfile, baseline) then fail("no-profile extra() changed", deepPath) end

local keyProfile = {
  key = { tonic = 0, mode = "minor" },
  sides = {
    left = { degree = 2 },
    right = { enabled = false },
    center = { enabled = false },
    bassDown = { enabled = false },
  },
}
local keyed = improve.extra(source, { dynamicIntensity = false, profile = keyProfile })
eq(keyed.right, nil, "profile disables right")
eq(keyed.center, nil, "profile disables center")
eq(keyed.bassDown, nil, "profile disables bassDown")
local prog = keyed.left and keyed.left.channels[1].program
if not prog then fail("profile left missing") end
eq(prog[3].pitch, 3, "C -> E-flat on minor scale")
eq(prog[4].pitch, 5, "D -> F on minor scale")

local gainProfile = { sides = { center = { gain = 0.5 } } }
local gained = improve.extra(source, { dynamicIntensity = false, profile = gainProfile })
eq(gained.center.channels[1].program[2].notetype.volume, 6, "profile gain")

local ignored = improve.extra(source, {
  dynamicIntensity = false,
  keyAware = false,
  profile = { key = { tonic = 0, mode = "minor" } },
})
if not deepEqual(ignored, baseline) then fail("keyAware=false must ignore profile key") end

print("song_profiles_test OK")
