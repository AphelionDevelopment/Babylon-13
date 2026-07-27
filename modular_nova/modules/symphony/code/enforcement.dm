/// Starts a revoke for a ckey. Warn them, wait out the grace period, then send them to the lobby if still unwhitelisted.
/proc/symphony_revoke(target_ckey)
	target_ckey = ckey(target_ckey)
	// The push is the news, so drop any cached answer instead of waiting out the TTL.
	symphony_invalidate_whitelist_cache(target_ckey)
	var/client/found = GLOB.directory[target_ckey]
	if(!found)
		return
	// Staff exemption, matching gate.dm - an admin who isn't in the Discord keeps their body.
	if(found.holder)
		return
	// Already in the lobby - just refresh the title screen to the gate, no grace needed.
	if(isnewplayer(found.mob))
		var/mob/dead/new_player/lobby = found.mob
		to_chat(found, span_userdanger("Your Discord whitelist role was removed."))
		// Round start reads `ready` directly and never consults the gate, so clear it or they still spawn as crew.
		lobby.ready = PLAYER_NOT_READY
		lobby.show_title_screen()
		return
	var/grace = CONFIG_GET(number/symphony_grace_seconds)
	to_chat(found, span_userdanger("Your Discord whitelist role was removed. You will be returned to the lobby in [grace] seconds unless it is restored."))
	addtimer(CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(symphony_enforce_kick), target_ckey), grace SECONDS, TIMER_UNIQUE | TIMER_OVERRIDE)

/// Fires after the grace period. Returns the player to the lobby unless their role came back.
/proc/symphony_enforce_kick(target_ckey)
	var/client/found = GLOB.directory[target_ckey]
	if(!found || isnewplayer(found.mob))
		return
	// Re-checked here too: the grace period is long enough for someone to be adminned in between.
	if(found.holder)
		return
	if(is_symphony_whitelisted(target_ckey))
		to_chat(found, span_notice("Whitelist role restored - you may continue playing."))
		return
	to_chat(found, span_userdanger("Whitelist lost. Returning you to the lobby."))
	symphony_return_to_lobby(found)

/// Moves a client back to a fresh lobby (new_player) mob, leaving their old body as an SSD.
/proc/symphony_return_to_lobby(client/target)
	var/mob/old_mob = target.mob
	if(old_mob && !isnewplayer(old_mob))
		old_mob.log_message("returned to lobby by discord whitelist enforcement", LOG_GAME)
		// The lobby mob's Login() mints a fresh mind, so retire the old one or the key ends up owning two.
		if(old_mob.mind)
			old_mob.mind.active = FALSE
	var/mob/dead/new_player/lobby = new()
	lobby.key = target.key
	lobby.show_title_screen()
	// The body is left behind on purpose, so a revoke on an antag orphans a live one. Never do that silently.
	message_admins("Symphony: [key_name_admin(target)] was returned to the lobby by whitelist enforcement. Their body was left in place[old_mob ? " at [AREACOORD(old_mob)]" : ""].")

/// Re-check on connect. The grace timer is one-shot, so a relog could otherwise sit out enforcement.
/client/New()
	. = ..()
	if(!.)
		return
	if(!CONFIG_GET(flag/symphony_enabled))
		return
	if(!ckey || !mob || isnewplayer(mob)) // the lobby has its own gate
		return
	if(holder) // staff exemption, as in gate.dm
		return
	if(is_symphony_whitelisted(ckey))
		return
	symphony_revoke(ckey)

/// Tells a waiting player their role came through and refreshes their lobby.
/proc/symphony_notify_grant(target_ckey)
	symphony_invalidate_whitelist_cache(target_ckey)
	var/client/found = GLOB.directory[ckey(target_ckey)]
	if(!found)
		return
	to_chat(found, span_greentext("You are now whitelisted - you can join the round."))
	var/mob/dead/new_player/lobby_mob = found.mob
	if(istype(lobby_mob))
		lobby_mob.show_title_screen()
