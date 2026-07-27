/// Safety net: periodically re-checks connected players in case a revoke push was missed.
SUBSYSTEM_DEF(symphony)
	name = "Discord Whitelist"
	wait = 5 MINUTES
	ss_flags = SS_BACKGROUND | SS_NO_INIT
	runlevels = RUNLEVEL_LOBBY | RUNLEVEL_SETUP | RUNLEVEL_GAME

/datum/controller/subsystem/symphony/fire()
	if(!CONFIG_GET(flag/symphony_enabled))
		return
	// One query for the whole server. null means "couldn't check" so we bail, an empty list means nobody holds it.
	var/list/holders = symphony_ingame_role_ckeys("whitelist")
	if(isnull(holders))
		return
	// Iterate a copy: revoking can qdel a client, and mutating GLOB.clients mid-loop skips entries.
	for(var/client/checked as anything in GLOB.clients.Copy())
		if(!checked || !checked.ckey)
			continue
		// We already have the authoritative answer in bulk, so bin the stale per-ckey cache here.
		symphony_invalidate_whitelist_cache(checked.ckey)
		if(holders[checked.ckey])
			continue
		// Staff exemption, matching gate.dm - admins keep both their body and their readiness.
		if(checked.holder)
			continue
		// Lobby players need unreadying too, or a lost revoke push still spawns them. Only touch the ready ones.
		if(isnewplayer(checked.mob))
			var/mob/dead/new_player/lobby = checked.mob
			if(lobby.ready != PLAYER_NOT_READY)
				lobby.ready = PLAYER_NOT_READY
				lobby.show_title_screen()
			continue
		if(!checked.mob)
			continue
		symphony_revoke(checked.ckey)
