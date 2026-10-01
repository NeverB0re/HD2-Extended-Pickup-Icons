-- HD2-Addon: mods/codex/pickup_icon_range_test
-- Guarded pickup icon range extension for build 25480438.

if rawget(_G, 'CodexPickupIconRangeTest') then return end

local ffi = require('ffi')
assert(ffi.abi('64bit'), 'Windows x64 is required')

ffi.cdef[[
void *GetModuleHandleA(const char *name);
uint32_t GetModuleFileNameW(void *module, uint16_t *path, uint32_t capacity);
void *GetCurrentProcess(void);
int ReadProcessMemory(void *process, const void *address, void *buffer, size_t size, size_t *read_count);
int WriteProcessMemory(void *process, void *address, const void *buffer, size_t size, size_t *write_count);
size_t VirtualQuery(const void *address, void *region, size_t size);
int VirtualProtect(void *address, size_t size, uint32_t new_protect, uint32_t *old_protect);
void *CreateFileW(const uint16_t *path, uint32_t access, uint32_t share, void *security,
                  uint32_t disposition, uint32_t flags, void *template_file);
int ReadFile(void *file, void *buffer, uint32_t size, uint32_t *read_count, void *overlapped);
int CloseHandle(void *handle);
int32_t BCryptOpenAlgorithmProvider(void **algorithm, const uint16_t *name,
                                    const uint16_t *provider, uint32_t flags);
int32_t BCryptCloseAlgorithmProvider(void *algorithm, uint32_t flags);
int32_t BCryptCreateHash(void *algorithm, void **hash, void *object, uint32_t object_size,
                         const void *secret, uint32_t secret_size, uint32_t flags);
int32_t BCryptHashData(void *hash, const void *data, uint32_t size, uint32_t flags);
int32_t BCryptFinishHash(void *hash, void *digest, uint32_t size, uint32_t flags);
int32_t BCryptDestroyHash(void *hash);
uint64_t GetTickCount64(void);
typedef struct {
    void *base; void *allocation_base; uint32_t allocation_protect;
    uint16_t partition; uint16_t reserved; size_t size;
    uint32_t state; uint32_t protect; uint32_t kind; uint32_t padding;
} CodexPickupMemoryRegion;
]]

local kernel = ffi.load('kernel32')
local bcrypt = ffi.load('bcrypt')
local process = kernel.GetCurrentProcess()
local state = {version='extended-pickup-icons-2.4', active=false, status='pending', attempts=0}
_G.CodexPickupIconRangeTest = state

local EXE_SHA = 'F5FEE03DCFDB2E553A4752C283590950AC13316B376D8196AA556FF0400D5F06'
local GAME_SHA = '2E2C3B7C2500646DADD5F2B4C6E0504DBB7E7896139F64CDDC0D1813C718F51E'
local INSTANCE_SHA = '49F0B2118E8B8B1C84C1CCE1B6D3B70C6CAAABCFED06A2A9E36EAB55A524382F'
local REGION_SIZE = 46616576
local INSTANCE_OFFSET = 0x196AC68
local INSTANCE_BYTES = 632780
local DATA_BYTES = 632752
local MAP_BYTES = 17824
local RECORD_BYTES = 1104
local RECORD_COUNT = 557
local ENTRY_COUNT = 1114

local function report(message)
    state.status = tostring(message)
    print('[CodexPickupIconRangeTest] '..state.status)
    pcall(function()
        local loader = rawget(_G, 'CowboyBingusModLoader')
        local file = loader and loader.open_log and loader.open_log('CodexPickupIconRangeTest.log')
        if file then file:write(state.version..'\n'..state.status..'\n'); file:close() end
    end)
end

local function sha256(feed)
    local algorithm = ffi.new('void *[1]')
    local handle = ffi.new('void *[1]')
    local name = ffi.new('uint16_t[7]', {83,72,65,50,53,54,0})
    assert(bcrypt.BCryptOpenAlgorithmProvider(algorithm, name, nil, 0) == 0, 'SHA256 unavailable')
    local ok, result = pcall(function()
        assert(bcrypt.BCryptCreateHash(algorithm[0], handle, nil, 0, nil, 0, 0) == 0,
               'SHA256 initialization failed')
        local function update(bytes, count)
            assert(bcrypt.BCryptHashData(handle[0], bytes, count, 0) == 0, 'SHA256 update failed')
        end
        feed(update)
        local digest = ffi.new('uint8_t[32]')
        assert(bcrypt.BCryptFinishHash(handle[0], digest, 32, 0) == 0, 'SHA256 finish failed')
        local result_hex = {}
        for i=0,31 do result_hex[#result_hex+1] = string.format('%02X', digest[i]) end
        return table.concat(result_hex)
    end)
    if handle[0] ~= nil then bcrypt.BCryptDestroyHash(handle[0]) end
    bcrypt.BCryptCloseAlgorithmProvider(algorithm[0], 0)
    if not ok then error(result) end
    return result
end

local function hash_bytes(bytes)
    return sha256(function(update)
        update(ffi.cast('const uint8_t *', bytes), #bytes)
    end)
end

local function hash_module(module)
    local path = ffi.new('uint16_t[32768]')
    local length = kernel.GetModuleFileNameW(module, path, 32768)
    assert(length > 0 and length < 32768, 'Cannot resolve module path')
    local file = kernel.CreateFileW(path, 0x80000000, 7, nil, 3, 0x08000000, nil)
    assert(file ~= ffi.cast('void *', -1), 'Cannot open module file')
    local ok, result = pcall(function()
        return sha256(function(update)
            local buffer = ffi.new('uint8_t[1048576]')
            local count = ffi.new('uint32_t[1]')
            while true do
                assert(kernel.ReadFile(file, buffer, 1048576, count, nil) ~= 0,
                       'Cannot read module file')
                if count[0] == 0 then break end
                update(buffer, count[0])
            end
        end)
    end)
    kernel.CloseHandle(file)
    if not ok then error(result) end
    return result
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
    {name='unresolved_dropped_sample_carrier_a9936cbe561e8180#zone0', feature='equipment', id=unhex('80811e56be6c93a9'), slot=6, index=39, zone=0, zone_name=0x4CCB322C, radius=unhex('0000003f'), before=unhex('00007041'), after=unhex('00000c42'), interact_type=12},
    {name='unresolved_mission_carryable_d8a28bfb827392be#zone0', feature='equipment', id=unhex('be927382fb8ba2d8'), slot=20, index=378, zone=0, zone_name=0xF2760503, radius=unhex('0000803f'), before=unhex('0000a041'), after=unhex('00000c42'), interact_type=31},
    {name='unresolved_mission_carryable_7ca1b74b22c2eb9c#zone0', feature='equipment', id=unhex('9cebc2224bb7a17c'), slot=26, index=93, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00008040'), after=unhex('00000c42'), interact_type=31},
    {name='content/fac_helldivers/equipment/backpacks/drone_weapons/drone_stun_gun/drone_stun_gun_mount#zone0', feature='equipment', id=unhex('bf8c5216362c53a0'), slot=33, index=453, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00002041'), after=unhex('00000c42'), interact_type=1},
    {name='content/objectives/obj_common/raise_flag/carry_flag#zone0', feature='equipment', id=unhex('55335e09117e3a9d'), slot=49, index=404, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000a041'), after=unhex('00000c42'), interact_type=31},
    {name='content/fac_helldivers/equipment/melee_weapons/hand_axe/hand_axe#zone0', feature='equipment', id=unhex('50c839c177608175'), slot=58, index=458, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00002041'), after=unhex('00000c42'), interact_type=2},
    {name='content/fac_helldivers/equipment/melee_weapons/machete/machete#zone0', feature='equipment', id=unhex('e6d60f342a5d2d79'), slot=60, index=459, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00002041'), after=unhex('00000c42'), interact_type=2},
    {name='content/fac_helldivers/equipment/melee_weapons/survival_shovel/survival_shovel#zone0', feature='equipment', id=unhex('b36ff9933f625ee8'), slot=63, index=236, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00002041'), after=unhex('00000c42'), interact_type=3},
    {name='content/fac_helldivers/equipment/backpacks/ammo_backpack/ammo_backpack#zone0', feature='equipment', id=unhex('589a230971a4f94e'), slot=88, index=205, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00008040'), after=unhex('00000c42'), interact_type=13},
    {name='content/fac_helldivers/equipment/backpacks/ammo_backpack/ammo_backpack#zone1', feature='equipment', id=unhex('589a230971a4f94e'), slot=88, index=205, zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00002041'), after=unhex('00000c42'), interact_type=29},
    {name='content/env_super_earth/samples/research_tech_sample_01#zone0', feature='samples', id=unhex('939ebe44e8b7fc4e'), slot=91, index=197, zone=0, zone_name=0x4CCB322C, radius=unhex('0000403f'), before=unhex('00001041'), after=unhex('00000c42'), interact_type=11},
    {name='content/fac_helldivers/equipment/backpacks/minigun_backpack/minigun_backpack#zone0', feature='equipment', id=unhex('3e721ee2c5e16d05'), slot=94, index=231, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00008040'), after=unhex('00000c42'), interact_type=13},
    {name='content/fac_helldivers/equipment/backpacks/minigun_backpack/minigun_backpack#zone1', feature='equipment', id=unhex('3e721ee2c5e16d05'), slot=94, index=231, zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00002041'), after=unhex('00000c42'), interact_type=29},
    {name='content/fac_helldivers/equipment/backpacks/energy_shield_backpack/energy_shield_backpack#zone0', feature='equipment', id=unhex('5c7a89c31ad7c812'), slot=108, index=222, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00008040'), after=unhex('00000c42'), interact_type=13},
    {name='content/fac_helldivers/equipment/backpacks/energy_shield_backpack/energy_shield_backpack#zone1', feature='equipment', id=unhex('5c7a89c31ad7c812'), slot=108, index=222, zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00002041'), after=unhex('00000c42'), interact_type=29},
    {name='unresolved_mission_carryable_38cb9c758e07bc58#zone0', feature='equipment', id=unhex('58bc078e759ccb38'), slot=116, index=37, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000a041'), after=unhex('00000c42'), interact_type=31},
    {name='content/fac_helldivers/equipment/backpacks/ballistic_shield_backpack/ballistic_shield_backpack#zone0', feature='equipment', id=unhex('3b36ae0b5ed17e96'), slot=119, index=208, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00008040'), after=unhex('00000c42'), interact_type=13},
    {name='content/fac_helldivers/equipment/backpacks/ballistic_shield_backpack/ballistic_shield_backpack#zone1', feature='equipment', id=unhex('3b36ae0b5ed17e96'), slot=119, index=208, zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00002041'), after=unhex('00000c42'), interact_type=29},
    {name='content/env_shared/assets/samples/bio_sample_01/bio_sample_01#zone0', feature='samples', id=unhex('6652448a9d9bb464'), slot=128, index=153, zone=0, zone_name=0x4CCB322C, radius=unhex('0000403f'), before=unhex('00001041'), after=unhex('00000c42'), interact_type=11},
    {name='content/env_cyborg/samples/automaton_super_sample_01#zone0', feature='samples', id=unhex('9b8b682e7b0c1cc7'), slot=145, index=144, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000a041'), after=unhex('00000c42'), interact_type=31},
    {name='unresolved_mission_carryable_5684d928c9ab00d1#zone0', feature='equipment', id=unhex('d100abc928d98456'), slot=146, index=382, zone=0, zone_name=0xF2760503, radius=unhex('0000803f'), before=unhex('0000a041'), after=unhex('00000c42'), interact_type=31},
    {name='content/fac_helldivers/equipment/primary_weapons/lmg_stalwart/lmg_stalwart#zone0', feature='equipment', id=unhex('7f324acbac35a7a6'), slot=147, index=490, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00000041'), after=unhex('00000c42'), interact_type=13},
    {name='content/fac_helldivers/equipment/primary_weapons/lmg_stalwart/lmg_stalwart#zone1', feature='equipment', id=unhex('7f324acbac35a7a6'), slot=147, index=490, zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000a041'), after=unhex('00000c42'), interact_type=3},
    {name='unresolved_mission_carryable_7c81de10f0023d08#zone0', feature='equipment', id=unhex('083d02f010de817c'), slot=148, index=541, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000a041'), after=unhex('00000c42'), interact_type=31},
    {name='unresolved_resupply_pickup_unit_cc102a849e8930ef#zone0', feature='supplies', id=unhex('ef30899e842a10cc'), slot=157, index=32, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00008040'), after=unhex('0000a041'), interact_type=4},
    {name='content/fac_helldivers/equipment/melee_weapons/electric_baton/stun_baton#zone0', feature='equipment', id=unhex('97b33ccababfcd52'), slot=175, index=456, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00002041'), after=unhex('00000c42'), interact_type=2},
    {name='unresolved_mission_carryable_f598598c47617605#zone0', feature='equipment', id=unhex('057661478c5998f5'), slot=178, index=416, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00008040'), after=unhex('00007041'), interact_type=31},
    {name='content/fac_helldivers/discoverables/ammo_box_discoverable_01/ammo_box_discoverable_01#zone0', feature='supplies', id=unhex('a9f3e381d2ffcc79'), slot=179, index=31, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00008040'), after=unhex('0000a041'), interact_type=4},
    {name='content/env_bugs/assets/samples/bug_egg_super_sample_01#zone0', feature='samples', id=unhex('844a3aee86315d2b'), slot=189, index=137, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000a041'), after=unhex('00000c42'), interact_type=31},
    {name='content/fac_helldivers/equipment/support_weapons/faf_missile_launcher_helghast/faf_missile_launcher_helghast#zone0', feature='equipment', id=unhex('657efe91646f78cc'), slot=193, index=514, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00000041'), after=unhex('00000c42'), interact_type=13},
    {name='content/fac_helldivers/equipment/support_weapons/faf_missile_launcher_helghast/faf_missile_launcher_helghast#zone1', feature='equipment', id=unhex('657efe91646f78cc'), slot=193, index=514, zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000a041'), after=unhex('00000c42'), interact_type=3},
    {name='content/fac_helldivers/equipment/backpacks/recoilless_rifle_backpack/recoilless_rifle_backpack#zone0', feature='equipment', id=unhex('8029a22a54c6df96'), slot=195, index=232, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00008040'), after=unhex('00000c42'), interact_type=13},
    {name='content/fac_helldivers/equipment/backpacks/recoilless_rifle_backpack/recoilless_rifle_backpack#zone1', feature='equipment', id=unhex('8029a22a54c6df96'), slot=195, index=232, zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00002041'), after=unhex('00000c42'), interact_type=29},
    {name='content/fac_helldivers/equipment/backpacks/hover_backpack/hover_backpack#zone0', feature='equipment', id=unhex('cf66db1c4f0fc85e'), slot=201, index=228, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00008040'), after=unhex('00000c42'), interact_type=13},
    {name='content/fac_helldivers/equipment/backpacks/hover_backpack/hover_backpack#zone1', feature='equipment', id=unhex('cf66db1c4f0fc85e'), slot=201, index=228, zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00002041'), after=unhex('00000c42'), interact_type=29},
    {name='unresolved_hellpod_equipment_fc13460592ca79aa#zone0', feature='equipment', id=unhex('aa79ca92054613fc'), slot=202, index=527, zone=0, zone_name=0x4CCB322C, radius=unhex('0000003f'), before=unhex('00000041'), after=unhex('00000c42'), interact_type=13},
    {name='unresolved_dropped_weapon_fc13460592ca79aa#zone1', feature='equipment', id=unhex('aa79ca92054613fc'), slot=202, index=527, zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000a041'), after=unhex('00000c42'), interact_type=3},
    {name='content/fac_helldivers/equipment/support_weapons/recoilless_rifle/recoilless_rifle#zone0', feature='equipment', id=unhex('0fe4a7127ad6809f'), slot=203, index=530, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00000041'), after=unhex('00000c42'), interact_type=13},
    {name='content/fac_helldivers/equipment/support_weapons/recoilless_rifle/recoilless_rifle#zone1', feature='equipment', id=unhex('0fe4a7127ad6809f'), slot=203, index=530, zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000a041'), after=unhex('00000c42'), interact_type=3},
    {name='content/fac_helldivers/equipment/backpacks/drone_gas_projector_backpack/drone_gas_projector_backpack#zone0', feature='equipment', id=unhex('da8e1a97cdb4fcbf'), slot=204, index=217, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00008040'), after=unhex('00000c42'), interact_type=13},
    {name='content/fac_helldivers/equipment/backpacks/drone_gas_projector_backpack/drone_gas_projector_backpack#zone1', feature='equipment', id=unhex('da8e1a97cdb4fcbf'), slot=204, index=217, zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00002041'), after=unhex('00000c42'), interact_type=29},
    {name='content/fac_helldivers/equipment/support_weapons/laser_cannon/laser_cannon#zone0', feature='equipment', id=unhex('7328f7c005954bd5'), slot=206, index=521, zone=0, zone_name=0x4CCB322C, radius=unhex('0000003f'), before=unhex('00000041'), after=unhex('00000c42'), interact_type=13},
    {name='content/fac_helldivers/equipment/support_weapons/laser_cannon/laser_cannon#zone1', feature='equipment', id=unhex('7328f7c005954bd5'), slot=206, index=521, zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000a041'), after=unhex('00000c42'), interact_type=3},
    {name='content/env_super_earth/samples/research_bio_sample_01#zone0', feature='samples', id=unhex('42ac705266da4e29'), slot=212, index=192, zone=0, zone_name=0x4CCB322C, radius=unhex('0000403f'), before=unhex('00001041'), after=unhex('00000c42'), interact_type=11},
    {name='content/fac_helldivers/equipment/backpacks/faf_missile_launcher_backpack/faf_missile_launcher_backpack#zone0', feature='equipment', id=unhex('9a572e5f6b02c38e'), slot=214, index=223, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00008040'), after=unhex('00000c42'), interact_type=13},
    {name='content/fac_helldivers/equipment/backpacks/faf_missile_launcher_backpack/faf_missile_launcher_backpack#zone1', feature='equipment', id=unhex('9a572e5f6b02c38e'), slot=214, index=223, zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00002041'), after=unhex('00000c42'), interact_type=29},
    {name='content/objectives/obj_common/seaf_gun/seaf_gun_ammo#zone0', feature='equipment', id=unhex('8340085ee2e2626c'), slot=218, index=107, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00008040'), after=unhex('00007041'), interact_type=31},
    {name='content/objectives/obj_common/black_box/black_box_01#zone0', feature='equipment', id=unhex('97683ba35e41e23d'), slot=225, index=376, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000a041'), after=unhex('00000c42'), interact_type=31},
    {name='content/fac_helldivers/equipment/support_weapons/belt_fed_grenade_launcher/belt_fed_grenade_launcher#zone0', feature='equipment', id=unhex('9f7c5ad89ad0c288'), slot=231, index=507, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00000041'), after=unhex('00000c42'), interact_type=13},
    {name='content/fac_helldivers/equipment/support_weapons/belt_fed_grenade_launcher/belt_fed_grenade_launcher#zone1', feature='equipment', id=unhex('9f7c5ad89ad0c288'), slot=231, index=507, zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000a041'), after=unhex('00000c42'), interact_type=3},
    {name='unresolved_mission_carryable_46918a7483d70f3e#zone0', feature='equipment', id=unhex('3e0fd783748a9146'), slot=234, index=371, zone=0, zone_name=0xF2760503, radius=unhex('0000803f'), before=unhex('0000a041'), after=unhex('00000c42'), interact_type=31},
    {name='unresolved_mission_carryable_36c5e772f8a3b9d3#zone0', feature='equipment', id=unhex('d3b9a3f872e7c536'), slot=237, index=428, zone=0, zone_name=0xF2760503, radius=unhex('0000803f'), before=unhex('0000a041'), after=unhex('00000c42'), interact_type=31},
    {name='content/fac_helldivers/equipment/backpacks/drone_weapons/drone_laser_rifle/drone_laser_rifle_backpack#zone0', feature='equipment', id=unhex('02dc6dcb3c689baf'), slot=244, index=221, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00008040'), after=unhex('00000c42'), interact_type=13},
    {name='content/fac_helldivers/equipment/backpacks/drone_weapons/drone_laser_rifle/drone_laser_rifle_backpack#zone1', feature='equipment', id=unhex('02dc6dcb3c689baf'), slot=244, index=221, zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00002041'), after=unhex('00000c42'), interact_type=29},
    {name='content/env_cyborg/samples/automaton_enemy_sample_01#zone0', feature='samples', id=unhex('996adf2360b9eee4'), slot=261, index=141, zone=0, zone_name=0x4CCB322C, radius=unhex('0000403f'), before=unhex('00001041'), after=unhex('00000c42'), interact_type=11},
    {name='content/fac_helldivers/equipment/backpacks/displacement_backpack/displacement_backpack#zone0', feature='equipment', id=unhex('680e9b5d795697b4'), slot=270, index=215, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00008040'), after=unhex('00000c42'), interact_type=13},
    {name='content/fac_helldivers/equipment/backpacks/displacement_backpack/displacement_backpack#zone1', feature='equipment', id=unhex('680e9b5d795697b4'), slot=270, index=215, zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00002041'), after=unhex('00000c42'), interact_type=29},
    {name='unresolved_mission_carryable_d616d0bddb1be7dc#zone0', feature='equipment', id=unhex('dce71bdbbdd016d6'), slot=278, index=1, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000a041'), after=unhex('00000c42'), interact_type=31},
    {name='content/fac_helldivers/equipment/melee_weapons/ceremonial_saber/ceremonial_saber#zone0', feature='equipment', id=unhex('5a63ac7ee6a6d8fc'), slot=296, index=454, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00002041'), after=unhex('00000c42'), interact_type=2},
    {name='content/env_shared_forest/assets/samples/plant_sample_01#zone0', feature='samples', id=unhex('b44279d987cbf386'), slot=311, index=162, zone=0, zone_name=0x4CCB322C, radius=unhex('0000403f'), before=unhex('00001041'), after=unhex('00000c42'), interact_type=11},
    {name='content/env_bugs/assets/samples/bug_sample_01#zone0', feature='samples', id=unhex('6cfbdc7f39ee1650'), slot=317, index=140, zone=0, zone_name=0x4CCB322C, radius=unhex('0000403f'), before=unhex('00001041'), after=unhex('00000c42'), interact_type=11},
    {name='unresolved_sample_type_0_b65ec1c74612dc2c#zone0', feature='samples', id=unhex('2cdc1246c7c15eb6'), slot=320, index=136, zone=0, zone_name=0x4CCB322C, radius=unhex('0000003f'), before=unhex('0000c040'), after=unhex('00000c42'), interact_type=11},
    {name='content/fac_helldivers/equipment/support_weapons/machinegun/machinegun#zone0', feature='equipment', id=unhex('5689b3ab3b7dc211'), slot=322, index=525, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00000041'), after=unhex('00000c42'), interact_type=13},
    {name='content/fac_helldivers/equipment/support_weapons/machinegun/machinegun#zone1', feature='equipment', id=unhex('5689b3ab3b7dc211'), slot=322, index=525, zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000a041'), after=unhex('00000c42'), interact_type=3},
    {name='unresolved_hellpod_equipment_d53ee03481ae73fd#zone0', feature='equipment', id=unhex('fd73ae8134e03ed5'), slot=329, index=538, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00000041'), after=unhex('00000c42'), interact_type=13},
    {name='unresolved_dropped_weapon_d53ee03481ae73fd#zone1', feature='equipment', id=unhex('fd73ae8134e03ed5'), slot=329, index=538, zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000a041'), after=unhex('00000c42'), interact_type=3},
    {name='content/fac_helldivers/equipment/support_weapons/grenade_launcher/grenade_launcher#zone0', feature='equipment', id=unhex('3096a41f0bcdee02'), slot=332, index=516, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00000041'), after=unhex('00000c42'), interact_type=13},
    {name='content/fac_helldivers/equipment/support_weapons/grenade_launcher/grenade_launcher#zone1', feature='equipment', id=unhex('3096a41f0bcdee02'), slot=332, index=516, zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000a041'), after=unhex('00000c42'), interact_type=3},
    {name='unresolved_hellpod_equipment_8e7968d7e7aa4eab#zone0', feature='equipment', id=unhex('ab4eaae7d768798e'), slot=339, index=531, zone=0, zone_name=0x4CCB322C, radius=unhex('0000003f'), before=unhex('00000041'), after=unhex('00000c42'), interact_type=13},
    {name='unresolved_dropped_weapon_8e7968d7e7aa4eab#zone1', feature='equipment', id=unhex('ab4eaae7d768798e'), slot=339, index=531, zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000a041'), after=unhex('00000c42'), interact_type=3},
    {name='unresolved_sample_type_1_92bcc263e751bd45#zone0', feature='samples', id=unhex('45bd51e763c2bc92'), slot=341, index=196, zone=0, zone_name=0x4CCB322C, radius=unhex('0000403f'), before=unhex('00001041'), after=unhex('00000c42'), interact_type=11},
    {name='unresolved_hellpod_equipment_cd00bdc1149c2928#zone0', feature='equipment', id=unhex('28299c14c1bd00cd'), slot=344, index=535, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00000041'), after=unhex('00000c42'), interact_type=13},
    {name='unresolved_dropped_weapon_cd00bdc1149c2928#zone1', feature='equipment', id=unhex('28299c14c1bd00cd'), slot=344, index=535, zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000a041'), after=unhex('00000c42'), interact_type=3},
    {name='content/fac_helldivers/equipment/support_weapons/laser_pulse_cannon/laser_pulse_cannon#zone0', feature='equipment', id=unhex('7ec49c619612a635'), slot=347, index=523, zone=0, zone_name=0x4CCB322C, radius=unhex('0000003f'), before=unhex('00000041'), after=unhex('00000c42'), interact_type=13},
    {name='content/fac_helldivers/equipment/support_weapons/laser_pulse_cannon/laser_pulse_cannon#zone1', feature='equipment', id=unhex('7ec49c619612a635'), slot=347, index=523, zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000a041'), after=unhex('00000c42'), interact_type=3},
    {name='unresolved_dropped_sample_carrier_1c8764d62e12925a#zone0', feature='equipment', id=unhex('5a92122ed664871c'), slot=350, index=38, zone=0, zone_name=0x4CCB322C, radius=unhex('0000003f'), before=unhex('00007041'), after=unhex('00000c42'), interact_type=12},
    {name='content/fac_helldivers/equipment/melee_weapons/sledge_hammer/sledge_hammer#zone0', feature='equipment', id=unhex('5385bda2bdc93e5f'), slot=359, index=234, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00002041'), after=unhex('00000c42'), interact_type=3},
    {name='content/fac_helldivers/equipment/melee_weapons/sledge_hammer/sledge_hammer#zone1', feature='equipment', id=unhex('5385bda2bdc93e5f'), slot=359, index=234, zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00000041'), after=unhex('00000c42'), interact_type=13},
    {name='content/env_super_earth/samples/se_intel_sample_01#zone0', feature='samples', id=unhex('f0e91ffa74b17983'), slot=378, index=198, zone=0, zone_name=0x4CCB322C, radius=unhex('0000403f'), before=unhex('00001041'), after=unhex('00000c42'), interact_type=42},
    {name='content/fac_helldivers/hellpod/ammo_rack/supply_box#zone0', feature='supplies', id=unhex('79754f01ca1349a9'), slot=383, index=47, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00008040'), after=unhex('0000a041'), interact_type=8},
    {name='content/fac_helldivers/hellpod/ammo_rack/supply_box#zone1', feature='supplies', id=unhex('79754f01ca1349a9'), slot=383, index=47, zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00008040'), after=unhex('0000a041'), interact_type=7},
    {name='content/fac_helldivers/equipment/backpacks/ballistic_shield_backpack_mk2/ballistic_shield_backpack_mk2#zone0', feature='equipment', id=unhex('a0acb55ced7ac6f5'), slot=388, index=209, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00008040'), after=unhex('00000c42'), interact_type=13},
    {name='content/fac_helldivers/equipment/backpacks/ballistic_shield_backpack_mk2/ballistic_shield_backpack_mk2#zone1', feature='equipment', id=unhex('a0acb55ced7ac6f5'), slot=388, index=209, zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00002041'), after=unhex('00000c42'), interact_type=29},
    {name='content/fac_helldivers/hellpod/health_pack_rack/health_pack#zone0', feature='supplies', id=unhex('a829a746c6168d3b'), slot=389, index=49, zone=0, zone_name=0x4CCB322C, radius=unhex('0000003f'), before=unhex('00008040'), after=unhex('0000a041'), interact_type=5},
    {name='content/objectives/obj_common/carry_data/carry_data_stratagem#zone0', feature='equipment', id=unhex('9225a1e3dabcf233'), slot=392, index=380, zone=0, zone_name=0xF2760503, radius=unhex('0000803f'), before=unhex('0000a041'), after=unhex('00000c42'), interact_type=31},
    {name='content/fac_helldivers/equipment/melee_weapons/flag/melee_flag#zone0', feature='equipment', id=unhex('d8381dba54b3f1b0'), slot=400, index=457, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00002041'), after=unhex('00000c42'), interact_type=3},
    {name='unresolved_mission_carryable_a7381b87f3a3b455#zone0', feature='equipment', id=unhex('55b4a3f3871b38a7'), slot=401, index=408, zone=0, zone_name=0xF2760503, radius=unhex('0000803f'), before=unhex('0000a041'), after=unhex('00000c42'), interact_type=31},
    {name='unresolved_mission_carryable_dc19126d15692d04#zone0', feature='equipment', id=unhex('042d69156d1219dc'), slot=409, index=412, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00008040'), after=unhex('00007041'), interact_type=31},
    {name='content/fac_helldivers/equipment/sidearm_weapons/smart_pistol_missile/smart_pistol_missile#zone0', feature='equipment', id=unhex('a4c7566050d4d514'), slot=413, index=257, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00002041'), after=unhex('00000c42'), interact_type=2},
    {name='content/entities/base_sample_dynamic#zone0', feature='samples', id=unhex('8614ca0cf70398ca'), slot=421, index=2, zone=0, zone_name=0x4CCB322C, radius=unhex('0000403f'), before=unhex('00001041'), after=unhex('00000c42'), interact_type=11},
    {name='content/env_shared_desert/assets/samples/mineral_sample_01#zone0', feature='samples', id=unhex('54be95b06cea0882'), slot=432, index=161, zone=0, zone_name=0x4CCB322C, radius=unhex('0000403f'), before=unhex('00001041'), after=unhex('00000c42'), interact_type=11},
    {name='content/objectives/obj_common/carry_data/carry_data#zone0', feature='equipment', id=unhex('fdc56524893214f4'), slot=435, index=379, zone=0, zone_name=0xF2760503, radius=unhex('0000803f'), before=unhex('0000a041'), after=unhex('00000c42'), interact_type=31},
    {name='unresolved_mission_carryable_e4be3fdf0c857b7f#zone0', feature='equipment', id=unhex('7f7b850cdf3fbee4'), slot=445, index=415, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00008040'), after=unhex('00007041'), interact_type=31},
    {name='content/fac_helldivers/equipment/sidearm_weapons/smart_pistol/smart_pistol#zone0', feature='equipment', id=unhex('2da46765ff3489cf'), slot=446, index=256, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00002041'), after=unhex('00000c42'), interact_type=2},
    {name='content/fac_helldivers/equipment/support_weapons/automatic_cannon/automatic_cannon#zone0', feature='equipment', id=unhex('5f5c0b6f31fbcfa8'), slot=449, index=506, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00000041'), after=unhex('00000c42'), interact_type=13},
    {name='content/fac_helldivers/equipment/support_weapons/automatic_cannon/automatic_cannon#zone1', feature='equipment', id=unhex('5f5c0b6f31fbcfa8'), slot=449, index=506, zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000a041'), after=unhex('00000c42'), interact_type=3},
    {name='content/objectives/obj_bugs/retrieve_larva/bug_larva_container_backpack#zone0', feature='equipment', id=unhex('66e7f8a6ee9ca89e'), slot=478, index=372, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00008040'), after=unhex('00000c42'), interact_type=13},
    {name='content/objectives/obj_bugs/retrieve_larva/bug_larva_container_backpack#zone1', feature='equipment', id=unhex('66e7f8a6ee9ca89e'), slot=478, index=372, zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000a041'), after=unhex('00000c42'), interact_type=29},
    {name='content/fac_helldivers/equipment/support_weapons/heavy_mg/heavy_mg#zone0', feature='equipment', id=unhex('18c40a7b14d55221'), slot=480, index=520, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00000041'), after=unhex('00000c42'), interact_type=13},
    {name='content/fac_helldivers/equipment/support_weapons/heavy_mg/heavy_mg#zone1', feature='equipment', id=unhex('18c40a7b14d55221'), slot=480, index=520, zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000a041'), after=unhex('00000c42'), interact_type=3},
    {name='content/env_shared/assets/samples/crystalized_e710_sample_01/crystalized_e710_sample_01#zone0', feature='samples', id=unhex('aa495a812e2a97ad'), slot=482, index=155, zone=0, zone_name=0x4CCB322C, radius=unhex('0000403f'), before=unhex('00001041'), after=unhex('00000c42'), interact_type=11},
    {name='content/env_super_earth/samples/research_artifact_sample_01#zone0', feature='samples', id=unhex('57f2d1ed4dd41acf'), slot=495, index=191, zone=0, zone_name=0x4CCB322C, radius=unhex('0000403f'), before=unhex('00001041'), after=unhex('00000c42'), interact_type=11},
    {name='content/fac_helldivers/equipment/backpacks/drone_weapons/drone_laser_rifle/drone_laser_rifle_mount#zone0', feature='equipment', id=unhex('2c3d54b201c2662c'), slot=496, index=452, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00002041'), after=unhex('00000c42'), interact_type=1},
    {name='content/env_shared/assets/samples/tech_sample_01/tech_sample_01#zone0', feature='samples', id=unhex('bf4155e900950e70'), slot=499, index=158, zone=0, zone_name=0x4CCB322C, radius=unhex('0000403f'), before=unhex('00001041'), after=unhex('00000c42'), interact_type=11},
    {name='content/fac_helldivers/equipment/backpacks/directional_energy_shield/directional_energy_shield_backpack#zone0', feature='equipment', id=unhex('0ab40148f896e7a4'), slot=504, index=214, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00008040'), after=unhex('00000c42'), interact_type=13},
    {name='content/fac_helldivers/equipment/backpacks/directional_energy_shield/directional_energy_shield_backpack#zone1', feature='equipment', id=unhex('0ab40148f896e7a4'), slot=504, index=214, zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00002041'), after=unhex('00000c42'), interact_type=29},
    {name='content/fac_helldivers/discoverables/grenade_box_discoverable_01/grenade_box_discoverable_01#zone0', feature='supplies', id=unhex('9c4093f0fb34af97'), slot=512, index=33, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00008040'), after=unhex('0000a041'), interact_type=6},
    {name='content/fac_helldivers/equipment/support_weapons/expendable_napalm_launcher/expendable_napalm_launcher#zone0', feature='equipment', id=unhex('9e5f6085d1e0b5b2'), slot=522, index=512, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00000041'), after=unhex('00000c42'), interact_type=13},
    {name='content/fac_helldivers/equipment/support_weapons/expendable_napalm_launcher/expendable_napalm_launcher#zone1', feature='equipment', id=unhex('9e5f6085d1e0b5b2'), slot=522, index=512, zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000a041'), after=unhex('00000c42'), interact_type=3},
    {name='content/fac_helldivers/vehicles/frv/armaments/frv_mg/frv_mg#zone0', feature='equipment', id=unhex('4ec28e03db1e5c08'), slot=538, index=534, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00000041'), after=unhex('00000c42'), interact_type=13},
    {name='content/fac_helldivers/vehicles/frv/armaments/frv_mg/frv_mg#zone1', feature='equipment', id=unhex('4ec28e03db1e5c08'), slot=538, index=534, zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000a041'), after=unhex('00000c42'), interact_type=3},
    {name='unresolved_hellpod_equipment_073270650f859dd0#zone0', feature='equipment', id=unhex('d09d850f65703207'), slot=546, index=373, zone=0, zone_name=0x4CCB322C, radius=unhex('00000040'), before=unhex('00008040'), after=unhex('00000c42'), interact_type=13},
    {name='unresolved_backpack_073270650f859dd0#zone1', feature='equipment', id=unhex('d09d850f65703207'), slot=546, index=373, zone=1, zone_name=0x4CCB322C, radius=unhex('00000040'), before=unhex('0000a041'), after=unhex('00000c42'), interact_type=29},
    {name='content/fac_helldivers/equipment/sidearm_weapons/magnum_pistol/magnum_pistol#zone0', feature='equipment', id=unhex('a1d2b8e15871431a'), slot=551, index=501, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00002041'), after=unhex('00000c42'), interact_type=2},
    {name='content/objectives/obj_cyborgs/cyborg_carry_data/cy_carry_data#zone0', feature='equipment', id=unhex('a1624ca4865e0e9e'), slot=553, index=424, zone=0, zone_name=0xF2760503, radius=unhex('0000803f'), before=unhex('0000a041'), after=unhex('00000c42'), interact_type=31},
    {name='content/fac_helldivers/equipment/backpacks/medic_backpack/medic_backpack#zone0', feature='equipment', id=unhex('1d982b0904e5550a'), slot=557, index=230, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00008040'), after=unhex('00000c42'), interact_type=13},
    {name='content/fac_helldivers/equipment/backpacks/medic_backpack/medic_backpack#zone1', feature='equipment', id=unhex('1d982b0904e5550a'), slot=557, index=230, zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00002041'), after=unhex('00000c42'), interact_type=29},
    {name='content/fac_helldivers/equipment/melee_weapons/stun_spear/stun_spear#zone0', feature='equipment', id=unhex('64b4fc07ddaeb6e3'), slot=560, index=235, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00002041'), after=unhex('00000c42'), interact_type=2},
    {name='unresolved_mission_carryable_74f33bd19068a439#zone0', feature='equipment', id=unhex('39a46890d13bf374'), slot=563, index=159, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00008040'), after=unhex('00000c42'), interact_type=31},
    {name='content/fac_helldivers/equipment/backpacks/drone_weapons/drone_assault_rifle/drone_assault_rifle_backpack#zone0', feature='equipment', id=unhex('819dbb8aa55a8ae8'), slot=569, index=220, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00008040'), after=unhex('00000c42'), interact_type=13},
    {name='content/fac_helldivers/equipment/backpacks/drone_weapons/drone_assault_rifle/drone_assault_rifle_backpack#zone1', feature='equipment', id=unhex('819dbb8aa55a8ae8'), slot=569, index=220, zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00002041'), after=unhex('00000c42'), interact_type=29},
    {name='content/fac_helldivers/equipment/melee_weapons/chainsaw_greatsword/chainsaw_greatsword#zone0', feature='equipment', id=unhex('a4b5bfea2afd4cbf'), slot=570, index=455, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000a041'), after=unhex('00000c42'), interact_type=3},
    {name='content/fac_helldivers/equipment/melee_weapons/chainsaw_greatsword/chainsaw_greatsword#zone1', feature='equipment', id=unhex('a4b5bfea2afd4cbf'), slot=570, index=455, zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00000041'), after=unhex('00000c42'), interact_type=13},
    {name='content/fac_helldivers/equipment/support_weapons/air_burst_rocket_launcher/air_burst_rocket_launcher#zone0', feature='equipment', id=unhex('965227ea3704e426'), slot=574, index=504, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00000041'), after=unhex('00000c42'), interact_type=13},
    {name='content/fac_helldivers/equipment/support_weapons/air_burst_rocket_launcher/air_burst_rocket_launcher#zone1', feature='equipment', id=unhex('965227ea3704e426'), slot=574, index=504, zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000a041'), after=unhex('00000c42'), interact_type=3},
    {name='unresolved_hellpod_equipment_dfc8b9519169b67a#zone0', feature='equipment', id=unhex('7ab6699151b9c8df'), slot=576, index=218, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00008040'), after=unhex('00000c42'), interact_type=13},
    {name='unresolved_backpack_dfc8b9519169b67a#zone1', feature='equipment', id=unhex('7ab6699151b9c8df'), slot=576, index=218, zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00002041'), after=unhex('00000c42'), interact_type=29},
    {name='content/fac_helldivers/equipment/backpacks/ballistic_shield_backpack_small/ballistic_shield_backpack_small#zone0', feature='equipment', id=unhex('9882732bc7ea9a5f'), slot=578, index=210, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00008040'), after=unhex('00000c42'), interact_type=13},
    {name='content/fac_helldivers/equipment/backpacks/ballistic_shield_backpack_small/ballistic_shield_backpack_small#zone1', feature='equipment', id=unhex('9882732bc7ea9a5f'), slot=578, index=210, zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00002041'), after=unhex('00000c42'), interact_type=29},
    {name='content/objectives/obj_cyborgs/cyborg_airbase_control_tower/cyborg_carry_data#zone0', feature='equipment', id=unhex('886b5ea2233c993e'), slot=582, index=544, zone=0, zone_name=0xF2760503, radius=unhex('0000803f'), before=unhex('0000a041'), after=unhex('00000c42'), interact_type=31},
    {name='content/objectives/obj_common/briefcase/briefcase#zone0', feature='equipment', id=unhex('a1d663c5ea1f0090'), slot=587, index=377, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000a041'), after=unhex('00000c42'), interact_type=31},
    {name='content/fac_helldivers/equipment/support_weapons/expendable_machinegun/expendable_machinegun#zone0', feature='equipment', id=unhex('779ba50a499d6cb1'), slot=603, index=510, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00000041'), after=unhex('00000c42'), interact_type=13},
    {name='content/fac_helldivers/equipment/support_weapons/expendable_machinegun/expendable_machinegun#zone1', feature='equipment', id=unhex('779ba50a499d6cb1'), slot=603, index=510, zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000a041'), after=unhex('00000c42'), interact_type=3},
    {name='content/objectives/obj_cyborgs/cyborg_orbital_cannon/cy_orbital_cannon_ammo_carry#zone0', feature='equipment', id=unhex('b34122ed6f272657'), slot=604, index=127, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00008040'), after=unhex('00007041'), interact_type=31},
    {name='content/fac_helldivers/equipment/backpacks/automatic_cannon_backpack/automatic_cannon_backpack#zone0', feature='equipment', id=unhex('4c0f09e045e00ae6'), slot=608, index=206, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00008040'), after=unhex('00000c42'), interact_type=13},
    {name='content/fac_helldivers/equipment/backpacks/automatic_cannon_backpack/automatic_cannon_backpack#zone1', feature='equipment', id=unhex('4c0f09e045e00ae6'), slot=608, index=206, zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00002041'), after=unhex('00000c42'), interact_type=29},
    {name='content/fac_helldivers/equipment/backpacks/backpack_base#zone0', feature='equipment', id=unhex('868ef9ea2ad02687'), slot=622, index=35, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00008040'), after=unhex('00000c42'), interact_type=13},
    {name='content/fac_helldivers/equipment/backpacks/backpack_base#zone1', feature='equipment', id=unhex('868ef9ea2ad02687'), slot=622, index=35, zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00002041'), after=unhex('00000c42'), interact_type=29},
    {name='unresolved_hellpod_equipment_4f8a477e577aaba9#zone0', feature='equipment', id=unhex('a9ab7a577e478a4f'), slot=631, index=498, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00000041'), after=unhex('00000c42'), interact_type=13},
    {name='unresolved_dropped_weapon_4f8a477e577aaba9#zone1', feature='equipment', id=unhex('a9ab7a577e478a4f'), slot=631, index=498, zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000a041'), after=unhex('00000c42'), interact_type=3},
    {name='content/fac_helldivers/equipment/backpacks/air_burst_rocket_backpack/air_burst_rocket_backpack#zone0', feature='equipment', id=unhex('ac128a858ed65ce7'), slot=633, index=204, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00008040'), after=unhex('00000c42'), interact_type=13},
    {name='content/fac_helldivers/equipment/backpacks/air_burst_rocket_backpack/air_burst_rocket_backpack#zone1', feature='equipment', id=unhex('ac128a858ed65ce7'), slot=633, index=204, zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00002041'), after=unhex('00000c42'), interact_type=29},
    {name='unresolved_hellpod_equipment_b9606c5aab32c3c2#zone0', feature='equipment', id=unhex('c2c332ab5a6c60b9'), slot=634, index=537, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00000041'), after=unhex('00000c42'), interact_type=13},
    {name='unresolved_dropped_weapon_b9606c5aab32c3c2#zone1', feature='equipment', id=unhex('c2c332ab5a6c60b9'), slot=634, index=537, zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000a041'), after=unhex('00000c42'), interact_type=3},
    {name='unresolved_mission_carryable_0dc9084e50c051f3#zone0', feature='equipment', id=unhex('f351c0504e08c90d'), slot=646, index=422, zone=0, zone_name=0xF2760503, radius=unhex('0000803f'), before=unhex('00004041'), after=unhex('00000c42'), interact_type=31},
    {name='unresolved_hellpod_equipment_1b00bca55e364292#zone0', feature='equipment', id=unhex('9242365ea5bc001b'), slot=653, index=233, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00008040'), after=unhex('00000c42'), interact_type=13},
    {name='unresolved_backpack_1b00bca55e364292#zone1', feature='equipment', id=unhex('9242365ea5bc001b'), slot=653, index=233, zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00002041'), after=unhex('00000c42'), interact_type=29},
    {name='content/fac_helldivers/equipment/support_weapons/lat_oneshot/lat_oneshot#zone0', feature='equipment', id=unhex('d30169eda02f9380'), slot=654, index=524, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00000041'), after=unhex('00000c42'), interact_type=13},
    {name='content/fac_helldivers/equipment/support_weapons/lat_oneshot/lat_oneshot#zone1', feature='equipment', id=unhex('d30169eda02f9380'), slot=654, index=524, zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000a041'), after=unhex('00000c42'), interact_type=3},
    {name='content/fac_helldivers/discoverables/health_pack_discoverable_01/health_pack_discoverable_01#zone0', feature='supplies', id=unhex('65792f925b4ccab4'), slot=655, index=34, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00008040'), after=unhex('0000a041'), interact_type=5},
    {name='content/fac_helldivers/equipment/backpacks/jumppack_backpack/jumppack_backpack#zone0', feature='equipment', id=unhex('79b3499483cac559'), slot=672, index=229, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00008040'), after=unhex('00000c42'), interact_type=13},
    {name='content/fac_helldivers/equipment/backpacks/jumppack_backpack/jumppack_backpack#zone1', feature='equipment', id=unhex('79b3499483cac559'), slot=672, index=229, zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00002041'), after=unhex('00000c42'), interact_type=29},
    {name='content/fac_helldivers/equipment/backpacks/faf_missile_launcher_helghast_backpack/faf_missile_launcher_helghast_backpack#zone0', feature='equipment', id=unhex('f31e1c19ccb0feb8'), slot=675, index=225, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00008040'), after=unhex('00000c42'), interact_type=13},
    {name='content/fac_helldivers/equipment/backpacks/faf_missile_launcher_helghast_backpack/faf_missile_launcher_helghast_backpack#zone1', feature='equipment', id=unhex('f31e1c19ccb0feb8'), slot=675, index=225, zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00002041'), after=unhex('00000c42'), interact_type=29},
    {name='content/fac_helldivers/equipment/backpacks/guard_dog_stun_backpack/guard_dog_stun_backpack#zone0', feature='equipment', id=unhex('fa3d2eb112a78dc2'), slot=682, index=226, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00008040'), after=unhex('00000c42'), interact_type=13},
    {name='content/fac_helldivers/equipment/backpacks/guard_dog_stun_backpack/guard_dog_stun_backpack#zone1', feature='equipment', id=unhex('fa3d2eb112a78dc2'), slot=682, index=226, zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00002041'), after=unhex('00000c42'), interact_type=29},
    {name='unresolved_sample_type_1_4c63119f69165321#zone0', feature='samples', id=unhex('215316699f11634c'), slot=684, index=194, zone=0, zone_name=0x4CCB322C, radius=unhex('0000403f'), before=unhex('00001041'), after=unhex('00000c42'), interact_type=11},
    {name='unresolved_mission_carryable_8ad7a3118bd48d1c#zone0', feature='equipment', id=unhex('1c8dd48b11a3d78a'), slot=698, index=386, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000a041'), after=unhex('00000c42'), interact_type=31},
    {name='content/objectives/obj_common/seaf_artillery/seaf_shell#zone0', feature='equipment', id=unhex('e9e6a96669161240'), slot=699, index=106, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00008040'), after=unhex('00007041'), interact_type=31},
    {name='content/env_shared/assets/samples/super_uranium/super_uranium_sample_01#zone0', feature='samples', id=unhex('1ab4b669fa35499d'), slot=702, index=157, zone=0, zone_name=0x4CCB322C, radius=unhex('0000403f'), before=unhex('00001041'), after=unhex('00000c42'), interact_type=11},
    {name='unresolved_hellpod_equipment_35b5af8b1e859540#zone0', feature='equipment', id=unhex('4095851e8bafb535'), slot=705, index=224, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00008040'), after=unhex('00000c42'), interact_type=13},
    {name='unresolved_backpack_35b5af8b1e859540#zone1', feature='equipment', id=unhex('4095851e8bafb535'), slot=705, index=224, zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00002041'), after=unhex('00000c42'), interact_type=29},
    {name='content/env_shared_arctic/assets/samples/crystal_sample_01#zone0', feature='samples', id=unhex('a945de3bf8f2d6b4'), slot=706, index=160, zone=0, zone_name=0x4CCB322C, radius=unhex('0000403f'), before=unhex('00001041'), after=unhex('00000c42'), interact_type=11},
    {name='content/fac_helldivers/equipment/backpacks/c4_charge_backpack/c4_charge_detonator#zone0', feature='equipment', id=unhex('3d2ff521630df551'), slot=707, index=444, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00000041'), after=unhex('00000c42'), interact_type=13},
    {name='content/fac_helldivers/equipment/backpacks/c4_charge_backpack/c4_charge_detonator#zone1', feature='equipment', id=unhex('3d2ff521630df551'), slot=707, index=444, zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000a041'), after=unhex('00000c42'), interact_type=3},
    {name='unresolved_hellpod_equipment_b43235dbd493750c#zone0', feature='equipment', id=unhex('0c7593d4db3532b4'), slot=709, index=536, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00000041'), after=unhex('00000c42'), interact_type=13},
    {name='unresolved_dropped_weapon_b43235dbd493750c#zone1', feature='equipment', id=unhex('0c7593d4db3532b4'), slot=709, index=536, zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000a041'), after=unhex('00000c42'), interact_type=3},
    {name='content/entities/base_sample_static#zone0', feature='samples', id=unhex('38940c0f734f9bbc'), slot=714, index=3, zone=0, zone_name=0x4CCB322C, radius=unhex('0000403f'), before=unhex('00001041'), after=unhex('00000c42'), interact_type=11},
    {name='content/fac_helldivers/equipment/support_weapons/energy_weapon_shark/energy_weapon_shark#zone0', feature='equipment', id=unhex('66021a80f8c7fc6c'), slot=716, index=509, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00000041'), after=unhex('00000c42'), interact_type=13},
    {name='content/fac_helldivers/equipment/support_weapons/energy_weapon_shark/energy_weapon_shark#zone1', feature='equipment', id=unhex('66021a80f8c7fc6c'), slot=716, index=509, zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000a041'), after=unhex('00000c42'), interact_type=3},
    {name='content/env_cyborg/samples/automaton_intel_sample_01#zone0', feature='samples', id=unhex('9e42f5bad28604cd'), slot=726, index=142, zone=0, zone_name=0x4CCB322C, radius=unhex('0000403f'), before=unhex('00001041'), after=unhex('00000c42'), interact_type=42},
    {name='unresolved_mission_carryable_4a3e722b5a865e38#zone0', feature='equipment', id=unhex('385e865a2b723e4a'), slot=734, index=385, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000a041'), after=unhex('00000c42'), interact_type=31},
    {name='unresolved_mission_carryable_e09fcb5a280acb1d#zone0', feature='equipment', id=unhex('1dcb0a285acb9fe0'), slot=737, index=414, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00008040'), after=unhex('00007041'), interact_type=31},
    {name='content/fac_helldivers/equipment/backpacks/heavy_flamethrower_backpack/heavy_flamethrower_backpack#zone0', feature='equipment', id=unhex('e060181a3c1ceb43'), slot=760, index=227, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00008040'), after=unhex('00000c42'), interact_type=13},
    {name='content/fac_helldivers/equipment/backpacks/heavy_flamethrower_backpack/heavy_flamethrower_backpack#zone1', feature='equipment', id=unhex('e060181a3c1ceb43'), slot=760, index=227, zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00002041'), after=unhex('00000c42'), interact_type=29},
    {name='unresolved_hellpod_equipment_88f61afff48ac8a4#zone0', feature='equipment', id=unhex('a4c88af4ff1af688'), slot=766, index=508, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00000041'), after=unhex('00000c42'), interact_type=13},
    {name='unresolved_dropped_weapon_88f61afff48ac8a4#zone1', feature='equipment', id=unhex('a4c88af4ff1af688'), slot=766, index=508, zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000a041'), after=unhex('00000c42'), interact_type=3},
    {name='content/fac_helldivers/equipment/backpacks/drone_flamethrower_backpack/drone_flamethrower_backpack#zone0', feature='equipment', id=unhex('4d8d9fa66a621530'), slot=768, index=216, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00008040'), after=unhex('00000c42'), interact_type=13},
    {name='content/fac_helldivers/equipment/backpacks/drone_flamethrower_backpack/drone_flamethrower_backpack#zone1', feature='equipment', id=unhex('4d8d9fa66a621530'), slot=768, index=216, zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00002041'), after=unhex('00000c42'), interact_type=29},
    {name='content/fac_helldivers/equipment/support_weapons/expendable_massive_rocket_launcher/expendable_massive_rocket_launcher#zone0', feature='equipment', id=unhex('c738ac6527641776'), slot=772, index=511, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00000041'), after=unhex('00000c42'), interact_type=13},
    {name='content/fac_helldivers/equipment/support_weapons/expendable_massive_rocket_launcher/expendable_massive_rocket_launcher#zone1', feature='equipment', id=unhex('c738ac6527641776'), slot=772, index=511, zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000a041'), after=unhex('00000c42'), interact_type=3},
    {name='content/env_shared/assets/samples/artifact_sample_01/artifact_sample_01#zone0', feature='samples', id=unhex('83c3d5735ccf9fb3'), slot=774, index=152, zone=0, zone_name=0x4CCB322C, radius=unhex('0000403f'), before=unhex('00001041'), after=unhex('00000c42'), interact_type=11},
    {name='unresolved_hellpod_equipment_26bddf070c31b275#zone0', feature='equipment', id=unhex('75b2310c07dfbd26'), slot=778, index=207, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00008040'), after=unhex('00000c42'), interact_type=13},
    {name='unresolved_backpack_26bddf070c31b275#zone1', feature='equipment', id=unhex('75b2310c07dfbd26'), slot=778, index=207, zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00002041'), after=unhex('00000c42'), interact_type=29},
    {name='unresolved_mission_carryable_0f1a0189b327c5cb#zone0', feature='equipment', id=unhex('cbc527b389011a0f'), slot=779, index=543, zone=0, zone_name=0xF2760503, radius=unhex('0000803f'), before=unhex('0000a041'), after=unhex('00000c42'), interact_type=31},
    {name='content/fac_helldivers/equipment/backpacks/c4_charge_backpack/c4_charge_backpack#zone0', feature='equipment', id=unhex('7167a2441cf8182a'), slot=808, index=213, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00008040'), after=unhex('00000c42'), interact_type=13},
    {name='content/fac_helldivers/equipment/backpacks/c4_charge_backpack/c4_charge_backpack#zone1', feature='equipment', id=unhex('7167a2441cf8182a'), slot=808, index=213, zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00002041'), after=unhex('00000c42'), interact_type=29},
    {name='content/env_shared/assets/samples/legendarium_sample_01/legendarium_sample_01#zone0', feature='samples', id=unhex('3dc267252c06fede'), slot=813, index=156, zone=0, zone_name=0x4CCB322C, radius=unhex('0000403f'), before=unhex('00001041'), after=unhex('00000c42'), interact_type=11},
    {name='unresolved_mission_carryable_c8f9a2233048b836#zone0', feature='equipment', id=unhex('36b8483023a2f9c8'), slot=828, index=56, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00008040'), after=unhex('00000c42'), interact_type=31},
    {name='content/fac_helldivers/equipment/support_weapons/laser_guided_missile_launcher/laser_guided_missile_launcher#zone0', feature='equipment', id=unhex('cb162b143d129059'), slot=831, index=522, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00000041'), after=unhex('00000c42'), interact_type=13},
    {name='content/fac_helldivers/equipment/support_weapons/laser_guided_missile_launcher/laser_guided_missile_launcher#zone1', feature='equipment', id=unhex('cb162b143d129059'), slot=831, index=522, zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000a041'), after=unhex('00000c42'), interact_type=3},
    {name='unresolved_mission_carryable_8f7d4d9c196018c8#zone0', feature='equipment', id=unhex('c81860199c4d7d8f'), slot=844, index=431, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000a041'), after=unhex('00000c42'), interact_type=31},
    {name='content/env_bugs/assets/samples/bug_intel_sample_01#zone0', feature='samples', id=unhex('b5527382b3339576'), slot=847, index=139, zone=0, zone_name=0x4CCB322C, radius=unhex('0000403f'), before=unhex('00001041'), after=unhex('00000c42'), interact_type=42},
    {name='content/fac_helldivers/equipment/backpacks/drone_mg/drone_mg_backpack#zone0', feature='equipment', id=unhex('ecced76757bc5e25'), slot=850, index=219, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00008040'), after=unhex('00000c42'), interact_type=13},
    {name='content/fac_helldivers/equipment/backpacks/drone_mg/drone_mg_backpack#zone1', feature='equipment', id=unhex('ecced76757bc5e25'), slot=850, index=219, zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00002041'), after=unhex('00000c42'), interact_type=29},
    {name='unresolved_hellpod_equipment_35f50dec0ec647c6#zone0', feature='equipment', id=unhex('c647c60eec0df535'), slot=868, index=36, zone=0, zone_name=0x4CCB322C, radius=unhex('0000003f'), before=unhex('00008040'), after=unhex('00000c42'), interact_type=13},
    {name='unresolved_backpack_35f50dec0ec647c6#zone1', feature='equipment', id=unhex('c647c60eec0df535'), slot=868, index=36, zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000c040'), after=unhex('00000c42'), interact_type=29},
    {name='content/fac_helldivers/equipment/support_weapons/plasma_blaster/plasma_blaster#zone0', feature='equipment', id=unhex('540e78d79af4d5e8'), slot=878, index=528, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00000041'), after=unhex('00000c42'), interact_type=13},
    {name='content/fac_helldivers/equipment/support_weapons/plasma_blaster/plasma_blaster#zone1', feature='equipment', id=unhex('540e78d79af4d5e8'), slot=878, index=528, zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000a041'), after=unhex('00000c42'), interact_type=3},
    {name='unresolved_mission_carryable_3e099ddf97acf85f#zone0', feature='equipment', id=unhex('5ff8ac97df9d093e'), slot=889, index=409, zone=0, zone_name=0xF2760503, radius=unhex('0000803f'), before=unhex('0000a041'), after=unhex('00000c42'), interact_type=31},
    {name='content/fac_helldivers/hellpod/ammo_rack/ammo_box#zone0', feature='supplies', id=unhex('484a28eb12961149'), slot=906, index=46, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00008040'), after=unhex('0000a041'), interact_type=4},
    {name='content/objectives/obj_common/shoulder_mounted_camera/shoulder_mounted_camera#zone0', feature='equipment', id=unhex('765ac010e9812437'), slot=910, index=419, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00000041'), after=unhex('00000c42'), interact_type=13},
    {name='content/objectives/obj_common/shoulder_mounted_camera/shoulder_mounted_camera#zone1', feature='equipment', id=unhex('765ac010e9812437'), slot=910, index=419, zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000a041'), after=unhex('00000c42'), interact_type=3},
    {name='content/objectives/obj_illuminate/il_artifact_01/il_artifact_01#zone0', feature='equipment', id=unhex('42d259b41e7563b6'), slot=916, index=435, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000a041'), after=unhex('00000c42'), interact_type=31},
    {name='unresolved_mission_carryable_6b7ee87fb2ec6455#zone0', feature='equipment', id=unhex('5564ecb27fe87e6b'), slot=917, index=413, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00008040'), after=unhex('00007041'), interact_type=31},
    {name='unresolved_mission_carryable_15e2a2b11ba78c5a#zone0', feature='equipment', id=unhex('5a8ca71bb1a2e215'), slot=924, index=95, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000a041'), after=unhex('00000c42'), interact_type=31},
    {name='content/fac_helldivers/equipment/support_weapons/sniper_rifle/sniper_rifle#zone0', feature='equipment', id=unhex('0742ca083e49c589'), slot=939, index=532, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00000041'), after=unhex('00000c42'), interact_type=13},
    {name='content/fac_helldivers/equipment/support_weapons/sniper_rifle/sniper_rifle#zone1', feature='equipment', id=unhex('0742ca083e49c589'), slot=939, index=532, zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000a041'), after=unhex('00000c42'), interact_type=3},
    {name='unresolved_mission_carryable_2d3bc1683a54298d#zone0', feature='equipment', id=unhex('8d29543a68c13b2d'), slot=949, index=429, zone=0, zone_name=0x4CCB322C, radius=unhex('00000040'), before=unhex('0000f041'), after=unhex('00000c42'), interact_type=31},
    {name='content/fac_helldivers/equipment/support_weapons/minigun/minigun#zone0', feature='equipment', id=unhex('7c19fa9cb88ca543'), slot=950, index=526, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00000041'), after=unhex('00000c42'), interact_type=13},
    {name='content/fac_helldivers/equipment/support_weapons/minigun/minigun#zone1', feature='equipment', id=unhex('7c19fa9cb88ca543'), slot=950, index=526, zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000a041'), after=unhex('00000c42'), interact_type=3},
    {name='content/objectives/obj_common/carry_warhead/warhead_01#zone0', feature='equipment', id=unhex('3ad7a9a936015b70'), slot=962, index=76, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00008040'), after=unhex('00007041'), interact_type=31},
    {name='unresolved_hellpod_equipment_9f27e0579375b865#zone0', feature='equipment', id=unhex('65b8759357e0279f'), slot=971, index=259, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00000041'), after=unhex('00000c42'), interact_type=13},
    {name='unresolved_dropped_weapon_9f27e0579375b865#zone1', feature='equipment', id=unhex('65b8759357e0279f'), slot=971, index=259, zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000a041'), after=unhex('00000c42'), interact_type=3},
    {name='content/fac_super_earth/equipment/support_weapons/shotgun_doublebarrel/shotgun_doublebarrel#zone0', feature='equipment', id=unhex('e4153426491f0752'), slot=994, index=317, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00000041'), after=unhex('00000c42'), interact_type=13},
    {name='content/fac_super_earth/equipment/support_weapons/shotgun_doublebarrel/shotgun_doublebarrel#zone1', feature='equipment', id=unhex('e4153426491f0752'), slot=994, index=317, zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000a041'), after=unhex('00000c42'), interact_type=3},
    {name='content/env_shared/assets/samples/blacksaffron_sample_01/blacksaffron_sample_01#zone0', feature='samples', id=unhex('6625ed26847530bd'), slot=1008, index=154, zone=0, zone_name=0x4CCB322C, radius=unhex('0000403f'), before=unhex('00001041'), after=unhex('00000c42'), interact_type=11},
    {name='content/fac_helldivers/equipment/support_weapons/faf_missile_launcher/faf_missile_launcher#zone0', feature='equipment', id=unhex('eef43c64d42faa25'), slot=1010, index=513, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00000041'), after=unhex('00000c42'), interact_type=13},
    {name='content/fac_helldivers/equipment/support_weapons/faf_missile_launcher/faf_missile_launcher#zone1', feature='equipment', id=unhex('eef43c64d42faa25'), slot=1010, index=513, zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000a041'), after=unhex('00000c42'), interact_type=3},
    {name='content/fac_helldivers/equipment/backpacks/drone_mg/drone_mg_weapon#zone0', feature='equipment', id=unhex('7933e1bde32126a3'), slot=1011, index=446, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00002041'), after=unhex('00000c42'), interact_type=1},
    {name='content/fac_helldivers/equipment/support_weapons/railgun/railgun#zone0', feature='equipment', id=unhex('609eb048dc0b9d2e'), slot=1016, index=529, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00000041'), after=unhex('00000c42'), interact_type=13},
    {name='content/fac_helldivers/equipment/support_weapons/railgun/railgun#zone1', feature='equipment', id=unhex('609eb048dc0b9d2e'), slot=1016, index=529, zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000a041'), after=unhex('00000c42'), interact_type=3},
    {name='content/fac_helldivers/equipment/support_weapons/harpoon_gun/harpoon_gun#zone0', feature='equipment', id=unhex('97e8a91a05e22838'), slot=1027, index=518, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00000041'), after=unhex('00000c42'), interact_type=13},
    {name='content/fac_helldivers/equipment/support_weapons/harpoon_gun/harpoon_gun#zone1', feature='equipment', id=unhex('97e8a91a05e22838'), slot=1027, index=518, zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000a041'), after=unhex('00000c42'), interact_type=3},
    {name='content/fac_helldivers/equipment/backpacks/belt_fed_grenade_launcher_backpack/belt_fed_grenade_launcher_backpack#zone0', feature='equipment', id=unhex('fd74f988b5154bbb'), slot=1029, index=211, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00008040'), after=unhex('00000c42'), interact_type=13},
    {name='content/fac_helldivers/equipment/backpacks/belt_fed_grenade_launcher_backpack/belt_fed_grenade_launcher_backpack#zone1', feature='equipment', id=unhex('fd74f988b5154bbb'), slot=1029, index=211, zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00002041'), after=unhex('00000c42'), interact_type=29},
    {name='content/fac_helldivers/equipment/backpacks/drone_weapons/drone_gas_projector/drone_gas_projector_mount#zone0', feature='equipment', id=unhex('edca3b15baa229b7'), slot=1045, index=451, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00002041'), after=unhex('00000c42'), interact_type=1},
    {name='content/env_cyborg/samples/automaton_sample_01#zone0', feature='samples', id=unhex('72bf369ef0a0b2be'), slot=1047, index=143, zone=0, zone_name=0x4CCB322C, radius=unhex('0000403f'), before=unhex('00001041'), after=unhex('00000c42'), interact_type=11},
    {name='content/fac_helldivers/equipment/support_weapons/flamethrower/flamethrower#zone0', feature='equipment', id=unhex('bfa347518999ab39'), slot=1049, index=515, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00000041'), after=unhex('00000c42'), interact_type=13},
    {name='content/fac_helldivers/equipment/support_weapons/flamethrower/flamethrower#zone1', feature='equipment', id=unhex('bfa347518999ab39'), slot=1049, index=515, zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000a041'), after=unhex('00000c42'), interact_type=3},
    {name='unresolved_sample_type_1_4932cbf33cd47ef9#zone0', feature='samples', id=unhex('f97ed43cf3cb3249'), slot=1050, index=195, zone=0, zone_name=0x4CCB322C, radius=unhex('0000403f'), before=unhex('00001041'), after=unhex('00000c42'), interact_type=11},
    {name='unresolved_hellpod_equipment_1d5943301a29c940#zone0', feature='equipment', id=unhex('40c9291a3043591d'), slot=1052, index=533, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00000041'), after=unhex('00000c42'), interact_type=13},
    {name='unresolved_dropped_weapon_1d5943301a29c940#zone1', feature='equipment', id=unhex('40c9291a3043591d'), slot=1052, index=533, zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000a041'), after=unhex('00000c42'), interact_type=3},
    {name='content/fac_helldivers/equipment/support_weapons/heavy_flamethrower/heavy_flamethrower#zone0', feature='equipment', id=unhex('9507a7635f18a878'), slot=1063, index=519, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00000041'), after=unhex('00000c42'), interact_type=13},
    {name='content/fac_helldivers/equipment/support_weapons/heavy_flamethrower/heavy_flamethrower#zone1', feature='equipment', id=unhex('9507a7635f18a878'), slot=1063, index=519, zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000a041'), after=unhex('00000c42'), interact_type=3},
    {name='content/fac_helldivers/equipment/sidearm_weapons/standard_pistol/standard_pistol#zone0', feature='equipment', id=unhex('a2446edbc2e5e405'), slot=1077, index=258, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00002041'), after=unhex('00000c42'), interact_type=2},
    {name='content/fac_helldivers/equipment/support_weapons/grenade_launcher_tactical/grenade_launcher_tactical#zone0', feature='equipment', id=unhex('9b3fa6cfb2293bfe'), slot=1079, index=517, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00000041'), after=unhex('00000c42'), interact_type=13},
    {name='content/fac_helldivers/equipment/support_weapons/grenade_launcher_tactical/grenade_launcher_tactical#zone1', feature='equipment', id=unhex('9b3fa6cfb2293bfe'), slot=1079, index=517, zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000a041'), after=unhex('00000c42'), interact_type=3},
    {name='content/env_super_earth/samples/research_sample_01#zone0', feature='samples', id=unhex('ba818869e7097e30'), slot=1082, index=193, zone=0, zone_name=0x4CCB322C, radius=unhex('0000403f'), before=unhex('00001041'), after=unhex('00000c42'), interact_type=11},
    {name='content/fac_helldivers/equipment/backpacks/bomb_backpack/bomb_backpack#zone1', feature='equipment', id=unhex('8ebc1a423886ce9a'), slot=1084, index=212, zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00002041'), after=unhex('00000c42'), interact_type=13},
    {name='content/fac_helldivers/equipment/backpacks/bomb_backpack/bomb_backpack#zone2', feature='equipment', id=unhex('8ebc1a423886ce9a'), slot=1084, index=212, zone=2, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00002041'), after=unhex('00000c42'), interact_type=29},
    {name='content/fac_helldivers/equipment/sidearm_weapons/pistol_broomhandle/pistol_broomhandle#zone0', feature='equipment', id=unhex('0fda4795d7bc80c7'), slot=1085, index=502, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00002041'), after=unhex('00000c42'), interact_type=2},
    {name='unresolved_mission_carryable_c02c2623b6359bb3#zone0', feature='equipment', id=unhex('b39b35b623262cc0'), slot=1089, index=411, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00008040'), after=unhex('00007041'), interact_type=31},
    {name='content/objectives/obj_cyborgs/cyborg_chemicals_backpack/cy_chemicals_backpack#zone0', feature='equipment', id=unhex('6b047e6ef660ec43'), slot=1090, index=425, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00008040'), after=unhex('00000c42'), interact_type=13},
    {name='content/objectives/obj_cyborgs/cyborg_chemicals_backpack/cy_chemicals_backpack#zone1', feature='equipment', id=unhex('6b047e6ef660ec43'), slot=1090, index=425, zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000a041'), after=unhex('00000c42'), interact_type=29},
    {name='content/env_bugs/assets/samples/bug_enemy_sample_01#zone0', feature='samples', id=unhex('a70bcd41648363d4'), slot=1091, index=138, zone=0, zone_name=0x4CCB322C, radius=unhex('0000403f'), before=unhex('00001041'), after=unhex('00000c42'), interact_type=11},
    {name='content/fac_helldivers/equipment/sidearm_weapons/pistol_nacho/pistol_nacho#zone0', feature='equipment', id=unhex('c574b78770c7584d'), slot=1093, index=503, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00002041'), after=unhex('00000c42'), interact_type=2},
    {name='content/env_illuminate/samples/illuminate_enemy_sample_01#zone0', feature='samples', id=unhex('9fc129e1d64e41a2'), slot=1096, index=147, zone=0, zone_name=0x4CCB322C, radius=unhex('0000403f'), before=unhex('00001041'), after=unhex('00000c42'), interact_type=11},
    {name='content/fac_helldivers/equipment/backpacks/drone_weapons/drone_flamethrower/drone_flamethrower_mount#zone0', feature='equipment', id=unhex('c6f323ba2543cd65'), slot=1098, index=450, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00002041'), after=unhex('00000c42'), interact_type=1},
    {name='content/fac_helldivers/equipment/support_weapons/arc_thrower/arc_thrower#zone0', feature='equipment', id=unhex('e606730fd59cde96'), slot=1100, index=505, zone=0, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('00000041'), after=unhex('00000c42'), interact_type=13},
    {name='content/fac_helldivers/equipment/support_weapons/arc_thrower/arc_thrower#zone1', feature='equipment', id=unhex('e606730fd59cde96'), slot=1100, index=505, zone=1, zone_name=0x4CCB322C, radius=unhex('0000803f'), before=unhex('0000a041'), after=unhex('00000c42'), interact_type=3},
}

local function validate_instance(instance, region_base, enabled)
    local blob = assert(read(instance, INSTANCE_BYTES), 'Cannot read interaction data')
    assert(u32(blob,0) == 0xFCCA29DB and blob:sub(5,8) == 'LDLD'
           and u32(blob,8) == 1 and u32(blob,12) == 0xFCCA29DB
           and u32(blob,16) == DATA_BYTES and blob:byte(21) == 1,
           'Interaction instance header mismatch')
    assert(hash_bytes(blob) == INSTANCE_SHA, 'Interaction data fingerprint mismatch')
    local data = blob:sub(29)
    assert(#data == DATA_BYTES and MAP_BYTES+RECORD_COUNT*RECORD_BYTES == #data,
           'Interaction structure size mismatch')
    local targets = {}
    for _, resource in ipairs(resources) do
        if enabled[resource.feature] then
        local start = resource.slot*16
        assert(data:sub(start+1,start+8) == resource.id
               and u32(data,start+8) == resource.index,
               resource.name..' resource identity mismatch')
        assert(resource.index < RECORD_COUNT, resource.name..' index out of bounds')
        local record = MAP_BYTES + resource.index*RECORD_BYTES
        local zone = record + 8 + resource.zone*136
        assert(data:sub(record+1,record+4) == unhex('01010100'),
               resource.name..' component flags mismatch')
        assert(u32(data,zone) == resource.zone_name,
               resource.name..' zone name mismatch')
        assert(data:sub(zone+5,zone+8) == resource.radius,
               resource.name..' radius mismatch')
        assert(data:sub(zone+9,zone+12) == resource.before,
               resource.name..' view distance mismatch')
        assert(u32(data,zone+40) == resource.interact_type,
               resource.name..' interaction type mismatch')
        local target = instance + 28 + zone + 8
        assert(target >= region_base and target+4 <= region_base+REGION_SIZE,
               resource.name..' target out of region')
        local page = assert(query(target), resource.name..' target page missing')
        assert(page.state == 0x1000 and page.kind == 0x20000
               and page.protect == 0x02, resource.name..' target page is not read-only data')
        targets[#targets+1] = {resource=resource, target=target, radius=target-4}
        end
    end
    return targets
end

local SPOT_INSTANCE_OFFSET = 0x5A6668
local SPOT_INSTANCE_BYTES = 72100
local SPOT_PAYLOAD_BYTES = 72072
local SPOT_INSTANCE_SHA = 'F154082AC22782251FF279CB4950F973E565EB0CB15B9AF49EE26FFA738776CB'
local function validate_spottable(region_base)
    local instance = region_base + SPOT_INSTANCE_OFFSET
    local blob = assert(read(instance,SPOT_INSTANCE_BYTES), 'Cannot read spottable data')
    assert(u32(blob,0) == 0x0A5E53DB and blob:sub(5,8) == 'LDLD'
           and u32(blob,8) == 1 and u32(blob,12) == 0x0A5E53DB
           and u32(blob,16) == SPOT_PAYLOAD_BYTES and blob:byte(21) == 1,
           'Spottable instance header mismatch')
    assert(hash_bytes(blob) == SPOT_INSTANCE_SHA, 'Spottable data fingerprint mismatch')
    local data = blob:sub(29)
    local health_at = 22176 + 70*72
    local rack_at = 22176 + 85*72
    assert(data:sub(961*16+1,961*16+8) == unhex('65792f925b4ccab4')
           and u32(data,961*16+8) == 70,
           'Health pack spottable resource mismatch')
    assert(data:sub(1382*16+1,1382*16+8) == unhex('a829a746c6168d3b')
           and u32(data,1382*16+8) == 85,
           'Rack health pack spottable resource mismatch')
    assert(u32(data,health_at+20) == 0 and u32(data,rack_at+20) == 10,
           'Health marker type mismatch')
    assert(data:byte(health_at+33) == 1 and data:byte(rack_at+33) == 1,
           'Health spottable inactive')
    assert(data:sub(health_at+57,health_at+68) == data:sub(rack_at+57,rack_at+68)
           and data:sub(health_at+57,health_at+64) == unhex('847193dcb7d27cb0'),
           'Health marker icon mismatch')
    local target = instance+28+health_at+20
    local page = assert(query(target), 'Health marker page missing')
    assert(page.state == 0x1000 and page.kind == 0x20000 and page.protect == 0x02,
           'Health marker is not read-only game data')
    return {resource={name='health_item_marker',
                      before=unhex('00000000'),after=unhex('0a000000')},
            target=target}
end

local function find_targets(enabled)
    local address, result, count = 0, nil, 0
    while address < 0x800000000000 do
        local region = query(address)
        if not region then break end
        local base, size = address_of(region.base), tonumber(region.size)
        assert(size > 0 and base+size > address, 'Invalid memory map')
        if region.state == 0x1000 and region.kind == 0x20000
           and region.protect == 0x02 and size == REGION_SIZE then
            local instance = base+INSTANCE_OFFSET
            local header = read(instance,28)
            if header and u32(header,0) == 0xFCCA29DB and header:sub(5,8) == 'LDLD' then
                count = count+1
                result = validate_instance(instance,base,enabled)
                if enabled.supplies then
                    result[#result+1] = validate_spottable(base)
                end
            end
        end
        address = base+size
    end
    if count == 0 then return nil end
    assert(count == 1 and result, 'Expected one interaction data buffer; found '..count)
    return result
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

local build_checked = false
local function apply()
    local choices = rawget(_G, 'CodexPickupIconChoices')
    local enabled = {
        samples=type(choices) == 'table' and choices.samples == true,
        supplies=type(choices) == 'table' and choices.supplies == true,
        equipment=type(choices) == 'table' and choices.equipment == true,
    }
    if not (enabled.samples or enabled.supplies or enabled.equipment) then
        return 'no range categories selected in Arsenal; no data changed'
    end
    if not build_checked then
        local exe = kernel.GetModuleHandleA(nil)
        local game = kernel.GetModuleHandleA('game.dll')
        assert(exe ~= nil and game ~= nil, 'Game modules unavailable')
        assert(hash_module(exe) == EXE_SHA, 'Unsupported EXE build; no change')
        assert(hash_module(game) == GAME_SHA, 'Unsupported game.dll build; no change')
        build_checked = true
    end
    local targets = find_targets(enabled)
    if not targets then return nil end
    local applied = {}
    local ok, problem = pcall(function()
        for _, entry in ipairs(targets) do
            set_view(entry, entry.resource.before, entry.resource.after)
            applied[#applied+1] = entry
        end
        for _, entry in ipairs(targets) do
            assert(read(entry.target,4) == entry.resource.after,
                   entry.resource.name..' final field check failed')
            if entry.radius then
                assert(read(entry.radius,4) == entry.resource.radius,
                       entry.resource.name..' final Radius check failed')
            end
        end
    end)
    if not ok then
        local rollback_ok = true
        for i=#applied,1,-1 do
            local entry = applied[i]
            if not pcall(set_view, entry, entry.resource.after, entry.resource.before) then
                rollback_ok = false
            end
        end
        assert(rollback_ok, tostring(problem)..'; prior-write rollback failed')
        error(problem)
    end
    local counts = {samples=0, supplies=0, equipment=0}
    for _, entry in ipairs(targets) do
        if entry.radius then
            local feature = entry.resource.feature
            counts[feature] = counts[feature] + 1
        end
    end
    local resupply = enabled.supplies and '; resupply unit CC102A849E8930EF and supply_box zones 0/1 verified 4.0->20.0' or ''
    return string.format('applied %d ViewDistance fields: samples=%d supplies=%d equipment=%d%s; internal ViewDistance targets: supplies=20.0 carry-ammo/warhead/SEAF-shells=15.0 other=35.0; Radius unchanged',
                         counts.samples+counts.supplies+counts.equipment,
                         counts.samples,counts.supplies,counts.equipment,resupply)

end

local previous_update = update
local finished = false
local next_retry_ms = 0
local wrapper
local function initialize()
    if finished then return end
    local now = tonumber(kernel.GetTickCount64())
    if now < next_retry_ms then return end
    state.attempts = state.attempts + 1
    local ok, message = pcall(apply)
    if ok and message == nil then
        next_retry_ms = now + 3000
        if state.attempts == 1 or state.attempts % 20 == 0 then
            report('waiting for loaded interaction data; attempts='..state.attempts)
        end
        return
    end
    finished = true
    state.active = ok
    report(message)
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
