/**
 * Version of this game module, reported to SSymphony so it can detect a mismatched pair.
 *
 * The two halves share database tables and this topic protocol, and drift between them fails SILENTLY
 * rather than loudly: the symptom is usually "nobody gets whitelisted" with no error anywhere. SSymphony
 * compares this against the minimum it needs and warns on the panel.
 *
 * BUMP THIS whenever the module changes in a way SSymphony can observe: a new or changed world_topic,
 * a change to what an existing topic returns, or a change to a shared database table. Then raise
 * REQUIRED_GAME_MODULE in SSymphony (src/core/gameModule.ts) to match, and tag that release vX.Y.Z-dm.
 */
#define SYMPHONY_MODULE_VERSION 2

/// Live server status for the SSymphony panel. Returns a raw list; the caller passes format=json.
/datum/world_topic/symphony_server_status
	keyword = "symphony_server_status"
	require_comms_key = TRUE
	log = FALSE

/datum/world_topic/symphony_server_status/Run(list/input)
	. = list()
	// Absent from the response entirely on a module older than this field, which is itself the signal
	// that the game side predates version reporting.
	.["module_version"] = SYMPHONY_MODULE_VERSION
	var/state = SSticker?.current_state
	.["game_state"] = state
	switch(state)
		if(GAME_STATE_STARTUP)
			.["game_state_name"] = "startup"
		if(GAME_STATE_PREGAME)
			.["game_state_name"] = "lobby"
		if(GAME_STATE_SETTING_UP)
			.["game_state_name"] = "setting up"
		if(GAME_STATE_PLAYING)
			.["game_state_name"] = "playing"
		if(GAME_STATE_FINISHED)
			.["game_state_name"] = "finished"
	.["round_id"] = GLOB.round_id

	// This is a Dynamic-based fork - no gamemode/storyteller. tier is null until roundstart.
	var/datum/dynamic_tier/tier = SSdynamic?.current_tier
	.["dynamic_tier"] = tier?.name
	var/list/rulesets = list()
	for(var/datum/dynamic_ruleset/rule as anything in SSdynamic?.executed_rulesets)
		rulesets += rule.name
	.["executed_rulesets"] = rulesets

	var/rst = SSticker?.round_start_time
	.["round_elapsed_secs"] = rst ? round((world.time - rst) / 10) : 0
	.["round_elapsed_text"] = rst ? DisplayTimeText(world.time - rst) : null

	.["clients"] = length(GLOB.clients)
	.["players_ingame"] = length(GLOB.player_list)
	.["players_alive"] = length(GLOB.alive_player_list)
	.["players_dead"] = length(GLOB.dead_player_list)
	.["observers"] = length(GLOB.current_observers_list)
	.["lobby"] = length(GLOB.new_player_list)
	.["admins_online"] = length(GLOB.admins)

	var/datum/map_config/mapcfg = SSmapping?.current_map
	.["map_name"] = mapcfg?.map_name
	.["station_name"] = GLOB.station_name

	var/obj/docking_port/mobile/emergency/shuttle = SSshuttle?.emergency
	if(shuttle)
		.["shuttle_mode"] = shuttle.mode
		.["shuttle_status"] = shuttle.getModeStr()
		.["shuttle_time_left_secs"] = shuttle.timeLeft(10)

	.["server_name"] = CONFIG_GET(string/servername)
	.["port"] = world.port
	.["byond_version"] = "[world.byond_version].[world.byond_build]"
	.["revision"] = GLOB.revdata?.commit

/// Live player list with per-player detail for the panel. Sensitive (ckeys, antag roles) - comms-key gated.
/datum/world_topic/symphony_player_list
	keyword = "symphony_player_list"
	require_comms_key = TRUE
	log = FALSE

/datum/world_topic/symphony_player_list/Run(list/input)
	. = list()
	var/list/players = list()
	// Fetch the whitelist-role holders once, instead of a per-player query inside the loop (60 players
	// was 60 serial DB round-trips with the game stalled on each panel refresh). This reports actual
	// role-holding, independent of whether the gate is enforced - same as the old per-player call. null
	// means the lookup failed; everyone then reads FALSE, matching the single-ckey path's fail-closed.
	var/list/whitelisted_ckeys = symphony_ingame_role_ckeys("whitelist")
	// GLOB.clients covers lobby + in-round + observers, one client per connected player.
	for(var/client/connected as anything in GLOB.clients)
		var/mob/player_mob = connected.mob
		var/datum/mind/player_mind = player_mob?.mind

		var/state
		if(isnewplayer(player_mob))
			state = "lobby"
		else if(isobserver(player_mob))
			state = "observer"
		else if(isnull(player_mob))
			state = "none"
		else
			switch(player_mob.stat)
				if(DEAD)
					state = "dead"
				if(UNCONSCIOUS)
					state = "unconscious"
				else
					state = "alive"

		var/list/antag_names = list()
		if(player_mind)
			for(var/datum/antagonist/antag as anything in player_mind.antag_datums)
				antag_names += "[antag.name]"

		var/datum/admins/holder = connected.holder
		players += list(list(
			"ckey" = connected.ckey,
			"character_name" = player_mob?.real_name,
			"job" = player_mind?.assigned_role?.title,
			"is_antag" = player_mob ? player_mob.is_antag() : FALSE,
			"antags" = antag_names,
			"is_admin" = !!holder,
			"admin_rank" = holder ? holder.rank_names() : null,
			"whitelisted" = whitelisted_ckeys?[connected.ckey] ? TRUE : FALSE,
			"state" = state,
			"ping" = round(connected.avgping, 1),
			"connected_secs" = connected.connection_time ? round((world.time - connected.connection_time) / 10) : 0,
		))

	.["count"] = length(players)
	.["players"] = players

#undef SYMPHONY_MODULE_VERSION
