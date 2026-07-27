/// Begins revocation for a ckey: warn, wait out the grace period, then re-check and return them to the lobby if still not whitelisted.
/proc/symphony_revoke(target_ckey)
	target_ckey = ckey(target_ckey)
	// The push IS the news, so drop any cached answer rather than letting the TTL delay enforcement.
	symphony_invalidate_whitelist_cache(target_ckey)
	var/client/found = GLOB.directory[target_ckey]
	if(!found)
		return
	// Staff exemption, matching gate.dm. Without it, an admin who is simply not in the Discord with the
	// mapped role - exactly the state that exemption exists to tolerate - is torn out of their body
	// within one sweep, leaving nobody able to fix it in-round.
	if(found.holder)
		return
	// Already in the lobby - just refresh the title screen to the gate, no grace needed.
	if(isnewplayer(found.mob))
		var/mob/dead/new_player/lobby = found.mob
		to_chat(found, span_userdanger("Your Discord whitelist role was removed."))
		// Clearing readiness is the point: round start reads `ready` directly and never consults the
		// gate, so a player who readied up while whitelisted would still be spawned as crew.
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
		// The lobby mob's Login() mints a fresh /datum/mind for this key. Retiring the old one first
		// stops the same key owning two active minds (and two bodies) if the role is later restored.
		if(old_mob.mind)
			old_mob.mind.active = FALSE
	var/mob/dead/new_player/lobby = new()
	lobby.key = target.key
	lobby.show_title_screen()
	// Tell the admins. The body is deliberately left behind rather than gibbed, which means a revoke
	// landing on an antagonist mid-round orphans a live body still holding its objectives and gear. That
	// is the intended behaviour, but it must not be silent: without this the first anyone knew was a
	// confused player, and a bot desync or a compromised Discord account fires the identical path.
	message_admins("Symphony: [key_name_admin(target)] was returned to the lobby by whitelist enforcement. Their body was left in place[old_mob ? " at [AREACOORD(old_mob)]" : ""].")

/// A revoke that lands while the player is disconnected is lost: the grace timer is one-shot and
/// returns without rescheduling when the client is gone. Re-check on connect so a relog can't be used
/// to sit out enforcement.
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

/// whitelist_grant handler effect: tell a waiting player they can now join and refresh their lobby.
/proc/symphony_notify_grant(target_ckey)
	symphony_invalidate_whitelist_cache(target_ckey)
	var/client/found = GLOB.directory[ckey(target_ckey)]
	if(!found)
		return
	to_chat(found, span_greentext("You are now whitelisted - you can join the round."))
	var/mob/dead/new_player/lobby_mob = found.mob
	if(istype(lobby_mob))
		lobby_mob.show_title_screen()
