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
		lp_units_tip = "Tick who's allowed to pull. Order is priority,\nbut a healthy one always beats a hurt one",
		lp_hide = "Hide in the trees",
		lp_hide_tip = "Your creep chills in the trees till the wave shows up.\nIf enemies spot it, it finds another bush",
		lp_where = "Where to catch the wave",
		lp_wheres_edge = "In front of their tower",
		lp_wheres_behind = "Behind their tower",
		lp_wheres_near = "Close to me",
		lp_where_tip = "In front: waits for the wave to walk out of the tower\nBehind: sneaks past it, waits before the next one",
		lp_mid_side = "Mid river crossing",
		lp_mid_sides_auto = "Pick for me",
		lp_mid_sides_top = "Top",
		lp_mid_sides_bot = "Bottom",
		lp_mid_side_tip = "On mid your creep gets past their tier 1 by the river\nstairs and brings the pack back the same way",
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
		lp_avoid_tip = "Your creep walks around enemy heroes and only\ncalls off the pull if one gets right up close",
		lp_avoid_radius = "How wide to walk around",
		lp_debug = "Debug overlay",
		lp_debug_tip = "Shows lanes, wave guesses, what your creep\nis up to and dumps stuff into the log",
		lp_bind_name = "Lane Pull",
		lp_panel = "Show status bar",
		lp_panel_tip = "Little bar that tells you what your creep is doing,\nno debug lines needed",
		lp_panel_x = "Horizontal spot",
		lp_panel_y = "Distance from the top",
		lp_gear_extra = "Extra",
		lp_gear_panel = "Look",
		lp_gear_avoid = "Hero check",
		lp_panel_icon = "Icon",
		lp_icons_square = "Rounded square",
		lp_icons_round = "Circle",
		lp_icons_none = "No icon",
		lp_panel_scale = "Size",
		lp_panel_alpha = "How dark the background is",
		lp_panel_blur = "Blur behind it",
		lp_panel_match = "Only in a match",
		lp_panel_match_tip = "Hides the status bar outside a match.\nTurn it off to set it up from the main menu",
		lp_st_wait = "Waiting for the %s wave",
		lp_st_approach = "Heading to the wave",
		lp_st_hook = "Hooking the wave",
		lp_st_lead = "Bringing the pack",
		lp_st_deliver = "Pack's at you",
		lp_st_return = "Heading back",
		lp_st_done = "Done",
		lp_st_cancel = "Called off",
		lp_st_idle = "Ready",
		lp_st_creep1 = "creep",
		lp_st_creep2 = "creeps",
		lp_st_creep5 = "creeps",
		lp_lane_top = "top",
		lp_lane_mid = "mid",
		lp_lane_bot = "bot",
	},
	ru = {
		lp_group_main = "Основное",
		lp_group_way = "Поведение",
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
		lp_units_tip = "Отметь, кто может пулить. Порядок это приоритет,\nно здоровый крип всегда важнее раненого",
		lp_hide = "Прятаться в деревьях",
		lp_hide_tip = "Крип ждет волну в деревьях и выходит к ее приходу.\nЕсли враги его видят, он меняет укрытие",
		lp_where = "Где ловить волну",
		lp_wheres_edge = "Перед вышкой",
		lp_wheres_behind = "За вышкой",
		lp_wheres_near = "Поближе ко мне",
		lp_where_tip = "Перед вышкой: ждет, пока волна выйдет из-под нее\nЗа вышкой: обходит ее и ждет перед второй вышкой",
		lp_mid_side = "Переправа на миде",
		lp_mid_sides_auto = "Сам выбирает",
		lp_mid_sides_top = "Верхняя",
		lp_mid_sides_bot = "Нижняя",
		lp_mid_side_tip = "На миде крип обходит т1 по лестницам через реку\nи ведет пачку назад тем же путем",
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
		lp_avoid_tip = "Крип обходит вражеских героев стороной и бросает\nвыпул, только если герой подошел вплотную",
		lp_avoid_radius = "Радиус обхода героев",
		lp_debug = "Отладочный оверлей",
		lp_debug_tip = "Линии, прогноз волны, состояние крипа\nи сообщения в лог",
		lp_bind_name = "Выпул волны",
		lp_panel = "Показывать панель",
		lp_panel_tip = "Маленькая строка с тем, что сейчас делает крип,\nбез отладочных линий",
		lp_panel_x = "Положение по горизонтали",
		lp_panel_y = "Отступ сверху",
		lp_gear_extra = "Дополнительно",
		lp_gear_panel = "Оформление",
		lp_gear_avoid = "Проверка героев",
		lp_panel_icon = "Иконка",
		lp_icons_square = "Скругленный квадрат",
		lp_icons_round = "Круг",
		lp_icons_none = "Без иконки",
		lp_panel_scale = "Размер",
		lp_panel_alpha = "Плотность фона",
		lp_panel_blur = "Размытие фона",
		lp_panel_match = "Только в матче",
		lp_panel_match_tip = "Прячет строку статуса вне матча.\nВыключи, чтобы настроить ее из главного меню",
		lp_st_wait = "Жду волну %s",
		lp_st_approach = "Иду к волне",
		lp_st_hook = "Цепляю волну",
		lp_st_lead = "Веду пачку",
		lp_st_deliver = "Пачка у тебя",
		lp_st_return = "Возвращаюсь",
		lp_st_done = "Готово",
		lp_st_cancel = "Отменено",
		lp_st_idle = "Готов",
		lp_st_creep1 = "крип",
		lp_st_creep2 = "крипа",
		lp_st_creep5 = "крипов",
		lp_lane_top = "топ",
		lp_lane_mid = "мид",
		lp_lane_bot = "бот",
	},
})

local UI = localization.WrapLibrary(Menu)

local ORDER_ID = "lane_pull"
local K = {
	STRUCT_MOVE_EPS = 50.0,
	ROAD_CLEAR      = 300.0,
	ROAD_END        = 200.0,
	ROAD_DETOUR     = 1.6,
	ROAD_SPACING    = 150.0,
	SIGHT_KEEP      = 200.0,
	UNSEEN_WAIT     = 1.5,

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
	ALLY_ALERT          = 1200.0,
	ALLY_ALERT_HYST     = 250.0,
	EVADE_MIN           = 1.0,
	HIDE_HERO_WEIGHT    = 0.5,
	HIDE_SWAPS          = 2,
	ALLY_CLUSTER        = 600.0,
	EVADE_STEP          = 600.0,
	HIDE_MAX            = 2000.0,
	HIDE_ANCHOR         = 2500.0,
	HIDE_TOWER_RING     = { 150.0, 300.0, 450.0, 600.0 },
	HIDE_CHECKS         = 30,
	CREEP_SIGHT         = 750.0,
	SIGHT_PAD           = 100.0,
	ENGAGE_SLACK        = 200.0,
	HOOK_OPEN           = 150.0,
	MEET_OPEN           = 100.0,
	OPEN_STEP           = 50.0,
	EXIT_SEARCH         = 1500.0,
	HERO_SIGHT          = 1800.0,
	GUIDE_REACH         = 120.0,
	GUIDE_LOOKAHEAD     = 500.0,
	PATH_DETOURS        = 6,
	ARC_STEP            = math.rad(25),
	ARC_PUSH            = { 0.0, 100.0, 200.0, 300.0 },
	ARC_BLOCKED         = 2000.0,
	HIT_FRESH           = 1.0,
	AGGRO_RADIUS        = 700.0,
	DODGE_MARGIN        = 200.0,
	ALLY_MARGIN         = 50.0,
	ALLY_LOOKAHEAD      = 1.0,
	SOFT_PAD            = 50.0,
	SOFT_MIN            = 300.0,
	HERO_ABORT          = 0.5,
	GATE_PERP           = 600.0,
	NAV_NEAR            = 1500.0,
	ATTACK_APPROACH     = 200.0,
	HOOK_OVERHEAD       = 0.5,
	CATCH_MARGIN        = 0.5,
	CLASH_PENALTY       = 3.0,
	EDGE_BAND           = 400.0,
	TRAIL_STEP          = 150.0,
	TRAIL_LOOP          = 250.0,
	TRAIL_KEEP          = 3,
	TRAIL_MAX           = 300,
	TRAIL_REACH         = 150.0,
	TRAIL_SKIP          = 6,
	TRAIL_LOOK          = 400.0,
	FLANK_DIST          = { 1100.0, 1300.0, 1500.0, 1800.0, 2100.0 },
	FLANK_COVER         = 300.0,
	FLANK_TREE_BONUS    = 60.0,
	FLANK_RIVER_DZ      = 100.0,
	FLANK_RIVER_COST    = 2500.0,
	FLANK_SLACK         = 300.0,
	CROSS_REACH         = 200.0,
	STUCK_ORDER         = 1.0,
	STUCK_FAR           = 250.0,
	STUCK_UNIT          = 1.5,
	MID_BAND            = 1800.0,
	HERO_MEMORY         = 10.0,
	CROSS_WAVE_COST     = 1500.0,
	CROSS_SIDE          = 400.0,
	CROSS_SIDE_COST     = 1500.0,
	CROSS_TIE           = 700.0,
	CROSS_SAME          = 2000.0,
	CROSS_HERO          = 1500.0,
	CROSS_HERO_COST     = 3000.0,
	CROSS_T1_MATCH      = 400.0,
	FLANK_REACH         = 400.0,
	FLANK_HERO          = 1500.0,
	FLANK_HERO_COST     = 3000.0,
	FOLLOW_MOVE         = 120.0,
	FOLLOW_AWAY         = -0.3,
	ARC_KEEP_DIST       = 700.0,
	ARC_SWITCH          = 3000.0,
	PANEL_HEIGHT        = 26,
	PANEL_ICON          = 20,
	PANEL_FONT          = 12,
	PANEL_LINGER        = 3.0,
	PANEL_CORNER        = 7,
	PANEL_ICON_CORNER   = 5,
	PANEL_ICON_ZOOM     = 0.06,
	PANEL_FADE          = 0.18,
	PANEL_TEXT_FADE     = 0.15,
	PANEL_WIDTH_SPEED   = 14.0,
	PANEL_COLOR_SPEED   = 12.0,
	PANEL_SLIDE         = 6.0,
	PANEL_ICON_EDGE     = 30,
	HERO_ICON           = "panorama/images/heroes/icons/%s_png.vtex_c",
	PANEL_FONT_SMALL    = 11,
	PANEL_GAP           = 8,
	PANEL_PAIR_GAP      = 5,
	PANEL_PAD_RIGHT     = 10,
	PANEL_DIVIDER       = 14,
	PANEL_DIVIDER_ALPHA = 26,
	LIFE_EPS            = 3.0,
	LIFE_NEED           = 25.0,
	FIT_HP              = 60.0,
	HP_EPS              = 5.0,
	PATH_FACTOR         = 1.15,
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
	CLASH_GAP           = 1100.0,
	FOG_STEP            = 150.0,
	FOG_CHECK_RADIUS    = 700.0,
	SEARCH_STEP         = 100.0,
	ARRIVE_SLACK        = 0.5,
	SEARCH_DETECT       = 1600.0,
	SEARCH_MAX          = 30.0,
	JOB_MAX             = 60.0,
	MISS_GRACE          = 5.0,
	MAX_MISSED          = 2,
	TOWER_MARGIN        = 250.0,
	TOWER_WATCH         = 200.0,

	HOOK_OFFSET         = 350.0,
	HOOK_ENGAGE         = 550.0,
	HOOK_TIMEOUT        = 4.0,
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
	STRAGGLER_DROP      = 2.5,
	STRAGGLER_DROP_HG   = 5.0,
	STRAGGLER_REACH     = 500.0,
	STRAGGLER_HG_REACH  = 400.0,
	HG_HOLD             = 2.0,
	ALLY_HERO_NEAR      = 1200.0,
	LEAD_SHORT          = 150.0,
	HG_DZ               = 64.0,
	HG_GAP              = 250.0,
	HG_LOOK             = 600.0,
	HG_STEP             = 100.0,
	STAIR_RISE          = 32.0,
	STAIR_COOLDOWN      = 2.0,
	CLIMB_GAP           = 350.0,
	CLIMB_STEP          = 300.0,
	CLIMB_TAIL          = 250.0,
	CLIMB_MAX           = 4.0,
	LEAD_STALL          = 1.5,

	HIDE_RADII          = { 300.0, 450.0, 600.0, 750.0 },
	HIDE_ANGLE_STEP     = 20,
	HIDE_TREE_RADIUS    = 200.0,
	HIDE_MIN_TREES      = 2,
	HIDE_LANE_DIST      = 250.0,
	HIDE_WATCH          = { 0.0, 400.0, 800.0 },
	HIDE_OPEN           = 50.0,
	TOWER_SIGHT         = 1900.0,
	SIGHT_STEP          = 60.0,
	SIGHT_TREE          = 60.0,
	HIDE_REACH          = 250.0,
	HIDE_TRY            = 1.5,
	WAYPOINT_SKIP       = 300.0,
	WAYPOINT_TIMEOUT    = 1.5,
	SETTLE_DIST         = 400.0,
	FACING_ANGLE        = 30.0,
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
local MID_CROSSINGS = {
	{ radiant = Vector(-1887.0, 201.0, 128.0), dire = Vector(-921.0, 1198.0, 128.0) },
	{ radiant = Vector(592.0, -1655.0, 128.0), dire = Vector(1162.0, -499.0, 128.0) },
}
local memo = { seen = {}, crossing = nil }
local creep_speed = K.DEFAULT_CREEP_SPEED
local speed_track = {}
local next_speed_sample = 0.0
local enemy_now = {}
local enemy_by_idx = {}
local enemy_heroes = {}
local allied_now = {}
local danger_towers = {}
local creep_sight = { near = K.CREEP_SIGHT, far = K.CREEP_SIGHT }
local last_msg = nil
local last_msg_t = -100.0
local debug_font = nil
local last_result = nil
local panel_fonts = nil
local panel_icons = {}
local panel_anim = { vis = 0.0, text_t = 1.0 }
local panel_error = nil

local ui = {}

do
	local tab = UI.Create("Creeps", "Main", "Lane Pull")
	tab:Icon("\u{f4d7}")

	local page = tab:Create("Settings")
	local g_main = page:Create("lp_group_main", Enum.GroupSide.Left)
	local g_way = page:Create("lp_group_way", Enum.GroupSide.Right)

	ui.enable = g_main:Switch("lp_enable", false, "\u{f011}")
	ui.enable:ToolTip("lp_enable_tip")
	local g_extra = ui.enable:Gear("lp_gear_extra")
	ui.debug = g_extra:Switch("lp_debug", false, "\u{f188}")
	ui.debug:ToolTip("lp_debug_tip")

	ui.key = g_main:Bind("lp_key", Enum.ButtonCode.KEY_NONE, "\u{f11c}")
	ui.key:ToolTip("lp_key_tip")

	ui.pick = g_main:Combo("lp_pick", { "lp_picks_hero", "lp_picks_puller", "lp_picks_cursor" }, 0)
	ui.pick:Icon("\u{f05b}")
	ui.pick:ToolTip("lp_pick_tip")

	ui.panel = g_main:Switch("lp_panel", true, "\u{f05a}")
	ui.panel:ToolTip("lp_panel_tip")
	local g_look = ui.panel:Gear("lp_gear_panel")
	ui.panel_icon = g_look:Combo("lp_panel_icon", { "lp_icons_square", "lp_icons_round", "lp_icons_none" }, 0)
	ui.panel_icon:Icon("\u{f03e}")
	ui.panel_scale = g_look:Slider("lp_panel_scale", 80, 160, 100, "%d%%")
	ui.panel_scale:Icon("\u{f065}")
	ui.panel_alpha = g_look:Slider("lp_panel_alpha", 0, 100, 82, "%d%%")
	ui.panel_alpha:Icon("\u{f043}")
	ui.panel_blur = g_look:Switch("lp_panel_blur", false, "\u{f042}")
	ui.panel_match = g_look:Switch("lp_panel_match", true, "\u{f11b}")
	ui.panel_match:ToolTip("lp_panel_match_tip")
	ui.panel_x = g_look:Slider("lp_panel_x", 0, 100, 50, "%d%%")
	ui.panel_x:Icon("\u{f337}")
	ui.panel_y = g_look:Slider("lp_panel_y", 0, 600, 70, "%d px")
	ui.panel_y:Icon("\u{f338}")

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

	ui.where = g_way:Combo("lp_where", { "lp_wheres_edge", "lp_wheres_behind", "lp_wheres_near" }, 0)
	ui.where:Icon("\u{f3c5}")
	ui.where:ToolTip("lp_where_tip")

	ui.mid_side = g_way:Combo("lp_mid_side", { "lp_mid_sides_auto", "lp_mid_sides_top", "lp_mid_sides_bot" }, 0)
	ui.mid_side:Icon("\u{f4d7}")
	ui.mid_side:ToolTip("lp_mid_side_tip")

	ui.dive = g_way:Switch("lp_dive", true, "\u{f447}")
	ui.dive:ToolTip("lp_dive_tip")

	ui.gap = g_way:Slider("lp_gap", 250, 700, 400, "%d")
	ui.gap:Icon("\u{f337}")
	ui.gap:ToolTip("lp_gap_tip")

	ui.after = g_way:Combo("lp_after", { "lp_afters_stay", "lp_afters_attack" }, 0)
	ui.after:Icon("\u{f11e}")
	ui.after:ToolTip("lp_after_tip")

	ui.abort_hp = g_way:Slider("lp_abort_hp", 10, 80, 30, "%d%%")
	ui.abort_hp:Icon("\u{f004}")
	ui.abort_hp:ToolTip("lp_abort_hp_tip")

	ui.avoid = g_way:Switch("lp_avoid", true, "\u{f70c}")
	ui.avoid:ToolTip("lp_avoid_tip")
	local g_avoid = ui.avoid:Gear("lp_gear_avoid")
	ui.avoid_radius = g_avoid:Slider("lp_avoid_radius", 500, 1600, 900, "%d")
	ui.avoid_radius:Icon("\u{f1ce}")

	ui.key:Properties(localization.Get("lp_bind_name"))
end

local function refresh_disabled()
	local on = ui.enable:Get()
	ui.key:Disabled(not on)
	ui.pick:Disabled(not on)
	ui.dive:Disabled(not on)
	ui.where:Disabled(not on)
	ui.mid_side:Disabled(not on)
	ui.hide:Disabled(not on)
	ui.units:Disabled(not on)
	ui.gap:Disabled(not on)
	ui.after:Disabled(not on)
	ui.abort_hp:Disabled(not on)
	ui.avoid:Disabled(not on)
	ui.avoid_radius:Disabled(not on or not ui.avoid:Get())
	ui.panel:Disabled(not on)
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

local function sight_blocked(a, b)
	local n = math.floor(a:Distance2D(b) / K.SIGHT_STEP)
	for k = 1, n - 1 do
		local trees = Trees.InRadius(a:Lerp(b, k / n), K.SIGHT_TREE, true)
		if trees and #trees > 0 then return true end
	end
	return false
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

local function road_leg(a, b)
	local clear = math.min(K.ROAD_CLEAR, a:Distance2D(b) * 0.3)
	local sa, sb = a:Extend2D(b, clear), b:Extend2D(a, clear)
	local leg = GridNav.BuildPath(sa, sb, false) or {}
	if #leg < 2 or leg[#leg]:Distance2D(sb) > K.ROAD_END then return nil end
	local len = sa:Distance2D(leg[1])
	for k = 2, #leg do len = len + leg[k - 1]:Distance2D(leg[k]) end
	if len > sa:Distance2D(sb) * K.ROAD_DETOUR then return nil end
	return leg
end

local function build_lanes(my_radiant)
	local us = my_radiant and "goodguys" or "badguys"
	local them = my_radiant and "badguys" or "goodguys"
	local result = {}
	for _, name in ipairs(LANE_NAMES) do
		local anchors = {}
		local function anchor(p)
			if not p then return end
			local last = anchors[#anchors]
			if last and last:Distance2D(p) < 50.0 then return end
			anchors[#anchors + 1] = p:Clone()
		end
		local our_t1 = tower_at(1, us, name)
		local their_t1 = tower_at(1, them, name)
		anchor(rax_at(us, name))
		anchor(tower_at(3, us, name))
		anchor(tower_at(2, us, name))
		anchor(our_t1)
		if name ~= "mid" and our_t1 and their_t1 then
			anchor(lane_corner(our_t1, their_t1))
		end
		anchor(their_t1)
		anchor(tower_at(2, them, name))
		anchor(tower_at(3, them, name))
		anchor(rax_at(them, name))

		local pts = {}
		local function push(p, spacing)
			local last = pts[#pts]
			if last and last:Distance2D(p) < spacing then return end
			pts[#pts + 1] = p:Clone()
		end
		for i = 1, #anchors do
			if i > 1 then
				local leg = road_leg(anchors[i - 1], anchors[i])
				if leg then
					for k = 1, #leg do push(leg[k], K.ROAD_SPACING) end
				end
			end
			push(anchors[i], 50.0)
		end
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

	local near, far = nil, nil
	for i = 1, #enemy_now do
		local e = enemy_now[i].ent
		local day, night = NPC.GetDayTimeVisionRange(e) or 0, NPC.GetNightTimeVisionRange(e) or 0
		if day > 0 and night > 0 then
			near = math.min(near or math.huge, day, night)
			far = math.max(far or 0, day, night)
		end
	end
	if near then
		creep_sight.near, creep_sight.far = near, far
	end

	enemy_heroes = {}
	local heroes = Heroes.GetAll()
	if heroes then
		for i = 1, #heroes do
			local h = heroes[i]
			if Entity.GetTeamNum(h) ~= my_team and Entity.IsAlive(h)
				and not Entity.IsDormant(h) and not NPC.IsIllusion(h) then
				local pos = Entity.GetAbsOrigin(h)
				enemy_heroes[#enemy_heroes + 1] = pos
				memo.seen[Entity.GetIndex(h)] = { pos = pos, t = GameRules.GetGameTime() }
			end
		end
	end

	danger_towers = {}
	local towers = Towers.GetAll()
	if towers then
		for i = 1, #towers do
			local t = towers[i]
			if Entity.IsAlive(t) and Entity.GetTeamNum(t) ~= my_team then
				local range = NPC.GetAttackRange(t) or 700.0
				danger_towers[#danger_towers + 1] = {
					ent = t,
					pos = Entity.GetAbsOrigin(t),
					r = range + K.TOWER_MARGIN,
					min = range,
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

local function detour_waypoint(from, to, circles)
	local fx, fy = from:GetX(), from:GetY()
	local dx, dy = to:GetX() - fx, to:GetY() - fy
	local len2 = dx * dx + dy * dy
	if len2 < 1.0 then return nil end
	local enter, t = first_entry(fx, fy, dx, dy, circles)
	if not enter then return nil end

	local cx, cy = t.pos:GetX(), t.pos:GetY()
	local k = ((cx - fx) * dx + (cy - fy) * dy) / len2
	k = math.max(0.0, math.min(1.0, k))
	local nx, ny = fx + dx * k - cx, fy + dy * k - cy
	local nl = math.sqrt(nx * nx + ny * ny)
	if nl < 1.0 then
		nx, ny, nl = -dy, dx, math.sqrt(len2)
	end
	local rad = t.r + K.DETOUR_MARGIN
	return Vector(cx + nx / nl * rad, cy + ny / nl * rad, to:GetZ()), t, enter
end

local function route(from, to, circles)
	local waypoint, t, enter = detour_waypoint(from, to, circles)
	if not waypoint then return to end
	if t.pos:Distance2D(to) < t.r then
		local dist = from:Distance2D(to)
		return from:Lerp(to, math.max(0.0, enter - K.CLIP_MARGIN / dist))
	end
	return walkable_near(waypoint, t.pos)
end

local function travel_dist(from, to)
	local total, cur = 0.0, from
	for _ = 1, K.PATH_DETOURS do
		local waypoint, t = detour_waypoint(cur, to, danger_towers)
		if not waypoint or t.pos:Distance2D(to) < t.r then break end
		total = total + cur:Distance2D(waypoint)
		cur = waypoint
	end
	return total + cur:Distance2D(to)
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
	local w = { members = {}, banned = {}, last = {}, vel = {}, vx = 0.0, vy = 0.0, seen_at = now, last_t = now }
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
			if not w.members[e.idx] and not w.banned[e.idx] then
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
					list[#list + 1] = { t0 = t0, s = s, lo = math.max(lo, 0.0), front = front }
				end
			end
		end
	end
	return list
end

local function reachable(lane, s, s_pred, from, from_speed, direct)
	local pt = lane_point(lane, s)
	local dist = direct and from:Distance2D(pt) or travel_dist(from, pt)
	local t_puller = dist * K.PATH_FACTOR / from_speed
	local t_wave = (s_pred - s) / creep_speed
	return t_puller + K.ARRIVE_SLACK <= t_wave, pt, t_wave
end

local function lane_open(lane, s)
	local cache = lane.open
	if not cache then
		cache = {}
		lane.open = cache
	end
	local key = math.floor(s / K.OPEN_STEP + 0.5)
	local known = cache[key]
	if known == nil then
		local p = lane_point(lane, key * K.OPEN_STEP)
		local trees = Trees.InRadius(p, K.MEET_OPEN, true)
		known = GridNav.IsTraversable(p) and not (trees and #trees > 0)
		cache[key] = known
	end
	return known
end

local function meet_score(lane, s, s_pred, from, from_speed, hero_pos)
	if not lane_open(lane, s) then return nil end
	local ok, pt, t_wave = reachable(lane, s, s_pred, from, from_speed)
	if not ok or in_danger(pt) then return nil end
	return pt:Distance2D(hero_pos), t_wave
end

local function road_exit(lane, pos)
	local s = lane_project(lane, pos)
	local stop = math.max(0.0, s - K.EXIT_SEARCH)
	while s > stop do
		local p = lane_point(lane, s)
		if not in_danger(p) and lane_open(lane, s) then return p end
		s = s - K.OPEN_STEP
	end
	return nil
end

local function lane_limits(lane)
	if not lane then return {} end
	local first, first_r, second = nil, nil, nil
	for i = 1, #danger_towers do
		local t = danger_towers[i]
		local s, perp = lane_project(lane, t.pos)
		if perp <= K.GATE_PERP then
			if not first or s < first then
				first, first_r, second = s, t.r, first
			elseif not second or s < second then
				second = s
			end
		end
	end
	local mode = ui.where:Get()
	return {
		gate = mode == 1 and first or nil,
		edge = mode == 0 and first and first - first_r or nil,
		first = first,
		ceil = second or lane.len,
	}
end

local function plan_meet(lane, from, from_speed, hero_pos, min_t0, keep_t0, keep_s, keep_dive, dive, lim)
	local batches = predict_batches(lane, min_t0)
	if #batches == 0 then return nil end
	local ceil = lim.ceil or lane.len
	local first = lim.first

	local function scan_batch(b, p)
		local best_s, best_score = nil, math.huge
		local s = math.min(b.s, lane.len, ceil, p.top or math.huge)
		local floor = p.relaxed and p.bottom or math.max(b.lo, p.bottom)
		while s >= floor do
			local dist, t_wave = meet_score(lane, s, b.s, from, from_speed, hero_pos)
			if dist then
				local score = (p.top and p.top - s or dist) + t_wave * K.WAIT_WEIGHT
				if s < b.lo then score = score + (b.lo - s) * K.CLASH_PENALTY end
				if score < best_score then best_s, best_score = s, score end
			end
			s = s - K.SEARCH_STEP
		end
		return best_s, best_score
	end

	local function kept(b)
		if not keep_t0 or b.t0 ~= keep_t0 or not keep_s or keep_s > ceil then return false end
		if keep_s > b.s then return keep_s <= b.s + creep_speed * K.MISS_GRACE end
		if keep_dive then return reachable(lane, keep_s, b.s, from, from_speed, true) end
		return meet_score(lane, keep_s, b.s, from, from_speed, hero_pos) ~= nil
	end

	local anywhere = { bottom = -math.huge }
	local each, later = {}, {}
	if lim.edge then each[#each + 1] = { bottom = lim.edge - K.EDGE_BAND, top = first } end
	if lim.gate then
		each[#each + 1] = { bottom = first }
		later[#later + 1] = anywhere
	else
		each[#each + 1] = anywhere
	end

	for i = 1, #batches do
		local b = batches[i]
		if kept(b) then return b.t0, b.s, keep_s, keep_dive end
		for k = 1, #each do
			local s = scan_batch(b, each[k])
			if s then return b.t0, b.s, s, false end
		end
		local bottom = lim.gate and first or b.front + K.FRONT_BUFFER
		local s = scan_batch(b, { bottom = bottom, relaxed = true })
		if s then return b.t0, b.s, s, false end
	end

	for k = 1, #later do
		local best_b, best_s, best_score = nil, nil, math.huge
		for i = 1, #batches do
			local s, score = scan_batch(batches[i], later[k])
			if s and score < best_score then best_b, best_s, best_score = batches[i], s, score end
		end
		if best_b then return best_b.t0, best_b.s, best_s, false end
	end

	if dive then
		for i = 1, #batches do
			local b = batches[i]
			local s = b.lo
			local top = math.min(b.s, lane.len, ceil)
			while s <= top do
				if reachable(lane, s, b.s, from, from_speed, true) then return b.t0, b.s, s, true end
				s = s + K.SEARCH_STEP
			end
		end
	end

	local b = batches[#batches]
	local s = math.min(b.lo, b.s, lane.len)
	if first and lim.ceil then s = math.min(s, (first + ceil) * 0.5) end
	return b.t0, b.s, s, false
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
	local p = walkable_near(target, center)
	local trees = Trees.InRadius(p, K.HOOK_OPEN, true)
	local open = GridNav.IsTraversable(p) and not (trees and #trees > 0)
	if open and (job.dive or not in_danger(p)) and not sight_blocked(front, p) then return p end
	if job.dive or not in_danger(front) then return front end
	return (job.lane and road_exit(job.lane, front)) or safe_point(front)
end

local function engage_range()
	return math.max(K.HOOK_ENGAGE, creep_sight.near + K.ENGAGE_SLACK)
end

local function wave_skipped(members, skipped)
	for i = 1, #members do
		if skipped[members[i].idx] then return true end
	end
	return false
end

local function wave_min_s(lane, members)
	local low = math.huge
	for i = 1, #members do
		local s = lane_project(lane, members[i].pos)
		if s < low then low = s end
	end
	return low
end

local function past_gate(lane, members, gate)
	return not gate or wave_min_s(lane, members) >= gate
end

local function detect_wave(lane, anchors, skipped, gate)
	local waves = cluster_waves(enemy_now)
	local best, best_d = nil, K.SEARCH_DETECT
	for i = 1, #waves do
		local members = waves[i]
		local on_lane = true
		if lane then
			local _, perp = lane_project(lane, wave_center(members))
			on_lane = perp <= K.LANE_BAND and past_gate(lane, members, gate)
		end
		if on_lane and not wave_engaged(members) and not wave_skipped(members, skipped) then
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
	if a.fit ~= b.fit then return a.fit end
	if a.rank ~= b.rank then return a.rank < b.rank end
	local ua, ub = math.min(a.life, K.LIFE_NEED), math.min(b.life, K.LIFE_NEED)
	if math.abs(ua - ub) > K.LIFE_EPS then return ua > ub end
	if math.abs(a.pct - b.pct) > K.HP_EPS then return a.pct > b.pct end
	if math.abs(a.life - b.life) > K.LIFE_EPS then return a.life > b.life end
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
					local life = life_left(u, now)
					local entry = {
						unit = u,
						rank = ranks[kind] or math.huge,
						life = life,
						pct = pct,
						fit = pct >= K.FIT_HP and life >= K.LIFE_NEED,
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

local function ally_circles(list)
	local waves = cluster_waves(allied_now)
	for i = 1, #waves do
		local members = waves[i]
		local c = wave_center(members)
		local spread, marching = 0.0, true
		for k = 1, #members do
			spread = math.max(spread, members[k].pos:Distance2D(c))
			if NPC.IsAttacking(members[k].ent) then marching = false end
		end
		local r = spread + K.ENGAGE_RADIUS + K.ALLY_MARGIN
		list[#list + 1] = { pos = c, r = r }
		local lane = marching and nearest_lane(c, K.LANE_BAND)
		if lane then
			local s = lane_project(lane, c)
			local base = lane_point(lane, s)
			local ahead = lane_point(lane, s + creep_speed * K.ALLY_LOOKAHEAD)
			list[#list + 1] = {
				pos = Vector(c:GetX() + ahead:GetX() - base:GetX(), c:GetY() + ahead:GetY() - base:GetY(), c:GetZ()),
				r = r,
			}
		end
	end
end

local function enemy_circles(list)
	local waves = cluster_waves(enemy_now)
	for i = 1, #waves do
		local members = waves[i]
		local c = wave_center(members)
		local spread = 0.0
		for k = 1, #members do spread = math.max(spread, members[k].pos:Distance2D(c)) end
		list[#list + 1] = { pos = c, r = spread + creep_sight.far }
	end
end

local function nav_circles(from, goal)
	local raw = {}
	if not job.dive then
		for i = 1, #danger_towers do raw[#raw + 1] = danger_towers[i] end
	end
	if ui.avoid:Get() then
		local r = ui.avoid_radius:Get()
		for i = 1, #enemy_heroes do raw[#raw + 1] = { pos = enemy_heroes[i], r = r } end
	end
	if job.state == "lead" then ally_circles(raw) end
	if job.state == "search" then enemy_circles(raw) end

	local out = {}
	for i = 1, #raw do
		local c = raw[i]
		local r = math.min(c.r, from:Distance2D(c.pos) - K.SOFT_PAD, goal:Distance2D(c.pos) - K.SOFT_PAD)
		if r >= (c.min or K.SOFT_MIN) then out[#out + 1] = { pos = c.pos, r = r } end
	end
	return out
end

local function closest_on_segment(a, b, p)
	local ax, ay = a:GetX(), a:GetY()
	local dx, dy = b:GetX() - ax, b:GetY() - ay
	local len2 = dx * dx + dy * dy
	local k = len2 > 0 and ((p:GetX() - ax) * dx + (p:GetY() - ay) * dy) / len2 or 0
	k = math.max(0.0, math.min(1.0, k))
	return Vector(ax + dx * k, ay + dy * k, p:GetZ())
end

local function segment_hit(a, b, circles)
	for i = 1, #circles do
		local c = circles[i]
		local q = closest_on_segment(a, b, c.pos)
		if q:Distance2D(c.pos) < c.r then return c, q end
	end
	return nil
end

local function arc_side(circle, a, b, dir)
	local cx, cy = circle.pos:GetX(), circle.pos:GetY()
	local rad = circle.r + K.DETOUR_MARGIN
	local da, db = a:Distance2D(circle.pos), b:Distance2D(circle.pos)
	local start = math.atan(a:GetY() - cy, a:GetX() - cx) + dir * (da > rad and math.acos(rad / da) or 0.0)
	local stop = math.atan(b:GetY() - cy, b:GetX() - cx) - dir * (db > rad and math.acos(rad / db) or 0.0)
	local sweep = (dir * (stop - start)) % (2 * math.pi)
	if sweep > 1.5 * math.pi then return nil end

	local n = math.max(1, math.ceil(sweep / K.ARC_STEP))
	local best, best_blocked, best_r = nil, math.huge, rad
	for i = 1, #K.ARC_PUSH do
		local r = rad + K.ARC_PUSH[i]
		local points, blocked = {}, 0
		for k = 0, n do
			local ang = start + dir * sweep * k / n
			local q = Vector(cx + math.cos(ang) * r, cy + math.sin(ang) * r, circle.pos:GetZ())
			if walkable(q) then
				points[#points + 1] = q
			else
				blocked = blocked + 1
			end
		end
		if blocked < best_blocked then best, best_blocked, best_r = points, blocked, r end
		if blocked == 0 then break end
	end
	if #best == 0 then return nil end
	return best, sweep * best_r + best_blocked * K.ARC_BLOCKED
end

local function preferred_side(circle, sides)
	if not sides then return nil end
	for i = 1, #sides do
		if sides[i].pos:Distance2D(circle.pos) < K.ARC_KEEP_DIST then return sides[i].dir end
	end
	return nil
end

local function arc_around(circle, a, b, sides)
	local rad = circle.r + K.DETOUR_MARGIN
	local q = closest_on_segment(a, b, circle.pos)
	local d = q:Distance2D(circle.pos)
	if d < rad then
		local keep = preferred_side(circle, sides)
		local best, best_cost, best_dir = nil, math.huge, nil
		for _, dir in ipairs({ 1, -1 }) do
			local points, cost = arc_side(circle, a, b, dir)
			if points then
				if keep and dir ~= keep then cost = cost + K.ARC_SWITCH end
				if cost < best_cost then best, best_cost, best_dir = points, cost, dir end
			end
		end
		if best then return best, best_dir end
	end
	if d < 1.0 then q = a end
	return { walkable_near(circle.pos:Extend2D(q, math.max(rad, d)), circle.pos) }, nil
end

local function build_legs(from, stops, cache)
	local path = {}
	local start = from
	for s = 1, #stops do
		local stop = stops[s]
		local row = cache[start]
		if not row then
			row = {}
			cache[start] = row
		end
		local leg = row[stop]
		if not leg then
			leg = GridNav.BuildPath(start, stop, false) or {}
			if #leg == 0 then leg = { stop } end
			row[stop] = leg
		end
		for k = 1, #leg do
			path[#path + 1] = { pos = leg[k], leg = s }
		end
		start = stop
	end
	return path
end

local function safe_path(from, goal, circles, sides)
	local stops = { goal }
	local cache = {}
	local chosen = {}
	local path = build_legs(from, stops, cache)
	for _ = 1, K.PATH_DETOURS do
		local hit, first, before = nil, nil, nil
		local prev = from
		for k = 1, #path do
			local cur = path[k].pos
			local c = segment_hit(prev, cur, circles)
			if c then
				hit, first, before = c, k, prev
				break
			end
			prev = cur
		end
		if not hit then break end
		local after = goal
		for k = first, #path do
			if path[k].pos:Distance2D(hit.pos) >= hit.r then
				after = path[k].pos
				break
			end
		end
		local arc, dir = arc_around(hit, before, after, sides)
		if dir then chosen[#chosen + 1] = { pos = hit.pos, dir = dir } end
		local at = path[first].leg
		for i = #arc, 1, -1 do table.insert(stops, at, arc[i]) end
		path = build_legs(from, stops, cache)
	end
	local points = {}
	for k = 1, #path do points[k] = path[k].pos end
	return points, chosen
end

local function circles_near_route(from, goal, circles)
	for i = 1, #circles do
		local c = circles[i]
		if closest_on_segment(from, goal, c.pos):Distance2D(c.pos) < c.r + K.NAV_NEAR then return true end
	end
	return false
end

local function navigate(from, goal, now, follow, idle)
	local nav = job.nav
	if not nav or nav.goal:Distance2D(goal) > K.GUIDE_REPLAN_DIST or now - nav.t > K.GUIDE_REPLAN_TIME then
		local circles = nav_circles(from, goal)
		nav = { goal = goal:Clone(), t = now, i = 1, i_t = now, path = {}, circles = circles }
		nav.near = circles_near_route(from, goal, circles)
		if follow or nav.near then
			nav.path, job.arc_sides = safe_path(from, goal, circles, job.arc_sides)
		end
		job.nav = nav
	end
	if not follow and not nav.near then return goal, true end

	local path = nav.path
	if #path == 0 then
		local p = route(from, goal, nav.circles)
		return p, p == goal
	end
	while nav.i <= #path do
		local d = from:Distance2D(path[nav.i])
		local stuck = idle and (d < K.WAYPOINT_SKIP or now - nav.i_t > K.WAYPOINT_TIMEOUT)
		if d >= K.GUIDE_REACH and not stuck then break end
		nav.i = nav.i + 1
		nav.i_t = now
	end
	if nav.i > #path then return goal, true end

	local j = math.max(nav.i, nav.j or 1)
	local fx, fy = from:GetX(), from:GetY()
	while j < #path do
		local nxt = path[j + 1]
		if from:Distance2D(nxt) >= K.GUIDE_LOOKAHEAD then break end
		if not GridNav.IsTraversableFromTo(from, nxt, false) then break end
		if first_entry(fx, fy, nxt:GetX() - fx, nxt:GetY() - fy, nav.circles) then break end
		j = j + 1
	end
	nav.j = j
	return path[j], j == #path
end

local function issue(kind, pos, target, no_settle)
	local u = job.unit
	if orders_blocked(u) then return end
	local now = GameRules.GetGameTime()
	local u_pos = Entity.GetAbsOrigin(u)
	local ux, uy = u_pos:GetX(), u_pos:GetY()
	local prev = job.order
	local goal = nil

	if kind == "attack" and target and not job.dive then
		local target_pos = Entity.GetAbsOrigin(target)
		local reach = (NPC.GetAttackRange(u) or 0) + K.ATTACK_APPROACH
		if u_pos:Distance2D(target_pos) > reach and circles_near_route(u_pos, target_pos, danger_towers) then
			kind, pos, target = "move", target_pos, nil
		end
	end

	local final = true
	if kind == "move" or kind == "attack_move" then
		if move_blocked(u) then return end
		local idle = prev ~= nil and not NPC.IsRunning(u) and now - prev.t > K.ARRIVE_IDLE
		pos, final = navigate(u_pos, pos, now, job.guided and job.state == "lead", idle)
	end
	if kind == "move" and final then
		local gx, gy = pos:GetX(), pos:GetY()
		local dist = dist_xy(ux, uy, gx, gy)
		local tolerance = math.max(K.POS_EPS, dist * K.POS_TOLERANCE)
		local stopped_short = not no_settle and prev and prev.kind == "move"
			and dist <= K.SETTLE_DIST
			and dist_xy(prev.gx, prev.gy, gx, gy) <= tolerance
			and not NPC.IsRunning(u)
			and now - prev.t > K.ARRIVE_IDLE
		local still_held = not no_settle and prev and prev.kind == "hold" and prev.gx
			and dist <= K.SETTLE_DIST
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
	job.nav = nil
	job.stair = nil
	job.flank = nil
	job.above_since = nil
	job.info.gap = nil
	if state == "lead" then
		job.trail_i = job.trail_i or #job.trail
		job.led = true
		job.follow = {}
	end
	if reason then note(state .. ": " .. reason) end
end

local function finish(reason)
	if reason then note("done: " .. reason) end
	last_result = {
		ok = job.state == "deliver",
		icon = job.icon,
		lane = job.lane and job.lane.name,
		t = GameRules.GetGameTime(),
	}
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

local function track_aggro(now, u_pos)
	for i = 1, #enemy_now do
		local e = enemy_now[i]
		local reach = (NPC.GetAttackRange(e.ent) or 100) + K.RANGED_SLACK
		if NPC.IsAttacking(e.ent) and e.pos:Distance2D(u_pos) <= reach then
			local facing = NPC.FindFacingNPC(e.ent, e.ent, TEAM_ENEMY, K.FACING_ANGLE, K.PACK_RANGE)
			if (facing and Entity.GetIndex(facing) == job.idx) or not allied_near(e.pos, reach) then
				job.aggro[e.idx] = now
			end
		end
	end
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

local function wave_catchable(ctx, members)
	local lane = job.lane
	if not lane then return true end
	local ours = {}
	for i = 1, #allied_now do
		local _, perp = lane_project(lane, allied_now[i].pos)
		if perp <= K.LANE_BAND then ours[#ours + 1] = allied_now[i] end
	end
	if #ours == 0 then return true end

	local gap = math.huge
	for i = 1, #members do
		local _, d = nearest(ours, members[i].pos)
		if d < gap then gap = d end
	end
	local _, moving = lane_front(lane)
	local closing = moving and creep_speed * 2.0 or creep_speed
	local clash_eta = math.max(0.0, gap - K.ENGAGE_RADIUS) / closing

	local _, reach = nearest(members, ctx.u_pos)
	local eta = math.max(0.0, reach - engage_range()) * K.PATH_FACTOR / ctx.u_speed + K.HOOK_OVERHEAD
	return eta + K.CATCH_MARGIN <= clash_eta
end

local function skip_wave(members)
	for i = 1, #members do job.skipped[members[i].idx] = true end
	if job.lane then
		local s = lane_project(job.lane, wave_center(members))
		local t0 = game_clock() - (job.lane.len - s) / creep_speed
		t0 = math.floor(t0 / K.SPAWN_PERIOD + 0.5) * K.SPAWN_PERIOD
		job.min_t0 = math.max(job.min_t0 or 0, t0 + K.SPAWN_PERIOD)
	end
	job.batch = nil
	job.meet_s = nil
	job.hide = nil
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
	if job.lane and not job.led and not wave_catchable(ctx, visible) then
		skip_wave(visible)
		job.wave = nil
		job.info.front = nil
		return set_state("search", "won't make it before our creeps, going for the next wave")
	end

	local _, close_d = nearest(outside_towers(visible), ctx.u_pos)
	if close_d <= engage_range() then
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

local function open_spot(p)
	if not GridNav.IsTraversable(p) then return false end
	local trees = Trees.InRadius(p, K.HIDE_OPEN, true)
	return not trees or #trees == 0
end

local function hide_watchers(lane, meet_s)
	local list = {}
	for i = 1, #K.HIDE_WATCH do
		list[#list + 1] = { pos = lane_point(lane, meet_s + K.HIDE_WATCH[i]), sight = creep_sight.far + K.SIGHT_PAD }
	end
	for i = 1, #danger_towers do
		list[#list + 1] = { pos = danger_towers[i].pos, sight = K.TOWER_SIGHT }
	end
	for i = 1, #enemy_heroes do
		list[#list + 1] = { pos = enemy_heroes[i], sight = K.HERO_SIGHT }
	end
	return list
end

local function hidden_from(p, watchers)
	for i = 1, #watchers do
		local w = watchers[i]
		if w.pos:Distance2D(p) <= w.sight and not sight_blocked(p, w.pos) then return false end
	end
	return true
end

local function hide_anchor(meet)
	local best, best_d = nil, K.HIDE_ANCHOR
	for i = 1, #danger_towers do
		local t = danger_towers[i]
		local d = t.pos:Distance2D(meet)
		if d < best_d then best, best_d = t, d end
	end
	return best
end

local function hide_candidates(meet, tower, reach)
	local list = {}
	local z = meet:GetZ()
	local function ring(center, r)
		local cx, cy = center:GetX(), center:GetY()
		for a = 0, 360 - K.HIDE_ANGLE_STEP, K.HIDE_ANGLE_STEP do
			local rad = math.rad(a)
			list[#list + 1] = Vector(cx + math.cos(rad) * r, cy + math.sin(rad) * r, z)
		end
	end
	for i = 1, #K.HIDE_RADII do
		if K.HIDE_RADII[i] <= reach then ring(meet, K.HIDE_RADII[i]) end
	end
	if tower then
		for i = 1, #K.HIDE_TOWER_RING do ring(tower.pos, tower.r + K.HIDE_TOWER_RING[i]) end
	end
	return list
end

local function find_hideout(lane, meet, meet_s, speed, t_wave, hero_pos)
	local budget = (t_wave - K.LEAVE_MARGIN - K.ARRIVE_SLACK) * speed / K.PATH_FACTOR
	local reach = math.min(K.HIDE_MAX, budget)
	if reach < K.HIDE_RADII[1] then return nil end

	local tower = hide_anchor(meet)
	local anchor = tower and tower.pos or meet
	local spots = {}
	local points = hide_candidates(meet, tower, reach)
	for i = 1, #points do
		local p = points[i]
		if p:Distance2D(meet) <= reach and open_spot(p) and not in_danger(p) and not hide_blocked(p) then
			local _, perp = lane_project(lane, p)
			local trees = Trees.InRadius(p, K.HIDE_TREE_RADIUS, true)
			if trees and #trees >= K.HIDE_MIN_TREES and perp >= K.HIDE_LANE_DIST then
				local d = p:Distance2D(anchor) + p:Distance2D(hero_pos) * K.HIDE_HERO_WEIGHT
				spots[#spots + 1] = { pos = p, d = d }
			end
		end
	end
	table.sort(spots, function(a, b) return a.d < b.d end)

	local watchers = hide_watchers(lane, meet_s)
	for i = 1, math.min(#spots, K.HIDE_CHECKS) do
		local p = spots[i].pos
		if travel_dist(p, meet) <= budget and hidden_from(p, watchers) then return p end
	end
	return nil
end

local function hide_target(ctx, lane, meet, meet_s, s_pred)
	if not ui.hide:Get() or job.dive then return nil end
	local t_wave = (s_pred - meet_s) / creep_speed
	if not job.hide or math.abs(job.hide.s - meet_s) > K.HIDE_RECALC then
		job.hide = { s = meet_s, pos = find_hideout(lane, meet, meet_s, ctx.u_speed, t_wave, ctx.hero_pos) }
		job.leaving = false
		job.seen_since = nil
	end
	local spot = job.hide.pos
	if not spot or job.leaving then return nil end

	local t_run = travel_dist(spot, meet) * K.PATH_FACTOR / ctx.u_speed
	if t_wave - t_run <= K.LEAVE_MARGIN then
		job.leaving = true
		note("coming out of the trees for the " .. clock_text(job.batch) .. " wave")
		return nil
	end

	local heading = job.info.target and job.info.target:Distance2D(spot) < 1.0
	if heading and not NPC.IsRunning(job.unit) and ctx.u_pos:Distance2D(spot) > K.HIDE_REACH then
		job.hide.stuck_since = job.hide.stuck_since or ctx.now
		if ctx.now - job.hide.stuck_since > K.HIDE_TRY then
			if (job.hide_swaps or 0) >= K.HIDE_SWAPS then
				job.hide.pos = nil
				note("can't get into the trees, waiting on the lane")
				return nil
			end
			job.hide_swaps = (job.hide_swaps or 0) + 1
			job.hide_bad[#job.hide_bad + 1] = spot
			job.hide = nil
			note("can't get into those trees, looking for another spot")
			return nil
		end
	else
		job.hide.stuck_since = nil
	end

	if ctx.u_pos:Distance2D(spot) <= K.ARRIVE_EPS * 2 and NPC.IsVisibleToEnemies(job.unit)
		and (job.hide_swaps or 0) < K.HIDE_SWAPS then
		job.seen_since = job.seen_since or ctx.now
		if ctx.now - job.seen_since > K.HIDE_SEEN_TIME then
			job.hide_swaps = (job.hide_swaps or 0) + 1
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

local function wave_near(pos, radius)
	local waves = cluster_waves(enemy_now)
	local best, best_d = nil, radius
	for i = 1, #waves do
		local _, d = nearest(waves[i], pos)
		if d < best_d and not wave_engaged(waves[i]) then best, best_d = waves[i], d end
	end
	return best
end

local function coming_at(lane, members, u_s)
	if not lane then return true end
	for i = 1, #members do
		if lane_project(lane, members[i].pos) >= u_s then return true end
	end
	return false
end

local function dodge_point(ctx, lane)
	local u_s = lane and lane_project(lane, ctx.u_pos) or 0.0
	local radius = creep_sight.far + K.SIGHT_PAD
	local close, d = nil, radius
	local waves = cluster_waves(enemy_now)
	for i = 1, #waves do
		local members = waves[i]
		local m, md = nearest(members, ctx.u_pos)
		if md < d and not wave_engaged(members) and coming_at(lane, members, u_s) then
			close, d = m, md
		end
	end
	if not close then return nil end
	local reach = radius + K.DODGE_MARGIN
	if lane then
		local s = u_s
		local a, b = lane_point(lane, s - 50.0), lane_point(lane, s + 50.0)
		local dx, dy = b:GetX() - a:GetX(), b:GetY() - a:GetY()
		local l = math.sqrt(dx * dx + dy * dy)
		if l >= 1.0 then
			local base = lane_point(lane, s)
			local nx, ny = -dy / l, dx / l
			local side = (ctx.u_pos:GetX() - base:GetX()) * nx + (ctx.u_pos:GetY() - base:GetY()) * ny
			local first = side >= 0 and 1 or -1
			for _, dist in ipairs({ reach, reach + 300.0 }) do
				for _, sign in ipairs({ first, -first }) do
					local p = Vector(base:GetX() + nx * sign * dist, base:GetY() + ny * sign * dist, base:GetZ())
					if walkable(p) and not in_danger(p) then return p end
				end
			end
		end
	end
	return walkable_near(close.pos:Extend2D(ctx.u_pos, reach), close.pos)
end

local function flank_point(lane, first, from, to)
	local c = lane_point(lane, first)
	local a, b = lane_point(lane, first - 100.0), lane_point(lane, first + 100.0)
	local dx, dy = b:GetX() - a:GetX(), b:GetY() - a:GetY()
	local l = math.sqrt(dx * dx + dy * dy)
	if l < 1.0 then return nil end
	local nx, ny = -dy / l, dx / l
	local tower_z = World.GetGroundZ(c:GetX(), c:GetY()) or c:GetZ()
	local best, best_cost = nil, math.huge
	for _, sign in ipairs({ 1, -1 }) do
		for i = 1, #K.FLANK_DIST do
			local d = K.FLANK_DIST[i]
			local p = Vector(c:GetX() + nx * sign * d, c:GetY() + ny * sign * d, c:GetZ())
			if walkable(p) and not in_danger(p) then
				local cost = from:Distance2D(p) + p:Distance2D(to)
				local trees = Trees.InRadius(p, K.FLANK_COVER, true)
				cost = cost - (trees and #trees or 0) * K.FLANK_TREE_BONUS
				local z = World.GetGroundZ(p:GetX(), p:GetY()) or p:GetZ()
				if z < tower_z - K.FLANK_RIVER_DZ then cost = cost + K.FLANK_RIVER_COST end
				for k = 1, #enemy_heroes do
					if enemy_heroes[k]:Distance2D(p) < K.FLANK_HERO then cost = cost + K.FLANK_HERO_COST end
				end
				if cost < best_cost then best, best_cost = p, cost end
			end
		end
	end
	return best
end

local function record_trail(pos)
	local tr = job.trail
	local last = tr[#tr]
	if last and last:Distance2D(pos) < K.TRAIL_STEP then return end
	for k = 1, #tr - K.TRAIL_KEEP do
		if tr[k]:Distance2D(pos) < K.TRAIL_LOOP then
			for m = #tr, k + 1, -1 do tr[m] = nil end
			break
		end
	end
	if #tr < K.TRAIL_MAX then tr[#tr + 1] = pos:Clone() end
end

local function trail_ahead(ctx)
	local tr, i = job.trail, job.trail_i
	if not tr or not i or i < 1 then return nil end
	local best, best_d = i, ctx.u_pos:Distance2D(tr[i])
	for k = i - 1, math.max(1, i - K.TRAIL_SKIP), -1 do
		local d = ctx.u_pos:Distance2D(tr[k])
		if d < best_d then best, best_d = k, d end
	end
	i = best
	while i >= 1 and ctx.u_pos:Distance2D(tr[i]) <= K.TRAIL_REACH do i = i - 1 end
	job.trail_i = i
	if i < 1 then return nil end
	local pts, target = {}, tr[i]
	local walked, prev = 0.0, ctx.u_pos
	for k = i, 1, -1 do
		walked = walked + prev:Distance2D(tr[k])
		if walked > K.HG_LOOK then break end
		pts[#pts + 1] = tr[k]
		if walked <= K.TRAIL_LOOK then target = tr[k] end
		prev = tr[k]
	end
	return target, pts
end

local function crossing_ok(lane, first)
	local them = lanes_radiant and "badguys" or "goodguys"
	local t1 = tower_at(1, them, "mid")
	return t1 ~= nil and lane_point(lane, first):Distance2D(t1) <= K.CROSS_T1_MATCH
end

local function lane_side(lane, p)
	local s = lane_project(lane, p)
	local a, b = lane_point(lane, s - 100.0), lane_point(lane, s + 100.0)
	local base = lane_point(lane, s)
	local l = a:Distance2D(b)
	if l < 1.0 then return 0.0 end
	return ((b:GetX() - a:GetX()) * (p:GetY() - base:GetY()) - (b:GetY() - a:GetY()) * (p:GetX() - base:GetX())) / l
end

local function crossing_cost(cr, ours, from, to, lane, outbound)
	local a, b = cr[ours], cr[ours == "radiant" and "dire" or "radiant"]
	local cost = from:Distance2D(a) + a:Distance2D(b) + b:Distance2D(to)
	local now = GameRules.GetGameTime()
	for _, seen in pairs(memo.seen) do
		if now - seen.t <= K.HERO_MEMORY
			and (seen.pos:Distance2D(a) < K.CROSS_HERO or seen.pos:Distance2D(b) < K.CROSS_HERO) then
			cost = cost + K.CROSS_HERO_COST
		end
	end
	if outbound then
		for i = 1, #enemy_now do
			if enemy_now[i].pos:Distance2D(b) < creep_sight.far then
				cost = cost + K.CROSS_WAVE_COST
				break
			end
		end
	end
	local mine = lane_side(lane, from)
	if math.abs(mine) > K.CROSS_SIDE and (mine > 0) ~= (lane_side(lane, cr.radiant) > 0) then
		cost = cost + K.CROSS_SIDE_COST
	end
	if cr == job.crossing then cost = cost - K.CROSS_SAME end
	return cost
end

local function crossing_route(ctx, target, outbound, lane)
	local ours = lanes_radiant and "radiant" or "dire"
	local theirs = lanes_radiant and "dire" or "radiant"
	local first_key = outbound and ours or theirs
	local top = crossing_cost(MID_CROSSINGS[1], first_key, ctx.u_pos, target, lane, outbound)
	local bot = crossing_cost(MID_CROSSINGS[2], first_key, ctx.u_pos, target, lane, outbound)
	local pick = ui.mid_side:Get()
	local best
	if pick == 1 or pick == 2 then
		best = MID_CROSSINGS[pick]
	elseif outbound and memo.crossing and math.abs(top - bot) < K.CROSS_TIE then
		best = memo.crossing == MID_CROSSINGS[1] and MID_CROSSINGS[2] or MID_CROSSINGS[1]
	else
		best = top <= bot and MID_CROSSINGS[1] or MID_CROSSINGS[2]
	end
	if outbound then memo.crossing = best end
	job.crossing = best
	local route = outbound and { best[ours], best[theirs] } or { best[theirs], best[ours] }
	local i = 1
	local z = World.GetGroundZ(ctx.u_pos:GetX(), ctx.u_pos:GetY()) or ctx.u_pos:GetZ()
	if ctx.u_pos:Distance2D(route[2]) < route[1]:Distance2D(route[2])
		or z < route[1]:GetZ() - K.STAIR_RISE then
		i = 2
	end
	return { route = route, i = i }
end

local function flank_target(ctx, lane, target)
	job.info.flank = nil
	local first = lane and lane.name == "mid" and lane_limits(lane).first
	if not first then
		job.flank = nil
		return target
	end
	local su = lane_project(lane, ctx.u_pos)
	local st, perp_t = lane_project(lane, target)
	local outbound = su < first - K.FLANK_SLACK and st > first
	local back = su > first + K.FLANK_SLACK
		and ((st < first and perp_t <= K.MID_BAND) or job.crossing ~= nil)
	local crossing = outbound or back
	if not crossing then
		job.flank = nil
		return target
	end
	local fl = job.flank
	if not fl then
		if crossing_ok(lane, first) then
			fl = crossing_route(ctx, target, outbound, lane)
			if fl then note("crossing the river by the side stairs") end
		end
		if not fl then
			fl = { pos = flank_point(lane, first, ctx.u_pos, target) }
			if fl.pos then
				job.flanked = true
				note("going around their tower through the side")
			end
		end
		job.flank = fl
	end
	if fl.route then
		local z = World.GetGroundZ(ctx.u_pos:GetX(), ctx.u_pos:GetY()) or ctx.u_pos:GetZ()
		while fl.i <= #fl.route do
			local wp = fl.route[fl.i]
			local passed = fl.i < #fl.route and z < wp:GetZ() - K.STAIR_RISE
			if ctx.u_pos:Distance2D(wp) > K.CROSS_REACH and not passed then break end
			fl.i = fl.i + 1
		end
		if fl.i > #fl.route then return target end
		job.info.flank = fl.route[fl.i]
		return fl.route[fl.i]
	end
	if not fl.pos or fl.done then return target end
	if ctx.u_pos:Distance2D(fl.pos) <= K.FLANK_REACH then
		fl.done = true
		return target
	end
	job.info.flank = fl.pos
	return fl.pos
end

local function step_search(ctx)
	local now = ctx.now
	local lane = job.lane

	if now - job.hit_at < K.HIT_FRESH then
		local attackers = wave_near(ctx.u_pos, K.AGGRO_RADIUS)
		if attackers then
			job.wave = track_wave(attackers, now)
			job.info.pred = nil
			job.info.meet = nil
			job.info.batch = nil
			job.started = now
			return set_state("lead", "the wave went for your creep, bringing it")
		end
	end

	local target, meet, batch
	local lim = lane_limits(lane)
	if lane then
		local t0, s_pred, meet_s, dove = plan_meet(lane, ctx.u_pos, ctx.u_speed, ctx.hero_pos,
			job.min_t0, job.batch, job.meet_s, job.dive, ui.dive:Get(), lim)
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
			job.hide_swaps = 0
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
		job.info.eta = (s_pred - meet_s) / creep_speed
		job.info.spot = nil
		if not dove and lim.first then
			if meet_s >= lim.first then
				job.info.spot = "meet behind tower"
			elseif lim.edge and meet_s >= lim.edge - K.EDGE_BAND then
				job.info.spot = "meet at tower edge"
			end
		end
		target = hide_target(ctx, lane, meet, meet_s, s_pred) or meet
		job.info.hidden = target ~= meet
	else
		meet = job.cursor
		target = job.cursor
	end

	local found = detect_wave(lane, { ctx.u_pos, meet }, job.skipped, lim.gate)
	if found and not wave_catchable(ctx, found) then
		skip_wave(found)
		note("won't make it before our creeps, going for the next wave")
		return
	end
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

	local dodge = dodge_point(ctx, lane)
	job.info.dodge = dodge ~= nil
	target = safe_point(dodge or flank_target(ctx, lane, target))
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
	local toward = (v.x * ux + v.y * uy) / ul
	if toward >= K.FOLLOW_SPEED then return true end
	if not job.aggro[m.idx] then return false end
	local speed = math.sqrt(v.x * v.x + v.y * v.y)
	return speed >= K.FOLLOW_MOVE and toward >= speed * K.FOLLOW_AWAY
end

local function stair_point(ctx, chaser, ahead)
	local pts = {}
	local nav = job.nav
	if ahead then
		pts = ahead
	elseif nav and nav.path and nav.i <= #nav.path then
		for k = nav.i, #nav.path do pts[#pts + 1] = nav.path[k] end
	elseif job.info.target then
		pts[1] = job.info.target
	end
	local base = World.GetGroundZ(ctx.u_pos:GetX(), ctx.u_pos:GetY()) or ctx.u_pos:GetZ()
	local rise, top_z, top_at = nil, nil, nil
	local route = { ctx.u_pos:Clone() }
	local prev, walked = ctx.u_pos, 0.0
	for i = 1, #pts do
		local seg = prev:Distance2D(pts[i])
		local steps = math.max(1, math.ceil(seg / K.HG_STEP))
		for k = 1, steps do
			local at = walked + seg * k / steps
			if top_at and at > top_at + K.CLIMB_TAIL then return rise, route, top_z end
			if not top_at and at > K.HG_LOOK then return nil end
			local p = prev:Lerp(pts[i], k / steps)
			local z = World.GetGroundZ(p:GetX(), p:GetY())
			if z then
				local q = Vector(p:GetX(), p:GetY(), z)
				route[#route + 1] = q
				if not rise and z >= base + K.STAIR_RISE then rise = q end
				if not top_at and z >= base + K.HG_DZ then top_z, top_at = z, at end
			end
		end
		walked = walked + seg
		prev = pts[i]
	end
	if top_at then return rise, route, top_z end
	return nil
end

local function route_ahead(route, pos, dist)
	local best, best_d = 1, math.huge
	for i = 1, #route do
		local d = route[i]:Distance2D(pos)
		if d < best_d then best, best_d = i, d end
	end
	local left, prev = dist, pos
	for i = best + 1, #route do
		local seg = prev:Distance2D(route[i])
		if seg >= left then return prev:Lerp(route[i], left / seg) end
		left = left - seg
		prev = route[i]
	end
	return route[#route]
end

local function update_stair(ctx, chaser, now, ahead)
	local st = job.stair
	if st then
		if chaser.pos:GetZ() >= st.top_z - K.STAIR_RISE or now - st.t > K.CLIMB_MAX then
			job.stair = nil
			job.stair_t = now
			return nil
		end
		return st
	end
	if now - (job.stair_t or -100.0) < K.STAIR_COOLDOWN then return nil end
	local p, route, top_z = stair_point(ctx, chaser, ahead)
	if not p then return nil end
	job.stair = { pos = p, route = route, top_z = top_z, go = false, t = now }
	note("stopping on the stairs for the pack")
	return job.stair
end

local function ally_threat(ctx, chaser, radius)
	if not chaser then return nil end
	local best, best_d = nil, radius
	for i = 1, #allied_now do
		local a = allied_now[i]
		local d = a.pos:Distance2D(chaser.pos)
		if d < best_d then best, best_d = a, d end
	end
	if not best then return nil end
	local sx, sy, n = 0.0, 0.0, 0
	for i = 1, #allied_now do
		local p = allied_now[i].pos
		if p:Distance2D(best.pos) <= K.ALLY_CLUSTER then
			sx, sy, n = sx + p:GetX(), sy + p:GetY(), n + 1
		end
	end
	local center = Vector(sx / n, sy / n, best.pos:GetZ())
	local hero_d = center:Distance2D(ctx.hero_pos)
	if hero_d <= K.ALLY_HERO_NEAR or hero_d < ctx.u_pos:Distance2D(ctx.hero_pos) * 0.5 then return nil end
	return center
end

local function evade_point(ctx, threat)
	local ux, uy = ctx.u_pos:GetX(), ctx.u_pos:GetY()
	local ax, ay = ux - threat:GetX(), uy - threat:GetY()
	local al = math.sqrt(ax * ax + ay * ay)
	if al < 1.0 then ax, ay, al = 1.0, 0.0, 1.0 end
	ax, ay = ax / al, ay / al
	local hx, hy = ctx.hero_pos:GetX() - ux, ctx.hero_pos:GetY() - uy
	local px, py = -ay, ax
	if px * hx + py * hy < 0 then px, py = -px, -py end
	for _, sign in ipairs({ 1, -1 }) do
		local vx, vy = ax + px * sign, ay + py * sign
		local vl = math.sqrt(vx * vx + vy * vy)
		local p = Vector(ux + vx / vl * K.EVADE_STEP, uy + vy / vl * K.EVADE_STEP, ctx.u_pos:GetZ())
		if walkable(p) and not in_danger(p) then return p end
	end
	return walkable_near(Vector(ux + ax * K.EVADE_STEP, uy + ay * K.EVADE_STEP, ctx.u_pos:GetZ()), ctx.u_pos)
end

local function step_lead(ctx)
	local now = ctx.now
	local w = job.wave
	local visible = refresh_wave(w, now)
	local pack = {}
	for i = 1, #visible do
		if visible[i].pos:Distance2D(ctx.u_pos) <= K.PACK_RANGE then pack[#pack + 1] = visible[i] end
	end
	if #visible == 0 and next(w.banned) then return abort("the pack ran into our creeps") end
	local chaser, gap = nearest(pack, ctx.u_pos)
	job.info.gap = chaser and gap or nil
	job.info.pack = #pack

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

	local trail_pos, trail_pts = nil, nil
	local hero_mid = false
	if job.lane then
		local _, perp_h = lane_project(job.lane, ctx.hero_pos)
		hero_mid = perp_h <= K.MID_BAND
	end
	if job.flanked and hero_mid then trail_pos, trail_pts = trail_ahead(ctx) end
	local stair = update_stair(ctx, chaser, now, trail_pts)
	local hg = ctx.u_pos:GetZ() - chaser.pos:GetZ() >= K.HG_DZ
		or ctx.hero_pos:GetZ() - chaser.pos:GetZ() >= K.HG_DZ
		or stair ~= nil
	job.info.hg = hg
	job.info.stair = stair and (stair.go and "climbing slowly" or "on the stairs") or nil
	local drop = hg and K.STRAGGLER_DROP_HG or K.STRAGGLER_DROP
	local reach = hg and K.STRAGGLER_HG_REACH or K.STRAGGLER_REACH

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
		if stuck_for > drop
			or (stuck_for > K.STUCK_TIME and allied_near(m.pos, K.ENGAGE_RADIUS)) then
			w.members[m.idx] = nil
			w.banned[m.idx] = true
			follow[m.idx] = nil
			note("one creep got lost, bringing the rest")
		elseif stuck_for > K.STUCK_TIME then
			if d < straggler_d and d <= reach and (job.dive or not in_danger(m.pos)) then
				straggler, straggler_d = m, d
			end
		elseif d > tail_d then
			tail_d = d
		end
	end

	local may_evade = not trail_pos and not stair and not (job.flank and job.flank.route)
	local radius = job.evading and K.ALLY_ALERT + K.ALLY_ALERT_HYST or K.ALLY_ALERT
	local threat = may_evade and ally_threat(ctx, chaser, radius) or nil
	if not threat and may_evade and job.evading and now - job.evade_t < K.EVADE_MIN then
		threat = job.evade_center
	end
	job.info.evade = threat ~= nil
	if threat and not job.evading then
		job.evading = true
		job.evade_t = now
		job.nav = nil
		note("our creeps are coming, turning away")
	elseif not threat and job.evading then
		job.evading = false
		job.nav = nil
	end
	job.evade_center = threat

	if straggler and not threat then
		job.waiting = false
		job.lead_t = now
		job.info.target = straggler.pos
		return issue("attack", nil, straggler.ent)
	end

	local shooting = now - (job.shot_at or -100.0) < K.SHOT_MEMORY
	local above = ctx.u_pos:GetZ() - chaser.pos:GetZ() >= K.HG_DZ
	if above and not stair and not threat and not shooting then
		job.above_since = job.above_since or now
		if now - job.above_since < K.HG_HOLD then
			job.waiting = false
			job.lead_t = now
			return issue("hold")
		end
	elseif not above then
		job.above_since = nil
	end

	if stair and not threat then
		job.waiting = false
		job.lead_t = now
		local close = gap <= K.CLIMB_GAP or shooting
		if not stair.go and close then
			stair.go = true
			note("the pack's on the stairs, going up slowly")
		end
		if not stair.go then
			job.info.target = stair.pos
			return issue("move", stair.pos, nil, true)
		end
		if not close then return issue("hold") end
		local step = route_ahead(stair.route, ctx.u_pos, K.CLIMB_STEP)
		if step:Distance2D(ctx.u_pos) > K.ARRIVE_EPS then
			job.info.target = step
			return issue("move", step, nil, true)
		end
		job.stair = nil
		job.stair_t = now
		stair = nil
	end

	local gap_max = ui.gap:Get()
	if hg then gap_max = math.min(gap_max, K.HG_GAP) end
	local span = math.max(gap, tail_d - K.PACK_SPREAD)

	local unseen = gap > K.SIGHT_KEEP and sight_blocked(chaser.pos, ctx.u_pos)
	if unseen then
		job.unseen_since = job.unseen_since or now
		if now - job.unseen_since > K.UNSEEN_WAIT then unseen = false end
	else
		job.unseen_since = nil
	end
	job.info.unseen = unseen

	local resume = gap_max - math.min(K.GAP_HYST, gap_max * 0.4)
	local can_flip = now - (job.pace_t or -100.0) >= K.PACE_MIN
	if job.waiting then
		if can_flip and ((span < resume and not unseen) or shooting) then
			job.waiting = false
			job.pace_t = now
		end
	elseif can_flip and (span > gap_max or unseen) and not shooting then
		job.waiting = true
		job.pace_t = now
	end

	if job.waiting then
		job.lead_t = now
		return issue("hold")
	end

	local target
	if threat then
		job.lead_t = now
		target = evade_point(ctx, threat)
	else
		local d_hero = ctx.u_pos:Distance2D(ctx.hero_pos)
		if not job.lead_best or d_hero < job.lead_best - K.STALL_PROGRESS then
			job.lead_best = d_hero
			job.lead_t = now
		end
		target = ctx.hero_pos:Extend2D(chaser.pos, K.LEAD_SHORT)
		local stalled = now - (job.lead_t or now) > K.LEAD_STALL and d_hero > K.LEAD_SHORT * 2
		if not walkable(target) or stalled then
			target = ctx.hero_pos
		end
		target = trail_pos or flank_target(ctx, job.lane, target)
	end
	target = safe_point(target)
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
	if ui.avoid:Get() then
		local near = Entity.GetHeroesInRadius(u, ui.avoid_radius:Get() * K.HERO_ABORT, TEAM_ENEMY, true, true)
		if near and #near > 0 then return "enemy hero around" end
	end
	return nil
end

local function tower_on_me(ctx)
	if job.dive then return nil end
	for i = 1, #danger_towers do
		local t = danger_towers[i]
		if t.pos:Distance2D(ctx.u_pos) <= t.r + K.TOWER_WATCH then
			local target = Tower.GetAttackTarget(t.ent)
			if target and Entity.GetIndex(target) == job.idx then return t end
		end
	end
	return nil
end

local function escape_tower(ctx, tower)
	if not job.escaping then
		job.escaping = true
		job.nav = nil
		note("the tower's hitting it, stepping out")
	end
	local cx, cy = tower.pos:GetX(), tower.pos:GetY()
	local radial = tower.pos:Extend2D(ctx.u_pos, tower.r + K.TOWER_WATCH + K.ARRIVE_EPS)
	local dx, dy = radial:GetX() - cx, radial:GetY() - cy
	local out = radial
	for _, deg in ipairs({ 0, 30, -30, 60, -60 }) do
		local a = math.rad(deg)
		local c, s = math.cos(a), math.sin(a)
		local q = Vector(cx + dx * c - dy * s, cy + dx * s + dy * c, radial:GetZ())
		if walkable(q) and not in_danger(q) then
			out = q
			break
		end
	end
	job.info.target = out
	issue("move", out, nil, true)
end

local function process()
	local hero = Heroes.GetLocal()
	if not hero then return end
	local now = GameRules.GetGameTime()
	refresh_world(hero, now)
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
	local order = job.order
	if order and order.kind == "move" and order.gx and not NPC.IsRunning(u)
		and now - order.t > K.STUCK_ORDER
		and dist_xy(ctx.u_pos:GetX(), ctx.u_pos:GetY(), order.gx, order.gy) > K.STUCK_FAR then
		job.stuck_since = job.stuck_since or now
		if now - job.stuck_since > K.STUCK_UNIT then
			job.stuck_since = nil
			job.nav = nil
			job.order = nil
			local fl = job.flank
			if fl and fl.route and fl.i <= #fl.route then
				fl.i = fl.i + 1
			elseif fl and fl.pos then
				fl.done = true
			end
			note("stuck, trying another way")
		end
	else
		job.stuck_since = nil
	end
	track_aggro(now, ctx.u_pos)
	if not job.led and (job.state == "search" or job.state == "approach" or job.state == "hook") then
		record_trail(ctx.u_pos)
	end

	if ACTIVE[job.state] then
		if job.state ~= "search" and now - job.started > K.JOB_MAX then
			return abort("took way too long")
		end
		local why = safety_reason(u, ctx)
		if why then return abort(why) end
		local tower = tower_on_me(ctx)
		if tower then return escape_tower(ctx, tower) end
	end
	if job.escaping then
		job.escaping = false
		job.nav = nil
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
			local lane = nearest_lane(wave_center(members), K.LANE_BAND)
			local open = not lane or past_gate(lane, members, lane_limits(lane).gate)
			if open and front.pos:Distance2D(hero_pos) > K.MIN_PULL_DIST then
				local _, d = nearest(members, anchor)
				if d < best_d then best_d, chosen = d, members end
			end
		end
	end
	if lanes then
		for i = 1, #lanes do
			local lane = lanes[i]
			local t0, _, s = plan_meet(lane, u_pos, u_speed, hero_pos, nil, nil, nil, false, ui.dive:Get(),
				lane_limits(lane))
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
		skipped = {},
		trail = { Entity.GetAbsOrigin(unit):Clone() },
		aggro = {},
		icon = (unit_kind(unit) or {}).icon,
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
		local now = GameRules.GetGameTime()
		job.hit_at = now
		job.aggro[Entity.GetIndex(source)] = now
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

do
	local COLORS = {
		text = Color(235, 235, 235, 255),
		dim = Color(175, 175, 175, 220),
		lane = Color(255, 255, 255, 60),
		pred = Color(255, 165, 60, 255),
		meet = Color(255, 225, 90, 255),
		target = Color(110, 220, 140, 255),
		front = Color(240, 90, 80, 255),
		avoid = Color(240, 90, 80, 90),
		band = Color(120, 180, 255, 110),
	}

	local function draw_ring(circle)
		local cx, cy, z = circle.pos:GetX(), circle.pos:GetY(), circle.pos:GetZ()
		local prev_s, prev_v = nil, false
		for i = 0, 32 do
			local a = i / 32 * math.pi * 2
			local s, v = Render.WorldToScreen(Vector(cx + math.cos(a) * circle.r, cy + math.sin(a) * circle.r, z))
			if prev_s and v and prev_v then
				Render.Line(prev_s, s, COLORS.avoid, 1.0)
			end
			prev_s, prev_v = s, v
		end
	end

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

	local function draw_band(lane, width)
		local pts = lane.samples
		for _, sign in ipairs({ 1, -1 }) do
			local prev_s, prev_v = nil, false
			for i = 1, #pts do
				local a, b = pts[math.max(1, i - 1)], pts[math.min(#pts, i + 1)]
				local dx, dy = b:GetX() - a:GetX(), b:GetY() - a:GetY()
				local l = math.sqrt(dx * dx + dy * dy)
				if l > 0 then
					local x = pts[i]:GetX() - dy / l * width * sign
					local y = pts[i]:GetY() + dx / l * width * sign
					local s, v = Render.WorldToScreen(Vector(x, y, World.GetGroundZ(x, y) or pts[i]:GetZ()))
					if prev_s and v and prev_v then Render.Line(prev_s, s, COLORS.band, 1.5) end
					prev_s, prev_v = s, v
				end
			end
		end
	end

	local PANEL = {
		wait = { 232, 178, 74 },
		move = { 143, 183, 255 },
		lead = { 64, 214, 108 },
		stop = { 226, 52, 52 },
		idle = { 170, 170, 180 },
	}

	local ROUND_ALL = Enum.DrawFlags.RoundCornersAll

	local function panel_icon(path, plain)
		if not path then return nil end
		local entry = panel_icons[path]
		if entry == nil then
			local handle = Render.LoadImage(path)
			entry = handle and { handle = handle } or false
			panel_icons[path] = entry
		end
		if not entry then return nil end
		if not entry.uv0 then
			local size = Render.ImageSize(entry.handle)
			if not size or size.x <= 0 or size.y <= 0 then return nil end
			local u0, v0, u1, v1 = 0.0, 0.0, 1.0, 1.0
			if size.x > size.y then
				local d = (1.0 - size.y / size.x) / 2
				u0, u1 = d, 1.0 - d
			elseif size.y > size.x then
				local d = (1.0 - size.x / size.y) / 2
				v0, v1 = d, 1.0 - d
			end
			local zoom = plain and 0.0 or K.PANEL_ICON_ZOOM
			local zu, zv = (u1 - u0) * zoom, (v1 - v0) * zoom
			entry.uv0 = Vec2(u0 + zu, v0 + zv)
			entry.uv1 = Vec2(u1 - zu, v1 - zv)
		end
		return entry
	end

	local function creeps_text(n)
		local m10, m100 = n % 10, n % 100
		local form = "lp_st_creep5"
		if m10 == 1 and m100 ~= 11 then
			form = "lp_st_creep1"
		elseif m10 >= 2 and m10 <= 4 and (m100 < 12 or m100 > 14) then
			form = "lp_st_creep2"
		end
		return n .. " " .. localization.Get(form)
	end

	local function lane_label(name)
		return name and localization.Get("lp_lane_" .. name) or nil
	end

	local function timer_text(seconds)
		local s = math.max(0, math.floor(seconds + 0.5))
		return string.format("%d:%02d", math.floor(s / 60), s % 60)
	end

	local function preview_icon()
		local enabled = ui.units:ListEnabled()
		local id = enabled and enabled[1] or UNIT_KINDS[1].id
		for i = 1, #UNIT_KINDS do
			if UNIT_KINDS[i].id == id then return UNIT_KINDS[i].icon end
		end
		return UNIT_KINDS[1].icon
	end

	local function panel_content(now, in_game)
		local T = localization.Get
		if in_game and job then
			local st, info = job.state, job.info
			local lane = lane_label(job.lane and job.lane.name)
			if st == "search" then
				local eta = info.eta and timer_text(info.eta) or nil
				return job.icon, PANEL.wait, string.format(T("lp_st_wait"), clock_text(info.batch or 0)), lane, eta
			elseif st == "approach" or st == "hook" then
				local dist = nil
				if info.front and NPCs.Contains(job.unit) then
					dist = tostring(math.floor(Entity.GetAbsOrigin(job.unit):Distance2D(info.front)))
				end
				return job.icon, PANEL.move, T(st == "hook" and "lp_st_hook" or "lp_st_approach"), lane, dist
			elseif st == "lead" then
				return job.icon, PANEL.lead, T("lp_st_lead"), lane, info.pack and creeps_text(info.pack) or nil
			elseif st == "deliver" then
				return job.icon, PANEL.lead, T("lp_st_deliver"), lane, nil
			end
			return job.icon, PANEL.stop, T("lp_st_return"), nil, nil
		end
		if in_game and last_result and now - last_result.t < K.PANEL_LINGER then
			local ok = last_result.ok
			return last_result.icon, ok and PANEL.lead or PANEL.stop, T(ok and "lp_st_done" or "lp_st_cancel"),
				lane_label(last_result.lane), nil
		end
		local hero = in_game and Heroes.GetLocal()
		local name = hero and NPC.GetUnitName(hero)
		if name then
			return string.format(K.HERO_ICON, name), PANEL.idle, T("lp_st_idle"), nil, nil, true
		end
		return preview_icon(), PANEL.idle, T("lp_st_idle"), nil, nil
	end

	local function ease_out(t)
		return 1 - (1 - t) ^ 3
	end

	local function approach(current, target, dt, speed)
		return current + (target - current) * (1 - math.exp(-dt * speed))
	end

	local function draw_panel(in_game)
		local an = panel_anim
		local dt = math.max(0.0, math.min(0.1, GlobalVars.GetAbsFrameTime() or 0.016))

		local shown = false
		if ui.panel:Get() then
			local icon_path, rgb, title, lane, value, plain = panel_content(in_game and GameRules.GetGameTime() or 0.0, in_game)
			if title then
				shown = true
				if an.title ~= title then
					an.title = title
					an.text_t = 0.0
				end
				an.last = { icon = icon_path, rgb = rgb, title = title, lane = lane, value = value, plain = plain }
			end
		end
		if shown then
			an.vis = math.min(1.0, an.vis + dt / K.PANEL_FADE)
		else
			an.vis = math.max(0.0, an.vis - dt / K.PANEL_FADE)
		end
		if an.vis <= 0 or not an.last then
			an.w, an.rgb, an.title = nil, nil, nil
			return
		end
		an.text_t = math.min(1.0, an.text_t + dt / K.PANEL_TEXT_FADE)

		local last = an.last
		if not panel_fonts then
			local flags = Enum.FontCreate.FONTFLAG_ANTIALIAS
			panel_fonts = {
				semi = Render.LoadFont("Segoe UI", flags, Enum.FontWeight.SEMIBOLD),
				regular = Render.LoadFont("Segoe UI", flags, Enum.FontWeight.NORMAL),
			}
		end

		local scale = ui.panel_scale:Get() / 100
		local h = math.floor(K.PANEL_HEIGHT * scale + 0.5)
		local s = math.floor(K.PANEL_ICON * scale + 0.5)
		local size = math.floor(K.PANEL_FONT * scale + 0.5)
		local small = math.floor(K.PANEL_FONT_SMALL * scale + 0.5)
		local gap = K.PANEL_GAP * scale
		local pair = K.PANEL_PAIR_GAP * scale

		local shape = ui.panel_icon:Get()
		local icon = shape ~= 2 and panel_icon(last.icon, last.plain) or nil
		local radius = shape == 0 and K.PANEL_CORNER * scale or h / 2
		local icon_r = shape == 0 and K.PANEL_ICON_CORNER * scale or s / 2
		local inset = (h - s) / 2

		local title_size = Render.TextSize(panel_fonts.semi, size, last.title)
		local lane_size = last.lane and Render.TextSize(panel_fonts.regular, small, last.lane) or nil
		local value_size = last.value and Render.TextSize(panel_fonts.semi, size, last.value) or nil
		local has_right = lane_size ~= nil or value_size ~= nil

		local lead = icon and (inset + s + gap) or K.PANEL_PAD_RIGHT * scale
		local target_w = lead + title_size.x + K.PANEL_PAD_RIGHT * scale
		if has_right then
			target_w = target_w + gap + 1 + gap
				+ (lane_size and lane_size.x or 0)
				+ ((lane_size and value_size) and pair or 0)
				+ (value_size and value_size.x or 0)
		end
		an.w = an.w and approach(an.w, target_w, dt, K.PANEL_WIDTH_SPEED) or target_w
		if an.rgb then
			for i = 1, 3 do an.rgb[i] = approach(an.rgb[i], last.rgb[i], dt, K.PANEL_COLOR_SPEED) end
		else
			an.rgb = { last.rgb[1], last.rgb[2], last.rgb[3] }
		end

		local e = ease_out(an.vis)
		local w = math.floor(an.w + 0.5)
		local screen = Render.ScreenSize()
		local x = math.floor(screen.x * ui.panel_x:Get() / 100 - w / 2)
		x = math.max(4, math.min(screen.x - w - 4, x))
		local y = math.floor(ui.panel_y:Get() - (1 - e) * K.PANEL_SLIDE * scale + 0.5)
		local a, b = Vec2(x, y), Vec2(x + w, y + h)

		local function faded(value)
			return math.floor(value * e + 0.5)
		end
		local t = ease_out(an.text_t)

		if ui.panel_blur:Get() then
			Render.Blur(a, b, 1.0, e, radius, ROUND_ALL)
		end
		Render.FilledRect(a, b, Color(14, 14, 18, faded(255 * ui.panel_alpha:Get() / 100)), radius, ROUND_ALL)

		if icon then
			local ia = Vec2(x + inset, y + inset)
			local ib = Vec2(x + inset + s, y + inset + s)
			Render.Image(icon.handle, ia, Vec2(s, s), Color(255, 255, 255, faded(255)),
				icon_r, ROUND_ALL, icon.uv0, icon.uv1)
			if not last.plain then
				local edge = Color(255, 255, 255, faded(K.PANEL_ICON_EDGE))
				Render.OutlineGradient(ia, ib, edge, edge, edge, edge, icon_r, ROUND_ALL, 1)
			end
		end

		Render.PushClip(a, b)
		local cx = x + lead
		local ty = y + math.floor((h - title_size.y) / 2)
		Render.Text(panel_fonts.semi, size, last.title, Vec2(cx, ty), Color(236, 236, 238, faded(255 * t)))
		cx = cx + title_size.x

		if has_right then
			cx = cx + gap
			local line_h = K.PANEL_DIVIDER * scale
			local ly = y + (h - line_h) / 2
			Render.FilledRect(Vec2(cx, ly), Vec2(cx + 1, ly + line_h), Color(255, 255, 255, faded(K.PANEL_DIVIDER_ALPHA)))
			cx = cx + 1 + gap
			if lane_size then
				local lane_y = ty + title_size.y - lane_size.y
				Render.Text(panel_fonts.regular, small, last.lane, Vec2(cx, lane_y), Color(154, 154, 162, faded(255 * t)))
				cx = cx + lane_size.x + (value_size and pair or 0)
			end
			if value_size then
				local rgb = an.rgb
				local color = Color(math.floor(rgb[1] + 0.5), math.floor(rgb[2] + 0.5), math.floor(rgb[3] + 0.5), faded(255 * t))
				Render.Text(panel_fonts.semi, size, last.value, Vec2(cx, ty), color)
			end
		end
		Render.PopClip()
	end

	function script.OnFrame()
		if not ui.enable:Get() then return end
		local in_game = Engine.IsInGame()
		if not in_game and ui.panel_match:Get() then return end
		local ok, err = pcall(draw_panel, in_game)
		if not ok and err ~= panel_error then
			panel_error = err
			Log.Write("[Lane Pull] status bar: " .. tostring(err))
		end
	end

	function script.OnDraw()
		if not ui.enable:Get() then return end
		if not Engine.IsInGame() or not ui.debug:Get() then return end

		if not debug_font then
			debug_font = Render.LoadFont("Verdana", Enum.FontCreate.FONTFLAG_ANTIALIAS, 500)
		end

		local clock = game_clock()
		local header = string.format("Lane Pull | %s | speed %.0f | spawn in %.0fs | lanes %d",
			job and job.state or "idle",
			creep_speed,
			K.SPAWN_PERIOD - (clock % K.SPAWN_PERIOD),
			lanes and #lanes or 0)
		local hero = Heroes.GetLocal()
		if hero and lanes then
			for i = 1, #lanes do
				if lanes[i].name == "mid" then
					local _, perp = lane_project(lanes[i], Entity.GetAbsOrigin(hero))
					header = header .. (perp <= K.MID_BAND and " | you're near mid" or " | you're away from mid")
				end
			end
		end
		Render.Text(debug_font, 15, header, Vec2(40, 280), COLORS.text)
		if last_msg and GameRules.GetGameTime() - last_msg_t < K.MSG_TIME then
			Render.Text(debug_font, 14, last_msg, Vec2(40, 300), COLORS.dim)
		end

		if lanes then
			for i = 1, #lanes do
				draw_lane(lanes[i])
				if lanes[i].name == "mid" then draw_band(lanes[i], K.MID_BAND) end
			end
		end

		if not job then return end
		local info = job.info
		draw_marker(info.pred, COLORS.pred, "spawn")
		draw_marker(info.meet, COLORS.meet, "meet")
		draw_marker(info.front, COLORS.front, "F")
		draw_marker(info.target, COLORS.target, job.state)
		draw_marker(info.flank, COLORS.meet, "side")
		if job.flank and job.flank.route then
			for k = 1, #job.flank.route do draw_marker(job.flank.route[k], COLORS.dim, "stairs " .. k) end
		end

		if job.nav and job.nav.circles then
			for i = 1, #job.nav.circles do draw_ring(job.nav.circles[i]) end
		end

		if job.nav and #job.nav.path > 0 then
			local path = job.nav.path
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
				if job.state == "search" and info.spot then text = text .. " | " .. info.spot end
				if job.state == "search" and info.dodge then text = text .. " | dodge" end
				if job.escaping then text = text .. " | out of tower" end
				if job.state == "lead" and info.evade then text = text .. " | evade" end
				if job.state == "lead" and info.unseen then text = text .. " | out of sight" end
				if job.state == "lead" and info.stair then
					text = text .. " | " .. info.stair
				elseif job.state == "lead" and info.hg then
					text = text .. " | high ground"
				end
				if info.gap then text = text .. string.format(" | gap %.0f", info.gap) end
				if job.retries > 0 then text = text .. " | retry " .. job.retries end
				Render.Text(debug_font, 14, text, Vec2(s.x - 40, s.y - 50), COLORS.target)
			end
		end
	end
end

function script.OnGameEnd()
	job = nil
	last_result = nil
	next_run = 0.0
	next_struct_scan = 0.0
	lanes = nil
	lanes_version = -1
	lanes_radiant = nil
	creep_speed = K.DEFAULT_CREEP_SPEED
	speed_track = {}
	next_speed_sample = 0.0
	enemy_now, enemy_by_idx, allied_now, danger_towers, enemy_heroes = {}, {}, {}, {}, {}
	creep_sight = { near = K.CREEP_SIGHT, far = K.CREEP_SIGHT }
	memo.seen, memo.crossing = {}, nil
end

return script
