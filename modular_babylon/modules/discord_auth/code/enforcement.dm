/// Begins revocation for a ckey: warn, wait out the grace period, then re-check and return them to the lobby if still not whitelisted.
/proc/discord_auth_revoke(target_ckey)
	target_ckey = ckey(target_ckey)
	var/client/found = GLOB.directory[target_ckey]
	if(!found || isnewplayer(found.mob))
		return
	var/grace = CONFIG_GET(number/discord_auth_grace_seconds)
	to_chat(found, span_userdanger("Your Discord whitelist role was removed. You will be returned to the lobby in [grace] seconds unless it is restored."))
	addtimer(CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(discord_auth_enforce_kick), target_ckey), grace SECONDS, TIMER_UNIQUE | TIMER_OVERRIDE)

/// Fires after the grace period. Returns the player to the lobby unless their role came back.
/proc/discord_auth_enforce_kick(target_ckey)
	var/client/found = GLOB.directory[target_ckey]
	if(!found || isnewplayer(found.mob))
		return
	if(is_discord_whitelisted(target_ckey))
		to_chat(found, span_notice("Whitelist role restored — you may continue playing."))
		return
	to_chat(found, span_userdanger("Whitelist lost. Returning you to the lobby."))
	discord_auth_return_to_lobby(found)

/// Moves a client back to a fresh lobby (new_player) mob, leaving their old body as an SSD.
/proc/discord_auth_return_to_lobby(client/target)
	var/mob/old_mob = target.mob
	var/mob/dead/new_player/lobby = new()
	lobby.key = target.key
	if(old_mob && !isnewplayer(old_mob))
		old_mob.log_message("returned to lobby by discord whitelist enforcement", LOG_GAME)

/// whitelist_grant handler effect: tell a waiting player they can now join and refresh their lobby.
/proc/discord_auth_notify_grant(target_ckey)
	var/client/found = GLOB.directory[ckey(target_ckey)]
	if(!found)
		return
	to_chat(found, span_greentext("You are now whitelisted — you can join the round."))
	var/mob/dead/new_player/lobby_mob = found.mob
	if(istype(lobby_mob))
		lobby_mob.show_title_screen()
