-- HD2-Addon: mods/codex/pickup_icon_range_test
-- Guarded pickup icon range extension. Finds data by resource ID and checks each field before writing.
-- Distances and on/off switches come from Mod Options Menu when it is installed.

if rawget(_G, 'CodexPickupIconRangeTest') then return end

local ffi = require('ffi')
assert(ffi.abi('64bit'), 'Windows x64 is required')

ffi.cdef[[
void *GetCurrentProcess(void);
int ReadProcessMemory(void *process, const void *address, void *buffer, size_t size, size_t *read_count);
int WriteProcessMemory(void *process, void *address, const void *buffer, size_t size, size_t *write_count);
size_t VirtualQuery(const void *address, void *region, size_t size);
int VirtualProtect(void *address, size_t size, uint32_t new_protect, uint32_t *old_protect);
uint64_t GetTickCount64(void);
typedef struct {
    void *base; void *allocation_base; uint32_t allocation_protect;
    uint16_t partition; uint16_t reserved; size_t size;
    uint32_t state; uint32_t protect; uint32_t kind; uint32_t padding;
} CodexPickupMemoryRegion;
]]

local kernel = ffi.load('kernel32')
local process = kernel.GetCurrentProcess()
local state = {version='extended-pickup-icons-3.0', active=false, status='pending', attempts=0}
_G.CodexPickupIconRangeTest = state

local LDLD = 0x444C444C
local INTERACTION = 0xFCCA29DB
local SPOTTABLE = 0x0A5E53DB
local RECORD_BYTES = 1104
local SPOT_RECORD_BYTES = 72
local SCAN_CHUNK = 0x100000

local function report(message)
    state.status = tostring(message)
    print('[CodexPickupIconRangeTest] '..state.status)
    pcall(function()
        local loader = rawget(_G, 'CowboyBingusModLoader')
        local file = loader and loader.open_log and loader.open_log('CodexPickupIconRangeTest.log')
        if file then file:write(state.version..'\n'..state.status..'\n'); file:close() end
    end)
end

local function address_of(pointer)
    return tonumber(ffi.cast('uintptr_t', pointer))
end

local function query(address)
    local region = ffi.new('CodexPickupMemoryRegion[1]')
    local got = kernel.VirtualQuery(ffi.cast('const void *', address),
                                    ffi.cast('void *', region), ffi.sizeof(region[0]))
    if got ~= ffi.sizeof(region[0]) then return nil end
    return region[0]
end

local function read(address, size)
    local buffer = ffi.new('uint8_t[?]', size)
    local count = ffi.new('size_t[1]')
    if kernel.ReadProcessMemory(process, ffi.cast('const void *', address),
                                buffer, size, count) == 0 or count[0] ~= size then
        return nil
    end
    return ffi.string(buffer, size)
end

local function write(address, bytes)
    local count = ffi.new('size_t[1]')
    return kernel.WriteProcessMemory(process, ffi.cast('void *', address),
                                     ffi.cast('const void *', bytes), #bytes, count) ~= 0
           and count[0] == #bytes
end

local function u32(bytes, offset)
    assert(offset >= 0 and offset+4 <= #bytes, 'Field out of bounds')
    local a,b,c,d = bytes:byte(offset+1,offset+4)
    return a + b*256 + c*65536 + d*16777216
end

local function unhex(value)
    return (value:gsub('%x%x', function(pair) return string.char(tonumber(pair,16)) end))
end

local resources = {
    {name='unresolved_dropped_sample_carrier_a9936cbe561e8180#zone0', group='equipment', id=unhex('80811e56be6c93a9'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000003f'), before=unhex('00007041'), interact_type=12},
    {name='unresolved_mission_carryable_d8a28bfb827392be#zone0', group='equipment', id=unhex('be927382fb8ba2d8'), zone=0, zone_name=0xF2760503, radius=unhex('0000803f'), before=unhex('0000a041'), interact_type=31},
    {name='unresolved_mission_carryable_7ca1b74b22c2eb9c#zone0', group='equipment', id=unhex('9cebc2224bb7a17c'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00008040'), interact_type=31},
    {name='content/fac_helldivers/equipment/backpacks/drone_weapons/drone_stun_gun/drone_stun_gun_mount#zone0', group='equipment', id=unhex('bf8c5216362c53a0'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00002041'), interact_type=1},
    {name='content/objectives/obj_common/raise_flag/carry_flag#zone0', group='equipment', id=unhex('55335e09117e3a9d'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000a041'), interact_type=31},
    {name='content/fac_helldivers/equipment/melee_weapons/hand_axe/hand_axe#zone0', group='equipment', id=unhex('50c839c177608175'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00002041'), interact_type=2},
    {name='content/fac_helldivers/equipment/melee_weapons/machete/machete#zone0', group='equipment', id=unhex('e6d60f342a5d2d79'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00002041'), interact_type=2},
    {name='content/fac_helldivers/equipment/melee_weapons/survival_shovel/survival_shovel#zone0', group='equipment', id=unhex('b36ff9933f625ee8'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00002041'), interact_type=3},
    {name='content/fac_helldivers/equipment/backpacks/ammo_backpack/ammo_backpack#zone0', group='equipment', id=unhex('589a230971a4f94e'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00008040'), interact_type=13},
    {name='content/fac_helldivers/equipment/backpacks/ammo_backpack/ammo_backpack#zone1', group='equipment', id=unhex('589a230971a4f94e'), zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00002041'), interact_type=29},
    {name='content/env_super_earth/samples/research_tech_sample_01#zone0', group='samples', id=unhex('939ebe44e8b7fc4e'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000403f'), before=unhex('00001041'), interact_type=11},
    {name='content/fac_helldivers/equipment/backpacks/minigun_backpack/minigun_backpack#zone0', group='equipment', id=unhex('3e721ee2c5e16d05'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00008040'), interact_type=13},
    {name='content/fac_helldivers/equipment/backpacks/minigun_backpack/minigun_backpack#zone1', group='equipment', id=unhex('3e721ee2c5e16d05'), zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00002041'), interact_type=29},
    {name='content/fac_helldivers/equipment/backpacks/energy_shield_backpack/energy_shield_backpack#zone0', group='equipment', id=unhex('5c7a89c31ad7c812'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00008040'), interact_type=13},
    {name='content/fac_helldivers/equipment/backpacks/energy_shield_backpack/energy_shield_backpack#zone1', group='equipment', id=unhex('5c7a89c31ad7c812'), zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00002041'), interact_type=29},
    {name='unresolved_mission_carryable_38cb9c758e07bc58#zone0', group='equipment', id=unhex('58bc078e759ccb38'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000a041'), interact_type=31},
    {name='content/fac_helldivers/equipment/backpacks/ballistic_shield_backpack/ballistic_shield_backpack#zone0', group='equipment', id=unhex('3b36ae0b5ed17e96'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00008040'), interact_type=13},
    {name='content/fac_helldivers/equipment/backpacks/ballistic_shield_backpack/ballistic_shield_backpack#zone1', group='equipment', id=unhex('3b36ae0b5ed17e96'), zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00002041'), interact_type=29},
    {name='content/env_shared/assets/samples/bio_sample_01/bio_sample_01#zone0', group='samples', id=unhex('6652448a9d9bb464'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000403f'), before=unhex('00001041'), interact_type=11},
    {name='content/env_cyborg/samples/automaton_super_sample_01#zone0', group='samples', id=unhex('9b8b682e7b0c1cc7'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000a041'), interact_type=31},
    {name='unresolved_mission_carryable_5684d928c9ab00d1#zone0', group='equipment', id=unhex('d100abc928d98456'), zone=0, zone_name=0xF2760503, radius=unhex('0000803f'), before=unhex('0000a041'), interact_type=31},
    {name='content/fac_helldivers/equipment/primary_weapons/lmg_stalwart/lmg_stalwart#zone0', group='equipment', id=unhex('7f324acbac35a7a6'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00000041'), interact_type=13},
    {name='content/fac_helldivers/equipment/primary_weapons/lmg_stalwart/lmg_stalwart#zone1', group='equipment', id=unhex('7f324acbac35a7a6'), zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000a041'), interact_type=3},
    {name='unresolved_mission_carryable_7c81de10f0023d08#zone0', group='equipment', id=unhex('083d02f010de817c'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000a041'), interact_type=31},
    {name='unresolved_resupply_pickup_unit_cc102a849e8930ef#zone0', group='supplies', id=unhex('ef30899e842a10cc'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00008040'), interact_type=4},
    {name='content/fac_helldivers/equipment/melee_weapons/electric_baton/stun_baton#zone0', group='equipment', id=unhex('97b33ccababfcd52'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00002041'), interact_type=2},
    {name='unresolved_mission_carryable_f598598c47617605#zone0', group='carry', id=unhex('057661478c5998f5'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00008040'), interact_type=31},
    {name='content/fac_helldivers/discoverables/ammo_box_discoverable_01/ammo_box_discoverable_01#zone0', group='supplies', id=unhex('a9f3e381d2ffcc79'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00008040'), interact_type=4},
    {name='content/env_bugs/assets/samples/bug_egg_super_sample_01#zone0', group='samples', id=unhex('844a3aee86315d2b'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000a041'), interact_type=31},
    {name='content/fac_helldivers/equipment/support_weapons/faf_missile_launcher_helghast/faf_missile_launcher_helghast#zone0', group='equipment', id=unhex('657efe91646f78cc'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00000041'), interact_type=13},
    {name='content/fac_helldivers/equipment/support_weapons/faf_missile_launcher_helghast/faf_missile_launcher_helghast#zone1', group='equipment', id=unhex('657efe91646f78cc'), zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000a041'), interact_type=3},
    {name='content/fac_helldivers/equipment/backpacks/recoilless_rifle_backpack/recoilless_rifle_backpack#zone0', group='equipment', id=unhex('8029a22a54c6df96'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00008040'), interact_type=13},
    {name='content/fac_helldivers/equipment/backpacks/recoilless_rifle_backpack/recoilless_rifle_backpack#zone1', group='equipment', id=unhex('8029a22a54c6df96'), zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00002041'), interact_type=29},
    {name='content/fac_helldivers/equipment/backpacks/hover_backpack/hover_backpack#zone0', group='equipment', id=unhex('cf66db1c4f0fc85e'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00008040'), interact_type=13},
    {name='content/fac_helldivers/equipment/backpacks/hover_backpack/hover_backpack#zone1', group='equipment', id=unhex('cf66db1c4f0fc85e'), zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00002041'), interact_type=29},
    {name='unresolved_hellpod_equipment_fc13460592ca79aa#zone0', group='equipment', id=unhex('aa79ca92054613fc'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000003f'), before=unhex('00000041'), interact_type=13},
    {name='unresolved_dropped_weapon_fc13460592ca79aa#zone1', group='equipment', id=unhex('aa79ca92054613fc'), zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000a041'), interact_type=3},
    {name='content/fac_helldivers/equipment/support_weapons/recoilless_rifle/recoilless_rifle#zone0', group='equipment', id=unhex('0fe4a7127ad6809f'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00000041'), interact_type=13},
    {name='content/fac_helldivers/equipment/support_weapons/recoilless_rifle/recoilless_rifle#zone1', group='equipment', id=unhex('0fe4a7127ad6809f'), zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000a041'), interact_type=3},
    {name='content/fac_helldivers/equipment/backpacks/drone_gas_projector_backpack/drone_gas_projector_backpack#zone0', group='equipment', id=unhex('da8e1a97cdb4fcbf'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00008040'), interact_type=13},
    {name='content/fac_helldivers/equipment/backpacks/drone_gas_projector_backpack/drone_gas_projector_backpack#zone1', group='equipment', id=unhex('da8e1a97cdb4fcbf'), zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00002041'), interact_type=29},
    {name='content/fac_helldivers/equipment/support_weapons/laser_cannon/laser_cannon#zone0', group='equipment', id=unhex('7328f7c005954bd5'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000003f'), before=unhex('00000041'), interact_type=13},
    {name='content/fac_helldivers/equipment/support_weapons/laser_cannon/laser_cannon#zone1', group='equipment', id=unhex('7328f7c005954bd5'), zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000a041'), interact_type=3},
    {name='content/env_super_earth/samples/research_bio_sample_01#zone0', group='samples', id=unhex('42ac705266da4e29'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000403f'), before=unhex('00001041'), interact_type=11},
    {name='content/fac_helldivers/equipment/backpacks/faf_missile_launcher_backpack/faf_missile_launcher_backpack#zone0', group='equipment', id=unhex('9a572e5f6b02c38e'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00008040'), interact_type=13},
    {name='content/fac_helldivers/equipment/backpacks/faf_missile_launcher_backpack/faf_missile_launcher_backpack#zone1', group='equipment', id=unhex('9a572e5f6b02c38e'), zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00002041'), interact_type=29},
    {name='content/objectives/obj_common/seaf_gun/seaf_gun_ammo#zone0', group='carry', id=unhex('8340085ee2e2626c'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00008040'), interact_type=31},
    {name='content/objectives/obj_common/black_box/black_box_01#zone0', group='equipment', id=unhex('97683ba35e41e23d'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000a041'), interact_type=31},
    {name='content/fac_helldivers/equipment/support_weapons/belt_fed_grenade_launcher/belt_fed_grenade_launcher#zone0', group='equipment', id=unhex('9f7c5ad89ad0c288'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00000041'), interact_type=13},
    {name='content/fac_helldivers/equipment/support_weapons/belt_fed_grenade_launcher/belt_fed_grenade_launcher#zone1', group='equipment', id=unhex('9f7c5ad89ad0c288'), zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000a041'), interact_type=3},
    {name='unresolved_mission_carryable_46918a7483d70f3e#zone0', group='equipment', id=unhex('3e0fd783748a9146'), zone=0, zone_name=0xF2760503, radius=unhex('0000803f'), before=unhex('0000a041'), interact_type=31},
    {name='unresolved_mission_carryable_36c5e772f8a3b9d3#zone0', group='equipment', id=unhex('d3b9a3f872e7c536'), zone=0, zone_name=0xF2760503, radius=unhex('0000803f'), before=unhex('0000a041'), interact_type=31},
    {name='content/fac_helldivers/equipment/backpacks/drone_weapons/drone_laser_rifle/drone_laser_rifle_backpack#zone0', group='equipment', id=unhex('02dc6dcb3c689baf'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00008040'), interact_type=13},
    {name='content/fac_helldivers/equipment/backpacks/drone_weapons/drone_laser_rifle/drone_laser_rifle_backpack#zone1', group='equipment', id=unhex('02dc6dcb3c689baf'), zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00002041'), interact_type=29},
    {name='content/env_cyborg/samples/automaton_enemy_sample_01#zone0', group='samples', id=unhex('996adf2360b9eee4'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000403f'), before=unhex('00001041'), interact_type=11},
    {name='content/fac_helldivers/equipment/backpacks/displacement_backpack/displacement_backpack#zone0', group='equipment', id=unhex('680e9b5d795697b4'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00008040'), interact_type=13},
    {name='content/fac_helldivers/equipment/backpacks/displacement_backpack/displacement_backpack#zone1', group='equipment', id=unhex('680e9b5d795697b4'), zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00002041'), interact_type=29},
    {name='unresolved_mission_carryable_d616d0bddb1be7dc#zone0', group='equipment', id=unhex('dce71bdbbdd016d6'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000a041'), interact_type=31},
    {name='content/fac_helldivers/equipment/melee_weapons/ceremonial_saber/ceremonial_saber#zone0', group='equipment', id=unhex('5a63ac7ee6a6d8fc'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00002041'), interact_type=2},
    {name='content/env_shared_forest/assets/samples/plant_sample_01#zone0', group='samples', id=unhex('b44279d987cbf386'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000403f'), before=unhex('00001041'), interact_type=11},
    {name='content/env_bugs/assets/samples/bug_sample_01#zone0', group='samples', id=unhex('6cfbdc7f39ee1650'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000403f'), before=unhex('00001041'), interact_type=11},
    {name='unresolved_sample_type_0_b65ec1c74612dc2c#zone0', group='samples', id=unhex('2cdc1246c7c15eb6'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000003f'), before=unhex('0000c040'), interact_type=11},
    {name='content/fac_helldivers/equipment/support_weapons/machinegun/machinegun#zone0', group='equipment', id=unhex('5689b3ab3b7dc211'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00000041'), interact_type=13},
    {name='content/fac_helldivers/equipment/support_weapons/machinegun/machinegun#zone1', group='equipment', id=unhex('5689b3ab3b7dc211'), zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000a041'), interact_type=3},
    {name='unresolved_hellpod_equipment_d53ee03481ae73fd#zone0', group='equipment', id=unhex('fd73ae8134e03ed5'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00000041'), interact_type=13},
    {name='unresolved_dropped_weapon_d53ee03481ae73fd#zone1', group='equipment', id=unhex('fd73ae8134e03ed5'), zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000a041'), interact_type=3},
    {name='content/fac_helldivers/equipment/support_weapons/grenade_launcher/grenade_launcher#zone0', group='equipment', id=unhex('3096a41f0bcdee02'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00000041'), interact_type=13},
    {name='content/fac_helldivers/equipment/support_weapons/grenade_launcher/grenade_launcher#zone1', group='equipment', id=unhex('3096a41f0bcdee02'), zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000a041'), interact_type=3},
    {name='unresolved_hellpod_equipment_8e7968d7e7aa4eab#zone0', group='equipment', id=unhex('ab4eaae7d768798e'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000003f'), before=unhex('00000041'), interact_type=13},
    {name='unresolved_dropped_weapon_8e7968d7e7aa4eab#zone1', group='equipment', id=unhex('ab4eaae7d768798e'), zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000a041'), interact_type=3},
    {name='unresolved_sample_type_1_92bcc263e751bd45#zone0', group='samples', id=unhex('45bd51e763c2bc92'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000403f'), before=unhex('00001041'), interact_type=11},
    {name='unresolved_hellpod_equipment_cd00bdc1149c2928#zone0', group='equipment', id=unhex('28299c14c1bd00cd'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00000041'), interact_type=13},
    {name='unresolved_dropped_weapon_cd00bdc1149c2928#zone1', group='equipment', id=unhex('28299c14c1bd00cd'), zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000a041'), interact_type=3},
    {name='content/fac_helldivers/equipment/support_weapons/laser_pulse_cannon/laser_pulse_cannon#zone0', group='equipment', id=unhex('7ec49c619612a635'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000003f'), before=unhex('00000041'), interact_type=13},
    {name='content/fac_helldivers/equipment/support_weapons/laser_pulse_cannon/laser_pulse_cannon#zone1', group='equipment', id=unhex('7ec49c619612a635'), zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000a041'), interact_type=3},
    {name='unresolved_dropped_sample_carrier_1c8764d62e12925a#zone0', group='equipment', id=unhex('5a92122ed664871c'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000003f'), before=unhex('00007041'), interact_type=12},
    {name='content/fac_helldivers/equipment/melee_weapons/sledge_hammer/sledge_hammer#zone0', group='equipment', id=unhex('5385bda2bdc93e5f'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00002041'), interact_type=3},
    {name='content/fac_helldivers/equipment/melee_weapons/sledge_hammer/sledge_hammer#zone1', group='equipment', id=unhex('5385bda2bdc93e5f'), zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00000041'), interact_type=13},
    {name='content/env_super_earth/samples/se_intel_sample_01#zone0', group='samples', id=unhex('f0e91ffa74b17983'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000403f'), before=unhex('00001041'), interact_type=42},
    {name='content/fac_helldivers/hellpod/ammo_rack/supply_box#zone0', group='supplies', id=unhex('79754f01ca1349a9'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00008040'), interact_type=8},
    {name='content/fac_helldivers/hellpod/ammo_rack/supply_box#zone1', group='supplies', id=unhex('79754f01ca1349a9'), zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00008040'), interact_type=7},
    {name='content/fac_helldivers/equipment/backpacks/ballistic_shield_backpack_mk2/ballistic_shield_backpack_mk2#zone0', group='equipment', id=unhex('a0acb55ced7ac6f5'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00008040'), interact_type=13},
    {name='content/fac_helldivers/equipment/backpacks/ballistic_shield_backpack_mk2/ballistic_shield_backpack_mk2#zone1', group='equipment', id=unhex('a0acb55ced7ac6f5'), zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00002041'), interact_type=29},
    {name='content/fac_helldivers/hellpod/health_pack_rack/health_pack#zone0', group='supplies', id=unhex('a829a746c6168d3b'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000003f'), before=unhex('00008040'), interact_type=5},
    {name='content/objectives/obj_common/carry_data/carry_data_stratagem#zone0', group='equipment', id=unhex('9225a1e3dabcf233'), zone=0, zone_name=0xF2760503, radius=unhex('0000803f'), before=unhex('0000a041'), interact_type=31},
    {name='content/fac_helldivers/equipment/melee_weapons/flag/melee_flag#zone0', group='equipment', id=unhex('d8381dba54b3f1b0'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00002041'), interact_type=3},
    {name='unresolved_mission_carryable_a7381b87f3a3b455#zone0', group='equipment', id=unhex('55b4a3f3871b38a7'), zone=0, zone_name=0xF2760503, radius=unhex('0000803f'), before=unhex('0000a041'), interact_type=31},
    {name='unresolved_mission_carryable_dc19126d15692d04#zone0', group='carry', id=unhex('042d69156d1219dc'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00008040'), interact_type=31},
    {name='content/fac_helldivers/equipment/sidearm_weapons/smart_pistol_missile/smart_pistol_missile#zone0', group='equipment', id=unhex('a4c7566050d4d514'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00002041'), interact_type=2},
    {name='content/entities/base_sample_dynamic#zone0', group='samples', id=unhex('8614ca0cf70398ca'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000403f'), before=unhex('00001041'), interact_type=11},
    {name='content/env_shared_desert/assets/samples/mineral_sample_01#zone0', group='samples', id=unhex('54be95b06cea0882'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000403f'), before=unhex('00001041'), interact_type=11},
    {name='content/objectives/obj_common/carry_data/carry_data#zone0', group='equipment', id=unhex('fdc56524893214f4'), zone=0, zone_name=0xF2760503, radius=unhex('0000803f'), before=unhex('0000a041'), interact_type=31},
    {name='unresolved_mission_carryable_e4be3fdf0c857b7f#zone0', group='carry', id=unhex('7f7b850cdf3fbee4'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00008040'), interact_type=31},
    {name='content/fac_helldivers/equipment/sidearm_weapons/smart_pistol/smart_pistol#zone0', group='equipment', id=unhex('2da46765ff3489cf'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00002041'), interact_type=2},
    {name='content/fac_helldivers/equipment/support_weapons/automatic_cannon/automatic_cannon#zone0', group='equipment', id=unhex('5f5c0b6f31fbcfa8'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00000041'), interact_type=13},
    {name='content/fac_helldivers/equipment/support_weapons/automatic_cannon/automatic_cannon#zone1', group='equipment', id=unhex('5f5c0b6f31fbcfa8'), zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000a041'), interact_type=3},
    {name='content/objectives/obj_bugs/retrieve_larva/bug_larva_container_backpack#zone0', group='equipment', id=unhex('66e7f8a6ee9ca89e'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00008040'), interact_type=13},
    {name='content/objectives/obj_bugs/retrieve_larva/bug_larva_container_backpack#zone1', group='equipment', id=unhex('66e7f8a6ee9ca89e'), zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000a041'), interact_type=29},
    {name='content/fac_helldivers/equipment/support_weapons/heavy_mg/heavy_mg#zone0', group='equipment', id=unhex('18c40a7b14d55221'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00000041'), interact_type=13},
    {name='content/fac_helldivers/equipment/support_weapons/heavy_mg/heavy_mg#zone1', group='equipment', id=unhex('18c40a7b14d55221'), zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000a041'), interact_type=3},
    {name='content/env_shared/assets/samples/crystalized_e710_sample_01/crystalized_e710_sample_01#zone0', group='samples', id=unhex('aa495a812e2a97ad'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000403f'), before=unhex('00001041'), interact_type=11},
    {name='content/env_super_earth/samples/research_artifact_sample_01#zone0', group='samples', id=unhex('57f2d1ed4dd41acf'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000403f'), before=unhex('00001041'), interact_type=11},
    {name='content/fac_helldivers/equipment/backpacks/drone_weapons/drone_laser_rifle/drone_laser_rifle_mount#zone0', group='equipment', id=unhex('2c3d54b201c2662c'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00002041'), interact_type=1},
    {name='content/env_shared/assets/samples/tech_sample_01/tech_sample_01#zone0', group='samples', id=unhex('bf4155e900950e70'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000403f'), before=unhex('00001041'), interact_type=11},
    {name='content/fac_helldivers/equipment/backpacks/directional_energy_shield/directional_energy_shield_backpack#zone0', group='equipment', id=unhex('0ab40148f896e7a4'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00008040'), interact_type=13},
    {name='content/fac_helldivers/equipment/backpacks/directional_energy_shield/directional_energy_shield_backpack#zone1', group='equipment', id=unhex('0ab40148f896e7a4'), zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00002041'), interact_type=29},
    {name='content/fac_helldivers/discoverables/grenade_box_discoverable_01/grenade_box_discoverable_01#zone0', group='supplies', id=unhex('9c4093f0fb34af97'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00008040'), interact_type=6},
    {name='content/fac_helldivers/equipment/support_weapons/expendable_napalm_launcher/expendable_napalm_launcher#zone0', group='equipment', id=unhex('9e5f6085d1e0b5b2'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00000041'), interact_type=13},
    {name='content/fac_helldivers/equipment/support_weapons/expendable_napalm_launcher/expendable_napalm_launcher#zone1', group='equipment', id=unhex('9e5f6085d1e0b5b2'), zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000a041'), interact_type=3},
    {name='content/fac_helldivers/vehicles/frv/armaments/frv_mg/frv_mg#zone0', group='equipment', id=unhex('4ec28e03db1e5c08'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00000041'), interact_type=13},
    {name='content/fac_helldivers/vehicles/frv/armaments/frv_mg/frv_mg#zone1', group='equipment', id=unhex('4ec28e03db1e5c08'), zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000a041'), interact_type=3},
    {name='unresolved_hellpod_equipment_073270650f859dd0#zone0', group='equipment', id=unhex('d09d850f65703207'), zone=0, zone_name=0x4CCB322C, radius=unhex('00000040'), before=unhex('00008040'), interact_type=13},
    {name='unresolved_backpack_073270650f859dd0#zone1', group='equipment', id=unhex('d09d850f65703207'), zone=1, zone_name=0x4CCB322C, radius=unhex('00000040'), before=unhex('0000a041'), interact_type=29},
    {name='content/fac_helldivers/equipment/sidearm_weapons/magnum_pistol/magnum_pistol#zone0', group='equipment', id=unhex('a1d2b8e15871431a'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00002041'), interact_type=2},
    {name='content/objectives/obj_cyborgs/cyborg_carry_data/cy_carry_data#zone0', group='equipment', id=unhex('a1624ca4865e0e9e'), zone=0, zone_name=0xF2760503, radius=unhex('0000803f'), before=unhex('0000a041'), interact_type=31},
    {name='content/fac_helldivers/equipment/backpacks/medic_backpack/medic_backpack#zone0', group='equipment', id=unhex('1d982b0904e5550a'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00008040'), interact_type=13},
    {name='content/fac_helldivers/equipment/backpacks/medic_backpack/medic_backpack#zone1', group='equipment', id=unhex('1d982b0904e5550a'), zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00002041'), interact_type=29},
    {name='content/fac_helldivers/equipment/melee_weapons/stun_spear/stun_spear#zone0', group='equipment', id=unhex('64b4fc07ddaeb6e3'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00002041'), interact_type=2},
    {name='unresolved_mission_carryable_74f33bd19068a439#zone0', group='equipment', id=unhex('39a46890d13bf374'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00008040'), interact_type=31},
    {name='content/fac_helldivers/equipment/backpacks/drone_weapons/drone_assault_rifle/drone_assault_rifle_backpack#zone0', group='equipment', id=unhex('819dbb8aa55a8ae8'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00008040'), interact_type=13},
    {name='content/fac_helldivers/equipment/backpacks/drone_weapons/drone_assault_rifle/drone_assault_rifle_backpack#zone1', group='equipment', id=unhex('819dbb8aa55a8ae8'), zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00002041'), interact_type=29},
    {name='content/fac_helldivers/equipment/melee_weapons/chainsaw_greatsword/chainsaw_greatsword#zone0', group='equipment', id=unhex('a4b5bfea2afd4cbf'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000a041'), interact_type=3},
    {name='content/fac_helldivers/equipment/melee_weapons/chainsaw_greatsword/chainsaw_greatsword#zone1', group='equipment', id=unhex('a4b5bfea2afd4cbf'), zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00000041'), interact_type=13},
    {name='content/fac_helldivers/equipment/support_weapons/air_burst_rocket_launcher/air_burst_rocket_launcher#zone0', group='equipment', id=unhex('965227ea3704e426'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00000041'), interact_type=13},
    {name='content/fac_helldivers/equipment/support_weapons/air_burst_rocket_launcher/air_burst_rocket_launcher#zone1', group='equipment', id=unhex('965227ea3704e426'), zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000a041'), interact_type=3},
    {name='unresolved_hellpod_equipment_dfc8b9519169b67a#zone0', group='equipment', id=unhex('7ab6699151b9c8df'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00008040'), interact_type=13},
    {name='unresolved_backpack_dfc8b9519169b67a#zone1', group='equipment', id=unhex('7ab6699151b9c8df'), zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00002041'), interact_type=29},
    {name='content/fac_helldivers/equipment/backpacks/ballistic_shield_backpack_small/ballistic_shield_backpack_small#zone0', group='equipment', id=unhex('9882732bc7ea9a5f'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00008040'), interact_type=13},
    {name='content/fac_helldivers/equipment/backpacks/ballistic_shield_backpack_small/ballistic_shield_backpack_small#zone1', group='equipment', id=unhex('9882732bc7ea9a5f'), zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00002041'), interact_type=29},
    {name='content/objectives/obj_cyborgs/cyborg_airbase_control_tower/cyborg_carry_data#zone0', group='equipment', id=unhex('886b5ea2233c993e'), zone=0, zone_name=0xF2760503, radius=unhex('0000803f'), before=unhex('0000a041'), interact_type=31},
    {name='content/objectives/obj_common/briefcase/briefcase#zone0', group='equipment', id=unhex('a1d663c5ea1f0090'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000a041'), interact_type=31},
    {name='content/fac_helldivers/equipment/support_weapons/expendable_machinegun/expendable_machinegun#zone0', group='equipment', id=unhex('779ba50a499d6cb1'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00000041'), interact_type=13},
    {name='content/fac_helldivers/equipment/support_weapons/expendable_machinegun/expendable_machinegun#zone1', group='equipment', id=unhex('779ba50a499d6cb1'), zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000a041'), interact_type=3},
    {name='content/objectives/obj_cyborgs/cyborg_orbital_cannon/cy_orbital_cannon_ammo_carry#zone0', group='carry', id=unhex('b34122ed6f272657'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00008040'), interact_type=31},
    {name='content/fac_helldivers/equipment/backpacks/automatic_cannon_backpack/automatic_cannon_backpack#zone0', group='equipment', id=unhex('4c0f09e045e00ae6'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00008040'), interact_type=13},
    {name='content/fac_helldivers/equipment/backpacks/automatic_cannon_backpack/automatic_cannon_backpack#zone1', group='equipment', id=unhex('4c0f09e045e00ae6'), zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00002041'), interact_type=29},
    {name='content/fac_helldivers/equipment/backpacks/backpack_base#zone0', group='equipment', id=unhex('868ef9ea2ad02687'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00008040'), interact_type=13},
    {name='content/fac_helldivers/equipment/backpacks/backpack_base#zone1', group='equipment', id=unhex('868ef9ea2ad02687'), zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00002041'), interact_type=29},
    {name='unresolved_hellpod_equipment_4f8a477e577aaba9#zone0', group='equipment', id=unhex('a9ab7a577e478a4f'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00000041'), interact_type=13},
    {name='unresolved_dropped_weapon_4f8a477e577aaba9#zone1', group='equipment', id=unhex('a9ab7a577e478a4f'), zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000a041'), interact_type=3},
    {name='content/fac_helldivers/equipment/backpacks/air_burst_rocket_backpack/air_burst_rocket_backpack#zone0', group='equipment', id=unhex('ac128a858ed65ce7'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00008040'), interact_type=13},
    {name='content/fac_helldivers/equipment/backpacks/air_burst_rocket_backpack/air_burst_rocket_backpack#zone1', group='equipment', id=unhex('ac128a858ed65ce7'), zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00002041'), interact_type=29},
    {name='unresolved_hellpod_equipment_b9606c5aab32c3c2#zone0', group='equipment', id=unhex('c2c332ab5a6c60b9'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00000041'), interact_type=13},
    {name='unresolved_dropped_weapon_b9606c5aab32c3c2#zone1', group='equipment', id=unhex('c2c332ab5a6c60b9'), zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000a041'), interact_type=3},
    {name='unresolved_mission_carryable_0dc9084e50c051f3#zone0', group='equipment', id=unhex('f351c0504e08c90d'), zone=0, zone_name=0xF2760503, radius=unhex('0000803f'), before=unhex('00004041'), interact_type=31},
    {name='unresolved_hellpod_equipment_1b00bca55e364292#zone0', group='equipment', id=unhex('9242365ea5bc001b'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00008040'), interact_type=13},
    {name='unresolved_backpack_1b00bca55e364292#zone1', group='equipment', id=unhex('9242365ea5bc001b'), zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00002041'), interact_type=29},
    {name='content/fac_helldivers/equipment/support_weapons/lat_oneshot/lat_oneshot#zone0', group='equipment', id=unhex('d30169eda02f9380'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00000041'), interact_type=13},
    {name='content/fac_helldivers/equipment/support_weapons/lat_oneshot/lat_oneshot#zone1', group='equipment', id=unhex('d30169eda02f9380'), zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000a041'), interact_type=3},
    {name='content/fac_helldivers/discoverables/health_pack_discoverable_01/health_pack_discoverable_01#zone0', group='supplies', id=unhex('65792f925b4ccab4'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00008040'), interact_type=5},
    {name='content/fac_helldivers/equipment/backpacks/jumppack_backpack/jumppack_backpack#zone0', group='equipment', id=unhex('79b3499483cac559'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00008040'), interact_type=13},
    {name='content/fac_helldivers/equipment/backpacks/jumppack_backpack/jumppack_backpack#zone1', group='equipment', id=unhex('79b3499483cac559'), zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00002041'), interact_type=29},
    {name='content/fac_helldivers/equipment/backpacks/faf_missile_launcher_helghast_backpack/faf_missile_launcher_helghast_backpack#zone0', group='equipment', id=unhex('f31e1c19ccb0feb8'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00008040'), interact_type=13},
    {name='content/fac_helldivers/equipment/backpacks/faf_missile_launcher_helghast_backpack/faf_missile_launcher_helghast_backpack#zone1', group='equipment', id=unhex('f31e1c19ccb0feb8'), zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00002041'), interact_type=29},
    {name='content/fac_helldivers/equipment/backpacks/guard_dog_stun_backpack/guard_dog_stun_backpack#zone0', group='equipment', id=unhex('fa3d2eb112a78dc2'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00008040'), interact_type=13},
    {name='content/fac_helldivers/equipment/backpacks/guard_dog_stun_backpack/guard_dog_stun_backpack#zone1', group='equipment', id=unhex('fa3d2eb112a78dc2'), zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00002041'), interact_type=29},
    {name='unresolved_sample_type_1_4c63119f69165321#zone0', group='samples', id=unhex('215316699f11634c'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000403f'), before=unhex('00001041'), interact_type=11},
    {name='unresolved_mission_carryable_8ad7a3118bd48d1c#zone0', group='equipment', id=unhex('1c8dd48b11a3d78a'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000a041'), interact_type=31},
    {name='content/objectives/obj_common/seaf_artillery/seaf_shell#zone0', group='carry', id=unhex('e9e6a96669161240'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00008040'), interact_type=31},
    {name='content/env_shared/assets/samples/super_uranium/super_uranium_sample_01#zone0', group='samples', id=unhex('1ab4b669fa35499d'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000403f'), before=unhex('00001041'), interact_type=11},
    {name='unresolved_hellpod_equipment_35b5af8b1e859540#zone0', group='equipment', id=unhex('4095851e8bafb535'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00008040'), interact_type=13},
    {name='unresolved_backpack_35b5af8b1e859540#zone1', group='equipment', id=unhex('4095851e8bafb535'), zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00002041'), interact_type=29},
    {name='content/env_shared_arctic/assets/samples/crystal_sample_01#zone0', group='samples', id=unhex('a945de3bf8f2d6b4'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000403f'), before=unhex('00001041'), interact_type=11},
    {name='content/fac_helldivers/equipment/backpacks/c4_charge_backpack/c4_charge_detonator#zone0', group='equipment', id=unhex('3d2ff521630df551'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00000041'), interact_type=13},
    {name='content/fac_helldivers/equipment/backpacks/c4_charge_backpack/c4_charge_detonator#zone1', group='equipment', id=unhex('3d2ff521630df551'), zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000a041'), interact_type=3},
    {name='unresolved_hellpod_equipment_b43235dbd493750c#zone0', group='equipment', id=unhex('0c7593d4db3532b4'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00000041'), interact_type=13},
    {name='unresolved_dropped_weapon_b43235dbd493750c#zone1', group='equipment', id=unhex('0c7593d4db3532b4'), zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000a041'), interact_type=3},
    {name='content/entities/base_sample_static#zone0', group='samples', id=unhex('38940c0f734f9bbc'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000403f'), before=unhex('00001041'), interact_type=11},
    {name='content/fac_helldivers/equipment/support_weapons/energy_weapon_shark/energy_weapon_shark#zone0', group='equipment', id=unhex('66021a80f8c7fc6c'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00000041'), interact_type=13},
    {name='content/fac_helldivers/equipment/support_weapons/energy_weapon_shark/energy_weapon_shark#zone1', group='equipment', id=unhex('66021a80f8c7fc6c'), zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000a041'), interact_type=3},
    {name='content/env_cyborg/samples/automaton_intel_sample_01#zone0', group='samples', id=unhex('9e42f5bad28604cd'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000403f'), before=unhex('00001041'), interact_type=42},
    {name='unresolved_mission_carryable_4a3e722b5a865e38#zone0', group='equipment', id=unhex('385e865a2b723e4a'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000a041'), interact_type=31},
    {name='unresolved_mission_carryable_e09fcb5a280acb1d#zone0', group='carry', id=unhex('1dcb0a285acb9fe0'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00008040'), interact_type=31},
    {name='content/fac_helldivers/equipment/backpacks/heavy_flamethrower_backpack/heavy_flamethrower_backpack#zone0', group='equipment', id=unhex('e060181a3c1ceb43'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00008040'), interact_type=13},
    {name='content/fac_helldivers/equipment/backpacks/heavy_flamethrower_backpack/heavy_flamethrower_backpack#zone1', group='equipment', id=unhex('e060181a3c1ceb43'), zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00002041'), interact_type=29},
    {name='unresolved_hellpod_equipment_88f61afff48ac8a4#zone0', group='equipment', id=unhex('a4c88af4ff1af688'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00000041'), interact_type=13},
    {name='unresolved_dropped_weapon_88f61afff48ac8a4#zone1', group='equipment', id=unhex('a4c88af4ff1af688'), zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000a041'), interact_type=3},
    {name='content/fac_helldivers/equipment/backpacks/drone_flamethrower_backpack/drone_flamethrower_backpack#zone0', group='equipment', id=unhex('4d8d9fa66a621530'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00008040'), interact_type=13},
    {name='content/fac_helldivers/equipment/backpacks/drone_flamethrower_backpack/drone_flamethrower_backpack#zone1', group='equipment', id=unhex('4d8d9fa66a621530'), zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00002041'), interact_type=29},
    {name='content/fac_helldivers/equipment/support_weapons/expendable_massive_rocket_launcher/expendable_massive_rocket_launcher#zone0', group='equipment', id=unhex('c738ac6527641776'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00000041'), interact_type=13},
    {name='content/fac_helldivers/equipment/support_weapons/expendable_massive_rocket_launcher/expendable_massive_rocket_launcher#zone1', group='equipment', id=unhex('c738ac6527641776'), zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000a041'), interact_type=3},
    {name='content/env_shared/assets/samples/artifact_sample_01/artifact_sample_01#zone0', group='samples', id=unhex('83c3d5735ccf9fb3'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000403f'), before=unhex('00001041'), interact_type=11},
    {name='unresolved_hellpod_equipment_26bddf070c31b275#zone0', group='equipment', id=unhex('75b2310c07dfbd26'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00008040'), interact_type=13},
    {name='unresolved_backpack_26bddf070c31b275#zone1', group='equipment', id=unhex('75b2310c07dfbd26'), zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00002041'), interact_type=29},
    {name='unresolved_mission_carryable_0f1a0189b327c5cb#zone0', group='equipment', id=unhex('cbc527b389011a0f'), zone=0, zone_name=0xF2760503, radius=unhex('0000803f'), before=unhex('0000a041'), interact_type=31},
    {name='content/fac_helldivers/equipment/backpacks/c4_charge_backpack/c4_charge_backpack#zone0', group='equipment', id=unhex('7167a2441cf8182a'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00008040'), interact_type=13},
    {name='content/fac_helldivers/equipment/backpacks/c4_charge_backpack/c4_charge_backpack#zone1', group='equipment', id=unhex('7167a2441cf8182a'), zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00002041'), interact_type=29},
    {name='content/env_shared/assets/samples/legendarium_sample_01/legendarium_sample_01#zone0', group='samples', id=unhex('3dc267252c06fede'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000403f'), before=unhex('00001041'), interact_type=11},
    {name='unresolved_mission_carryable_c8f9a2233048b836#zone0', group='equipment', id=unhex('36b8483023a2f9c8'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00008040'), interact_type=31},
    {name='content/fac_helldivers/equipment/support_weapons/laser_guided_missile_launcher/laser_guided_missile_launcher#zone0', group='equipment', id=unhex('cb162b143d129059'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00000041'), interact_type=13},
    {name='content/fac_helldivers/equipment/support_weapons/laser_guided_missile_launcher/laser_guided_missile_launcher#zone1', group='equipment', id=unhex('cb162b143d129059'), zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000a041'), interact_type=3},
    {name='unresolved_mission_carryable_8f7d4d9c196018c8#zone0', group='equipment', id=unhex('c81860199c4d7d8f'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000a041'), interact_type=31},
    {name='content/env_bugs/assets/samples/bug_intel_sample_01#zone0', group='samples', id=unhex('b5527382b3339576'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000403f'), before=unhex('00001041'), interact_type=42},
    {name='content/fac_helldivers/equipment/backpacks/drone_mg/drone_mg_backpack#zone0', group='equipment', id=unhex('ecced76757bc5e25'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00008040'), interact_type=13},
    {name='content/fac_helldivers/equipment/backpacks/drone_mg/drone_mg_backpack#zone1', group='equipment', id=unhex('ecced76757bc5e25'), zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00002041'), interact_type=29},
    {name='unresolved_hellpod_equipment_35f50dec0ec647c6#zone0', group='equipment', id=unhex('c647c60eec0df535'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000003f'), before=unhex('00008040'), interact_type=13},
    {name='unresolved_backpack_35f50dec0ec647c6#zone1', group='equipment', id=unhex('c647c60eec0df535'), zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000c040'), interact_type=29},
    {name='content/fac_helldivers/equipment/support_weapons/plasma_blaster/plasma_blaster#zone0', group='equipment', id=unhex('540e78d79af4d5e8'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00000041'), interact_type=13},
    {name='content/fac_helldivers/equipment/support_weapons/plasma_blaster/plasma_blaster#zone1', group='equipment', id=unhex('540e78d79af4d5e8'), zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000a041'), interact_type=3},
    {name='unresolved_mission_carryable_3e099ddf97acf85f#zone0', group='equipment', id=unhex('5ff8ac97df9d093e'), zone=0, zone_name=0xF2760503, radius=unhex('0000803f'), before=unhex('0000a041'), interact_type=31},
    {name='content/fac_helldivers/hellpod/ammo_rack/ammo_box#zone0', group='supplies', id=unhex('484a28eb12961149'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00008040'), interact_type=4},
    {name='content/objectives/obj_common/shoulder_mounted_camera/shoulder_mounted_camera#zone0', group='equipment', id=unhex('765ac010e9812437'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00000041'), interact_type=13},
    {name='content/objectives/obj_common/shoulder_mounted_camera/shoulder_mounted_camera#zone1', group='equipment', id=unhex('765ac010e9812437'), zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000a041'), interact_type=3},
    {name='content/objectives/obj_illuminate/il_artifact_01/il_artifact_01#zone0', group='equipment', id=unhex('42d259b41e7563b6'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000a041'), interact_type=31},
    {name='unresolved_mission_carryable_6b7ee87fb2ec6455#zone0', group='carry', id=unhex('5564ecb27fe87e6b'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00008040'), interact_type=31},
    {name='unresolved_mission_carryable_15e2a2b11ba78c5a#zone0', group='equipment', id=unhex('5a8ca71bb1a2e215'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000a041'), interact_type=31},
    {name='content/fac_helldivers/equipment/support_weapons/sniper_rifle/sniper_rifle#zone0', group='equipment', id=unhex('0742ca083e49c589'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00000041'), interact_type=13},
    {name='content/fac_helldivers/equipment/support_weapons/sniper_rifle/sniper_rifle#zone1', group='equipment', id=unhex('0742ca083e49c589'), zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000a041'), interact_type=3},
    {name='unresolved_mission_carryable_2d3bc1683a54298d#zone0', group='equipment', id=unhex('8d29543a68c13b2d'), zone=0, zone_name=0x4CCB322C, radius=unhex('00000040'), before=unhex('0000f041'), interact_type=31},
    {name='content/fac_helldivers/equipment/support_weapons/minigun/minigun#zone0', group='equipment', id=unhex('7c19fa9cb88ca543'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00000041'), interact_type=13},
    {name='content/fac_helldivers/equipment/support_weapons/minigun/minigun#zone1', group='equipment', id=unhex('7c19fa9cb88ca543'), zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000a041'), interact_type=3},
    {name='content/objectives/obj_common/carry_warhead/warhead_01#zone0', group='carry', id=unhex('3ad7a9a936015b70'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00008040'), interact_type=31},
    {name='unresolved_hellpod_equipment_9f27e0579375b865#zone0', group='equipment', id=unhex('65b8759357e0279f'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00000041'), interact_type=13},
    {name='unresolved_dropped_weapon_9f27e0579375b865#zone1', group='equipment', id=unhex('65b8759357e0279f'), zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000a041'), interact_type=3},
    {name='content/fac_super_earth/equipment/support_weapons/shotgun_doublebarrel/shotgun_doublebarrel#zone0', group='equipment', id=unhex('e4153426491f0752'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00000041'), interact_type=13},
    {name='content/fac_super_earth/equipment/support_weapons/shotgun_doublebarrel/shotgun_doublebarrel#zone1', group='equipment', id=unhex('e4153426491f0752'), zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000a041'), interact_type=3},
    {name='content/env_shared/assets/samples/blacksaffron_sample_01/blacksaffron_sample_01#zone0', group='samples', id=unhex('6625ed26847530bd'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000403f'), before=unhex('00001041'), interact_type=11},
    {name='content/fac_helldivers/equipment/support_weapons/faf_missile_launcher/faf_missile_launcher#zone0', group='equipment', id=unhex('eef43c64d42faa25'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00000041'), interact_type=13},
    {name='content/fac_helldivers/equipment/support_weapons/faf_missile_launcher/faf_missile_launcher#zone1', group='equipment', id=unhex('eef43c64d42faa25'), zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000a041'), interact_type=3},
    {name='content/fac_helldivers/equipment/backpacks/drone_mg/drone_mg_weapon#zone0', group='equipment', id=unhex('7933e1bde32126a3'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00002041'), interact_type=1},
    {name='content/fac_helldivers/equipment/support_weapons/railgun/railgun#zone0', group='equipment', id=unhex('609eb048dc0b9d2e'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00000041'), interact_type=13},
    {name='content/fac_helldivers/equipment/support_weapons/railgun/railgun#zone1', group='equipment', id=unhex('609eb048dc0b9d2e'), zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000a041'), interact_type=3},
    {name='content/fac_helldivers/equipment/support_weapons/harpoon_gun/harpoon_gun#zone0', group='equipment', id=unhex('97e8a91a05e22838'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00000041'), interact_type=13},
    {name='content/fac_helldivers/equipment/support_weapons/harpoon_gun/harpoon_gun#zone1', group='equipment', id=unhex('97e8a91a05e22838'), zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000a041'), interact_type=3},
    {name='content/fac_helldivers/equipment/backpacks/belt_fed_grenade_launcher_backpack/belt_fed_grenade_launcher_backpack#zone0', group='equipment', id=unhex('fd74f988b5154bbb'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00008040'), interact_type=13},
    {name='content/fac_helldivers/equipment/backpacks/belt_fed_grenade_launcher_backpack/belt_fed_grenade_launcher_backpack#zone1', group='equipment', id=unhex('fd74f988b5154bbb'), zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00002041'), interact_type=29},
    {name='content/fac_helldivers/equipment/backpacks/drone_weapons/drone_gas_projector/drone_gas_projector_mount#zone0', group='equipment', id=unhex('edca3b15baa229b7'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00002041'), interact_type=1},
    {name='content/env_cyborg/samples/automaton_sample_01#zone0', group='samples', id=unhex('72bf369ef0a0b2be'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000403f'), before=unhex('00001041'), interact_type=11},
    {name='content/fac_helldivers/equipment/support_weapons/flamethrower/flamethrower#zone0', group='equipment', id=unhex('bfa347518999ab39'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00000041'), interact_type=13},
    {name='content/fac_helldivers/equipment/support_weapons/flamethrower/flamethrower#zone1', group='equipment', id=unhex('bfa347518999ab39'), zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000a041'), interact_type=3},
    {name='unresolved_sample_type_1_4932cbf33cd47ef9#zone0', group='samples', id=unhex('f97ed43cf3cb3249'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000403f'), before=unhex('00001041'), interact_type=11},
    {name='unresolved_hellpod_equipment_1d5943301a29c940#zone0', group='equipment', id=unhex('40c9291a3043591d'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00000041'), interact_type=13},
    {name='unresolved_dropped_weapon_1d5943301a29c940#zone1', group='equipment', id=unhex('40c9291a3043591d'), zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000a041'), interact_type=3},
    {name='content/fac_helldivers/equipment/support_weapons/heavy_flamethrower/heavy_flamethrower#zone0', group='equipment', id=unhex('9507a7635f18a878'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00000041'), interact_type=13},
    {name='content/fac_helldivers/equipment/support_weapons/heavy_flamethrower/heavy_flamethrower#zone1', group='equipment', id=unhex('9507a7635f18a878'), zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000a041'), interact_type=3},
    {name='content/fac_helldivers/equipment/sidearm_weapons/standard_pistol/standard_pistol#zone0', group='equipment', id=unhex('a2446edbc2e5e405'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00002041'), interact_type=2},
    {name='content/fac_helldivers/equipment/support_weapons/grenade_launcher_tactical/grenade_launcher_tactical#zone0', group='equipment', id=unhex('9b3fa6cfb2293bfe'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00000041'), interact_type=13},
    {name='content/fac_helldivers/equipment/support_weapons/grenade_launcher_tactical/grenade_launcher_tactical#zone1', group='equipment', id=unhex('9b3fa6cfb2293bfe'), zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000a041'), interact_type=3},
    {name='content/env_super_earth/samples/research_sample_01#zone0', group='samples', id=unhex('ba818869e7097e30'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000403f'), before=unhex('00001041'), interact_type=11},
    {name='content/fac_helldivers/equipment/backpacks/bomb_backpack/bomb_backpack#zone1', group='equipment', id=unhex('8ebc1a423886ce9a'), zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00002041'), interact_type=13},
    {name='content/fac_helldivers/equipment/backpacks/bomb_backpack/bomb_backpack#zone2', group='equipment', id=unhex('8ebc1a423886ce9a'), zone=2, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00002041'), interact_type=29},
    {name='content/fac_helldivers/equipment/sidearm_weapons/pistol_broomhandle/pistol_broomhandle#zone0', group='equipment', id=unhex('0fda4795d7bc80c7'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00002041'), interact_type=2},
    {name='unresolved_mission_carryable_c02c2623b6359bb3#zone0', group='carry', id=unhex('b39b35b623262cc0'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00008040'), interact_type=31},
    {name='content/objectives/obj_cyborgs/cyborg_chemicals_backpack/cy_chemicals_backpack#zone0', group='equipment', id=unhex('6b047e6ef660ec43'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00008040'), interact_type=13},
    {name='content/objectives/obj_cyborgs/cyborg_chemicals_backpack/cy_chemicals_backpack#zone1', group='equipment', id=unhex('6b047e6ef660ec43'), zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000a041'), interact_type=29},
    {name='content/env_bugs/assets/samples/bug_enemy_sample_01#zone0', group='samples', id=unhex('a70bcd41648363d4'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000403f'), before=unhex('00001041'), interact_type=11},
    {name='content/fac_helldivers/equipment/sidearm_weapons/pistol_nacho/pistol_nacho#zone0', group='equipment', id=unhex('c574b78770c7584d'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00002041'), interact_type=2},
    {name='content/env_illuminate/samples/illuminate_enemy_sample_01#zone0', group='samples', id=unhex('9fc129e1d64e41a2'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000403f'), before=unhex('00001041'), interact_type=11},
    {name='content/fac_helldivers/equipment/backpacks/drone_weapons/drone_flamethrower/drone_flamethrower_mount#zone0', group='equipment', id=unhex('c6f323ba2543cd65'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00002041'), interact_type=1},
    {name='content/fac_helldivers/equipment/support_weapons/arc_thrower/arc_thrower#zone0', group='equipment', id=unhex('e606730fd59cde96'), zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00000041'), interact_type=13},
    {name='content/fac_helldivers/equipment/support_weapons/arc_thrower/arc_thrower#zone1', group='equipment', id=unhex('e606730fd59cde96'), zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000a041'), interact_type=3},
}

local function read_only_data(target)
    local page = query(target)
    return page ~= nil and page.state == 0x1000 and page.kind == 0x20000 and page.protect == 0x02
end

-- Instance layout: 28-byte header, 2*N map entries {id[8], index u32, pad u32}, then N records.
local function open_table(instance, magic, record_bytes)
    local header = read(instance, 28)
    if not header or u32(header,8) ~= 1 or u32(header,12) ~= magic
       or header:byte(21) ~= 1 then
        return nil
    end
    local size = u32(header,16)
    local records = size/(32+record_bytes)
    if records < 1 or records % 1 ~= 0 then return nil end
    local data = read(instance+28, size)
    if not data then return nil end
    local map_bytes = records*32
    local map = {}
    for at=0,map_bytes-16,16 do
        map[data:sub(at+1,at+8)] = u32(data,at+8)
    end
    return {instance=instance, data=data, map=map, map_bytes=map_bytes, records=records}
end

local function record_of(tbl, id, record_bytes)
    local index = tbl.map[id]
    if index and index < tbl.records then return tbl.map_bytes + index*record_bytes end
end

local FLAGS = unhex('01010100')
local function zone_target(tbl, resource)
    local record = record_of(tbl, resource.id, RECORD_BYTES)
    if not record then return nil end
    local data, zone = tbl.data, record + 8 + resource.zone*136
    if zone+44 > #data or data:sub(record+1,record+4) ~= FLAGS
       or u32(data,zone) ~= resource.zone_name
       or data:sub(zone+5,zone+8) ~= resource.radius
       or data:sub(zone+9,zone+12) ~= resource.before
       or u32(data,zone+40) ~= resource.interact_type then
        return nil
    end
    local target = tbl.instance + 28 + zone + 8
    if read_only_data(target) then return {resource=resource, group=resource.group, target=target, radius=target-4} end
end

local HEALTH_MARKER = {name='health_item_marker', before=unhex('00000000'), on=unhex('0a000000')}
local function health_target(tbl)
    local health = record_of(tbl, unhex('65792f925b4ccab4'), SPOT_RECORD_BYTES)
    local rack = record_of(tbl, unhex('a829a746c6168d3b'), SPOT_RECORD_BYTES)
    if not (health and rack) then return nil end
    local data = tbl.data
    if u32(data,health+20) ~= 0 or u32(data,rack+20) ~= 10
       or data:byte(health+33) ~= 1 or data:byte(rack+33) ~= 1
       or data:sub(health+57,health+68) ~= data:sub(rack+57,rack+68)
       or data:sub(health+57,health+64) ~= unhex('847193dcb7d27cb0') then
        return nil
    end
    local target = tbl.instance + 28 + health + 20
    if read_only_data(target) then return {resource=HEALTH_MARKER, group='supplies', marker=true, target=target} end
end

-- Finds data tables by header in read-only mapped memory; each region is scanned once, one chunk per frame.
local found = {[INTERACTION]={}, [SPOTTABLE]={}}
local scanned = {}
local chunk = ffi.new('uint8_t[?]', SCAN_CHUNK+16)
local words = ffi.cast('const uint32_t *', chunk)
local chunk_count = ffi.new('size_t[1]')

local function scan(base, size)
    for offset=0,size-16,SCAN_CHUNK do
        local length = math.min(SCAN_CHUNK+16, size-offset)
        if kernel.ReadProcessMemory(process, ffi.cast('const void *', base+offset),
                                    chunk, length, chunk_count) == 0 then
            return
        end
        for i=0,math.min(SCAN_CHUNK/4-1, math.floor((length-16)/4)) do
            if words[i+1] == LDLD then
                local magic = words[i]
                local list = found[magic]
                if list and words[i+3] == magic and words[i+2] == 1 then
                    list[#list+1] = base+offset+i*4
                end
            end
        end
        coroutine.yield()
    end
end

local function locate()
    local address = 0
    while address < 0x800000000000 do
        local region = query(address)
        if not region then break end
        local base, size = address_of(region.base), tonumber(region.size)
        assert(size > 0 and base+size > address, 'Invalid memory map')
        if region.state == 0x1000 and region.kind == 0x20000
           and region.protect == 0x02 and scanned[base] ~= size then
            scanned[base] = size
            scan(base, size)
        end
        address = base+size
    end
end

local function set_view(entry, expected, replacement)
    local resource, target = entry.resource, entry.target
    local location = ffi.cast('void *', target)
    local old = ffi.new('uint32_t[1]')
    assert(read(target,4) == expected, resource.name..' field changed before write')
    if entry.radius then
        assert(read(entry.radius,4) == resource.radius,
               resource.name..' radius changed before write')
    end
    assert(kernel.VirtualProtect(location,4,0x04,old) ~= 0,
           resource.name..' cannot unlock data page')
    local ok, problem = pcall(function()
        assert(old[0] == 0x02, resource.name..' original page protection mismatch')
        assert(write(target,replacement), resource.name..' field write failed')
        assert(read(target,4) == replacement, resource.name..' readback mismatch')
        if entry.radius then
            assert(read(entry.radius,4) == resource.radius,
                   resource.name..' radius changed unexpectedly')
        end
    end)
    local rollback_ok = true
    if not ok then
        local current = read(target,4)
        if current ~= expected then
            rollback_ok = write(target,expected) and read(target,4) == expected
        end
    end
    local restored = ffi.new('uint32_t[1]')
    local protect_ok = kernel.VirtualProtect(location,4,old[0],restored) ~= 0
    assert(protect_ok,
           resource.name..' cannot restore page protection')
    assert(rollback_ok, resource.name..' rollback failed: '..tostring(problem))
    assert(ok, problem)
end

-- In-game settings through Mod Options Menu; without it the defaults below apply.
local MENU_ID = 'codex.extended_pickup_icons'
local GROUPS = {
    {key='samples', default=35},
    {key='supplies', default=20}, {key='equipment', default=35},
    {key='carry', default=15, switch='equipment'},
}
local GROUP = {}
for _, group in ipairs(GROUPS) do GROUP[group.key] = group end

local TEXTS = {
    en={note="Changes take effect from the next mission. Very high distances can fill the screen with icons and spoil the game. This mod's default (the lowest setting) is recommended.",
        samples='Samples', samples_distance='Sample distance',
        supplies='Supplies', supplies_distance='Supply distance',
        equipment='Equipment & mission items', equipment_distance='Equipment distance',
        carry_distance='Carried ammo & warhead distance',
        samples_info='How far away sample icons appear: common, rare and super samples, plus intel. Off uses the game\'s own distance.',
        supplies_info='How far away ammo box, grenade pack, stim and resupply icons appear. On also marks stims with their ping icon.',
        equipment_info='How far away icons for support weapons, sidearms, melee weapons, backpacks and mission items appear. Off uses the game\'s own distance.',
        carry_info='How far away icons for SEAF shells, carried ammunition and warheads appear. Turned on and off with Equipment.'},
    ko={note="변경은 다음 미션부터 적용됩니다. 거리를 너무 높이면 화면에 아이콘이 너무 많이 떠서 게임 경험을 망칠 수 있습니다. 이 모드의 기본값(가장 낮은 값)을 권장합니다.",
        samples='샘플', samples_distance='샘플 거리',
        supplies='보급품', supplies_distance='보급품 거리',
        equipment='장비 및 임무 아이템', equipment_distance='장비 거리',
        carry_distance='운반 탄약 및 탄두 거리',
        samples_info='샘플 아이콘이 보이기 시작하는 거리입니다. 일반, 희귀, 슈퍼 샘플과 정보 샘플을 포함합니다. 끄면 게임 기본 거리를 씁니다.',
        supplies_info='탄약 상자, 수류탄 팩, 자극제, 재보급품 아이콘이 보이기 시작하는 거리입니다. 켜면 자극제에 핑 아이콘도 표시합니다.',
        equipment_info='지원 무기, 보조 무기, 근접 무기, 백팩, 임무 아이템 아이콘이 보이기 시작하는 거리입니다. 끄면 게임 기본 거리를 씁니다.',
        carry_info='SEAF 포탄, 운반 탄약, 탄두 아이콘이 보이기 시작하는 거리입니다. 장비 및 임무 아이템과 함께 켜고 꺼집니다.'},
    ja={note="変更は次のミッションから反映されます。距離を上げすぎると画面にアイコンがあふれ、ゲーム体験を損なう場合があります。このMODの初期値(一番低い値)をおすすめします。",
        samples='サンプル', samples_distance='サンプルの距離',
        supplies='補給品', supplies_distance='補給品の距離',
        equipment='装備と任務アイテム', equipment_distance='装備の距離',
        carry_distance='運搬弾薬と弾頭の距離',
        samples_info='サンプルのアイコンが表示され始める距離です。通常、レア、スーパーサンプルと情報サンプルを含みます。オフでゲーム本来の距離になります。',
        supplies_info='弾薬箱、グレネードパック、スティム、補給品のアイコンが表示され始める距離です。オンにするとスティムにピンアイコンも表示します。',
        equipment_info='支援武器、サイドアーム、近接武器、バックパック、任務アイテムのアイコンが表示され始める距離です。オフでゲーム本来の距離になります。',
        carry_info='SEAF砲弾、運搬弾薬、弾頭のアイコンが表示され始める距離です。装備と任務アイテムの設定と一緒に切り替わります。'},
    ['zh-Hans']={note="更改从下一个任务开始生效。距离设得过高会让屏幕上出现过多图标，影响游戏体验。建议使用本模组的默认值(最低值)。",
        samples='样本', samples_distance='样本距离',
        supplies='补给品', supplies_distance='补给品距离',
        equipment='装备与任务物品', equipment_distance='装备距离',
        carry_distance='搬运弹药与弹头距离',
        samples_info='样本图标开始显示的距离。包括普通、稀有、超级样本和情报样本。关闭时使用游戏原本的距离。',
        supplies_info='弹药箱、手雷包、兴奋剂和补给包图标开始显示的距离。开启时还会用标记图标显示兴奋剂。',
        equipment_info='支援武器、副武器、近战武器、背包和任务物品图标开始显示的距离。关闭时使用游戏原本的距离。',
        carry_info='SEAF炮弹、搬运弹药和弹头图标开始显示的距离。随装备与任务物品一起开启或关闭。'},
    ['zh-Hant']={note="變更從下一個任務開始生效。距離設得過高會讓畫面上出現過多圖示，影響遊戲體驗。建議使用本模組的預設值(最低值)。",
        samples='樣本', samples_distance='樣本距離',
        supplies='補給品', supplies_distance='補給品距離',
        equipment='裝備與任務物品', equipment_distance='裝備距離',
        carry_distance='搬運彈藥與彈頭距離',
        samples_info='樣本圖示開始顯示的距離。包括普通、稀有、超級樣本和情報樣本。關閉時使用遊戲原本的距離。',
        supplies_info='彈藥箱、手榴彈包、興奮劑和補給包圖示開始顯示的距離。開啟時還會以標記圖示顯示興奮劑。',
        equipment_info='支援武器、副武器、近戰武器、背包和任務物品圖示開始顯示的距離。關閉時使用遊戲原本的距離。',
        carry_info='SEAF砲彈、搬運彈藥和彈頭圖示開始顯示的距離。隨裝備與任務物品一起開啟或關閉。'},
    de={note="Änderungen gelten ab der nächsten Mission. Sehr hohe Distanzen füllen den Bildschirm mit Symbolen und können das Spielerlebnis verderben. Empfohlen wird der Standardwert dieser Mod (die niedrigste Stufe).",
        samples='Proben', samples_distance='Distanz Proben',
        supplies='Nachschub', supplies_distance='Distanz Nachschub',
        equipment='Ausrüstung & Missionsobjekte', equipment_distance='Distanz Ausrüstung',
        carry_distance='Distanz Tragemunition & Sprengköpfe',
        samples_info='Ab welcher Entfernung Probensymbole erscheinen: normale, seltene und Superproben sowie Geheimdienstproben. Aus nutzt die Distanz des Spiels.',
        supplies_info='Ab welcher Entfernung Symbole für Munitionskisten, Granatenpakete, Stims und Nachschub erscheinen. An markiert Stims zusätzlich mit ihrem Ping-Symbol.',
        equipment_info='Ab welcher Entfernung Symbole für Unterstützungswaffen, Sekundärwaffen, Nahkampfwaffen, Rucksäcke und Missionsobjekte erscheinen. Aus nutzt die Distanz des Spiels.',
        carry_info='Ab welcher Entfernung Symbole für SEAF-Granaten, Tragemunition und Sprengköpfe erscheinen. Wird mit Ausrüstung ein- und ausgeschaltet.'},
    fr={note="Les changements s'appliquent à partir de la mission suivante. Une distance très élevée peut remplir l'écran d'icônes et gâcher l'expérience de jeu. La valeur par défaut de ce mod (la plus basse) est recommandée.",
        samples='Échantillons', samples_distance='Distance échantillons',
        supplies='Ravitaillement', supplies_distance='Distance ravitaillement',
        equipment='Équipement & objets de mission', equipment_distance='Distance équipement',
        carry_distance='Distance munitions portées & ogives',
        samples_info='Distance à laquelle les icônes d\'échantillons apparaissent : communs, rares, super-échantillons et renseignements. Désactivé utilise la distance du jeu.',
        supplies_info='Distance à laquelle apparaissent les icônes de caisses de munitions, packs de grenades, stims et ravitaillements. Activé marque aussi les stims avec leur icône de ping.',
        equipment_info='Distance à laquelle apparaissent les icônes d\'armes de soutien, armes secondaires, armes de mêlée, sacs à dos et objets de mission. Désactivé utilise la distance du jeu.',
        carry_info='Distance à laquelle apparaissent les icônes d\'obus SEAF, de munitions portées et d\'ogives. Activé et désactivé avec Équipement.'},
    es={note="Los cambios se aplican desde la siguiente misión. Una distancia muy alta puede llenar la pantalla de iconos y arruinar la experiencia de juego. Se recomienda el valor predeterminado de este mod (el más bajo).",
        samples='Muestras', samples_distance='Distancia muestras',
        supplies='Suministros', supplies_distance='Distancia suministros',
        equipment='Equipo y objetos de misión', equipment_distance='Distancia equipo',
        carry_distance='Distancia munición portátil y ojivas',
        samples_info='Distancia a la que aparecen los iconos de muestras: comunes, raras, supermuestras e inteligencia. Desactivado usa la distancia del juego.',
        supplies_info='Distancia a la que aparecen los iconos de cajas de munición, paquetes de granadas, estimulantes y suministros. Activado también marca los estimulantes con su icono.',
        equipment_info='Distancia a la que aparecen los iconos de armas de apoyo, secundarias, cuerpo a cuerpo, mochilas y objetos de misión. Desactivado usa la distancia del juego.',
        carry_info='Distancia a la que aparecen los iconos de proyectiles SEAF, munición portátil y ojivas. Se activa y desactiva con Equipo.'},
    it={note="Le modifiche si applicano dalla missione successiva. Distanze molto alte possono riempire lo schermo di icone e rovinare l'esperienza di gioco. Si consiglia il valore predefinito di questa mod (il più basso).",
        samples='Campioni', samples_distance='Distanza campioni',
        supplies='Rifornimenti', supplies_distance='Distanza rifornimenti',
        equipment='Equipaggiamento e oggetti missione', equipment_distance='Distanza equipaggiamento',
        carry_distance='Distanza munizioni trasportabili e testate',
        samples_info='Distanza a cui compaiono le icone dei campioni: comuni, rari, supercampioni e intel. Disattivato usa la distanza del gioco.',
        supplies_info='Distanza a cui compaiono le icone di casse di munizioni, pacchi di granate, stimolanti e rifornimenti. Attivato segna anche gli stimolanti con la loro icona.',
        equipment_info='Distanza a cui compaiono le icone di armi di supporto, secondarie, da mischia, zaini e oggetti di missione. Disattivato usa la distanza del gioco.',
        carry_info='Distanza a cui compaiono le icone di proiettili SEAF, munizioni trasportabili e testate. Si attiva e disattiva con Equipaggiamento.'},
    pl={note="Zmiany działają od następnej misji. Bardzo duży zasięg może zapełnić ekran ikonami i zepsuć rozgrywkę. Zalecana jest domyślna wartość tego moda (najniższa).",
        samples='Próbki', samples_distance='Zasięg próbek',
        supplies='Zaopatrzenie', supplies_distance='Zasięg zaopatrzenia',
        equipment='Sprzęt i przedmioty misji', equipment_distance='Zasięg sprzętu',
        carry_distance='Zasięg amunicji do noszenia i głowic',
        samples_info='Odległość, z której widać ikony próbek: zwykłych, rzadkich, superpróbek i danych wywiadu. Wyłączone używa odległości z gry.',
        supplies_info='Odległość, z której widać ikony skrzynek z amunicją, paczek granatów, stymulantów i zaopatrzenia. Włączone oznacza też stymulanty ich ikoną.',
        equipment_info='Odległość, z której widać ikony broni wsparcia, broni bocznej, broni białej, plecaków i przedmiotów misji. Wyłączone używa odległości z gry.',
        carry_info='Odległość, z której widać ikony pocisków SEAF, amunicji do noszenia i głowic. Włączane i wyłączane razem ze Sprzętem.'},
    ['pt-BR']={note="As mudanças valem a partir da próxima missão. Distâncias muito altas podem encher a tela de ícones e estragar a experiência de jogo. Recomenda-se o valor padrão deste mod (o mais baixo).",
        samples='Amostras', samples_distance='Distância amostras',
        supplies='Suprimentos', supplies_distance='Distância suprimentos',
        equipment='Equipamento e itens de missão', equipment_distance='Distância equipamento',
        carry_distance='Distância munição carregável e ogivas',
        samples_info='Distância em que os ícones de amostras aparecem: comuns, raras, superamostras e inteligência. Desligado usa a distância do jogo.',
        supplies_info='Distância em que aparecem os ícones de caixas de munição, pacotes de granadas, estimulantes e suprimentos. Ligado também marca os estimulantes com o ícone deles.',
        equipment_info='Distância em que aparecem os ícones de armas de suporte, secundárias, corpo a corpo, mochilas e itens de missão. Desligado usa a distância do jogo.',
        carry_info='Distância em que aparecem os ícones de projéteis SEAF, munição carregável e ogivas. Liga e desliga junto com Equipamento.'},
    ru={note="Изменения вступают в силу со следующей миссии. Слишком большая дальность может заполнить экран значками и испортить игру. Рекомендуется значение этого мода по умолчанию (самое низкое).",
        samples='Образцы', samples_distance='Дальность образцов',
        supplies='Припасы', supplies_distance='Дальность припасов',
        equipment='Снаряжение и предметы задания', equipment_distance='Дальность снаряжения',
        carry_distance='Дальность переносных боеприпасов и боеголовок',
        samples_info='С какого расстояния видны значки образцов: обычных, редких, суперобразцов и разведданных. Выкл.: расстояние игры.',
        supplies_info='С какого расстояния видны значки ящиков с патронами, гранат, стимуляторов и припасов. Вкл. также отмечает стимуляторы их значком.',
        equipment_info='С какого расстояния видны значки оружия поддержки, пистолетов, оружия ближнего боя, рюкзаков и предметов задания. Выкл.: расстояние игры.',
        carry_info='С какого расстояния видны значки снарядов SEAF, переносных боеприпасов и боеголовок. Включается и выключается вместе со Снаряжением.'},
}
local ALIASES = {zh='zh-Hans', pt='pt-BR'}

-- The game's Text Language as Mod Options Menu records it (BingusTranslations), else English.
local function texts()
    local registry = rawget(_G, 'BingusTranslations')
    local tag = type(registry) == 'table' and (rawget(registry, 'override') or rawget(registry, 'game_language'))
    if type(tag) ~= 'string' then return TEXTS.en end
    local base = tag:match('^[^-]+')
    return TEXTS[tag] or TEXTS[ALIASES[tag] or base] or TEXTS[base] or TEXTS.en
end
local function text(key)
    return function() return texts()[key] or TEXTS.en[key] end
end
local function description(key)
    return function()
        local t = texts()
        return (t[key] or TEXTS.en[key])..' '..(t.note or TEXTS.en.note)
    end
end

local menu, menu_status = nil, 'not checked'
local function setting(id, default)
    local value = menu and menu.get(id)
    if value == nil then return default end
    return value
end
local function enabled(group) return setting(MENU_ID..'.'..(group.switch or group.key), true) end
local function distance(group) return setting(MENU_ID..'.'..group.key..'_distance', group.default) end

local entries
local sync

local function register_menu()
    local api = rawget(_G, 'ModOptionsMenu')
    if type(api) ~= 'table' or type(api.register_option) ~= 'function' then
        return 'not found; default settings'
    end
    for index, group in ipairs(GROUPS) do
        local rows = {}
        if not group.switch then
            rows[1] = {MENU_ID..'.'..group.key, {type='toggle', label=text(group.key), default=true}}
        end
        rows[#rows+1] = {MENU_ID..'.'..group.key..'_distance', {type='slider', label=text(group.key..'_distance'),
                         min=group.default, max=100, step=1, default=group.default}}
        for row, item in ipairs(rows) do
            local spec = item[2]
            spec.mod, spec.mod_id, spec.description = 'Extended Pickup Icons', MENU_ID, description(group.key..'_info')
            spec.gap = index > 1 and row == 1 and not group.switch
            local ok, why = api.register_option(item[1], spec)
            if not ok then return 'refused '..item[1]..' ('..tostring(why)..'); default settings' end
            api.on_change(item[1], function() sync() end)
        end
    end
    menu = api
    return 'registered'
end

local function desired(entry)
    local group = GROUP[entry.group]
    if not enabled(group) then return entry.resource.before end
    if entry.marker then return HEALTH_MARKER.on end
    return ffi.string(ffi.new('float[1]', distance(group)), 4)
end

local function describe(written, failures)
    local parts = {}
    for _, group in ipairs(GROUPS) do
        parts[#parts+1] = group.key..'='..(enabled(group) and distance(group) or 'off')
    end
    local matched = {}
    for _, entry in ipairs(entries) do
        if not entry.marker then matched[entry.group] = (matched[entry.group] or 0) + 1 end
    end
    local counts = {}
    for _, group in ipairs(GROUPS) do counts[#counts+1] = group.key..'='..(matched[group.key] or 0) end
    return string.format('settings %s; menu %s; matched %s; wrote %d fields%s; skipped %d unmatched%s; Radius unchanged',
        table.concat(parts, ' '), menu_status, table.concat(counts, ' '), written,
        #failures > 0 and ('; failed '..#failures..': '..failures[1]) or '',
        #state.skipped, #state.skipped > 0 and ': '..table.concat(state.skipped, ', ') or '')
end

-- Writes each field whose wanted value differs from what it holds now; runs at start and on each menu change.
function sync()
    if not entries then return end
    local written, failures = 0, {}
    for _, entry in ipairs(entries) do
        local want = desired(entry)
        if want ~= entry.current then
            local ok, why = pcall(set_view, entry, entry.current, want)
            if ok then entry.current, written = want, written + 1 else failures[#failures+1] = tostring(why) end
        end
    end
    local message = describe(written, failures)
    state.active = #failures == 0
    report(message)
    return message
end

local function apply()
    locate()
    local interactions = found[INTERACTION]
    if #interactions == 0 then return nil end
    assert(#interactions == 1, 'Expected one interaction data buffer; found '..#interactions)
    local tbl = assert(open_table(interactions[1], INTERACTION, RECORD_BYTES),
                       'Interaction data layout mismatch; no change')
    local list, skipped = {}, {}
    for _, resource in ipairs(resources) do
        local entry = zone_target(tbl, resource)
        if entry then list[#list+1] = entry else skipped[#skipped+1] = resource.name end
    end
    local spots = found[SPOTTABLE]
    local spot = #spots == 1 and open_table(spots[1], SPOTTABLE, SPOT_RECORD_BYTES)
    local marker = spot and health_target(spot)
    if marker then list[#list+1] = marker else skipped[#skipped+1] = HEALTH_MARKER.name end
    for _, entry in ipairs(list) do entry.current = entry.resource.before end
    state.skipped, entries = skipped, list
    return sync()
end

local worker = coroutine.create(function()
    menu_status = register_menu()
    while true do
        state.attempts = state.attempts + 1
        local message = apply()
        if message ~= nil then return message end
        if state.attempts == 1 or state.attempts % 20 == 0 then
            report('waiting for loaded interaction data; attempts='..state.attempts..'; menu '..menu_status)
        end
        local resume_at = tonumber(kernel.GetTickCount64()) + 3000
        repeat coroutine.yield() until tonumber(kernel.GetTickCount64()) >= resume_at
    end
end)

local previous_update = update
local wrapper
local function initialize()
    if coroutine.status(worker) == 'dead' then return end
    local ok, message = coroutine.resume(worker)
    if ok and coroutine.status(worker) ~= 'dead' then return end
    if not ok then
        state.active = false
        report(message)
    end
    if update == wrapper then update = previous_update or function() end end
end
local function after_update(...)
    initialize()
    return ...
end
wrapper = function(dt,...)
    if previous_update then return after_update(previous_update(dt,...)) end
    initialize()
end
update = wrapper
