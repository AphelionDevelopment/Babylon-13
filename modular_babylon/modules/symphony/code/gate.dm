/// The single gate. TRUE means this new_player is blocked from readying up or joining the round.
/// Inert (returns FALSE) when the module is disabled.
/mob/dead/new_player/proc/symphony_blocks_play()
	if(!CONFIG_GET(flag/symphony_enabled))
		return FALSE
	if(!client)
		return TRUE
	return !is_symphony_whitelisted(ckey)

/// Message shown at the gate, pointing players at the Get Whitelisted verb.
/mob/dead/new_player/proc/symphony_gate_notice()
	if(is_guest_key(ckey))
		to_chat(src, span_userdanger("You are logged in as a BYOND guest."))
		to_chat(src, span_warning("Guest accounts cannot be whitelisted. Sign in with a real BYOND account and reconnect to play."))
		return
	to_chat(src, span_userdanger("You are not whitelisted."))
	to_chat(src, span_warning("<a href='byond://?src=[REF(src)];get_whitelisted=1'><b>Click here to Get Whitelisted</b></a> — link your Discord account to gain access. You must stay in the Discord with the whitelist role to play."))
