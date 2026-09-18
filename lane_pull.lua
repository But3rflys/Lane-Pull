local qLocalization = (function()
	local lib = {}

	local a = function(...)
		return ...
	end

	local state = {
		lang = Menu.Find("SettingsHidden", "", "", "", "Main", "Language"),
		instances = {},
	}

	local setters = {
		ToolTip = "tooltip",
	}

	local helpers
	do
		helpers = {
			resolve = a(function(root, path)
				for key in path:gmatch("[^.]+") do
					if type(root) ~= "table" then
						return
					end

					root = root[key]
				end

				return root
			end),

			is_object = a(function(value)
				return type(value) == "table" or type(value) == "userdata"
			end),

			has_method = a(function(object, name)
				return helpers.is_object(object) and type(object[name]) == "function"
			end),

			is_menu_object = a(function(value)
				return helpers.has_method(value, "Name") and helpers.has_method(value, "Type")
			end),

			is_list = a(function(value)
				if type(value) ~= "table" or #value == 0 then
					return false
				end

				for i = 1, #value do
					if type(value[i]) ~= "string" then
						return false
					end
				end

				return true
			end),

			is_indexed_list = a(function(object)
				return helpers.has_method(object, "List") and not helpers.has_method(object, "ListEnabled")
			end),
		}
	end

	function lib.new(translations)
		local languages = {}

		for i, name in ipairs(state.lang and state.lang:List() or {}) do
			local code = name:match("%a+")

			if code and translations[code] then
				languages[i - 1] = code
			end
		end

		local localization = {
			translations = translations,
			languages = languages,
			objects = {},
		}

		local methods
		do
			methods = {
				get_language = a(function(language_index)
					if language_index == nil and state.lang then
						language_index = state.lang:Get()
					end

					return localization.languages[language_index] or "en"
				end),

				localize = a(function(path, language_index)
					if type(path) ~= "string" then
						return path
					end

					local language = methods.get_language(language_index)

					return helpers.resolve(localization.translations[language], path)
						or helpers.resolve(localization.translations.en, path)
						or path
				end),

				has = a(function(path)
					if type(path) ~= "string" then
						return false
					end

					return helpers.resolve(localization.translations.en, path) ~= nil
						or helpers.resolve(localization.translations[methods.get_language()], path) ~= nil
				end),

				localize_items = a(function(items, language_index)
					local result, localized = {}, false

					for i = 1, #items do
						local value = items[i]

						if methods.has(value) then
							result[i] = methods.localize(value, language_index)
							localized = true
						else
							result[i] = value
						end
					end

					return result, localized
				end),

				apply = a(function(object, kind, path, language_index)
					if kind == "label" then
						object:ForceLocalization(methods.localize(path, language_index))
					elseif kind == "tooltip" then
						object:ToolTip(methods.localize(path, language_index))
					elseif kind == "items" then
						local value = object:Get()

						object:Update((methods.localize_items(path, language_index)))
						object:Set(value)
					end
				end),

				track = a(function(object, kind, path, apply_now)
					local record = localization.objects[object]

					if record == nil then
						record = {}
						localization.objects[object] = record
					end

					record[kind] = path

					if apply_now then
						methods.apply(object, kind, path)
					end
				end),

				register = a(function(object, path)
					if not methods.has(path) or not helpers.has_method(object, "ForceLocalization") then
						return
					end

					methods.track(object, "label", path, true)
				end),

				update = a(function(language_index)
					for object, record in pairs(localization.objects) do
						for kind, path in pairs(record) do
							methods.apply(object, kind, path, language_index)
						end
					end
				end),

				wrap = a(function(target, bind_self)
					if not helpers.is_object(target) then
						return target
					end

					local proxy

					proxy = setmetatable({}, {
						__index = function(_, key)
							local member = target[key]

							if type(member) ~= "function" then
								return member
							end

							return function(...)
								local args = table.pack(...)

								if bind_self and args[1] == proxy then
									table.remove(args, 1)
									args.n = args.n - 1
								end

								if key == "Switch" and args.n < 2 then
									args[2] = false
									args.n = 2
								end

								local name_path, item_paths

								if setters[key] then
									if methods.has(args[1]) then
										methods.track(target, setters[key], args[1], false)

										args[1] = methods.localize(args[1])
									end
								else
									local name_index = bind_self and 1 or args.n

									if methods.has(args[name_index]) then
										name_path = args[name_index]
									end

									local items_index

									if key == "Combo" then
										items_index = 2
									elseif key == "Update" and helpers.is_indexed_list(target) then
										items_index = 1
									end

									if items_index ~= nil and helpers.is_list(args[items_index]) then
										local items, localized = methods.localize_items(args[items_index])

										if localized then
											item_paths = args[items_index]
											args[items_index] = items
										end
									end
								end

								local results

								if bind_self then
									results = table.pack(member(target, table.unpack(args, 1, args.n)))
								else
									results = table.pack(member(table.unpack(args, 1, args.n)))
								end

								for i = 1, results.n do
									local result = results[i]

									if helpers.is_menu_object(result) then
										if name_path then
											methods.register(result, name_path)
										end

										if item_paths then
											methods.track(result, "items", item_paths, false)
											item_paths = nil
										end

										results[i] = methods.wrap(result, true)
									end
								end

								if item_paths then
									methods.track(target, "items", item_paths, false)
								end

								return table.unpack(results, 1, results.n)
							end
						end,

						__newindex = function(_, key, value)
							target[key] = value
						end,
					})

					return proxy
				end),
			}
		end

		state.instances[methods] = true

		return {
			GetLanguage = methods.get_language,

			Get = methods.localize,
			Localize = methods.localize,

			Update = methods.update,
			Register = methods.register,

			Wrap = methods.wrap,

			WrapLibrary = function(library)
				return methods.wrap(library, false)
			end,
		}
	end

	if state.lang then
		state.lang:SetCallback(function(this)
			local language_index = this:Get()

			for methods in pairs(state.instances) do
				methods.update(language_index)
			end
		end, true)
	else
		Log.Write("[qLocalization] Language widget not found, using English fallback")
	end

	return lib
end)()

local localization = qLocalization.new({
	en = {
		lp_group_main = "The basics",
		lp_group_way = "How it plays",
		lp_group_safe = "Stay safe",
		lp_group_debug = "Debug stuff",
		lp_enable = "Turn it on",
		lp_enable_tip = "Hit the key and your Dominator creep grabs\nthe enemy wave and drags it right to you",
		lp_key = "Pull key",
		lp_key_tip = "Tap once to go pull, tap again to call it off.\nWave's in the fog? It just waits for the spawn",
		lp_pick = "Which wave to grab",
		lp_picks_hero = "Closest to me",
		lp_picks_puller = "Closest to my creep",
		lp_picks_cursor = "Whatever's by my cursor",
		lp_pick_tip = "For waves in the fog it counts the distance\nto the spot where your creep meets them",
		lp_units = "Who does the pulling",
		lp_units_tip = "Tick who's allowed to pull. Order is priority,\njust drag the icons around",
		lp_hide = "Hide in the trees",
		lp_hide_tip = "Your creep chills in the trees till the wave shows up.\nIf enemies spot it, it finds another bush",
		lp_dive = "Tower dive for waves",
		lp_dive_tip = "No safe spot to catch the wave? Your creep\nsits under their tower and just eats the shots",
		lp_gap = "How far it can run ahead",
		lp_gap_tip = "How far your creep can get ahead of the pack.\nIf they fall behind more, it waits up",
		lp_after = "Once the wave's here",
		lp_afters_stay = "Chill behind me",
		lp_afters_attack = "Help me farm",
		lp_after_tip = "What your creep does when the wave reaches you",
		lp_abort_hp = "Bail out below HP",
		lp_abort_hp_tip = "Drop below this and your creep ditches\nthe pull and runs back to you",
		lp_avoid = "Dodge enemy heroes",
		lp_avoid_tip = "Calls off the pull if an enemy hero\nshows up near your creep",
		lp_avoid_radius = "How close is too close",
		lp_debug = "Debug overlay",
		lp_debug_tip = "Shows lanes, wave guesses, what your creep\nis up to and dumps stuff into the log",
		lp_bind_name = "Lane Pull",
	},
	ru = {
		lp_group_main = "Основное",
		lp_group_way = "Поведение",
		lp_group_safe = "Безопасность",
		lp_group_debug = "Отладка",
		lp_enable = "Включить",
		lp_enable_tip = "Крип с Доминатора по нажатию клавиши забирает\nвражескую волну и ведет ее к герою",
		lp_key = "Клавиша выпула",
		lp_key_tip = "Первое нажатие запускает выпул, второе отменяет.\nЕсли волна в тумане, крип ждет ее по таймеру спавна",
		lp_pick = "Какую волну пулить",
		lp_picks_hero = "Ближайшую к герою",
		lp_picks_puller = "Ближайшую к нашему крипу",
		lp_picks_cursor = "У курсора",
		lp_pick_tip = "Для волны в тумане расстояние считается\nдо точки, где крип ее встретит",
		lp_units = "Кем пулить",
		lp_units_tip = "Отметь, кто может пулить волну. Порядок это приоритет,\nперетаскивай иконки мышкой",
		lp_hide = "Прятаться в деревьях",
		lp_hide_tip = "Крип ждет волну в деревьях и выходит к ее приходу.\nЕсли враги его видят, он меняет укрытие",
		lp_dive = "Забегать под вышку",
		lp_dive_tip = "Если вне радиуса вражеских вышек волну не встретить,\nкрип встает под вышку, и ее выстрелы выпул не отменяют",
		lp_gap = "Дистанция ведения",
		lp_gap_tip = "Насколько крип может оторваться от пачки.\nЕсли пачка отстала сильнее, он ждет",
		lp_after = "После доставки",
		lp_afters_stay = "Стоять за героем",
		lp_afters_attack = "Бить вместе с героем",
		lp_after_tip = "Что делает крип, когда волна дошла до героя",
		lp_abort_hp = "Отмена при HP ниже",
		lp_abort_hp_tip = "Ниже этого порога крип бросает выпул\nи возвращается к герою",
		lp_avoid = "Избегать вражеских героев",
		lp_avoid_tip = "Бросить выпул, если рядом с нашим крипом\nвиден вражеский герой",
		lp_avoid_radius = "Радиус проверки героев",
		lp_debug = "Отладочный оверлей",
		lp_debug_tip = "Линии, прогноз волны, состояние крипа\nи сообщения в лог",
		lp_bind_name = "Выпул волны",
	},
})

local UI = localization.WrapLibrary(Menu)

local tab = UI.Create("Creeps", "Main", "Lane Pull")
tab:Icon("\u{f4d7}")

local page = tab:Create("Settings")
local g_main = page:Create("lp_group_main", Enum.GroupSide.Left)
local g_way = page:Create("lp_group_way", Enum.GroupSide.Left)
local g_safe = page:Create("lp_group_safe", Enum.GroupSide.Right)
local g_debug = page:Create("lp_group_debug", Enum.GroupSide.Right)

local ORDER_ID = "lane_pull"
local K = {
	STRUCT_MOVE_EPS = 50.0,

	UPDATE_INTERVAL     = 0.10,
	POS_EPS             = 90.0,
	POS_TOLERANCE       = 0.15,
	ARRIVE_IDLE         = 0.80,
	HOLD_RELEASE        = 250.0,
	HOLD_DRIFT          = 150.0,
	PROGRESS_EPS        = 20.0,
	PROGRESS_TIMEOUT    = 2.00,
	ATTACK_IDLE         = 1.00,
	PACE_MIN            = 0.60,
	SHOT_MEMORY         = 1.00,
	CLIP_MARGIN         = 60.0,
	DETOUR_MARGIN       = 150.0,
	GUIDE_REPLAN_DIST   = 300.0,
	GUIDE_REPLAN_TIME   = 1.5,
	GUIDE_REACH         = 120.0,
	GUIDE_LOOKAHEAD     = 500.0,
	LIFE_EPS            = 3.0,
	ALLY_CLEAR          = 650.0,
	PATH_FACTOR         = 1.25,
	WAIT_WEIGHT         = 25.0,
	FUTURE_BATCHES      = 2,
	PRESS_DEBOUNCE      = 0.25,

	SPAWN_PERIOD        = 30.0,
	DEFAULT_CREEP_SPEED = 325.0,
	SPEED_SAMPLE        = 0.5,
	SPEED_MIN           = 200.0,
	SPEED_MAX           = 480.0,
	SPEED_ALPHA         = 0.2,
	STRUCT_SCAN         = 5.0,

	WAVE_LINK           = 450.0,
	LANE_BAND           = 900.0,
	CURSOR_WAVE         = 900.0,
	CURSOR_LANE         = 1800.0,
	ENGAGE_RADIUS       = 700.0,
	FRONT_BUFFER        = 400.0,
	CLASH_GAP           = 1400.0,
	FOG_STEP            = 150.0,
	FOG_CHECK_RADIUS    = 700.0,
	SEARCH_STEP         = 100.0,
	ARRIVE_SLACK        = 1.0,
	SEARCH_DETECT       = 1600.0,
	SEARCH_MAX          = 30.0,
	JOB_MAX             = 60.0,
	MISS_GRACE          = 5.0,
	MAX_MISSED          = 2,
	TOWER_MARGIN        = 250.0,
	TOWER_WATCH         = 200.0,

	HOOK_OFFSET         = 350.0,
	HOOK_ENGAGE         = 550.0,
	HOOK_TIMEOUT        = 3.0,
	INTERCEPT_MAX_T     = 6.0,
	CONTACT_RANGE       = 220.0,
	CONTACT_TIME        = 0.6,
	MELEE_HIT_RADIUS    = 350.0,
	MAX_RETRIES         = 3,
	MIN_PULL_DIST       = 600.0,

	PACK_RANGE          = 1300.0,
	PACK_SPREAD         = 250.0,
	LOST_GAP            = 850.0,
	LOST_TIME           = 1.2,
	GAP_HYST            = 150.0,
	RANGED_SLACK        = 150.0,
	STALL_PROGRESS      = 40.0,
	FOLLOW_SPEED        = 80.0,
	FOLLOW_CONTACT      = 250.0,
	STUCK_TIME          = 0.8,
	STRAGGLER_DROP      = 4.0,
	HG_DZ               = 64.0,
	HG_GAP              = 150.0,
	LEAD_STALL          = 1.5,

	HIDE_RADII          = { 250.0, 350.0, 450.0 },
	HIDE_TREE_RADIUS    = 250.0,
	HIDE_MIN_TREES      = 3,
	HIDE_LANE_DIST      = 200.0,
	HIDE_RECALC         = 150.0,
	HIDE_SEEN_TIME      = 1.5,
	HIDE_BAD_RADIUS     = 150.0,
	LEAVE_MARGIN        = 1.5,
	WAVE_LOST_TIME      = 2.5,
	MEMBER_FORGET       = 3.0,

	DELIVER_RADIUS      = 450.0,
	DELIVER_TIME        = 5.0,
	DELIVER_DONE_RADIUS = 1500.0,
	BEHIND              = 200.0,
	ARRIVE_EPS          = 90.0,
	RETURN_DONE         = 450.0,
	RETURN_TIME         = 5.0,
	FALLBACK_SPEED      = 300.0,
	MSG_TIME            = 4.0,
}

local UT = Enum.UnitTypeFlags
local STATE = Enum.ModifierState
local TEAM_ENEMY = Enum.TeamType.TEAM_ENEMY
local RADIANT = Enum.TeamNum.TEAM_RADIANT
local ISSUER_UNIT = Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY
local ISSUER_SELECTED = Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_SELECTED_UNITS
local GAME_IN_PROGRESS = Enum.GameState.DOTA_GAMERULES_STATE_GAME_IN_PROGRESS

local ORDER_KIND = {
	move = Enum.UnitOrder.DOTA_UNIT_ORDER_MOVE_TO_POSITION,
	attack = Enum.UnitOrder.DOTA_UNIT_ORDER_ATTACK_TARGET,
	attack_move = Enum.UnitOrder.DOTA_UNIT_ORDER_ATTACK_MOVE,
	hold = Enum.UnitOrder.DOTA_UNIT_ORDER_HOLD_POSITION,
}

local ORDER_BLOCK_STATES = {
	STATE.MODIFIER_STATE_STUNNED,
	STATE.MODIFIER_STATE_HEXED,
	STATE.MODIFIER_STATE_FEARED,
	STATE.MODIFIER_STATE_FROZEN,
	STATE.MODIFIER_STATE_NIGHTMARED,
	STATE.MODIFIER_STATE_TAUNTED,
	STATE.MODIFIER_STATE_COMMAND_RESTRICTED,
	STATE.MODIFIER_STATE_OUT_OF_GAME,
}

local MOVE_BLOCK_STATES = {
	STATE.MODIFIER_STATE_ROOTED,
}

local FREE_PATHING_STATES = {}
for _, name in ipairs({
	"MODIFIER_STATE_FLYING",
	"MODIFIER_STATE_FLYING_FOR_PATHING_PURPOSES_ONLY",
	"MODIFIER_STATE_ALLOW_PATHING_THROUGH_TREES",
	"MODIFIER_STATE_ALLOW_PATHING_THROUGH_CLIFFS",
	"MODIFIER_STATE_ALLOW_PATHING_THROUGH_OBSTRUCTIONS",
}) do
	if STATE[name] then FREE_PATHING_STATES[#FREE_PATHING_STATES + 1] = STATE[name] end
end

local LANE_NAMES = { "top", "mid", "bot" }

local UNIT_KINDS = {
	{ id = "Dominator creep", on = true, patterns = { "^npc_dota_neutral_" },
		icon = "panorama/images/items/helm_of_the_dominator_png.vtex_c" },
	{ id = "Spirit Bear", on = true, patterns = { "lone_druid_bear", "spirit_bear" },
		icon = "panorama/images/spellicons/lone_druid_spirit_bear_png.vtex_c" },
	{ id = "Lycan wolves", on = false, patterns = { "lycan_wolf" },
		icon = "panorama/images/spellicons/lycan_summon_wolves_png.vtex_c" },
	{ id = "Treants", on = false, guide = true, patterns = { "furion_treant" },
		icon = "panorama/images/spellicons/furion_force_of_nature_png.vtex_c" },
	{ id = "Eidolons", on = false, patterns = { "eidolon" },
		icon = "panorama/images/spellicons/enigma_demonic_conversion_png.vtex_c" },
	{ id = "Boar", on = false, patterns = { "beastmaster_boar" },
		icon = "panorama/images/spellicons/beastmaster_call_of_the_wild_png.vtex_c" },
	{ id = "Familiars", on = false, guide = true, patterns = { "visage_familiar" },
		icon = "panorama/images/spellicons/visage_summon_familiars_png.vtex_c" },
	{ id = "Forged Spirits", on = false, patterns = { "forged_spirit" },
		icon = "panorama/images/spellicons/invoker_forge_spirit_png.vtex_c" },
	{ id = "Spiderlings", on = false, guide = true, patterns = { "broodmother_spider" },
		icon = "panorama/images/spellicons/broodmother_spawn_spiderlings_png.vtex_c" },
}

local STRUCTURES = {
	["npc_dota_goodguys_tower1_top"] = { -6336.0, 1856.0, 128.0 },
	["npc_dota_goodguys_tower2_top"] = { -6501.0, -872.0, 128.0 },
	["npc_dota_goodguys_tower3_top"] = { -6592.0, -3408.0, 256.0 },
	["npc_dota_goodguys_melee_rax_top"] = { -6336.0, -3758.0, 256.0 },
	["npc_dota_goodguys_range_rax_top"] = { -6844.0, -3759.0, 256.0 },
	["npc_dota_goodguys_tower1_mid"] = { -1544.0, -1408.0, 128.0 },
	["npc_dota_goodguys_tower2_mid"] = { -3190.3, -2926.2, 128.0 },
	["npc_dota_goodguys_tower3_mid"] = { -4640.0, -4144.0, 256.0 },
	["npc_dota_goodguys_melee_rax_mid"] = { -4672.0, -4552.0, 256.0 },
	["npc_dota_goodguys_range_rax_mid"] = { -5060.0, -4199.0, 256.0 },
	["npc_dota_goodguys_tower1_bot"] = { 4859.9, -6379.2, 128.0 },
	["npc_dota_goodguys_tower2_bot"] = { -360.0, -6256.0, 128.0 },
	["npc_dota_goodguys_tower3_bot"] = { -3952.0, -6112.0, 256.0 },
	["npc_dota_goodguys_melee_rax_bot"] = { -4280.0, -6360.0, 256.0 },
	["npc_dota_goodguys_range_rax_bot"] = { -4279.0, -5853.0, 256.0 },
	["npc_dota_badguys_tower1_top"] = { -5274.6, 6036.0, 128.0 },
	["npc_dota_badguys_tower2_top"] = { -128.0, 6016.0, 128.0 },
	["npc_dota_badguys_tower3_top"] = { 3552.0, 5776.0, 256.0 },
	["npc_dota_badguys_melee_rax_top"] = { 3898.0, 5496.0, 256.0 },
	["npc_dota_badguys_range_rax_top"] = { 3894.0, 6025.0, 256.0 },
	["npc_dota_badguys_tower1_mid"] = { 524.0, 652.0, 128.0 },
	["npc_dota_badguys_tower2_mid"] = { 2496.0, 2112.0, 128.0 },
	["npc_dota_badguys_tower3_mid"] = { 4272.0, 3759.0, 256.0 },
	["npc_dota_badguys_melee_rax_mid"] = { 4702.0, 3824.0, 256.0 },
	["npc_dota_badguys_range_rax_mid"] = { 4336.0, 4183.0, 256.0 },
	["npc_dota_badguys_tower1_bot"] = { 6269.3, -2240.0, 128.0 },
	["npc_dota_badguys_tower2_bot"] = { 6400.0, 384.0, 128.0 },
	["npc_dota_badguys_tower3_bot"] = { 6336.0, 3032.0, 256.0 },
	["npc_dota_badguys_melee_rax_bot"] = { 6592.0, 3392.0, 256.0 },
	["npc_dota_badguys_range_rax_bot"] = { 6064.0, 3376.0, 256.0 },
}
local ROTATIONS = { 30, -30, 60, -60 }
local ACTIVE = { search = true, approach = true, hook = true, lead = true }

local job = nil
local next_run = 0.0
local last_press = -100.0
local struct_pos = {}
local struct_version = 0
local next_struct_scan = 0.0
local lanes = nil
local lanes_version = -1
local lanes_radiant = nil
local creep_speed = K.DEFAULT_CREEP_SPEED
local speed_track = {}
local next_speed_sample = 0.0
local enemy_now = {}
local enemy_by_idx = {}
local allied_now = {}
local danger_towers = {}
local ally_zones = {}
local last_msg = nil
local last_msg_t = -100.0
local debug_font = nil

local ui = {}

ui.enable = g_main:Switch("lp_enable", false, "\u{f011}")
ui.enable:ToolTip("lp_enable_tip")

ui.key = g_main:Bind("lp_key", Enum.ButtonCode.KEY_NONE, "\u{f11c}")
ui.key:ToolTip("lp_key_tip")

ui.pick = g_main:Combo("lp_pick", { "lp_picks_hero", "lp_picks_puller", "lp_picks_cursor" }, 0)
ui.pick:Icon("\u{f05b}")
ui.pick:ToolTip("lp_pick_tip")

local unit_items = {}
for i = 1, #UNIT_KINDS do
	local kind = UNIT_KINDS[i]
	unit_items[i] = { kind.id, kind.icon, kind.on }
end
ui.units = g_main:MultiSelect("lp_units", unit_items, true)
ui.units:DragAllowed(true)
ui.units:ToolTip("lp_units_tip")

ui.hide = g_way:Switch("lp_hide", true, "\u{f1bb}")
ui.hide:ToolTip("lp_hide_tip")

ui.dive = g_way:Switch("lp_dive", true, "\u{f447}")
ui.dive:ToolTip("lp_dive_tip")

ui.gap = g_way:Slider("lp_gap", 250, 700, 400, "%d")
ui.gap:Icon("\u{f337}")
ui.gap:ToolTip("lp_gap_tip")

ui.after = g_way:Combo("lp_after", { "lp_afters_stay", "lp_afters_attack" }, 0)
ui.after:Icon("\u{f11e}")
ui.after:ToolTip("lp_after_tip")

ui.abort_hp = g_safe:Slider("lp_abort_hp", 10, 80, 30, "%d%%")
ui.abort_hp:Icon("\u{f004}")
ui.abort_hp:ToolTip("lp_abort_hp_tip")

ui.avoid = g_safe:Switch("lp_avoid", true, "\u{f70c}")
ui.avoid:ToolTip("lp_avoid_tip")

ui.avoid_radius = g_safe:Slider("lp_avoid_radius", 500, 1600, 900, "%d")
ui.avoid_radius:Icon("\u{f1ce}")

ui.debug = g_debug:Switch("lp_debug", false, "\u{f188}")
ui.debug:ToolTip("lp_debug_tip")

ui.key:Properties(localization.Get("lp_bind_name"))

local function refresh_disabled()
	local on = ui.enable:Get()
	ui.key:Disabled(not on)
	ui.pick:Disabled(not on)
	ui.dive:Disabled(not on)
	ui.hide:Disabled(not on)
	ui.units:Disabled(not on)
	ui.gap:Disabled(not on)
	ui.after:Disabled(not on)
	ui.abort_hp:Disabled(not on)
	ui.avoid:Disabled(not on)
	ui.avoid_radius:Disabled(not on or not ui.avoid:Get())
	ui.debug:Disabled(not on)
end

ui.enable:SetCallback(function()
	refresh_disabled()
	if not ui.enable:Get() then
		job = nil
	end
end, true)

ui.avoid:SetCallback(function() refresh_disabled() end)

local function note(text)
	last_msg = text
	last_msg_t = GameRules.GetGameTime()
	if ui.debug:Get() then
		Log.Write("[Lane Pull] " .. text)
	end
end

local function has_any_state(u, list)
	for i = 1, #list do
		if NPC.HasState(u, list[i]) then return true end
	end
	return false
end

local function orders_blocked(u)
	return has_any_state(u, ORDER_BLOCK_STATES)
end

local function move_blocked(u)
	return orders_blocked(u) or has_any_state(u, MOVE_BLOCK_STATES)
end

local function can_issue()
	if not Humanizer or not Humanizer.OrdersCanBeCastedThisTick then return true end
	return Humanizer.OrdersCanBeCastedThisTick() > 0
end

local function game_clock()
	local t = GameRules.GetDOTATime(false, false)
	if not t or t <= 0 then
		t = GameRules.GetGameTime() - (GameRules.GetGameStartTime() or 0)
	end
	if t < 0 then return 0 end
	return t
end

local function in_match()
	if not Engine.IsInGame() then return false end
	if GameRules.IsPaused() then return false end
	return GameRules.GetGameState() == GAME_IN_PROGRESS
end

local function unit_speed(u)
	local speed = NPC.GetMoveSpeed(u)
	if not speed or speed <= 0 then return K.FALLBACK_SPEED end
	return speed
end

local function point_visible(p)
	if not FogOfWar or not FogOfWar.IsPointVisible then return false end
	return FogOfWar.IsPointVisible(p) == true
end

local function walkable(p)
	if not GridNav.IsTraversable(p) then return false end
	local trees = Trees.InRadius(p, 80, true)
	return not trees or #trees == 0
end

local function lane_point(lane, s)
	local pts, cum = lane.pts, lane.cum
	if s <= 0 then return pts[1]:Clone() end
	if s >= lane.len then return pts[#pts]:Clone() end
	for i = 2, #pts do
		if s <= cum[i] then
			local seg = cum[i] - cum[i - 1]
			local t = seg > 0 and (s - cum[i - 1]) / seg or 0
			return pts[i - 1]:Lerp(pts[i], t)
		end
	end
	return pts[#pts]:Clone()
end

local function lane_project(lane, pos)
	local px, py = pos:GetX(), pos:GetY()
	local pts, cum = lane.pts, lane.cum
	local best_s, best_d = 0.0, math.huge
	for i = 2, #pts do
		local ax, ay = pts[i - 1]:GetX(), pts[i - 1]:GetY()
		local dx, dy = pts[i]:GetX() - ax, pts[i]:GetY() - ay
		local len2 = dx * dx + dy * dy
		local t = 0.0
		if len2 > 0 then
			t = ((px - ax) * dx + (py - ay) * dy) / len2
			if t < 0 then t = 0.0 elseif t > 1 then t = 1.0 end
		end
		local cx, cy = ax + dx * t, ay + dy * t
		local d = (px - cx) * (px - cx) + (py - cy) * (py - cy)
		if d < best_d then
			best_d = d
			best_s = cum[i - 1] + (cum[i] - cum[i - 1]) * t
		end
	end
	return best_s, math.sqrt(best_d)
end

local function load_structures()
	for name, p in pairs(STRUCTURES) do
		struct_pos[name] = Vector(p[1], p[2], p[3])
	end
	struct_version = struct_version + 1
end

local function remember_structure(ent)
	if not Entity.IsAlive(ent) then return end
	local name = NPC.GetUnitName(ent)
	if not name then return end
	if not (name:find("_tower%d_") or name:find("_rax_")) then return end
	local pos = Entity.GetAbsOrigin(ent)
	local known = struct_pos[name]
	if known and known:Distance2D(pos) < K.STRUCT_MOVE_EPS then return end
	struct_pos[name] = pos:Clone()
	struct_version = struct_version + 1
end

local function scan_structures()
	local towers = Towers.GetAll()
	if towers then
		for i = 1, #towers do remember_structure(towers[i]) end
	end
	local raxes = NPCs.GetAll(UT.TYPE_BARRACKS)
	if raxes then
		for i = 1, #raxes do remember_structure(raxes[i]) end
	end
end

local function tower_at(tier, side, lane)
	return struct_pos[string.format("npc_dota_%s_tower%d_%s", side, tier, lane)]
end

local function rax_at(side, lane)
	local melee = struct_pos[string.format("npc_dota_%s_melee_rax_%s", side, lane)]
	local range = struct_pos[string.format("npc_dota_%s_range_rax_%s", side, lane)]
	if melee and range then return melee:Lerp(range, 0.5) end
	return melee or range
end

local function lane_corner(ours, theirs)
	local a = Vector(ours:GetX(), theirs:GetY(), ours:GetZ())
	local b = Vector(theirs:GetX(), ours:GetY(), ours:GetZ())
	local corner = a:Length2D() > b:Length2D() and a or b
	if corner:Length2D() <= math.max(ours:Length2D(), theirs:Length2D()) then return nil end
	corner:SetGroundZ()
	return corner
end

local function lane_samples(pts)
	local samples = {}
	for i = 2, #pts do
		local a, b = pts[i - 1], pts[i]
		local n = math.max(1, math.ceil(a:Distance2D(b) / 250.0))
		local first = i == 2 and 0 or 1
		for k = first, n do
			local p = a:Lerp(b, k / n)
			p:SetGroundZ()
			samples[#samples + 1] = p
		end
	end
	return samples
end

local function build_lanes(my_radiant)
	local us = my_radiant and "goodguys" or "badguys"
	local them = my_radiant and "badguys" or "goodguys"
	local result = {}
	for _, name in ipairs(LANE_NAMES) do
		local pts = {}
		local function push(p)
			if not p then return end
			local last = pts[#pts]
			if last and last:Distance2D(p) < 50.0 then return end
			pts[#pts + 1] = p:Clone()
		end
		local our_t1 = tower_at(1, us, name)
		local their_t1 = tower_at(1, them, name)
		push(rax_at(us, name))
		push(tower_at(3, us, name))
		push(tower_at(2, us, name))
		push(our_t1)
		if name ~= "mid" and our_t1 and their_t1 then
			push(lane_corner(our_t1, their_t1))
		end
		push(their_t1)
		push(tower_at(2, them, name))
		push(tower_at(3, them, name))
		push(rax_at(them, name))
		if #pts >= 2 then
			local cum = { 0.0 }
			for i = 2, #pts do
				cum[i] = cum[i - 1] + pts[i - 1]:Distance2D(pts[i])
			end
			result[#result + 1] = {
				name = name,
				pts = pts,
				cum = cum,
				len = cum[#pts],
				samples = lane_samples(pts),
			}
		end
	end
	return result
end

local function ensure_lanes(now, my_radiant)
	if now >= next_struct_scan then
		next_struct_scan = now + K.STRUCT_SCAN
		scan_structures()
	end
	if lanes and lanes_version == struct_version and lanes_radiant == my_radiant then return end
	lanes = build_lanes(my_radiant)
	lanes_version = struct_version
	lanes_radiant = my_radiant
end

local function collect(my_team)
	enemy_now, enemy_by_idx, allied_now = {}, {}, {}
	local list = NPCs.GetAll(UT.TYPE_LANE_CREEP)
	if list then
		for i = 1, #list do
			local n = list[i]
			if NPC.IsLaneCreep(n)
				and Entity.IsAlive(n)
				and not Entity.IsDormant(n)
				and not NPC.IsWaitingToSpawn(n) then
				local entry = { ent = n, idx = Entity.GetIndex(n), pos = Entity.GetAbsOrigin(n) }
				if Entity.GetTeamNum(n) == my_team then
					allied_now[#allied_now + 1] = entry
				else
					enemy_now[#enemy_now + 1] = entry
					enemy_by_idx[entry.idx] = entry
				end
			end
		end
	end

	danger_towers = {}
	local towers = Towers.GetAll()
	if towers then
		for i = 1, #towers do
			local t = towers[i]
			if Entity.IsAlive(t) and Entity.GetTeamNum(t) ~= my_team then
				danger_towers[#danger_towers + 1] = {
					ent = t,
					pos = Entity.GetAbsOrigin(t),
					r = (NPC.GetAttackRange(t) or 700.0) + K.TOWER_MARGIN,
				}
			end
		end
	end
end

local function refresh_world(hero, now)
	local my_team = Entity.GetTeamNum(hero)
	collect(my_team)
	ensure_lanes(now, my_team == RADIANT)
	return my_team
end

local function sample_speed(now)
	if now < next_speed_sample then return end
	next_speed_sample = now + K.SPEED_SAMPLE
	local samples = {}
	local seen = {}
	for i = 1, #allied_now do
		local e = allied_now[i]
		local x, y = e.pos:GetX(), e.pos:GetY()
		seen[e.idx] = true
		local prev = speed_track[e.idx]
		if prev and not NPC.IsAttacking(e.ent) then
			local dt = now - prev.t
			if dt > 0.2 then
				local v = math.sqrt((x - prev.x) * (x - prev.x) + (y - prev.y) * (y - prev.y)) / dt
				if v >= K.SPEED_MIN and v <= K.SPEED_MAX then
					samples[#samples + 1] = v
				end
			end
		end
		speed_track[e.idx] = { x = x, y = y, t = now }
	end
	for idx in pairs(speed_track) do
		if not seen[idx] then speed_track[idx] = nil end
	end
	if #samples >= 3 then
		table.sort(samples)
		local pick = samples[math.max(1, math.ceil(#samples * 0.75))]
		creep_speed = creep_speed + (pick - creep_speed) * K.SPEED_ALPHA
	end
end

local function nearest(list, pos)
	local best, best_d = nil, math.huge
	for i = 1, #list do
		local d = list[i].pos:Distance2D(pos)
		if d < best_d then best, best_d = list[i], d end
	end
	return best, best_d
end

local function enemy_near(pos, radius)
	for i = 1, #enemy_now do
		if enemy_now[i].pos:Distance2D(pos) <= radius then return true end
	end
	return false
end

local function allied_near(pos, radius)
	for i = 1, #allied_now do
		if allied_now[i].pos:Distance2D(pos) <= radius then return true end
	end
	return false
end

local function in_danger(pt)
	for i = 1, #danger_towers do
		local t = danger_towers[i]
		if pt:Distance2D(t.pos) < t.r then return true end
	end
	return false
end

local function safe_point(pt)
	if job and job.dive then return pt end
	local p = pt
	for _ = 1, 2 do
		local moved = false
		for i = 1, #danger_towers do
			local t = danger_towers[i]
			local d = p:Distance2D(t.pos)
			if d < t.r and d > 1.0 then
				p = t.pos:Extend2D(p, t.r)
				moved = true
			end
		end
		if not moved then break end
	end
	return p
end

local function first_entry(fx, fy, dx, dy, circles, first, hit)
	local a = dx * dx + dy * dy
	for i = 1, #circles do
		local t = circles[i]
		local ox, oy = fx - t.pos:GetX(), fy - t.pos:GetY()
		local c = ox * ox + oy * oy - t.r * t.r
		if c > 0 then
			local b = 2 * (ox * dx + oy * dy)
			local disc = b * b - 4 * a * c
			if disc >= 0 then
				local enter = (-b - math.sqrt(disc)) / (2 * a)
				if enter >= 0 and enter <= 1 and (not first or enter < first) then
					first, hit = enter, t
				end
			end
		end
	end
	return first, hit
end

local function walkable_near(pt, center)
	if walkable(pt) then return pt end
	local cx, cy = center:GetX(), center:GetY()
	local dx, dy = pt:GetX() - cx, pt:GetY() - cy
	for i = 1, #ROTATIONS do
		local a = math.rad(ROTATIONS[i])
		local c, s = math.cos(a), math.sin(a)
		local candidate = Vector(cx + dx * c - dy * s, cy + dx * s + dy * c, pt:GetZ())
		if walkable(candidate) then return candidate end
	end
	return pt
end

local function route(from, to, use_towers, use_allies)
	local fx, fy = from:GetX(), from:GetY()
	local dx, dy = to:GetX() - fx, to:GetY() - fy
	local len2 = dx * dx + dy * dy
	if len2 < 1.0 then return to end
	local enter, t = nil, nil
	if use_towers then enter, t = first_entry(fx, fy, dx, dy, danger_towers, enter, t) end
	if use_allies then enter, t = first_entry(fx, fy, dx, dy, ally_zones, enter, t) end
	if not enter then return to end

	if t.pos:Distance2D(to) < t.r then
		if t.ally then return to end
		local k = math.max(0.0, enter - K.CLIP_MARGIN / math.sqrt(len2))
		return Vector(fx + dx * k, fy + dy * k, to:GetZ())
	end

	local cx, cy = t.pos:GetX(), t.pos:GetY()
	local k = ((cx - fx) * dx + (cy - fy) * dy) / len2
	k = math.max(0.0, math.min(1.0, k))
	local nx, ny = fx + dx * k - cx, fy + dy * k - cy
	local nl = math.sqrt(nx * nx + ny * ny)
	if nl < 1.0 then
		nx, ny, nl = -dy, dx, math.sqrt(len2)
	end
	local rad = t.r + K.DETOUR_MARGIN
	local waypoint = Vector(cx + nx / nl * rad, cy + ny / nl * rad, to:GetZ())
	return walkable_near(waypoint, t.pos)
end

local function behind_point(ref, hero_pos)
	local d = ref:Distance2D(hero_pos)
	if d < 1.0 then return hero_pos:Clone() end
	return ref:Extend2D(hero_pos, d + K.BEHIND)
end

local function nearest_lane(pos, limit)
	if not lanes then return nil end
	local best, best_d = nil, limit
	for i = 1, #lanes do
		local _, perp = lane_project(lanes[i], pos)
		if perp < best_d then best, best_d = lanes[i], perp end
	end
	return best
end

local function cluster_waves(list)
	local waves = {}
	local used = {}
	for i = 1, #list do
		if not used[i] then
			used[i] = true
			local members = { list[i] }
			local k = 1
			while k <= #members do
				local p = members[k].pos
				for j = 1, #list do
					if not used[j] and list[j].pos:Distance2D(p) <= K.WAVE_LINK then
						used[j] = true
						members[#members + 1] = list[j]
					end
				end
				k = k + 1
			end
			waves[#waves + 1] = members
		end
	end
	return waves
end

local function wave_center(members)
	local sx, sy, sz = 0.0, 0.0, 0.0
	for i = 1, #members do
		local p = members[i].pos
		sx, sy, sz = sx + p:GetX(), sy + p:GetY(), sz + p:GetZ()
	end
	local n = #members
	return Vector(sx / n, sy / n, sz / n)
end

local function wave_engaged(members)
	for i = 1, #members do
		if allied_near(members[i].pos, K.ENGAGE_RADIUS) then return true end
	end
	return false
end

local function track_wave(members, now)
	local w = { members = {}, last = {}, vel = {}, vx = 0.0, vy = 0.0, seen_at = now, last_t = now }
	for i = 1, #members do
		local m = members[i]
		w.members[m.idx] = now
		w.last[m.idx] = { x = m.pos:GetX(), y = m.pos:GetY() }
	end
	return w
end

local function refresh_wave(w, now)
	local visible = {}
	local dt = now - w.last_t
	local sx, sy, n = 0.0, 0.0, 0
	for idx, seen in pairs(w.members) do
		local e = enemy_by_idx[idx]
		if e then
			visible[#visible + 1] = e
			w.members[idx] = now
			local x, y = e.pos:GetX(), e.pos:GetY()
			local prev = w.last[idx]
			if prev and dt > 0.01 then
				local mx, my = (x - prev.x) / dt, (y - prev.y) / dt
				sx, sy, n = sx + mx, sy + my, n + 1
				local v = w.vel[idx]
				if v then
					v.x = v.x + (mx - v.x) * 0.5
					v.y = v.y + (my - v.y) * 0.5
				else
					w.vel[idx] = { x = mx, y = my }
				end
			end
			w.last[idx] = { x = x, y = y }
		elseif now - seen > K.MEMBER_FORGET then
			w.members[idx] = nil
			w.last[idx] = nil
			w.vel[idx] = nil
		else
			w.last[idx] = nil
			w.vel[idx] = nil
		end
	end

	if #visible > 0 then
		for i = 1, #enemy_now do
			local e = enemy_now[i]
			if not w.members[e.idx] then
				for j = 1, #visible do
					if visible[j].pos:Distance2D(e.pos) <= K.WAVE_LINK then
						w.members[e.idx] = now
						w.last[e.idx] = { x = e.pos:GetX(), y = e.pos:GetY() }
						visible[#visible + 1] = e
						break
					end
				end
			end
		end
		w.seen_at = now
	end

	if n > 0 then
		w.vx = w.vx + (sx / n - w.vx) * 0.35
		w.vy = w.vy + (sy / n - w.vy) * 0.35
	end
	w.last_t = now
	return visible
end

local function lane_front(lane)
	local front, moving = 0.0, true
	for i = 1, #allied_now do
		local a = allied_now[i]
		local s, perp = lane_project(lane, a.pos)
		if perp <= K.LANE_BAND and s > front then
			front = s
			moving = not NPC.IsAttacking(a.ent)
		end
	end
	return front, moving
end

local function clock_text(t)
	return string.format("%d:%02d", math.floor(t / 60), math.floor(t % 60))
end

local function predict_batches(lane, min_t0)
	local front, moving = lane_front(lane)
	local clock = game_clock()
	local next_spawn = (math.floor(clock / K.SPAWN_PERIOD) + 1) * K.SPAWN_PERIOD
	local list = {}
	for j = 8, -K.FUTURE_BATCHES + 1, -1 do
		local t0 = next_spawn - K.SPAWN_PERIOD * j
		if t0 >= 0 and (not min_t0 or t0 >= min_t0) then
			local s = lane.len - creep_speed * (clock - t0)
			if s >= front + K.FRONT_BUFFER then
				local spawned = s < lane.len
				if spawned then
					while s < lane.len do
						local p = lane_point(lane, s)
						if not point_visible(p) or enemy_near(p, K.FOG_CHECK_RADIUS) then break end
						s = s + K.FOG_STEP
					end
				end
				if not spawned or s < lane.len then
					local lo
					if moving and spawned then
						lo = front + (s - front) * 0.5 + K.CLASH_GAP * 0.5
					else
						lo = front + K.CLASH_GAP
					end
					list[#list + 1] = { t0 = t0, s = s, lo = math.max(lo, 0.0) }
				end
			end
		end
	end
	return list
end

local function reachable(lane, s, s_pred, from, from_speed)
	local pt = lane_point(lane, s)
	local t_puller = from:Distance2D(pt) * K.PATH_FACTOR / from_speed
	local t_wave = (s_pred - s) / creep_speed
	return t_puller + K.ARRIVE_SLACK <= t_wave, pt, t_wave
end

local function meet_score(lane, s, s_pred, from, from_speed, hero_pos)
	local ok, pt, t_wave = reachable(lane, s, s_pred, from, from_speed)
	if not ok or in_danger(pt) then return nil end
	return pt:Distance2D(hero_pos) + t_wave * K.WAIT_WEIGHT
end

local function plan_meet(lane, from, from_speed, hero_pos, min_t0, keep_t0, keep_s, keep_dive, dive)
	local batches = predict_batches(lane, min_t0)
	if #batches == 0 then return nil end

	if keep_t0 and keep_s then
		for i = 1, #batches do
			local b = batches[i]
			if b.t0 == keep_t0 and keep_s >= b.lo and keep_s <= b.s then
				if keep_dive then
					if reachable(lane, keep_s, b.s, from, from_speed) then return b.t0, b.s, keep_s, true end
				elseif meet_score(lane, keep_s, b.s, from, from_speed, hero_pos) then
					return b.t0, b.s, keep_s, false
				end
			end
		end
	end

	local best_b, best_s, best_score = nil, nil, math.huge
	for i = 1, #batches do
		local b = batches[i]
		local s = math.min(b.s, lane.len)
		while s >= b.lo do
			local score = meet_score(lane, s, b.s, from, from_speed, hero_pos)
			if score and score < best_score then best_b, best_s, best_score = b, s, score end
			s = s - K.SEARCH_STEP
		end
	end
	if best_b then return best_b.t0, best_b.s, best_s, false end

	if dive then
		for i = 1, #batches do
			local b = batches[i]
			local s = b.lo
			local top = math.min(b.s, lane.len)
			while s <= top do
				if reachable(lane, s, b.s, from, from_speed) then return b.t0, b.s, s, true end
				s = s + K.SEARCH_STEP
			end
		end
	end

	local b = batches[1]
	return b.t0, b.s, math.min(b.lo, b.s, lane.len), false
end

local function hook_point(front, hero_pos, w, from, from_speed)
	local offset = math.min(K.HOOK_OFFSET, front:Distance2D(hero_pos) * 0.5)
	local base = offset > 1.0 and front:Extend2D(hero_pos, offset) or front:Clone()
	local bx, by = base:GetX(), base:GetY()
	local px, py = from:GetX(), from:GetY()
	local tx, ty = bx, by
	for _ = 1, 2 do
		local dist = math.sqrt((tx - px) * (tx - px) + (ty - py) * (ty - py))
		local t = math.min(dist / from_speed, K.INTERCEPT_MAX_T)
		tx, ty = bx + w.vx * t, by + w.vy * t
	end
	local target = Vector(tx, ty, base:GetZ())
	local center = Vector(front:GetX() + (tx - bx), front:GetY() + (ty - by), front:GetZ())
	return safe_point(walkable_near(target, center))
end

local function detect_wave(lane, anchors)
	local waves = cluster_waves(enemy_now)
	local best, best_d = nil, K.SEARCH_DETECT
	for i = 1, #waves do
		local members = waves[i]
		local on_lane = true
		if lane then
			local _, perp = lane_project(lane, wave_center(members))
			on_lane = perp <= K.LANE_BAND
		end
		if on_lane and not wave_engaged(members) then
			for j = 1, #anchors do
				local _, d = nearest(members, anchors[j])
				if d < best_d then best, best_d = members, d end
			end
		end
	end
	return best
end

local function unit_kind(u)
	local name = NPC.GetUnitName(u) or ""
	for i = 1, #UNIT_KINDS do
		local kind = UNIT_KINDS[i]
		for j = 1, #kind.patterns do
			if name:find(kind.patterns[j]) then return kind end
		end
	end
	return nil
end

local function free_pathing(u)
	for i = 1, #FREE_PATHING_STATES do
		if NPC.HasState(u, FREE_PATHING_STATES[i]) then return true end
	end
	local kind = unit_kind(u)
	return kind ~= nil and kind.guide == true
end

local function puller_kind(u, my_id, hero)
	if u == hero then return nil end
	if not Entity.IsAlive(u) or Entity.IsDormant(u) then return nil end
	if NPC.IsWaitingToSpawn(u) then return nil end
	if not Entity.IsControllableByPlayer(u, my_id) then return nil end
	if NPC.IsIllusion(u) or NPC.IsLaneCreep(u) then return nil end
	if NPC.IsCourier(u) or NPC.IsWard(u) or NPC.IsStructure(u) then return nil end
	local kind = unit_kind(u)
	if kind and ui.units:Get(kind.id) then return kind.id end
	return nil
end

local function spirit_bear(hero)
	if not CustomEntities or not CustomEntities.GetSpiritBear then return nil end
	local ability = NPC.GetAbility(hero, "lone_druid_spirit_bear")
	return ability and CustomEntities.GetSpiritBear(ability) or nil
end

local function life_left(u, now)
	local timer = NPC.GetModifier(u, "modifier_kill")
	if not timer then return math.huge end
	local die = Modifier.GetDieTime(timer) or 0
	if die <= 0 then return math.huge end
	return die - now
end

local function better_puller(a, b)
	if not b then return true end
	if a.rank ~= b.rank then return a.rank < b.rank end
	if math.abs(a.life - b.life) > K.LIFE_EPS then return a.life > b.life end
	if a.hp ~= b.hp then return a.hp > b.hp end
	return a.d < b.d
end

local function pick_puller(my_id, hero, anchor)
	local list = NPCs.GetAll() or {}
	local bear = spirit_bear(hero)
	if bear then list[#list + 1] = bear end

	local ranks = {}
	local enabled = ui.units:ListEnabled()
	for i = 1, #enabled do ranks[enabled[i]] = i end

	local now = GameRules.GetGameTime()
	local min_hp = ui.abort_hp:Get() + 5
	local seen = {}
	local best = nil
	for i = 1, #list do
		local u = list[i]
		local idx = Entity.GetIndex(u)
		if not seen[idx] then
			seen[idx] = true
			local kind = puller_kind(u, my_id, hero)
			if kind then
				local hp = Entity.GetHealth(u) or 0
				local max_hp = Entity.GetMaxHealth(u) or 0
				local pct = max_hp > 0 and (hp / max_hp * 100.0) or 0
				if pct >= min_hp then
					local entry = {
						unit = u,
						rank = ranks[kind] or math.huge,
						life = life_left(u, now),
						hp = hp,
						d = Entity.GetAbsOrigin(u):Distance2D(anchor),
					}
					if better_puller(entry, best) then best = entry end
				end
			end
		end
	end
	return best and best.unit or nil
end

local function dist_xy(ax, ay, bx, by)
	local dx, dy = ax - bx, ay - by
	return math.sqrt(dx * dx + dy * dy)
end

local function guide_point(from, goal, now)
	local g = job.guide
	if not g or g.goal:Distance2D(goal) > K.GUIDE_REPLAN_DIST or now - g.t > K.GUIDE_REPLAN_TIME then
		g = { goal = goal:Clone(), path = GridNav.BuildPath(from, goal, false) or {}, i = 1, t = now }
		job.guide = g
	end
	local path = g.path
	if #path == 0 then return goal end
	while g.i <= #path and from:Distance2D(path[g.i]) < K.GUIDE_REACH do
		g.i = g.i + 1
	end
	if g.i > #path then return goal end
	local j = g.i
	while j < #path
		and from:Distance2D(path[j + 1]) < K.GUIDE_LOOKAHEAD
		and GridNav.IsTraversableFromTo(from, path[j + 1], false) do
		j = j + 1
	end
	return path[j]
end

local function issue(kind, pos, target, no_settle, no_route)
	local u = job.unit
	if orders_blocked(u) then return end
	local now = GameRules.GetGameTime()
	local u_pos = Entity.GetAbsOrigin(u)
	local ux, uy = u_pos:GetX(), u_pos:GetY()
	local prev = job.order
	local goal = nil

	if kind == "move" or kind == "attack_move" then
		if move_blocked(u) then return end
		if not no_route then
			pos = route(u_pos, pos, not job.dive, job.state == "lead")
		end
	end
	if kind == "move" then
		local gx, gy = pos:GetX(), pos:GetY()
		local dist = dist_xy(ux, uy, gx, gy)
		local tolerance = math.max(K.POS_EPS, dist * K.POS_TOLERANCE)
		local stopped_short = not no_settle and prev and prev.kind == "move"
			and dist_xy(prev.gx, prev.gy, gx, gy) <= tolerance
			and not NPC.IsRunning(u)
			and now - prev.t > K.ARRIVE_IDLE
		local still_held = not no_settle and prev and prev.kind == "hold" and prev.gx
			and dist_xy(prev.gx, prev.gy, gx, gy) <= K.HOLD_RELEASE
		if dist <= K.ARRIVE_EPS or stopped_short or still_held then
			goal = pos
			kind, pos = "hold", nil
		end
	end

	local tidx = target and Entity.GetIndex(target) or nil
	if prev and prev.kind == kind and prev.target == tidx then
		if kind == "hold" then
			if dist_xy(ux, uy, prev.x, prev.y) <= K.HOLD_DRIFT then return end
		elseif kind == "attack" then
			if NPC.IsAttacking(u) or NPC.IsRunning(u) or now - prev.t < K.ATTACK_IDLE then return end
		else
			local gx, gy = pos:GetX(), pos:GetY()
			local dist = dist_xy(ux, uy, gx, gy)
			if dist_xy(prev.gx, prev.gy, gx, gy) <= math.max(K.POS_EPS, dist * K.POS_TOLERANCE) then
				if dist < prev.best - K.PROGRESS_EPS then
					prev.best = dist
					prev.progress_t = now
				end
				local busy = NPC.IsRunning(u) or NPC.IsAttacking(u)
				if busy and now - prev.progress_t < K.PROGRESS_TIMEOUT then return end
				if not busy and now - prev.t < K.ARRIVE_IDLE then return end
			end
		end
	end
	if not can_issue() then return end

	local player = Players.GetLocal()
	if not player then return end
	local at = pos or u_pos
	Player.PrepareUnitOrders(
		player, ORDER_KIND[kind], target, at, nil, ISSUER_UNIT, u,
		false, false, true, false, ORDER_ID
	)

	local anchor = goal or pos
	job.order = {
		kind = kind,
		x = at:GetX(),
		y = at:GetY(),
		gx = anchor and anchor:GetX() or nil,
		gy = anchor and anchor:GetY() or nil,
		target = tidx,
		t = now,
		best = pos and u_pos:Distance2D(pos) or 0.0,
		progress_t = now,
	}
end

local function set_state(state, reason)
	job.state = state
	job.since = GameRules.GetGameTime()
	job.contact_since = nil
	job.waiting = false
	job.lost_since = nil
	job.pace_t = nil
	job.hook_idx = nil
	job.lead_best = nil
	job.lead_t = nil
	job.guide = nil
	job.info.gap = nil
	if state == "lead" then
		job.led = true
		job.follow = {}
	end
	if reason then note(state .. ": " .. reason) end
end

local function finish(reason)
	if reason then note("done: " .. reason) end
	job = nil
end

local function abort(reason)
	set_state("return", reason)
end

local function rehook(reason, visible)
	if wave_engaged(visible) then
		return abort("the wave ran into our creeps")
	end
	job.retries = job.retries + 1
	if job.retries > K.MAX_RETRIES then
		return abort(reason)
	end
	set_state("hook", reason)
end

local function hooked()
	return job.hit_at >= job.since
end

local function wave_busy()
	if job.lane and not job.led then
		job.wave = nil
		job.info.front = nil
		job.batch = nil
		job.meet_s = nil
		job.missed = job.missed + 1
		if job.missed > K.MAX_MISSED then return abort("the wave ran into our creeps") end
		return set_state("search", "the wave's busy with our creeps, waiting for the next one")
	end
	abort("the wave ran into our creeps")
end

local function wave_lost(now)
	if now - job.wave.seen_at <= K.WAVE_LOST_TIME then return end
	if job.lane then
		job.wave = nil
		set_state("search", "lost sight of the wave")
	else
		abort("lost sight of the wave")
	end
end

local function outside_towers(list)
	if job.dive then return list end
	local out = {}
	for i = 1, #list do
		if not in_danger(list[i].pos) then out[#out + 1] = list[i] end
	end
	return out
end

local function step_hook(ctx)
	local now = ctx.now
	local visible = refresh_wave(job.wave, now)
	if #visible == 0 then return wave_lost(now) end
	if hooked() then return set_state("lead", "got the wave's attention") end
	if wave_engaged(visible) then return wave_busy() end

	local safe = outside_towers(visible)
	if #safe == 0 then return set_state("approach", nil) end

	local close = nil
	for i = 1, #safe do
		if safe[i].idx == job.hook_idx then close = safe[i] break end
	end
	if not close then
		close = nearest(safe, ctx.u_pos)
		job.hook_idx = close.idx
	end
	local close_d = close.pos:Distance2D(ctx.u_pos)
	job.info.front = close.pos
	if close_d <= K.CONTACT_RANGE then
		job.contact_since = job.contact_since or now
		if now - job.contact_since >= K.CONTACT_TIME then
			return set_state("lead", "bumped right into the wave")
		end
	else
		job.contact_since = nil
	end
	if now - job.since > K.HOOK_TIMEOUT then return rehook("couldn't hook the wave", visible) end

	job.info.target = close.pos
	issue("attack", nil, close.ent)
end

local function step_approach(ctx)
	local now = ctx.now
	local w = job.wave
	local visible = refresh_wave(w, now)
	if #visible == 0 then return wave_lost(now) end

	local front = nearest(visible, ctx.hero_pos)
	job.info.front = front.pos
	if front.pos:Distance2D(ctx.hero_pos) <= K.MIN_PULL_DIST then
		return set_state("deliver", "the wave's already at you")
	end
	if hooked() then return set_state("lead", "picked up aggro on the way") end
	if wave_engaged(visible) then return wave_busy() end

	local _, close_d = nearest(outside_towers(visible), ctx.u_pos)
	if close_d <= K.HOOK_ENGAGE then
		set_state("hook", nil)
		return step_hook(ctx)
	end

	local target = hook_point(front.pos, ctx.hero_pos, w, ctx.u_pos, ctx.u_speed)
	job.info.target = target
	issue("move", target)
end

local function hide_blocked(p)
	for i = 1, #job.hide_bad do
		if job.hide_bad[i]:Distance2D(p) < K.HIDE_BAD_RADIUS then return true end
	end
	return false
end

local function find_hideout(lane, meet, hero_pos)
	local hx, hy = hero_pos:GetX() - meet:GetX(), hero_pos:GetY() - meet:GetY()
	local hl = math.sqrt(hx * hx + hy * hy)
	if hl < 1.0 then hx, hy, hl = 1.0, 0.0, 1.0 end
	local best, best_score = nil, -math.huge
	for i = 1, #K.HIDE_RADII do
		local r = K.HIDE_RADII[i]
		for a = 0, 330, 30 do
			local rad = math.rad(a)
			local cx, cy = math.cos(rad), math.sin(rad)
			local p = Vector(meet:GetX() + cx * r, meet:GetY() + cy * r, meet:GetZ())
			if walkable(p) and not in_danger(p) and not hide_blocked(p) then
				local trees = Trees.InRadius(p, K.HIDE_TREE_RADIUS, true)
				local n = trees and #trees or 0
				local _, perp = lane_project(lane, p)
				if n >= K.HIDE_MIN_TREES and perp >= K.HIDE_LANE_DIST then
					local side = (cx * hx + cy * hy) / hl
					local score = n * 10.0 + side * 60.0 - r * 0.1
					if score > best_score then best, best_score = p, score end
				end
			end
		end
	end
	return best
end

local function hide_target(ctx, lane, meet, meet_s, s_pred)
	if not ui.hide:Get() or job.dive then return nil end
	if not job.hide or math.abs(job.hide.s - meet_s) > K.HIDE_RECALC then
		job.hide = { s = meet_s, pos = find_hideout(lane, meet, ctx.hero_pos) }
		job.leaving = false
		job.seen_since = nil
	end
	local spot = job.hide.pos
	if not spot or job.leaving then return nil end

	local t_wave = (s_pred - meet_s) / creep_speed
	local t_run = spot:Distance2D(meet) * K.PATH_FACTOR / ctx.u_speed
	if t_wave - t_run <= K.LEAVE_MARGIN then
		job.leaving = true
		note("coming out of the trees for the " .. clock_text(job.batch) .. " wave")
		return nil
	end

	if ctx.u_pos:Distance2D(spot) <= K.ARRIVE_EPS * 2 and NPC.IsVisibleToEnemies(job.unit) then
		job.seen_since = job.seen_since or ctx.now
		if ctx.now - job.seen_since > K.HIDE_SEEN_TIME then
			job.hide_bad[#job.hide_bad + 1] = spot
			job.hide = nil
			job.seen_since = nil
			return nil
		end
	else
		job.seen_since = nil
	end
	return spot
end

local function step_search(ctx)
	local now = ctx.now
	local lane = job.lane
	local target, meet, batch
	if lane then
		local t0, s_pred, meet_s, dove = plan_meet(lane, ctx.u_pos, ctx.u_speed, ctx.hero_pos,
			job.min_t0, job.batch, job.meet_s, job.dive, ui.dive:Get())
		if not t0 then return abort("no wave anywhere") end
		if job.batch and t0 ~= job.batch then
			if t0 > job.batch then
				job.missed = job.missed + 1
				if job.missed > K.MAX_MISSED then return abort("the wave never showed up") end
				job.min_t0 = math.max(job.min_t0 or 0, job.batch + K.SPAWN_PERIOD)
				note("the " .. clock_text(job.batch) .. " wave slipped away, waiting for " .. clock_text(t0))
			end
		end
		if t0 ~= job.batch then
			job.hide = nil
		end
		job.batch = t0
		job.meet_s = meet_s
		batch = t0
		job.dive = dove
		if dove and not job.info.dive_noted then
			job.info.dive_noted = true
			note("no safe spot, running under the tower for the " .. clock_text(t0) .. " wave")
		end
		meet = lane_point(lane, meet_s)
		job.info.pred = lane_point(lane, s_pred)
		job.info.meet = meet
		job.info.batch = t0
		target = hide_target(ctx, lane, meet, meet_s, s_pred) or meet
		job.info.hidden = target ~= meet
	else
		meet = job.cursor
		target = job.cursor
	end

	local found = detect_wave(lane, { ctx.u_pos, meet })
	if found then
		job.wave = track_wave(found, now)
		job.info.pred = nil
		job.info.meet = nil
		job.info.batch = nil
		job.started = now
		set_state("approach", "wave spotted")
		return step_approach(ctx)
	end

	if batch then
		local passed = lane.len - creep_speed * (game_clock() - batch)
		if passed < job.meet_s - creep_speed * K.MISS_GRACE then
			job.missed = job.missed + 1
			if job.missed > K.MAX_MISSED then return abort("the wave never showed up") end
			job.min_t0 = batch + K.SPAWN_PERIOD
			job.batch = nil
			job.meet_s = nil
			note("the " .. clock_text(batch) .. " wave never came, waiting for the next one")
			return
		end
	elseif now - job.since > K.SEARCH_MAX then
		return abort("the wave never showed up")
	end

	target = safe_point(target)
	job.info.target = target
	issue("move", target)
end

local function member_following(w, m, u_pos, d, attacking)
	if attacking or d <= K.FOLLOW_CONTACT then return true end
	local v = w.vel[m.idx]
	if not v then return true end
	local ux, uy = u_pos:GetX() - m.pos:GetX(), u_pos:GetY() - m.pos:GetY()
	local ul = math.sqrt(ux * ux + uy * uy)
	if ul < 1.0 then return true end
	return (v.x * ux + v.y * uy) / ul >= K.FOLLOW_SPEED
end

local function step_lead(ctx)
	local now = ctx.now
	local w = job.wave
	local visible = refresh_wave(w, now)
	local pack = {}
	for i = 1, #visible do
		if visible[i].pos:Distance2D(ctx.u_pos) <= K.PACK_RANGE then pack[#pack + 1] = visible[i] end
	end
	local chaser, gap = nearest(pack, ctx.u_pos)
	job.info.gap = chaser and gap or nil

	if not chaser or gap > K.LOST_GAP then
		job.lost_since = job.lost_since or now
		if now - job.lost_since > K.LOST_TIME then return rehook("the wave fell behind", visible) end
	else
		job.lost_since = nil
	end

	if not chaser then return issue("hold") end
	job.info.front = chaser.pos
	if chaser.pos:Distance2D(ctx.hero_pos) <= K.DELIVER_RADIUS then
		return set_state("deliver", "the wave's at you")
	end

	local follow = job.follow
	local tail_d = gap
	local straggler, straggler_d = nil, math.huge
	for i = 1, #pack do
		local m = pack[i]
		local d = m.pos:Distance2D(ctx.u_pos)
		local attacking = NPC.IsAttacking(m.ent) and d <= (NPC.GetAttackRange(m.ent) or 0) + K.RANGED_SLACK
		if attacking then job.shot_at = now end
		if not follow[m.idx] or member_following(w, m, ctx.u_pos, d, attacking) then
			follow[m.idx] = now
		end
		local stuck_for = now - follow[m.idx]
		if stuck_for > K.STRAGGLER_DROP
			or (stuck_for > K.STUCK_TIME and allied_near(m.pos, K.ENGAGE_RADIUS)) then
			w.members[m.idx] = nil
			follow[m.idx] = nil
			note("one creep got lost, bringing the rest")
		elseif stuck_for > K.STUCK_TIME then
			if d < straggler_d then straggler, straggler_d = m, d end
		elseif d > tail_d then
			tail_d = d
		end
	end

	if straggler then
		job.waiting = false
		job.lead_t = now
		job.info.target = straggler.pos
		return issue("attack", nil, straggler.ent)
	end

	local shooting = now - (job.shot_at or -100.0) < K.SHOT_MEMORY
	local gap_max = ui.gap:Get()
	local hg = ctx.u_pos:GetZ() - chaser.pos:GetZ() >= K.HG_DZ
		or ctx.hero_pos:GetZ() - chaser.pos:GetZ() >= K.HG_DZ
	if hg then gap_max = math.min(gap_max, K.HG_GAP) end
	local span = math.max(gap, tail_d - K.PACK_SPREAD)

	local resume = gap_max - math.min(K.GAP_HYST, gap_max * 0.4)
	local can_flip = now - (job.pace_t or -100.0) >= K.PACE_MIN
	if job.waiting then
		if can_flip and (span < resume or shooting) then
			job.waiting = false
			job.pace_t = now
		end
	elseif can_flip and span > gap_max and not shooting then
		job.waiting = true
		job.pace_t = now
	end

	if job.waiting then
		job.lead_t = now
		return issue("hold")
	end

	local d_hero = ctx.u_pos:Distance2D(ctx.hero_pos)
	if not job.lead_best or d_hero < job.lead_best - K.STALL_PROGRESS then
		job.lead_best = d_hero
		job.lead_t = now
	end
	local target = behind_point(chaser.pos, ctx.hero_pos)
	if not walkable(target) or now - (job.lead_t or now) > K.LEAD_STALL then
		target = ctx.hero_pos
	end
	target = safe_point(target)
	if job.guided then
		local detour = route(ctx.u_pos, target, not job.dive, true)
		target = guide_point(ctx.u_pos, detour, now)
		job.info.target = target
		return issue("move", target, nil, true, true)
	end
	job.info.target = target
	issue("move", target, nil, true)
end

local function step_deliver(ctx)
	local now = ctx.now
	local visible = refresh_wave(job.wave, now)
	local near = {}
	for i = 1, #visible do
		if visible[i].pos:Distance2D(ctx.hero_pos) <= K.DELIVER_DONE_RADIUS then
			near[#near + 1] = visible[i]
		end
	end
	if #near == 0 and now - job.since > 0.5 then return finish("the wave's dead") end
	if now - job.since > K.DELIVER_TIME then return finish("wave delivered") end

	local chaser = nearest(near, ctx.hero_pos)
	if ui.after:Get() == 1 and chaser then
		job.info.target = ctx.hero_pos
		return issue("attack_move", ctx.hero_pos)
	end

	local target = behind_point(chaser and chaser.pos or ctx.u_pos, ctx.hero_pos)
	job.info.target = target
	if ctx.u_pos:Distance2D(target) > K.ARRIVE_EPS then
		issue("move", target)
	else
		issue("hold")
	end
end

local function step_return(ctx)
	if ctx.u_pos:Distance2D(ctx.hero_pos) <= K.RETURN_DONE or ctx.now - job.since > K.RETURN_TIME then
		return finish(nil)
	end
	job.info.target = ctx.hero_pos
	issue("move", ctx.hero_pos)
end

local STEPS = {
	search = step_search,
	approach = step_approach,
	hook = step_hook,
	lead = step_lead,
	deliver = step_deliver,
	["return"] = step_return,
}

local function safety_reason(u, ctx)
	local max_hp = Entity.GetMaxHealth(u) or 0
	if max_hp > 0 and (Entity.GetHealth(u) or 0) / max_hp * 100.0 < ui.abort_hp:Get() then
		return "low HP"
	end
	if not job.dive then
		for i = 1, #danger_towers do
			local t = danger_towers[i]
			if t.pos:Distance2D(ctx.u_pos) <= t.r + K.TOWER_WATCH then
				local target = Tower.GetAttackTarget(t.ent)
				if target and Entity.GetIndex(target) == job.idx then
					return "the tower's hitting it"
				end
			end
		end
	end
	if ui.avoid:Get() then
		local near = Entity.GetHeroesInRadius(u, ui.avoid_radius:Get(), TEAM_ENEMY, true, true)
		if near and #near > 0 then return "enemy hero around" end
	end
	return nil
end

local function build_ally_zones()
	local zones = {}
	local groups = cluster_waves(allied_now)
	for i = 1, #groups do
		local members = groups[i]
		local center = wave_center(members)
		local spread = 0.0
		for j = 1, #members do
			local d = members[j].pos:Distance2D(center)
			if d > spread then spread = d end
		end
		zones[#zones + 1] = { pos = center, r = spread + K.ALLY_CLEAR, ally = true }
	end
	return zones
end

local function process()
	local hero = Heroes.GetLocal()
	if not hero then return end
	local now = GameRules.GetGameTime()
	refresh_world(hero, now)
	ally_zones = build_ally_zones()
	sample_speed(now)
	if not job then return end

	local u = job.unit
	if not NPCs.Contains(u) or not Entity.IsAlive(u) then return finish("your creep died") end
	if not Entity.IsAlive(hero) then return finish("you're dead") end

	local ctx = {
		now = now,
		hero_pos = Entity.GetAbsOrigin(hero),
		u_pos = Entity.GetAbsOrigin(u),
		u_speed = unit_speed(u),
	}

	local hp = Entity.GetHealth(u) or 0
	if job.last_hp and hp < job.last_hp - 1 and enemy_near(ctx.u_pos, K.MELEE_HIT_RADIUS) then
		job.hit_at = now
	end
	job.last_hp = hp
	job.guided = free_pathing(u)

	if ACTIVE[job.state] then
		if job.state ~= "search" and now - job.started > K.JOB_MAX then
			return abort("took way too long")
		end
		local why = safety_reason(u, ctx)
		if why then return abort(why) end
	end

	STEPS[job.state](ctx)
end

local function pick_by_distance(anchor, hero_pos, u_pos, u_speed)
	local best_d, chosen, chosen_lane = math.huge, nil, nil
	local waves = cluster_waves(enemy_now)
	for i = 1, #waves do
		local members = waves[i]
		if not wave_engaged(members) then
			local front = nearest(members, hero_pos)
			if front.pos:Distance2D(hero_pos) > K.MIN_PULL_DIST then
				local _, d = nearest(members, anchor)
				if d < best_d then best_d, chosen = d, members end
			end
		end
	end
	if lanes then
		for i = 1, #lanes do
			local lane = lanes[i]
			local t0, _, s = plan_meet(lane, u_pos, u_speed, hero_pos, nil, nil, nil, false, ui.dive:Get())
			if t0 then
				local d = lane_point(lane, s):Distance2D(anchor)
				if d < best_d then best_d, chosen, chosen_lane = d, nil, lane end
			end
		end
	end
	if chosen then
		return chosen, nearest_lane(wave_center(chosen), K.LANE_BAND)
	end
	return nil, chosen_lane
end

local function pick_by_cursor(cursor, hero_pos)
	local waves = cluster_waves(enemy_now)
	local near_cursor, best_d = nil, K.CURSOR_WAVE
	for i = 1, #waves do
		local _, d = nearest(waves[i], cursor)
		if d < best_d then near_cursor, best_d = waves[i], d end
	end
	local chosen = nil
	if near_cursor and not wave_engaged(near_cursor) then chosen = near_cursor end

	local lane = nil
	if lanes and #lanes > 0 then
		if near_cursor then
			lane = nearest_lane(wave_center(near_cursor), K.LANE_BAND)
		end
		lane = lane or nearest_lane(cursor, K.CURSOR_LANE) or nearest_lane(hero_pos, math.huge)
		if not chosen then
			local lane_best = math.huge
			for i = 1, #waves do
				local center = wave_center(waves[i])
				local _, perp = lane_project(lane, center)
				if perp <= K.LANE_BAND and not wave_engaged(waves[i]) then
					local d = center:Distance2D(cursor)
					if d < lane_best then chosen, lane_best = waves[i], d end
				end
			end
		end
	end
	return chosen, lane, near_cursor ~= nil and chosen == nil
end

local function start_pull()
	local hero = Heroes.GetLocal()
	local player = Players.GetLocal()
	if not hero or not player or not Entity.IsAlive(hero) then return end
	local my_id = Player.GetPlayerID(player)
	if my_id < 0 then return end

	local now = GameRules.GetGameTime()
	refresh_world(hero, now)
	local hero_pos = Entity.GetAbsOrigin(hero)
	local cursor = Input.GetWorldCursorPos()

	local unit = pick_puller(my_id, hero, hero_pos)
	if not unit then
		return note("nobody with enough HP to pull")
	end

	local chosen, lane, busy
	local mode = ui.pick:Get()
	if mode == 2 then
		chosen, lane, busy = pick_by_cursor(cursor, hero_pos)
	else
		local u_pos = Entity.GetAbsOrigin(unit)
		local anchor = mode == 1 and u_pos or hero_pos
		chosen, lane = pick_by_distance(anchor, hero_pos, u_pos, unit_speed(unit))
	end

	if chosen then
		local front = nearest(chosen, hero_pos)
		if front.pos:Distance2D(hero_pos) <= K.MIN_PULL_DIST then
			return note("the wave's already at you")
		end
	elseif not lane then
		return note(busy and "the wave's busy with our creeps" or "no wave anywhere")
	end

	job = {
		unit = unit,
		idx = Entity.GetIndex(unit),
		started = now,
		since = now,
		lane = lane,
		cursor = cursor,
		retries = 0,
		missed = busy and 1 or 0,
		hide_bad = {},
		hit_at = -100.0,
		last_hp = Entity.GetHealth(unit),
		info = {},
		order = nil,
	}

	if chosen then
		job.wave = track_wave(chosen, now)
		set_state("approach", "visible wave")
	elseif busy then
		set_state("search", "the wave by your cursor is busy with our creeps, waiting for the next one")
	else
		set_state("search", lane.name .. " lane")
	end
end

load_structures()

local script = {}

function script.OnUpdate()
	if not ui.enable:Get() then
		job = nil
		return
	end
	if not in_match() then return end

	if ui.key:IsPressed() and not (Input.IsInputCaptured and Input.IsInputCaptured()) then
		local t = GameRules.GetGameTime()
		if t - last_press > K.PRESS_DEBOUNCE then
			last_press = t
			if not job then
				start_pull()
			elseif job.state == "return" then
				finish("cancelled")
			else
				abort("cancelled with the key")
			end
		end
	end

	local now = GameRules.GetGameTime()
	if now < next_run then return end
	next_run = now + K.UPDATE_INTERVAL
	process()
end

function script.OnProjectile(data)
	if not job or not data or not data.isAttack then return end
	local target = data.target
	if not target or Entity.GetIndex(target) ~= job.idx then return end
	local source = data.source
	if source and NPC.IsLaneCreep(source) then
		job.hit_at = GameRules.GetGameTime()
	end
end

function script.OnPrepareUnitOrders(data)
	if not job or not data then return true end
	if data.identifier == ORDER_ID then return true end

	local player = Players.GetLocal()
	if not player or data.player ~= player then return true end

	local hero = Heroes.GetLocal()
	local involved, with_hero = false, false
	local function check(u)
		if not u then return end
		if Entity.GetIndex(u) == job.idx then involved = true end
		if hero and u == hero then with_hero = true end
	end

	check(data.npc)
	if data.orderIssuer == ISSUER_SELECTED then
		local selected = Player.GetSelectedUnits(player)
		if selected then
			for i = 1, #selected do check(selected[i]) end
		end
	end

	if involved then
		if with_hero then
			job.order = nil
		else
			finish("you took over")
		end
	end
	return true
end

local COLORS = {
	text = Color(235, 235, 235, 255),
	dim = Color(175, 175, 175, 220),
	lane = Color(255, 255, 255, 60),
	pred = Color(255, 165, 60, 255),
	meet = Color(255, 225, 90, 255),
	target = Color(110, 220, 140, 255),
	front = Color(240, 90, 80, 255),
}

local function draw_marker(pos, color, label)
	if not pos then return end
	local s, visible = Render.WorldToScreen(pos)
	if not visible then return end
	Render.Circle(s, 6, color, 2)
	Render.Text(debug_font, 13, label, Vec2(s.x + 9, s.y - 8), color)
end

local function draw_lane(lane)
	local samples = lane.samples
	local prev_s, prev_v = nil, false
	for i = 1, #samples do
		local s, v = Render.WorldToScreen(samples[i])
		if prev_s and v and prev_v then
			Render.Line(prev_s, s, COLORS.lane, 1.5)
		end
		prev_s, prev_v = s, v
	end
end

function script.OnDraw()
	if not ui.enable:Get() or not ui.debug:Get() then return end
	if not Engine.IsInGame() then return end

	if not debug_font then
		debug_font = Render.LoadFont("Verdana", Enum.FontCreate.FONTFLAG_ANTIALIAS, 500)
	end

	local clock = game_clock()
	local header = string.format("Lane Pull | %s | speed %.0f | spawn in %.0fs | lanes %d",
		job and job.state or "idle",
		creep_speed,
		K.SPAWN_PERIOD - (clock % K.SPAWN_PERIOD),
		lanes and #lanes or 0)
	Render.Text(debug_font, 15, header, Vec2(40, 280), COLORS.text)
	if last_msg and GameRules.GetGameTime() - last_msg_t < K.MSG_TIME then
		Render.Text(debug_font, 14, last_msg, Vec2(40, 300), COLORS.dim)
	end

	if lanes then
		for i = 1, #lanes do draw_lane(lanes[i]) end
	end

	if not job then return end
	local info = job.info
	draw_marker(info.pred, COLORS.pred, "spawn")
	draw_marker(info.meet, COLORS.meet, "meet")
	draw_marker(info.front, COLORS.front, "F")
	draw_marker(info.target, COLORS.target, job.state)

	if job.guide and job.state == "lead" then
		local path = job.guide.path
		local prev_s, prev_v = nil, false
		for i = 1, #path do
			local s, v = Render.WorldToScreen(path[i])
			if prev_s and v and prev_v then
				Render.Line(prev_s, s, COLORS.meet, 1.5)
			end
			prev_s, prev_v = s, v
		end
	end

	if NPCs.Contains(job.unit) then
		local s, visible = Render.WorldToScreen(Entity.GetAbsOrigin(job.unit))
		if visible then
			local text = job.state
			if job.state == "search" and info.batch then
				local left = info.batch - clock
				if left > 0 then
					text = text .. string.format(" | wave %s in %.0fs", clock_text(info.batch), left)
				else
					text = text .. " | wave " .. clock_text(info.batch)
				end
			end
			if job.dive then text = text .. " | dive" end
			if job.guided then text = text .. " | ground path" end
			if job.state == "search" and info.hidden then text = text .. " | hide" end
			if info.gap then text = text .. string.format(" | gap %.0f", info.gap) end
			if job.retries > 0 then text = text .. " | retry " .. job.retries end
			Render.Text(debug_font, 14, text, Vec2(s.x - 40, s.y - 50), COLORS.target)
		end
	end
end

function script.OnGameEnd()
	job = nil
	next_run = 0.0
	next_struct_scan = 0.0
	lanes = nil
	lanes_version = -1
	lanes_radiant = nil
	creep_speed = K.DEFAULT_CREEP_SPEED
	speed_track = {}
	next_speed_sample = 0.0
	enemy_now, enemy_by_idx, allied_now, danger_towers, ally_zones = {}, {}, {}, {}, {}
end

return script
