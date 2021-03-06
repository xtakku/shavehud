if string.lower(RequiredScript) == "lib/units/beings/player/states/playerstandard" then
	if ShaveHUD:getSetting({"Fixes", "RELOAD_SPEED_BOOST"}, true) then
		local reload_fix_start_action_reload_enter = PlayerStandard._start_action_reload_enter
		function PlayerStandard:_start_action_reload_enter(t, ...)
			local weapon = self._equipped_unit:base()
			if weapon and weapon._current_reload_speed_multiplier and weapon:can_reload() then
				weapon._current_reload_speed_multiplier = nil
			end
			reload_fix_start_action_reload_enter(self, t, ...)
		end
	end

	if ShaveHUD:getSetting({"Fixes", "SHOTGUN_RELOAD"}, true) then
		function PlayerStandard:_interupt_action_reload(t)
			if alive(self._equipped_unit) then
				self._equipped_unit:base():check_bullet_objects()
			end
		
			if self:_is_reloading() then
				self._equipped_unit:base():tweak_data_anim_stop("reload_enter")
				self._equipped_unit:base():tweak_data_anim_stop("reload")
				self._equipped_unit:base():tweak_data_anim_stop("reload_not_empty")
				self._equipped_unit:base():tweak_data_anim_stop("reload_exit")
			end
		
			self._state_data.reload_enter_expire_t = nil
			self._state_data.reload_expire_t = nil
			self._state_data.reload_exit_expire_t = nil
			--The fix is literally just this line right here
			self._queue_reload_interupt = nil
		
			managers.player:remove_property("shock_and_awe_reload_multiplier")
			self:send_reload_interupt()
		end
	end

	if ShaveHUD:getSetting({"Fixes", "ABILITY_USE"}, true) then
		local _update_check_actions = PlayerStandard._update_check_actions
	
		local function nop() end
	
		function PlayerStandard:_update_check_actions(t, dt, paused)
			local projectile_entry = managers.blackmarket:equipped_projectile()
			local projectile_tweak = tweak_data.blackmarket.projectiles[projectile_entry]
	
			if projectile_tweak.ability then
				local _check_action_use_ability = PlayerStandard._check_action_use_ability
				local getInput = PlayerStandard._get_input
				local input = self:_get_input(t, dt, paused)
	
				PlayerStandard._get_input = function(t, dt, paused)
					return input
				end
	
				self:_check_action_use_ability(t, input)
				PlayerStandard._check_action_use_ability = nop
				_update_check_actions(self, t, dt, paused)
				PlayerStandard._check_action_use_ability = _check_action_use_ability
				PlayerStandard._get_input = getInput
			else
				_update_check_actions(self, t, dt, paused)
			end
		end
	end

	PlayerStandard.NADE_TIMEOUT = ShaveHUD:getTweakEntry("STEALTH_NADE_TIMEOUT", "number", 0.25)		--Timeout for 2 NadeKey pushes, to prevent accidents in stealth

	local enter_original = PlayerStandard.enter
	local _update_interaction_timers_original = PlayerStandard._update_interaction_timers
	local _check_action_interact_original = PlayerStandard._check_action_interact
	local _start_action_reload_original = PlayerStandard._start_action_reload
	local _update_reload_timers_original = PlayerStandard._update_reload_timers
	local _interupt_action_reload_original = PlayerStandard._interupt_action_reload
	local _start_action_melee_original = PlayerStandard._start_action_melee
	local _update_melee_timers_original = PlayerStandard._update_melee_timers
	local _do_melee_damage_original = PlayerStandard._do_melee_damage
	local _check_action_throw_grenade_original = PlayerStandard._check_action_throw_grenade

	function PlayerStandard:_update_interaction_timers(t, ...)
		self:_check_interaction_locked(t)
		return _update_interaction_timers_original(self, t, ...)
	end

	function PlayerStandard:_check_action_interact(t, input, ...)
		if not self:_check_interact_toggle(t, input) then
			return _check_action_interact_original(self, t, input, ...)
		end
	end

	function PlayerStandard:_check_interaction_locked(t)
		PlayerStandard.LOCK_MODE = ShaveHUD:getSetting({"INTERACTION", "LOCK_MODE"}, 3)						--Lock interaction, if MIN_TIMER_DURATION is longer then total interaction time, or current interaction time
		PlayerStandard.MIN_TIMER_DURATION = ShaveHUD:getSetting({"INTERACTION", "MIN_TIMER_DURATION"}, 5)			--Min interaction duration (in seconds) for the toggle behavior to activate
		local is_locked = false
		if self._interact_params ~= nil then
			local tweak_data = self._interact_params.tweak_data or ""
			local total_timer = self._interact_params.timer or 0
			if PlayerStandard.LOCK_MODE >= 5 then
				is_locked = tweak_data == "corpse_alarm_pager"
			elseif PlayerStandard.LOCK_MODE >= 4 then
				is_locked = (tweak_data == "corpse_alarm_pager" or string.match(tweak_data, "pick_lock"))
			elseif PlayerStandard.LOCK_MODE >= 3 then
				is_locked = self._interact_params and (self._interact_params.timer >= PlayerStandard.MIN_TIMER_DURATION) -- lock interaction, when total timer time is longer then given time
			elseif PlayerStandard.LOCK_MODE >= 2 then
				is_locked = (total_timer  - self._interact_expire_t) >= PlayerStandard.MIN_TIMER_DURATION --lock interaction, when interacting longer then given time
			end
		end

		if self._interaction_locked ~= is_locked then
			managers.hud:set_interaction_bar_locked(is_locked, self._interact_params and self._interact_params.tweak_data or "")
			self._interaction_locked = is_locked
		end
	end

	function PlayerStandard:_check_interact_toggle(t, input)
		PlayerStandard.EQUIPMENT_PRESS_INTERRUPT = ShaveHUD:getSetting({"INTERACTION", "EQUIPMENT_PRESS_INTERRUPT"}, true) 	--Use the equipment key ('G') to toggle off active interactions
		local interrupt_key_press = input.btn_interact_press
		if PlayerStandard.EQUIPMENT_PRESS_INTERRUPT then
			interrupt_key_press = input.btn_use_item_press
		end

		if interrupt_key_press and self:_interacting() then
			self:_interupt_action_interact()
			return true
		elseif input.btn_interact_release and self._interact_params then
			if self._interaction_locked then
				return true
			end
		end
	end

	local hide_int_state = {
		["bleed_out"] = true,
		["fatal"] = true,
		["incapacitated"] = true,
		["arrested"] = true,
		["jerry1"] = true
	}
	function PlayerStandard:enter(...)
		enter_original(self, ...)
		if hide_int_state[managers.player:current_state()] and (self._state_data.show_reload or self._state_data.show_melee) then
			managers.hud:hide_interaction_bar(false)
			self._state_data.show_reload = false
			self._state_data.show_melee = false
		end
	end

	function PlayerStandard:_start_action_reload(t, ...)
		_start_action_reload_original(self, t, ...)
		PlayerStandard.SHOW_RELOAD = ShaveHUD:getSetting({"INTERACTION", "SHOW_RELOAD"}, false)
		if PlayerStandard.SHOW_RELOAD and not hide_int_state[managers.player:current_state()] then
			if self._equipped_unit and not self._equipped_unit:base():clip_full() then
				self._state_data.show_reload = true
				managers.hud:show_interaction_bar(0, self._state_data.reload_expire_t or 0)
				self._state_data.reload_offset = t
			end
		end
	end

	function PlayerStandard:_update_reload_timers(t, ...)
		_update_reload_timers_original(self, t, ...)
		if PlayerStandard.SHOW_RELOAD then
			if self._state_data.show_reload and hide_int_state[managers.player:current_state()] then
				managers.hud:hide_interaction_bar(false)
				self._state_data.show_reload = false
			elseif not self._state_data.reload_expire_t and self._state_data.show_reload then
				managers.hud:hide_interaction_bar(true)
				self._state_data.show_reload = false
			elseif self._state_data.show_reload then
				managers.hud:set_interaction_bar_width(	t and t - self._state_data.reload_offset or 0, self._state_data.reload_expire_t and self._state_data.reload_expire_t - self._state_data.reload_offset or 0 )
			end
		end
	end

	function PlayerStandard:_interupt_action_reload(...)
		local val = _interupt_action_reload_original(self, ...)
		if self._state_data.show_reload and PlayerStandard.SHOW_RELOAD then
			managers.hud:hide_interaction_bar(false)
			self._state_data.show_reload = false
		end
		return val
	end

	function PlayerStandard:_start_action_melee(t, input, instant, ...)
		local val = _start_action_melee_original(self, t, input, instant, ...)
		if not instant then
			PlayerStandard.SHOW_MELEE = ShaveHUD:getSetting({"INTERACTION", "SHOW_MELEE"}, false)
			if PlayerStandard.SHOW_MELEE and self._state_data.meleeing and not hide_int_state[managers.player:current_state()] then
				self._state_data.show_melee = true
				self._state_data.melee_charge_duration = tweak_data.blackmarket.melee_weapons[managers.blackmarket:equipped_melee_weapon()].stats.charge_time or 1
				managers.hud:show_interaction_bar(0, self._state_data.melee_charge_duration)
			end
		end
		return val
	end

	function PlayerStandard:_update_melee_timers(t, ...)
		local val = _update_melee_timers_original(self, t, ...)
		if PlayerStandard.SHOW_MELEE and self._state_data.meleeing and self._state_data.show_melee then
			local melee_lerp = self:_get_melee_charge_lerp_value(t)
			if hide_int_state[managers.player:current_state()] then
				managers.hud:hide_interaction_bar(false)
				self._state_data.show_melee = false
			elseif melee_lerp < 1 then
				managers.hud:set_interaction_bar_width(self._state_data.melee_charge_duration * melee_lerp, self._state_data.melee_charge_duration)
			elseif self._state_data.show_melee then
				managers.hud:hide_interaction_bar(true)
				self._state_data.show_melee = false
			end
		end
		return val
	end

	function PlayerStandard:_do_melee_damage(...)
		managers.hud:hide_interaction_bar(false)
		self._state_data.show_melee = false
		return _do_melee_damage_original(self, ...)
	end

	function PlayerStandard:_check_action_throw_grenade(t, input, ...)
		if input.btn_throw_grenade_press and ShaveHUD:getSetting({"INTERACTION", "SUPRESS_NADES_STEALTH"}, true) then
			if managers.groupai:state():whisper_mode() and (t - (self._last_grenade_t or 0) >= PlayerStandard.NADE_TIMEOUT) then
				self._last_grenade_t = t
				return
			end
		end

		return _check_action_throw_grenade_original(self, t, input, ...)
	end

elseif string.lower(RequiredScript) == "lib/units/beings/player/states/playercivilian" then

	local _update_interaction_timers_original = PlayerCivilian._update_interaction_timers
	local _check_action_interact_original = PlayerCivilian._check_action_interact

	function PlayerCivilian:_update_interaction_timers(t, ...)
		self:_check_interaction_locked(t)
		return _update_interaction_timers_original(self, t, ...)
	end

	function PlayerCivilian:_check_action_interact(t, input, ...)
		if not self:_check_interact_toggle(t, input) then
			return _check_action_interact_original(self, t, input, ...)
		end
	end

elseif string.lower(RequiredScript) == "lib/units/beings/player/states/playerdriving" then
	if ShaveHUD:getSetting({"Fixes", "ABILITY_USE"}, true) then
		local _update_check_actions_driver = PlayerDriving._update_check_actions_driver
	
		function PlayerDriving:_update_check_actions_driver(t, dt, input)
			local projectile_entry = managers.blackmarket:equipped_projectile()
			local projectile_tweak = tweak_data.blackmarket.projectiles[projectile_entry]
			
			_update_check_actions_driver(self, t, dt, input)
	
			if projectile_tweak.ability then
				self:_check_action_use_ability(t, input)
			end
		end
	end

	local _update_action_timers_original = PlayerDriving._update_action_timers
	local _start_action_exit_vehicle_original = PlayerDriving._start_action_exit_vehicle
	local _check_action_exit_vehicle_original = PlayerDriving._check_action_exit_vehicle

	function PlayerDriving:_update_action_timers(t, ...)
		self:_check_interaction_locked(t)
		return _update_action_timers_original(self, t, ...)
	end

	function PlayerDriving:_start_action_exit_vehicle(t)
		if not self:_interacting() then
			return _start_action_exit_vehicle_original(self, t)
		end
	end

	function PlayerDriving:_check_action_exit_vehicle(t, input, ...)
		if not self:_check_interact_toggle(t, input) then
			return _check_action_exit_vehicle_original(self, t, input, ...)
		end
	end

	function PlayerDriving:_check_interact_toggle(t, input)
		PlayerDriving.EQUIPMENT_PRESS_INTERRUPT = ShaveHUD:getSetting({"INTERACTION", "EQUIPMENT_PRESS_INTERRUPT"}, true) 	--Use the equipment key ('G') to toggle off active interactions
		local interrupt_key_press = input.btn_interact_press
		if PlayerDriving.EQUIPMENT_PRESS_INTERRUPT then
			interrupt_key_press = input.btn_use_item_press
		end
		if interrupt_key_press and self:_interacting() then
			self:_interupt_action_exit_vehicle()
			return true
		elseif input.btn_interact_release and self:_interacting() then
			if self._interaction_locked then
				return true
			end
		end
	end

	function PlayerDriving:_check_interaction_locked(t)
		PlayerDriving.LOCK_MODE = ShaveHUD:getSetting({"INTERACTION", "LOCK_MODE"}, 3)						--Lock interaction, if MIN_TIMER_DURATION is longer then total interaction time, or current interaction time
		PlayerDriving.MIN_TIMER_DURATION = ShaveHUD:getSetting({"INTERACTION", "MIN_TIMER_DURATION"}, 5)			--Min interaction duration (in seconds) for the toggle behavior to activate
		local is_locked = false
		if self._exit_vehicle_expire_t ~= nil then
			if PlayerDriving.LOCK_MODE == 3 then
				is_locked = (PlayerDriving.EXIT_VEHICLE_TIMER >= PlayerDriving.MIN_TIMER_DURATION) -- lock interaction, when total timer time is longer then given time
			elseif PlayerDriving.LOCK_MODE == 2 then
				is_locked = self._exit_vehicle_expire_t and (t - (self._exit_vehicle_expire_t - PlayerDriving.EXIT_VEHICLE_TIMER) >= PlayerDriving.MIN_TIMER_DURATION) --lock interaction, when interacting longer then given time
			end
		end

		if self._interaction_locked ~= is_locked then
			managers.hud:set_interaction_bar_locked(is_locked, "")
			self._interaction_locked = is_locked
		end
	end
elseif string.lower(RequiredScript) == "lib/units/beings/player/states/playercarry" then
	if not ShaveHUD:getSetting({"Misc", "NO_BAG_TILT"}, true) then
		return
	end
    
	PlayerCarry.target_tilt = 0 --original: -5
elseif string.lower(RequiredScript) == "lib/units/beings/player/states/playermaskoff" then
	if not ShaveHUD:getSetting({"INTERACTION", "PRESSTOMASKUP"}, true) then
		return
	end
	--PRESS ONCE TO MASK UP by hejoro (template script Toggle Interact by LazyOzzy)
    --Press your mask key only once to put it on (NOT instant mask up)
    if not _PlayerMaskOff__check_use_item then _PlayerMaskOff__check_use_item = PlayerMaskOff._check_use_item end
    function PlayerMaskOff:_check_use_item( t, input )
        if input.btn_use_item_press and self._start_standard_expire_t then
            self:_interupt_action_start_standard()
            return false
        elseif input.btn_use_item_release then
            return false
        end
        return _PlayerMaskOff__check_use_item(self, t, input)
    end
elseif string.lower(RequiredScript) == "lib/states/ingameparachuting" then
	if not ShaveHUD:getSetting({"EQUIPMENT", "AUTO_DISCARD_PARACHUTE"}, true) then
		return
	end
	
	local at_exit_actual = IngameParachuting.at_exit
	function IngameParachuting:at_exit(...)
		at_exit_actual(self, ...)

		local playermanager = managers.player
		if playermanager:get_my_carry_data() ~= nil then
			playermanager:drop_carry()
		end
	end
elseif string.lower(RequiredScript) == "lib/units/beings/player/states/playertased" then
	if not ShaveHUD:getSetting({"Fixes", "COUNTER_TASER"}, true) then
		return
	end

	Hooks:PostHook( PlayerTased, "on_tase_ended", "crash_prevent_1", function(self)
		self._tase_ended = true
	end)

	Hooks:PostHook( PlayerTased, "exit", "crash_prevent_2", function(self, state_data, enter_data)
		self._tase_ended = nil
	end)

	function PlayerTased:call_teammate(line, t, no_gesture, skip_alert)
		local voice_type, plural, prime_target = self:_get_unit_intimidation_action(true, false, false, true, false)
		local interact_type, queue_name
		if voice_type == "stop_cop" or voice_type == "mark_cop" then
			local prime_target_tweak = tweak_data.character[prime_target.unit:base()._tweak_table]
			local shout_sound = prime_target_tweak.priority_shout
			shout_sound = managers.groupai:state():whisper_mode() and prime_target_tweak.silent_priority_shout or shout_sound
			if shout_sound then
				interact_type = "cmd_point"
				queue_name = "s07x_sin"
				if managers.player:has_category_upgrade("player", "special_enemy_highlight") then
					prime_target.unit:contour():add(managers.player:get_contour_for_marked_enemy(), true, managers.player:upgrade_value("player", "mark_enemy_time_multiplier", 1))
				end
				if not self._tase_ended and managers.player:has_category_upgrade("player", "escape_taser") and prime_target.unit:key() == self._unit:character_damage():tase_data().attacker_unit:key() then
					self:_start_action_counter_tase(t, prime_target)
				end
			end
		end
		if interact_type then
			if not no_gesture then
			else
			end
			--self:_do_action_intimidate(t, interact_type or nil, queue_name, skip_alert)
		end
	end
elseif string.lower(RequiredScript) == "lib/managers/hudmanagerpd2" then
	function HUDManager:set_interaction_bar_locked(status, tweak_entry)
		self._hud_interaction:set_locked(status, tweak_entry)
	end

	if not ShaveHUD:getSetting({"SkipIt", "SKIP_BLACKSCREEN"}, true) then
		function HUDManager:set_blackscreen_skip_circle(current, total)
			IngameWaitingForPlayersState._skip_data = {total = 0, current = 1}
			managers.hud._hud_blackscreen:set_skip_circle(current, total)
		end
	end
elseif string.lower(RequiredScript) == "lib/managers/hud/hudinteraction" then
	local init_original 				= HUDInteraction.init
	local show_interaction_bar_original = HUDInteraction.show_interaction_bar
	local hide_interaction_bar_original = HUDInteraction.hide_interaction_bar
	local show_interact_original		= HUDInteraction.show_interact
	local destroy_original				= HUDInteraction.destroy

	local set_interaction_bar_width_original = HUDInteraction.set_interaction_bar_width

	function HUDInteraction:init(...)
		init_original(self, ...)

		local interact_text = self._hud_panel:child(self._child_name_text)
		local invalid_text = self._hud_panel:child(self._child_ivalid_name_text)
		self._original_circle_radius = self._circle_radius
		self._original_interact_text_font_size = interact_text:font_size()
		self._original_invalid_text_font_size = invalid_text:font_size()

		self:_rescale()
	end

	function HUDInteraction:set_interaction_bar_width(current, total)
		set_interaction_bar_width_original(self, current, total)

		if HUDInteraction.SHOW_TIME_REMAINING then
			local text = string.format("%.1fs", math.max(total - current, 0))
			self._interact_time:set_text(text)
			local perc = current/total
			local show = perc < 1
			local color = math.lerp(HUDInteraction.GRADIENT_COLOR_START, ShaveHUD:getColor(HUDInteraction.GRADIENT_COLOR_NAME, 0.4), perc)
			self._interact_time:set_color(color)
			self._interact_time:set_alpha(1)
			self._interact_time:set_visible(show)
		end
	end

	function HUDInteraction:show_interaction_bar(current, total)
		self:_rescale()
		if self._interact_circle_locked then
			self._interact_circle_locked:remove()
			self._interact_circle_locked = nil
		end

		local val = show_interaction_bar_original(self, current, total)

		HUDInteraction.SHOW_LOCK_INDICATOR = ShaveHUD:getSetting({"INTERACTION", "SHOW_LOCK_INDICATOR"}, true)
		HUDInteraction.SHOW_TIME_REMAINING = ShaveHUD:getSetting({"INTERACTION", "SHOW_TIME_REMAINING"}, true)
		HUDInteraction.SHOW_TIME_REMAINING_OUTLINE = ShaveHUD:getSetting({"INTERACTION", "SHOW_TIME_REMAINING_OUTLINE"}, false)
		HUDInteraction.SHOW_CIRCLE 	= ShaveHUD:getSetting({"INTERACTION", "SHOW_CIRCLE"}, true)
		HUDInteraction.LOCK_MODE = PlayerStandard.LOCK_MODE or 1
		HUDInteraction.GRADIENT_COLOR_NAME = ShaveHUD:getSetting({"INTERACTION", "GRADIENT_COLOR"}, "light_green")
		HUDInteraction.GRADIENT_COLOR_START = ShaveHUD:getColorSetting({"INTERACTION", "GRADIENT_COLOR_START"}, "white")
		if HUDInteraction.SHOW_CIRCLE then
			if HUDInteraction.LOCK_MODE > 1 and HUDInteraction.SHOW_LOCK_INDICATOR then
				self._interact_circle_locked = CircleBitmapGuiObject:new(self._hud_panel, {
					radius = self._circle_radius,
					color = self._old_text and Color.green or Color.red,
					blend_mode = "normal",
					alpha = 0.25,
				})
				self._interact_circle_locked:set_position(self._hud_panel:w() / 2 - self._circle_radius, self._hud_panel:h() / 2 - self._circle_radius)
				self._interact_circle_locked._circle:set_render_template(Idstring("Text"))
			end
		else
			HUDInteraction.SHOW_LOCK_INDICATOR = false
			self._interact_circle:set_visible(false)
		end

		if HUDInteraction.SHOW_TIME_REMAINING then
			local fontSize = 32 * (self._circle_scale or 1) * ShaveHUD:getSetting({"INTERACTION", "TIMER_SCALE"}, 1)
			if not self._interact_time then
				self._interact_time = OutlinedText:new(self._hud_panel, {
					name = "interaction_timer",
					visible = false,
					text = "",
					valign = "center",
					align = "center",
					layer = 2,
					color = HUDInteraction.GRADIENT_COLOR_START,
					font = tweak_data.menu.pd2_large_font,
					font_size = fontSize,
					h = 64
				})
			else
				self._interact_time:set_font_size(fontSize)
			end
			local text = string.format("%.1fs", total)
			self._interact_time:set_y(self._hud_panel:center_y() + self._circle_radius - (1.5 * self._interact_time:font_size()))
			self._interact_time:set_text(text)
			self._interact_time:set_outlines_visible(HUDInteraction.SHOW_TIME_REMAINING_OUTLINE)
			self._interact_time:show()
		end

		return val
	end

	function HUDInteraction:hide_interaction_bar(complete, ...)
		if self._interact_circle_locked then
			self._interact_circle_locked:remove()
			self._interact_circle_locked = nil
		end

		if self._interact_time then
			self._interact_time:set_text("")
			self._interact_time:set_visible(false)
		end

		if self._old_text then
			self._hud_panel:child(self._child_name_text):set_text(self._old_text or "")
			self._old_text = nil
		end

		if complete and HUDInteraction.SHOW_CIRCLE then
			local bitmap = self._hud_panel:bitmap({texture = "guis/textures/pd2/hud_progress_active", blend_mode = "add", align = "center", valign = "center", layer = 2, w = 2 * self._circle_radius, h = 2 * self._circle_radius})
			bitmap:set_position(bitmap:parent():w() / 2 - bitmap:w() / 2, bitmap:parent():h() / 2 - bitmap:h() / 2)
			local circle = CircleBitmapGuiObject:new(self._hud_panel, {radius = self._circle_radius, sides = 64, current = 64, total = 64, color = Color.white:with_alpha(1), blend_mode = "normal", layer = 3})
			circle:set_position(self._hud_panel:w() / 2 - self._circle_radius, self._hud_panel:h() / 2 - self._circle_radius)
			bitmap:animate(callback(self, self, "_animate_interaction_complete"), circle)
		end

		return hide_interaction_bar_original(self, false, ...)
	end

	function HUDInteraction:set_locked(status, tweak_entry)
		if self._interact_circle_locked then
			self._interact_circle_locked._circle:set_color(status and Color.green or Color.red)
		end

		if status then
			self._old_text = self._hud_panel:child(self._child_name_text):text()
			local locked_text = ""
			if ShaveHUD:getSetting({"INTERACTION", "SHOW_INTERRUPT_HINT"}, true) then
				local btn_cancel = PlayerStandard.EQUIPMENT_PRESS_INTERRUPT and (managers.localization:btn_macro("use_item", true) or managers.localization:get_default_macro("BTN_USE_ITEM")) or (managers.localization:btn_macro("interact", true) or managers.localization:get_default_macro("BTN_INTERACT"))
				locked_text = managers.localization:to_upper_text(tweak_entry == "corpse_alarm_pager" and "shavehud_int_locked_pager" or "shavehud_int_locked", {BTN_CANCEL = btn_cancel})
			end
			self._hud_panel:child(self._child_name_text):set_text(locked_text)
		end
	end

	function HUDInteraction:show_interact(data)
		self:_rescale()
		if not self._old_text then
			return show_interact_original(self, data)
		end
	end

	function HUDInteraction:destroy()
		if self._interact_time and self._hud_panel then
			self._interact_time:remove()
			self._interact_time = nil
		end
		if self._interact_time_bgs and self._hud_panel then
			for _, bg in pairs(self._interact_time_bgs) do
				self._hud_panel:remove(bg)
			end
			self._interact_time_bgs = nil
		end
		destroy_original(self)
	end

	function HUDInteraction:_rescale(circle_scale, text_scale)
		local circle_scale = circle_scale or ShaveHUD:getSetting({"INTERACTION", "CIRCLE_SCALE"}, 0.8)
		local text_scale = text_scale or ShaveHUD:getSetting({"INTERACTION", "TEXT_SCALE"}, 0.8)
		local interact_text = self._hud_panel:child(self._child_name_text)
		local invalid_text = self._hud_panel:child(self._child_ivalid_name_text)
		local changed = false
		if self._circle_scale ~= circle_scale then
			self._circle_radius = self._original_circle_radius * circle_scale
			self._circle_scale = circle_scale
			changed = true
		end
		if self._text_scale ~= text_scale then
			local interact_text = self._hud_panel:child(self._child_name_text)
			local invalid_text = self._hud_panel:child(self._child_ivalid_name_text)
			interact_text:set_font_size(self._original_interact_text_font_size * text_scale)
			invalid_text:set_font_size(self._original_invalid_text_font_size * text_scale)
			self._text_scale = text_scale
			changed = true
		end
		if changed then
			interact_text:set_y(self._hud_panel:h() / 2 + self._circle_radius + interact_text:font_size() / 2)
			invalid_text:set_center_y(interact_text:center_y())
		end
	end
elseif string.lower(RequiredScript) == "lib/units/interactions/interactionext" then
	local _add_string_macros_original = BaseInteractionExt._add_string_macros

	function BaseInteractionExt:would_be_bonus_bag(carry_id)
		if managers.loot:get_mandatory_bags_data().carry_id ~= "none" and carry_id and carry_id ~= managers.loot:get_mandatory_bags_data().carry_id then
			return true
		end
		local mandatory_bags_amount = managers.loot:get_mandatory_bags_data().amount or 0
		for _, data in ipairs(managers.loot._global.secured) do
			if not tweak_data.carry.small_loot[data.carry_id] and not tweak_data.carry[data.carry_id].is_vehicle then
				if mandatory_bags_amount > 1 and (managers.loot:get_mandatory_bags_data().carry_id == "none" or managers.loot:get_mandatory_bags_data().carry_id == data.carry_id) then
					mandatory_bags_amount = mandatory_bags_amount - 1
				elseif mandatory_bags_amount <= 1 then
					return true
				end
			end
		end
		return false
	end

	function BaseInteractionExt:get_unsecured_bag_value(carry_id, mult)
		local bag_value = managers.money:get_bag_value(carry_id, mult)
		local bag_skill_bonus = managers.player:upgrade_value("player", "secured_bags_money_multiplier", 1)
		if self:would_be_bonus_bag(carry_id) then
			local stars = managers.job:has_active_job() and managers.job:current_difficulty_stars() or 0
			local money_multiplier = managers.money:get_contract_difficulty_multiplier(stars)
			bag_value =  bag_value + math.round(bag_value * money_multiplier)
		end
		return math.round(bag_value * bag_skill_bonus / managers.money:get_tweak_value("money_manager", "offshore_rate"))
	end

	function BaseInteractionExt:_add_string_macros(macros, ...)
		_add_string_macros_original(self, macros, ...)
		macros.INTERACT = self:_btn_interact() or managers.localization:get_default_macro("BTN_INTERACT") --Ascii ID for RB
		if self._unit:carry_data() then
			local carry_id = self._unit:carry_data():carry_id()
			macros.BAG = managers.localization:text(tweak_data.carry[carry_id].name_id)
			if not (managers.crime_spree and managers.crime_spree:is_active()) then
				macros.VALUE = not tweak_data.carry[carry_id].skip_exit_secure and " (" .. managers.experience:cash_string(self:get_unsecured_bag_value(carry_id, 1)) .. ")" or ""
			else
				macros.VALUE = ""
			end
		else
			macros.VALUE = ""
		end
	end

elseif string.lower(RequiredScript) == "lib/managers/objectinteractionmanager" then
	ObjectInteractionManager.AUTO_PICKUP_DELAY = ShaveHUD:getTweakEntry("AUTO_PICKUP_DELAY", "number", 0)	 --Delay in seconds between auto-pickup procs (0 -> as fast as possible)
	local _update_targeted_original = ObjectInteractionManager._update_targeted
	function ObjectInteractionManager:_update_targeted(player_pos, player_unit, ...)
		_update_targeted_original(self, player_pos, player_unit, ...)

		if ShaveHUD:getSetting({"INTERACTION", "HOLD2PICK"}, true) and alive(self._active_unit) and not self._active_object_locked_data then
			local t = Application:time()
			if self._active_unit:base() and self._active_unit:base().small_loot and (t >= (self._next_auto_pickup_t or 0)) then
				self._next_auto_pickup_t = t + ObjectInteractionManager.AUTO_PICKUP_DELAY
				local success = self:interact(player_unit)
			end
		end
	end
elseif string.lower(RequiredScript) == "lib/tweak_data/interactiontweakdata" then
	if not ShaveHUD:getSetting({"INTERACTION", "INSTA_GAGE"}, true) then
		return
	end

	Hooks:PostHook(InteractionTweakData, "init", "Insta_Pickup_Gage_Packages", function(self, tweak_data)
        self.gage_assignment.timer = 0      
        self.gage_assignment.sound_start = "money_grab" 
        self.gage_assignment.sound_event = "money_grab" 
        self.gage_assignment.sound_done = "money_grab"  
	end)
	Hooks:Add("LocalizationManagerPostInit", "Insta_Pickup_Gage_Packages", function(loc) --Change 'YOUR_MOD_NAME' to something else.
		LocalizationManager:add_localized_strings({
			["debug_interact_gage_assignment_take"] = "PRESS $BTN_INTERACT TO PICK UP THE PACKAGE",
		})
	end)
elseif string.lower(RequiredScript) == "lib/units/beings/player/states/playerbipod" then
	if ShaveHUD:getSetting({"Fixes", "ABILITY_USE"}, true) then
		local _update_check_actions = PlayerBipod._update_check_actions
	
		local function nop() end
	
		function PlayerBipod:_update_check_actions(t, dt, paused)
			local projectile_entry = managers.blackmarket:equipped_projectile()
			local projectile_tweak = tweak_data.blackmarket.projectiles[projectile_entry]
	
			if projectile_tweak.ability then
				local _check_action_use_ability = PlayerBipod._check_action_use_ability
				local getInput = PlayerBipod._get_input
				local input = self:_get_input(t, dt, paused)
	
				PlayerBipod._get_input = function(t, dt, paused)
					return input
				end
	
				self:_check_action_use_ability(t, input)
				PlayerBipod._check_action_use_ability = nop
				_update_check_actions(self, t, dt, paused)
				PlayerBipod._check_action_use_ability = _check_action_use_ability
				PlayerBipod._get_input = getInput
			else
				_update_check_actions(self, t, dt, paused)
			end
		end
	end
elseif string.lower(RequiredScript) == "lib/managers/hud/hudlootscreen" then
	if not ShaveHUD:getSetting({"SkipIt", "INSTANT_CARDFLIP"}, true) then
		return
	end
	
	function HUDLootScreen:begin_flip_card(peer_id)
		self._peer_data[peer_id].wait_t = 0
		local type_to_card = {
			weapon_mods = 2,
			materials = 5,
			colors = 6,
			safes = 8,
			cash = 3,
			masks = 1,
			xp = 4,
			textures = 7,
			drills = 9,
			weapon_bonus = 10
		}
		local card_nums = {
			"upcard_mask",
			"upcard_weapon",
			"upcard_cash",
			"upcard_xp",
			"upcard_material",
			"upcard_color",
			"upcard_pattern",
			"upcard_safe",
			"upcard_drill",
			"upcard_weapon_bonus"
		}
	
		table.insert(card_nums, "upcard_cosmetic")
	
		type_to_card.weapon_skins = #card_nums
		type_to_card.armor_skins = #card_nums
		local lootdrop_data = self._peer_data[peer_id].lootdrops
		local item_category = lootdrop_data[3]
		local item_id = lootdrop_data[4]
		local item_pc = lootdrop_data[6]
	
		if item_category == "weapon_mods" and managers.weapon_factory:get_type_from_part_id(item_id) == "bonus" then
			item_category = "weapon_bonus"
		end
	
		local card_i = type_to_card[item_category] or math.max(item_pc, 1)
		local texture, rect, coords = tweak_data.hud_icons:get_icon_data(card_nums[card_i] or "downcard_overkill_deck")
		local panel = self._peers_panel:child("peer" .. tostring(peer_id))
		local card_info_panel = panel:child("card_info")
		local main_text = card_info_panel:child("main_text")
	
		main_text:set_text(managers.localization:to_upper_text("menu_l_choose_card_chosen", {
			time = 0
		}))
	
		local _, _, _, hh = main_text:text_rect()
	
		main_text:set_h(hh + 2)
	
		local card_panel = panel:child("card" .. self._peer_data[peer_id].chosen_card_id)
		local upcard = card_panel:child("upcard")
	
		upcard:set_image(texture)
	
		if coords then
			local tl = Vector3(coords[1][1], coords[1][2], 0)
			local tr = Vector3(coords[2][1], coords[2][2], 0)
			local bl = Vector3(coords[3][1], coords[3][2], 0)
			local br = Vector3(coords[4][1], coords[4][2], 0)
	
			upcard:set_texture_coordinates(tl, tr, bl, br)
		else
			upcard:set_texture_rect(unpack(rect))
		end
	
		self._peer_data[peer_id].chosen_card_id = nil
	end
end