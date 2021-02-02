if string.lower(RequiredScript) == "lib/managers/hudmanagerpd2" then
	local set_teammate_ammo_amount_orig = HUDManager.set_teammate_ammo_amount
	local set_slot_ready_orig = HUDManager.set_slot_ready

	function HUDManager:set_teammate_ammo_amount(id, selection_index, max_clip, current_clip, current_left, max, ...)
		if ShaveHUD:getSetting({"CustomHUD", "USE_REAL_AMMO"}, true) then
			local total_left = current_left - current_clip
			if total_left >= 0 then
				current_left = total_left
				max = max - current_clip
			end
		end
		return set_teammate_ammo_amount_orig(self, id, selection_index, max_clip, current_clip, current_left, max, ...)
	end

	local FORCE_READY_CLICKS = 3
	local FORCE_READY_TIME = 2
	local FORCE_READY_ACTIVE_T = 90

	local force_ready_start_t = 0
	local force_ready_clicked = 0

	function HUDManager:set_slot_ready(peer, peer_id, ...)
		set_slot_ready_orig(self, peer, peer_id, ...)

		if Network:is_server() and not Global.game_settings.single_player then
			local session = managers.network and managers.network:session()
			local local_peer = session and session:local_peer()
			local time_elapsed = managers.game_play_central and managers.game_play_central:get_heist_timer() or 0
			if local_peer and local_peer:id() == peer_id then
				local t = Application:time()
				if (force_ready_start_t + FORCE_READY_TIME) > t then
					force_ready_clicked = force_ready_clicked + 1
					if force_ready_clicked >= FORCE_READY_CLICKS then
						local enough_wait_time = (time_elapsed > FORCE_READY_ACTIVE_T)
						local friends_list = not enough_wait_time and Steam:logged_on() and Steam:friends() or {}
						local abort = false
						for _, peer in ipairs(session:peers()) do
							local is_friend = false
							for _, friend in ipairs(friends_list) do
								if friend:id() == peer:user_id() then
									is_friend = true
									break
								end
							end
							if not (enough_wait_time or is_friend) or not (peer:synced() or peer:id() == local_peer:id()) then
								abort = true
								break
							end
						end
						if game_state_machine and not abort then
							local menu_options = {
								[1] = {
									text = managers.localization:text("dialog_yes"),
									callback = function(self, item)
										managers.chat:send_message(ChatManager.GAME, local_peer, "The Game was forced to start.")
										game_state_machine:current_state():start_game_intro()
									end,
								},
								[2] = {
									text = managers.localization:text("dialog_no"),
									is_cancel_button = true,
								}
							}
							QuickMenu:new( managers.localization:text("shavehud_dialog_force_start_title"), managers.localization:text("shavehud_dialog_force_start_desc"), menu_options, true )
						end
					end
				else
					force_ready_clicked = 1
					force_ready_start_t = t
				end
			end
		end
	end
elseif string.lower(RequiredScript) == "lib/tweak_data/weaponfactorytweakdata" then
	if not ShaveHUD:getSetting({"INVENTORY", "BIGGER_BETTER_REPLACED"}, true) then
		return
	end

	local sos_init_silencers_original = WeaponFactoryTweakData._init_silencers
	function WeaponFactoryTweakData:_init_silencers()
		sos_init_silencers_original(self)
		
		-- SpecOps Suppressed Barrel
		self.parts.wpn_fps_upg_ns_ass_smg_large.unit = "units/pd2_dlc_dec5/weapons/wpn_fps_smg_mp7_pts/wpn_fps_smg_mp7_b_suppressed"
		self.parts.wpn_fps_upg_ns_ass_smg_large.third_unit = "units/pd2_dlc_dec5/weapons/wpn_third_smg_mp7_pts/wpn_third_smg_mp7_b_suppressed"
		
		-- Jungle Ninja Suppressor
		-- self.parts.wpn_fps_upg_ns_ass_smg_large.unit = "units/pd2_dlc_butcher_mods/weapons/wpn_fps_upg_ns_pis_jungle/wpn_fps_upg_ns_pis_jungle"
		-- self.parts.wpn_fps_upg_ns_ass_smg_large.third_unit = "units/pd2_dlc_butcher_mods/weapons/wpn_third_upg_ns_pis_jungle/wpn_third_upg_ns_pis_jungle"
	end
elseif string.lower(RequiredScript) == "lib/tweak_data/timespeedeffecttweakdata" then
	local init_original = TimeSpeedEffectTweakData.init
	local FORCE_ENABLE = {
		mission_effects = true,
	}
	function TimeSpeedEffectTweakData:init(...)
		init_original(self, ...)
		if ShaveHUD:getSetting({"SkipIt", "NO_SLOWMOTION"}, true) then
			local function disable_effect(table)
				for name, data in pairs(table) do
					if not FORCE_ENABLE[name] then
						if data.speed and data.sustain then
							data.speed = 1
							data.fade_in_delay = 0
							data.fade_in = 0
							data.sustain = 0
							data.fade_out = 0
						elseif type(data) == "table" then
							disable_effect(data)
						end
					end
				end
			end

			disable_effect(self)
		end
	end
elseif string.lower(RequiredScript) == "lib/tweak_data/economytweakdata" then
	if EconomyTweakData then
		-- Fix community market links for Real Weapon Names
		Hooks:PostHook(EconomyTweakData, "create_weapon_skin_market_search_url" ,"ShaveHUD_EconomyTweakDataPostCreateWeaponSkinMarketSearchUrl", function(self, weapon_id, cosmetic_id)
			local cosmetic_name = tweak_data.blackmarket.weapon_skins[cosmetic_id] and managers.localization:text(tweak_data.blackmarket.weapon_skins[cosmetic_id].name_id)
			local weapon_name = managers.localization.orig.text(managers.localization, tweak_data.weapon[weapon_id].name_id) -- bypass custom localizations
			if cosmetic_name and weapon_name then
				cosmetic_name = string.gsub(cosmetic_name, " ", "+")
				weapon_name = string.gsub(weapon_name, " ", "+")
				return string.gsub("http://steamcommunity.com/market/search?appid=218620&q=" .. cosmetic_name .. "+" .. weapon_name, "++", "+")
			end
			return nil
		end)
	end
elseif string.lower(RequiredScript) == "lib/managers/menu/items/menuitemmultichoice" then
	if MenuItemMultiChoice then
		Hooks:PostHook( MenuItemMultiChoice , "setup_gui" , "MenuItemMultiChoicePostSetupGui_ShaveHUD" , function( self, node, row_item )
			if self:selected_option() and self:selected_option():parameters().color and row_item.choice_text then
				row_item.choice_text:set_blend_mode("normal")
			end
		end)
	end
elseif string.lower(RequiredScript) == "lib/managers/menu/menunodegui" then
	if MenuNodeMainGui then
		Hooks:PostHook( MenuNodeMainGui , "_add_version_string" , "MenuNodeMainGuiPostAddVersionString_ShaveHUD" , function( self )
			if alive(self._version_string) then
				self._version_string:set_text("Payday 2 v" .. Application:version() .. " | ShaveHUD v" .. ShaveHUD:getVersion())
			end
		end)
	end
elseif string.lower(RequiredScript) == "lib/managers/experiencemanager" then
	local cash_string_original = ExperienceManager.cash_string

	function ExperienceManager:cash_string(...)
		local val = cash_string_original(self, ...)
		if self._cash_sign ~= "$" and val:find(self._cash_sign) then
			val = val:gsub(self._cash_sign, "") .. self._cash_sign
		end
		return val
	end
elseif string.lower(RequiredScript) == "lib/managers/moneymanager" then
	function MoneyManager:total_string()
		local total = math.round(self:total())
		return managers.experience:cash_string(total)
	end
	function MoneyManager:total_collected_string()
		local total = math.round(self:total_collected())
		return managers.experience:cash_string(total)
	end
elseif string.lower(RequiredScript) == "lib/network/handlers/unitnetworkhandler" then
	if ShaveHUD:getSetting({"GADGETS", "NO_RED_LASERS"}, true) then
		function UnitNetworkHandler:set_weapon_gadget_color(unit, red, green, blue, sender)
			if not self._verify_character_and_sender(unit, sender) then
				return
			end
			if red and green and blue then 
				local threshold = 0.66 --can be changed at will
				--log("No Red Lasers: Filtered a red player laser! Attempted values " .. tostring(red) .. "|g:" .. tostring(green) .. "|b:" .. tostring(blue) .. " from sender" .. tostring(sender))
				if red * threshold > green + blue then --i'm only sanity checking my own stuff. if the other stuff crashes that's ovk's fault
					red = 1
					green = 51
					blue = 1
					--take that you red-laser-using SCUM
				end
			end
			unit:inventory():sync_weapon_gadget_color(Color(red / 255, green / 255, blue / 255))
		end
	end
elseif string.lower(RequiredScript) == "lib/units/cameras/fpcameraplayerbase" then
	if ShaveHUD:getSetting({"Fixes", "CLOAKER_CAM_LOCK"}, true) then
		function FPCameraPlayerBase:clbk_aim_assist(col_ray)
			if managers.controller:get_default_wrapper_type() ~= "pc" and managers.user:get_setting("aim_assist") then
				self:_start_aim_assist(col_ray, self._aim_assist)
			end
		end
	end
elseif string.lower(RequiredScript) == "lib/tweak_data/weapontweakdata" then
	if ShaveHUD:getSetting({"Fixes", "THIRD_PERSON_RECOIL"}, true) then
		Hooks:PostHook(WeaponTweakData, "init", "tpsmod_enable_anims", function(self)
			local blacklist = {
				["c45_crew"] = true,
				["x_c45_crew"] = true,
				["r870_crew"] = true,
				["mossberg_crew"] = true,
				["m95_crew"] = true,
				["msr_crew"] = true,
				["r93_crew"] = true,
				["ksg_crew"] = true,
				["winchester1874_crew"] = true,
				["m37_crew"] = true,
				["china_crew"] = true,
				["boot_crew"] = true,
				["desertfox_crew"] = true,
				["ecp_crew"] = true,
				["arblast_crew"] = true,
				["frankish_crew"] = true,
				["hunter_crew"] = true
			}
			for i,v in pairs(self) do
				if not blacklist[i] and string.match(i, "_crew") then
					self[i].has_fire_animation = true
				end
			end
		end)
	end
elseif string.lower(RequiredScript) == "lib/units/weapons/npcsawweaponbase" then
	if ShaveHUD:getSetting({"Fixes", "RECOIL_THIRD_PERSON"}, true) then
		Hooks:PostHook(NPCSawWeaponBase, "fire_blank", "tpsmod_enable_saw_anims", function(self)
			if self:weapon_tweak_data().has_fire_animation then
				self:tweak_data_anim_play("fire")
			end
		end)
	end
elseif string.lower(RequiredScript) == "lib/managers/criminalsmanager" then
	if ShaveHUD:getSetting({"Fixes", "KEEP_HEIST_OUTFITS"}, true) then
		function CriminalsManager:update_character_visual_state(character_name, visual_state)
			local character = self:character_by_name(character_name)
		
			if not character or not character.taken or not alive(character.unit) then
				return
			end
		
			visual_state = visual_state or {}
			local current_level = managers.job and managers.job:current_level_id()																								  
			local unit = character.unit
			local is_local_peer = visual_state.is_local_peer or character.visual_state.is_local_peer or false
			local visual_seed = visual_state.visual_seed or character.visual_state.visual_seed or CriminalsManager.get_new_visual_seed()
			local mask_id = visual_state.mask_id or character.visual_state.mask_id
			local armor_id = visual_state.armor_id or character.visual_state.armor_id or "level_1"
			local armor_skin = visual_state.armor_skin or character.visual_state.armor_skin or "none"
			local player_style = self:active_player_style() or managers.blackmarket:get_default_player_style()
			local suit_variation = nil
			local user_player_style = visual_state.player_style or character.visual_state.player_style or managers.blackmarket:get_default_player_style()
		
			if not self:is_active_player_style_locked() and user_player_style ~= managers.blackmarket:get_default_player_style() then
				if current_level and tweak_data.levels[current_level].player_style then
					player_style = tweak_data.levels[current_level] and tweak_data.levels[current_level].player_style
				else													 
					player_style = user_player_style
					suit_variation = visual_state.suit_variation or character.visual_state.suit_variation or "default"
				end
			end
		
			local glove_id = visual_state.glove_id or character.visual_state.glove_id or managers.blackmarket:get_default_glove_id()
			local character_visual_state = {
				is_local_peer = is_local_peer,
				visual_seed = visual_seed,
				player_style = player_style,
				suit_variation = suit_variation,
				glove_id = glove_id,
				mask_id = mask_id,
				armor_id = armor_id,
				armor_skin = armor_skin
			}
		
			local function get_value_string(value)
				return is_local_peer and tostring(value) or "third_" .. tostring(value)
			end
		
			if player_style then
				local unit_name = tweak_data.blackmarket:get_player_style_value(player_style, character_name, get_value_string("unit"))
		
				if unit_name then
					self:safe_load_asset(character, unit_name, "player_style")
				end
			end
		
			if glove_id then
				local unit_name = tweak_data.blackmarket:get_glove_value(glove_id, character_name, "unit", player_style, suit_variation)
		
				if unit_name then
					self:safe_load_asset(character, unit_name, "glove_id")
				end
			end
		
			CriminalsManager.set_character_visual_state(unit, character_name, character_visual_state)
		
			character.visual_state = {
				is_local_peer = is_local_peer,
				visual_seed = visual_seed,
				player_style = user_player_style,
				suit_variation = suit_variation,
				glove_id = glove_id,
				mask_id = mask_id,
				armor_id = armor_id,
				armor_skin = armor_skin
			}
		end
	end
elseif string.lower(RequiredScript) == "lib/tweak_data/levelstweakdata" then
	if ShaveHUD:getSetting({"Fixes", "LOGICAL_HEIST_OUTFITS"}, true) then
		Hooks:PostHook(LevelsTweakData, "init", "HeistOutfits", function (self)
			self.mad.player_style = "winter_suit"
			self.dinner.player_style = "slaughterhouse"
		end)
	end
elseif string.lower(RequiredScript) == "lib/managers/mission/elementfilter" then
	if ShaveHUD:getSetting({"Fixes", "DIFF_CHECK_FALLBACK"}, true) then
		Hooks:PostHook(ElementFilter, "_check_difficulty", "DiffCheckFallbackFix", function(self)
			local diff = Global.game_settings and Global.game_settings.difficulty or "hard"
			--Death Sentence fallback
			local is_difficulty_sm_wish = self._values.difficulty_sm_wish == nil and self._values.difficulty_overkill_290 or self._values.difficulty_sm_wish
		
			if is_difficulty_sm_wish and diff == "sm_wish" then
				return true
			end
			
			--Mayhem fallback
			local is_difficulty_easy_wish = self._values.difficulty_easy_wish == nil and self._values.difficulty_overkill_290 or self._values.difficulty_easy_wish
		
			if is_difficulty_easy_wish and diff == "easy_wish" then
				return true
			end
		end)
	end
elseif string.lower(RequiredScript) == "lib/managers/mission/elementspawnenemydummy" then
	if ShaveHUD:getSetting({"Fixes", "CORRECT_DIFF_ENEMIES"}, true) then
		--check for sc ai changes and dw+ ai changes
		if (SC and SC._data and SC._data.sc_ai_toggle) or (DW and DW.settings and DW.settings.dw_enemy_toggle_value) then return end

		--lazy fixes
		local ai_type = tweak_data.levels:get_ai_group_type()
		local job = Global.level_data and Global.level_data.level_id
		if ai_type ~= "america" or job == "firestarter_2" then return end

		--one down
		local sm_wish = {
				["units/payday2/characters/ene_bulldozer_1/ene_bulldozer_1"] = "units/pd2_dlc_gitgud/characters/ene_zeal_bulldozer_2/ene_zeal_bulldozer_2",
				["units/payday2/characters/ene_bulldozer_2/ene_bulldozer_2"] = "units/pd2_dlc_gitgud/characters/ene_zeal_bulldozer_3/ene_zeal_bulldozer_3",
				["units/payday2/characters/ene_bulldozer_3/ene_bulldozer_3"] = "units/pd2_dlc_gitgud/characters/ene_zeal_bulldozer/ene_zeal_bulldozer",
				["units/payday2/characters/ene_city_swat_1/ene_city_swat_1"] = "units/pd2_dlc_gitgud/characters/ene_zeal_swat_heavy/ene_zeal_swat_heavy",
				["units/payday2/characters/ene_city_swat_2/ene_city_swat_2"] = "units/pd2_dlc_gitgud/characters/ene_zeal_swat_heavy/ene_zeal_swat_heavy",
				["units/payday2/characters/ene_city_swat_3/ene_city_swat_3"] = "units/pd2_dlc_gitgud/characters/ene_zeal_swat_heavy/ene_zeal_swat_heavy",
				["units/payday2/characters/ene_fbi_swat_1/ene_fbi_swat_1"] = "units/pd2_dlc_gitgud/characters/ene_zeal_swat_heavy/ene_zeal_swat_heavy",
				["units/payday2/characters/ene_fbi_swat_2/ene_fbi_swat_2"] = "units/pd2_dlc_gitgud/characters/ene_zeal_swat_heavy/ene_zeal_swat_heavy",
				["units/payday2/characters/ene_swat_1/ene_swat_1"] = "units/pd2_dlc_gitgud/characters/ene_zeal_swat_heavy/ene_zeal_swat_heavy",
				["units/payday2/characters/ene_swat_2/ene_swat_2"] = "units/pd2_dlc_gitgud/characters/ene_zeal_swat_heavy/ene_zeal_swat_heavy",
				["units/payday2/characters/ene_swat_heavy_1/ene_swat_heavy_1"] = "units/pd2_dlc_gitgud/characters/ene_zeal_swat_heavy/ene_zeal_swat_heavy",
				["units/payday2/characters/ene_swat_heavy_r870/ene_swat_heavy_r870"] = "units/pd2_dlc_gitgud/characters/ene_zeal_swat_heavy/ene_zeal_swat_heavy",
				["units/payday2/characters/ene_shield_1/ene_shield_1"] = "units/pd2_dlc_gitgud/characters/ene_zeal_swat_shield/ene_zeal_swat_shield",
				["units/payday2/characters/ene_shield_2/ene_shield_2"] = "units/pd2_dlc_gitgud/characters/ene_zeal_swat_shield/ene_zeal_swat_shield",
				["units/payday2/characters/ene_city_shield/ene_city_shield"] = "units/pd2_dlc_gitgud/characters/ene_zeal_swat_shield/ene_zeal_swat_shield",
				["units/payday2/characters/ene_fbi_1/ene_fbi_1"] = "units/pd2_dlc_gitgud/characters/ene_zeal_swat/ene_zeal_swat",
				["units/payday2/characters/ene_fbi_2/ene_fbi_2"] = "units/pd2_dlc_gitgud/characters/ene_zeal_swat/ene_zeal_swat",
				["units/payday2/characters/ene_fbi_3/ene_fbi_3"] = "units/pd2_dlc_gitgud/characters/ene_zeal_swat/ene_zeal_swat",
				["units/payday2/characters/ene_fbi_heavy_1/ene_fbi_heavy_1"] = "units/pd2_dlc_gitgud/characters/ene_zeal_swat_heavy/ene_zeal_swat_heavy",
				["units/payday2/characters/ene_fbi_heavy_r870/ene_fbi_heavy_r870"] = "units/pd2_dlc_gitgud/characters/ene_zeal_swat_heavy/ene_zeal_swat_heavy"
			}
		--so much variety in the units, thanks ovk. how about giving the bulldozers correct weapons after five months?

		--dont have to do cloakers because overkill at least did those correctly

		--death wish/mayhem
		local deathwish = {
				["units/payday2/characters/ene_fbi_swat_1/ene_fbi_swat_1"] = "units/payday2/characters/ene_city_swat_1/ene_city_swat_1",
				["units/payday2/characters/ene_fbi_swat_2/ene_fbi_swat_2"] = "units/payday2/characters/ene_city_swat_2/ene_city_swat_2",
				["units/payday2/characters/ene_swat_1/ene_swat_1"] = "units/payday2/characters/ene_city_swat_1/ene_city_swat_1",
				["units/payday2/characters/ene_swat_2/ene_swat_2"] = "units/payday2/characters/ene_city_swat_2/ene_city_swat_2",
				["units/payday2/characters/ene_swat_heavy_1/ene_swat_heavy_1"] = "units/payday2/characters/ene_city_heavy_g36/ene_city_heavy_g36",
				["units/payday2/characters/ene_swat_heavy_r870/ene_swat_heavy_r870"] = "units/payday2/characters/ene_city_heavy_r870/ene_city_heavy_r870",
				["units/payday2/characters/ene_shield_1/ene_shield_1"] = "units/payday2/characters/ene_city_shield/ene_city_shield",
				["units/payday2/characters/ene_shield_2/ene_shield_2"] = "units/payday2/characters/ene_city_shield/ene_city_shield",
				["units/payday2/characters/ene_fbi_heavy_1/ene_fbi_heavy_1"] = "units/payday2/characters/ene_city_heavy_g36/ene_city_heavy_g36",
				["units/payday2/characters/ene_fbi_heavy_r870/ene_fbi_heavy_r870"] = "units/payday2/characters/ene_city_heavy_r870/ene_city_heavy_r870"
			}
		--putting gensec shotgunners in there because overkill can't be bothered, even if the fire rate is messed up

		function ElementSpawnEnemyDummy:init(...)
			ElementSpawnEnemyDummy.super.init(self, ...)
			local ai_type = tweak_data.levels:get_ai_group_type()
			local difficulty = Global.game_settings and Global.game_settings.difficulty or "normal"
			local difficulty_index = tweak_data:difficulty_to_index(difficulty)
			local job = Global.level_data and Global.level_data.level_id

			if ai_type == "america" and job ~= "firestarter_2" then --only replace enemies if we're in america and not on firestarter 2, otherwise DHS appear in FBI office and it looks fucking stupid
				if difficulty_index == 8 then --DHS over GenSec/FBI
					if sm_wish[self._values.enemy] then
						self._values.enemy = sm_wish[self._values.enemy]
					end
					self._values.enemy = sm_wish[self._values.enemy] or self._values.enemy
				elseif difficulty_index == 7 or difficulty_index == 6 then --GenSec over FBI
					if deathwish[self._values.enemy] then
						self._values.enemy = deathwish[self._values.enemy]
					end
					self._values.enemy = deathwish[self._values.enemy] or self._values.enemy
				end

				self._enemy_name = self._values.enemy and Idstring(self._values.enemy) or Idstring("units/payday2/characters/ene_swat_1/ene_swat_1")
				self._values.enemy = nil
				self._units = {}
				self._events = {}
				self:_finalize_values()
			end
		end
	end
elseif string.lower(RequiredScript) == "lib/network/base/networkpeer" then
	if ShaveHUD:getSetting({"CrewLoadout", "AUTOKICK_CHEAT_MODS"}, true) then
		Hooks:PostHook(NetworkPeer, "set_ip_verified", "cheaterz_go_to_hell_haha", function(self, state)
			if not Network:is_server() then
				return
			end
			DelayedCalls:Add( "cheaterz_go_to_hell_d", 2, function()
				local user = Steam:user(self:ip())
				if user and user:rich_presence("is_modded") == "1" or self:is_modded() then
					managers.chat:feed_system_message(1, self:name() .. " HAS MODS! Checking...")
					for i, mod in ipairs(self:synced_mods()) do
						local mod_mini = string.lower(mod.name)	
						local kick_on = {}
						local potential_hax = {}
						local prob_not_clean = nil
		
						kick_on = {
							"pirate perfection",
							"p3dhack",
							"p3dhack free",
							"dlc unlocker",
							"skin unlocker",
							"p3dunlocker",
							"arsium's weapons rebalance recoil",
							"overkill mod",
							"selective dlc unlocker",
							"the great skin unlock",
							"beyond cheats"
						}
		
						for _, v in pairs(kick_on) do
							if mod_mini == v then
								local identifier = "cheater_banned_" .. tostring(self:id())
								managers.ban_list:ban(identifier, self:name())
								managers.chat:feed_system_message(1, self:name() .. " has been kicked because of using the mod: " .. mod.name)
								local message_id = 0
								message_id = 6
								managers.network:session():send_to_peers("kick_peer", self:id(), message_id)
								managers.network:session():on_peer_kicked(self, self:id(), message_id)
								return
							end
						end
		
						potential_hax = {
							"pirate",
							"p3d",
							"hack",
							"cheat",
							"unlocker",
							"unlock",
							"dlc",
							"trainer",
							"silent assassin",
							"carry stacker",
							"god",
							"x-ray",
							"mvp"
						}
		
						for k, pc in pairs(potential_hax) do
							if string.find(mod_mini, pc) then
								log("found something!")
								managers.chat:feed_system_message(1, self:name() .. " is using a mod that can be a potential cheating mod: " .. mod.name)
								prob_not_clean = 1
							end
						end
					end
		
					if prob_not_clean then
						managers.chat:feed_system_message(1, self:name() .. " has a warning... Check his mods/profile manually to be sure.")
					else
						managers.chat:feed_system_message(1, self:name() .. " seems to be clean.")
					end
				else
					managers.chat:feed_system_message(1, self:name() .. " doesn't seem to have mods.")
				end
			end)
		end)
	end
elseif string.lower(RequiredScript) == "lib/units/beings/player/huskplayerdamage" then
    if ShaveHUD:getSetting({"Misc", "PLAYER_BLOOD"}, true) then
        Hooks:PostHook(HuskPlayerDamage, "sync_damage_bullet", "blood_splat_hpdmg", function(self, attacker_unit, damage, i_body, height_offset)
            local hit_pos = mvector3.copy(self._unit:movement():m_com())
            local attack_dir = nil
        
            if attacker_unit then
                attack_dir = hit_pos - attacker_unit:position()
        
                mvector3.normalize(attack_dir)
            else
                attack_dir = self._unit:rotation():y()
            end
        
            managers.game_play_central:sync_play_impact_flesh(hit_pos, attack_dir)
        end)
    end
elseif string.lower(RequiredScript) == "lib/units/beings/player/playerdamage" then
    if ShaveHUD:getSetting({"Misc", "PLAYER_BLOOD"}, true) then
        Hooks:PostHook(PlayerDamage, "damage_bullet", "blood_splat_pdmg", function(self, attack_data)
            if not self:_chk_can_take_dmg() then
                return
            end
        
            local hit_pos = mvector3.copy(self._unit:movement():m_com())
            local attack_dir = nil
            local attacker_unit = attack_data.attacker_unit
        
            if attacker_unit then
                attack_dir = hit_pos - attacker_unit:position()
                mvector3.normalize(attack_dir)
            else
                attack_dir = self._unit:rotation():y()
            end
        
            managers.game_play_central:sync_play_impact_flesh(hit_pos, attack_dir)
        end)
	end
elseif string.lower(RequiredScript) == "lib/utils/accelbyte/telemetry" then
	if not ShaveHUD:getSetting({"Misc", "DISABLE_TELEMETRY"}, true) then
		return
	end

	local base_url = "http://localhost/"

    local function get_geolocation()
        return
    end

    local function get_total_playtime()
        return
    end

    local function update_total_playtime(new_playtime)
        return
    end

    local function send_telemetry(telemetry_body)
        return
    end

    local function send_telemetry(telemetry_body)
        return
    end

    function Telemetry:init()
        return
    end
    function Telemetry:update(t, dt)
        return
    end
    function Telemetry:send_on_player_change_loadout(stats)
        return
    end
    function Telemetry:send_on_player_economy_event(event_origin, currency, amount, transaction_type)
        return
    end
    function Telemetry:on_start_heist(...)
        return
    end
    function Telemetry:send_on_player_tutorial()
        return
    end
    function Telemetry:on_end_heist()
        return
    end
    function Telemetry:last_quickplay_room_id()
        return
    end
    function Telemetry:send_on_player_logged_out()
        return
    end
    function Telemetry:send_batch_immediately()
        return
    end
    function Telemetry:send_telemetry_immediately(event_name, payload, event_namespace, callback)
        return
    end
    function Telemetry:send_on_player_lobby_setting()
        return
    end
    function Telemetry:send_on_player_heartbeat()
        return
    end
    function Telemetry:send_on_player_heist_end()
        return
    end
    function Telemetry:send_on_player_heist_start()
        return
    end
    function Telemetry:enable(is_enable)
        return false
    end
    function Telemetry:set_mission_payout(payout)
        return
    end
    function Telemetry:on_login_screen_passed()
        return
    end
    function Telemetry:send(event_name, payload, event_namespace)
        return
    end
    function Telemetry:on_login()
        return false
    end
    function Telemetry:send_on_heist_start()
        return
    end
    function Telemetry:send_on_heist_end(end_reason)
        return
    end
elseif string.lower(RequiredScript) == "lib/tweak_data/playertweakdata" then
	if not ShaveHUD:getSetting({"Misc", "NO_SWAY"}, true) then
		return
	end

	if not _PlayerTweakData_init then _PlayerTweakData_init = PlayerTweakData.init end
	function PlayerTweakData:init()
	_PlayerTweakData_init(self)
		for k, v in pairs(self.stances) do
			v.steelsight.shakers.breathing.amplitude = 0
		end
	end
elseif string.lower(RequiredScript) == "lib/managers/hud/hudmissionbriefing" then
	if ShaveHUD:getSetting({"Misc", "STARRING"}, true) then
		Hooks:PostHook( HUDMissionBriefing, "set_player_slot", "nephud_function_post_bs", function(self, nr, params)
			local criminal_name = managers.localization:text("menu_" .. tostring(params.character))
			local current_name = params.name
			local experience = (params.rank > 0 and managers.experience:rank_string(params.rank) .. "-" or "") .. tostring(params.level)
			
			local peer_id = tostring(nr)
			
			local main_panel = managers.hud._hud_blackscreen._blackscreen_panel:child("panel_" .. peer_id)
			local text_panel = main_panel:child("name_" .. peer_id)
			text_panel:set_text(current_name .. " as " .. criminal_name)
		
			if current_name == "Nepgearsy" then
				text_panel:set_color(Color(1, 0.72, 0.35, 1))
			end
		end)
	end
elseif string.lower(RequiredScript) == "lib/managers/hud/hudblackscreen" then
	if ShaveHUD:getSetting({"Misc", "STARRING"}, true) then
		Hooks:PostHook( HUDBlackScreen, "init", "nephud_function_custom_bs", function(self, hud)
			local Net = _G.LuaNetworking
			local stage_data = managers.job:current_stage_data()
			local level_data = managers.job:current_level_data()
			local name_id = stage_data.name_id or level_data.name_id
		
			local heist_name_panel = self._blackscreen_panel:panel({
				visible = true,
				name = "heist_name_panel",
				y = -500,
				valign = "grow",
				halign = "grow",
				layer = 1
			})
			
			local heist_name_text = heist_name_panel:text({
				text = managers.localization:to_upper_text(name_id),
				font = tweak_data.menu.pd2_large_font,
				font_size = tweak_data.menu.pd2_small_large_size,
				align = "center",
				vertical = "bottom",
				color = Color.white
			})
		
			local starring_panel = self._blackscreen_panel:panel({
				visible = true,
				name = "starring_panel",
				y = -240,
				valign = "grow",
				halign = "grow",
				layer = 1
			})
		
			local host_panel = self._blackscreen_panel:panel({
				name = "panel_1",
				visible = true,
				y = -210,
				valign = "grow",
				halign = "grow",
				layer = 1
			})
		
			local blue_panel = self._blackscreen_panel:panel({
				name = "panel_2",
				visible = true,
				y = -185,
				valign = "grow",
				halign = "grow",
				layer = 1
			})
		
			local red_panel = self._blackscreen_panel:panel({
				name = "panel_3",
				visible = true,
				y = -160,
				valign = "grow",
				halign = "grow",
				layer = 1
			})
		
			local blonde_panel = self._blackscreen_panel:panel({
				name = "panel_4",
				visible = true,
				y = -135,
				valign = "grow",
				halign = "grow",
				layer = 1
			})
		
			local extra_panel = self._blackscreen_panel:panel({
				name = "panel_5",
				visible = true,
				y = -110,
				valign = "grow",
				halign = "grow",
				layer = 1
			})
		
			local total_peers = Net:GetNumberOfPeers()
		
			local host_name = managers.network.account:username_id()
			local host_id = Net:LocalPeerID()
			local blue_name = ""
			local red_name = ""
			local blonde_name = ""
			local extra_name = ""
		
			local host_color = Color(1,1,1,1)
			local blue_color = Color(1,1,1,1)
			local red_color = Color(1,1,1,1)
			local blonde_color = Color(1,1,1,1)
		
			local starring_with = starring_panel:text({
				text = "STARRING",
				font = tweak_data.menu.pd2_large_font,
				font_size = 35,
				align = "center",
				vertical = "bottom",
				color = Color(1,1,0.70,0)
			})
		
			local host_name_text = host_panel:text({
				name = "name_1",
				text = host_name,
				font = tweak_data.menu.pd2_large_font,
				font_size = 25,
				align = "center",
				vertical = "bottom",
				color = Color(1,1,1,1)
			})
		
			local blue_name_text = blue_panel:text({
				name = "name_2",
				text = blue_name,
				font = tweak_data.menu.pd2_large_font,
				font_size = 25,
				align = "center",
				vertical = "bottom",
				color = host_color
			})
		
			local red_name_text = red_panel:text({
				name = "name_3",
				text = red_name,
				font = tweak_data.menu.pd2_large_font,
				font_size = 25,
				align = "center",
				vertical = "bottom",
				color = blue_color
			})
		
			local blonde_name_text = blonde_panel:text({
				name = "name_4",
				text = blonde_name,
				font = tweak_data.menu.pd2_large_font,
				font_size = 25,
				align = "center",
				vertical = "bottom",
				color = red_color
			})
		
			local extra_name_text = extra_panel:text({
				name = "name_5",
				text = extra_name,
				font = tweak_data.menu.pd2_large_font,
				font_size = 25,
				align = "center",
				vertical = "bottom",
				color = blonde_color
			})
		end)
	end

	if not ShaveHUD:getSetting({"Misc", "DIFFICULTY_ANIMATION"}, true) then
		return
	end

	function HUDBlackScreen:_set_job_data()
		if not managers.job:has_active_job() then
			return
		end
		local job_panel = self._blackscreen_panel:panel({
			visible = true,
			name = "job_panel",
			y = 0,
			valign = "grow",
			halign = "grow",
			layer = 1
		})
		local risk_panel = job_panel:panel({name = "risk_panel"})
		local last_risk_level
		local blackscreen_risk_textures = tweak_data.gui.blackscreen_risk_textures
		for i = 1, managers.job:current_difficulty_stars() do
			local difficulty_name = tweak_data.difficulties[i + 2]
			local texture = blackscreen_risk_textures[difficulty_name] or "guis/textures/pd2/risklevel_blackscreen"
			last_risk_level = risk_panel:bitmap({
				visible = false,
				texture = texture,
				color = tweak_data.screen_colors.risk
			})
			last_risk_level:move((i - 1) * last_risk_level:w(), 0)
		end
		if last_risk_level then
			self._has_skull_data = true
			risk_panel:set_size(last_risk_level:right(), last_risk_level:bottom())
			risk_panel:set_center(job_panel:w() / 2, job_panel:h() / 2)
			risk_panel:set_position(math.round(risk_panel:x()), math.round(risk_panel:y()))
		else
			risk_panel:set_size(64, 64)
			risk_panel:set_center_x(job_panel:w() / 2)
			risk_panel:set_bottom(job_panel:h() / 2)
			risk_panel:set_position(math.round(risk_panel:x()), math.round(risk_panel:y()))
		end
		local risk_text_panel = job_panel:panel({name = "risk_text_panel"})
		local risk_text = risk_text_panel:text({
			visible = false,
			align = "center",
			text = managers.localization:to_upper_text(tweak_data.difficulty_name_id),
			font = tweak_data.menu.pd2_large_font,
			font_size = tweak_data.menu.pd2_small_large_size,
			color = tweak_data.screen_colors.risk
		})
		local _, _, w, h = risk_text:text_rect()
		risk_text:set_size(w, h)
		risk_text_panel:set_h(h)
		risk_text_panel:set_bottom(risk_panel:top())
		risk_text_panel:set_center_x(risk_panel:center_x())
		risk_text:set_position(0, 0)
	end

	function HUDBlackScreen:_animate_fade_in(mid_text)
		local job_panel = self._blackscreen_panel:child("job_panel")
		mid_text:set_alpha(1)
		if job_panel then
			job_panel:set_alpha(1)
			local panels = {}
			local panels_skulls = {}
			job_panel:animate(function(t)
				for i = 1, managers.job:current_difficulty_stars() do
					panels[i] = job_panel:child("risk_text_panel"):text({
						text = managers.localization:to_upper_text(tweak_data.difficulty_name_ids[tweak_data.difficulties[i + 2]]),
						align = "center",
						font = tweak_data.menu.pd2_large_font,
						font_size = tweak_data.menu.pd2_small_large_size,
						color = tweak_data.screen_colors.risk
					})
					local _, _, _, h = panels[i]:text_rect()
					panels[i]:set_h(h)
					panels[i]:set_y(-h)
					if self._has_skull_data then
						panels_skulls[i] = job_panel:child("risk_panel"):bitmap({
							visible = true,
							layer = 1,
							texture = tweak_data.gui.blackscreen_risk_textures[tweak_data.difficulties[i + 2]] or "guis/textures/pd2/risklevel_blackscreen",
							color = tweak_data.screen_colors.risk
						})
					end
					panels_skulls[i]:set_x(i == 1 and (job_panel:child("risk_panel"):w() / 2) - 32 or panels_skulls[i - 1]:x())
					if i == 1 then
						local ow, oh = panels_skulls[i]:size()
						over(0.1, function(o)
							panels_skulls[i]:set_size(math.lerp(ow * 0.75, ow, o), math.lerp(oh * 0.75, oh, o))
							panels_skulls[i]:set_position((job_panel:child("risk_panel"):w() / 2) - 32, 0)
						end)
					end
					job_panel:child("risk_panel"):animate(function(o)
						local ox = panels_skulls[i]:x()
						local ax = {}
						for a = i - 1, 1, -1 do
							ax[a] = panels_skulls[a]:x()
						end
						over(0.3, function(p)
							if panels_skulls[i] and i ~= 1 then
								panels_skulls[i]:set_x(math.lerp(panels_skulls[i]:x(), ox + (panels_skulls[i]:w() / 2), p))
								for a = i - 1, 1, -1 do
									panels_skulls[a]:set_x(math.lerp(panels_skulls[a]:x(), ax[a] - (panels_skulls[a]:w() / 2), p))
								end
							end
						end)
					end)
					wait(0.1)
					job_panel:child("risk_text_panel"):animate(function(o)
						over(0.3, function(p)
							panels[i]:set_y(math.lerp(panels[i]:y(), 0, p))
							if panels[i - 1] then
								panels[i - 1]:set_y(math.lerp(panels[i - 1]:y(), h, p))
							end
						end)
					end)
					wait(0.3)
				end
				if managers.job:current_difficulty_stars() + 2 == #tweak_data.difficulties then
					local glow = job_panel:child("risk_panel"):bitmap({
						alpha = 0,
						layer = 0,
						texture = "guis/textures/pd2/crimenet_marker_glow",
						color = Color.red
					})
					glow:set_x(panels_skulls[#panels_skulls]:x())
					over(0.5, function(o)
						glow:set_alpha(math.lerp(0, 1, o))
					end)
				end
			end)
		end
		self._blackscreen_panel:set_alpha(1)
	end
elseif string.lower(RequiredScript) == "lib/network/base/basenetworksession" then
	if not ShaveHUD:getSetting({"Misc", "KICK_FRIEND"}, true) then
		return
	end

	local Original_on_peer_kicked = BaseNetworkSession.on_peer_kicked
	function BaseNetworkSession:on_peer_kicked(peer, peer_id, message_id)
		if Network:is_server() then
			if message_id == 0 then
				if Steam:logged_on() then
					for _, user in ipairs(Steam:friends() or {}) do
						if user:id() == peer:user_id() then
							return Original_on_peer_kicked(self, peer, peer_id, 1)
						end
					end
				end
			end
		end
		return Original_on_peer_kicked(self, peer, peer_id, message_id)
	end
elseif string.lower(RequiredScript) == "lib/tweak_data/lootdroptweakdata" then
	if not ShaveHUD:getSetting({"Misc", "REDUNDANT_CARD_REMOVAL"}, true) then
		return
	end

	local old_data = LootDropTweakData.init
	function LootDropTweakData:init(tweak_data)
		old_data(self, tweak_data)

		local min = 10
		local max = 100
		local range = {
			cash = {0, 0},
			weapon_mods = {50, 45},
			colors = {6, 11},
			textures = {7, 12},
			materials = {7, 12},
			masks = {10, 15},
			xp = {0, 0}
		}
		for i = min, max, 10 do
			local cash = math.lerp(range.cash[1], range.cash[2], i / max)
			local weapon_mods = math.lerp(range.weapon_mods[1], range.weapon_mods[2], i / max)
			local colors = math.lerp(range.colors[1], range.colors[2], i / max)
			local textures = math.lerp(range.textures[1], range.textures[2], i / max)
			local materials = math.lerp(range.materials[1], range.materials[2], i / max)
			local masks = math.lerp(range.masks[1], range.masks[2], i / max)
			local xp = math.lerp(range.xp[1], range.xp[2], i / max)
			self.WEIGHTED_TYPE_CHANCE[i] = {
				cash = cash,
				weapon_mods = weapon_mods,
				colors = colors,
				textures = textures,
				materials = materials,
				masks = masks,
				xp = xp
			}
		end
	end
end