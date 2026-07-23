/// The single gate. TRUE means this new_player is blocked from readying up or joining the round.
/// Inert (returns FALSE) when the module is disabled.
/mob/dead/new_player/proc/discord_auth_blocks_play()
	if(!CONFIG_GET(flag/discord_auth_enabled))
		return FALSE
	if(!client)
		return TRUE
	return !is_discord_whitelisted(ckey)

/// Message shown at the gate, pointing players at the Get Whitelisted verb.
/mob/dead/new_player/proc/discord_auth_gate_notice()
	to_chat(src, span_userdanger("You are not whitelisted."))
	to_chat(src, span_warning("Use the <b>Get Whitelisted</b> verb in the OOC tab to link your Discord account and gain access. You must stay in the Discord with the whitelist role to play."))
