/// Safety net: periodically re-checks connected players in case a revoke push was missed.
SUBSYSTEM_DEF(symphony)
	name = "Discord Whitelist"
	wait = 5 MINUTES
	ss_flags = SS_BACKGROUND | SS_NO_INIT
	runlevels = RUNLEVEL_LOBBY | RUNLEVEL_SETUP | RUNLEVEL_GAME

/datum/controller/subsystem/symphony/fire()
	if(!CONFIG_GET(flag/symphony_enabled))
		return
	// If the DB is unreachable, don't mass-revoke connected players over a transient blip.
	// New joins are still gated (fail-closed) by is_symphony_whitelisted separately.
	if(!SSdbcore.Connect())
		return
	for(var/client/checked as anything in GLOB.clients)
		if(!checked.mob || istype(checked.mob, /mob/dead/new_player))
			continue
		if(!is_symphony_whitelisted(checked.ckey))
			symphony_revoke(checked.ckey)
