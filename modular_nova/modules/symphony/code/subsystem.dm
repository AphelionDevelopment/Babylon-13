/// Safety net: periodically re-checks connected players in case a revoke push was missed.
SUBSYSTEM_DEF(symphony)
	name = "Discord Whitelist"
	wait = 5 MINUTES
	ss_flags = SS_BACKGROUND | SS_NO_INIT
	runlevels = RUNLEVEL_LOBBY | RUNLEVEL_SETUP | RUNLEVEL_GAME

/datum/controller/subsystem/symphony/fire()
	if(!CONFIG_GET(flag/symphony_enabled))
		return
	// One query for the whole server rather than a blocking round-trip per player. null means "couldn't
	// check" (no DB, query failed) — do nothing, so a transient blip can't mass-revoke everyone. An
	// empty list genuinely means nobody holds the role.
	var/list/holders = symphony_ingame_role_ckeys("whitelist")
	if(isnull(holders))
		return
	// Iterate a copy: revoking can qdel a client, and mutating GLOB.clients mid-loop skips entries.
	for(var/client/checked as anything in GLOB.clients.Copy())
		if(!checked || !checked.ckey || holders[checked.ckey])
			continue
		// Lobby players used to be skipped entirely, so a revoke push lost in transit was never repaired
		// and they still spawned at round start. Only act when they are actually ready, so this doesn't
		// re-notify every five minutes.
		if(isnewplayer(checked.mob))
			var/mob/dead/new_player/lobby = checked.mob
			if(lobby.ready != PLAYER_NOT_READY)
				lobby.ready = PLAYER_NOT_READY
				lobby.show_title_screen()
			continue
		if(!checked.mob)
			continue
		symphony_revoke(checked.ckey)
