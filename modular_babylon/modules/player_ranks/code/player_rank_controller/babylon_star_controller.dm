/// The list of all star players.
GLOBAL_LIST_EMPTY(babylon_star_list)
GLOBAL_PROTECT(babylon_star_list)


/datum/player_rank_controller/babylon_star
	rank_title = "babylon_star"


/datum/player_rank_controller/babylon_star/New()
	. = ..()
	legacy_file_path = "[global.config.directory]/babylon/babylon_star_players.txt"


/datum/player_rank_controller/babylon_star/add_player(ckey)
	if(IsAdminAdvancedProcCall())
		return

	ckey = ckey(ckey)

	// Associative list for extra SPEED!
	GLOB.babylon_star_list[ckey] = TRUE


/datum/player_rank_controller/babylon_star/remove_player(ckey)
	if(IsAdminAdvancedProcCall())
		return

	GLOB.babylon_star_list -= ckey


/datum/player_rank_controller/babylon_star/get_ckeys_for_legacy_save()
	if(IsAdminAdvancedProcCall())
		return

	return GLOB.babylon_star_list


/datum/player_rank_controller/babylon_star/should_use_legacy_system()
	return CONFIG_GET(flag/babylon_star_legacy_system)


/datum/player_rank_controller/babylon_star/clear_existing_rank_data()
	if(IsAdminAdvancedProcCall())
		return

	GLOB.babylon_star_list = list()
