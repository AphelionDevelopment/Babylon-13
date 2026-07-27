/// Href keys a gated player may still send - the readiness ping, the server swap button, and BYOND's routing key.
GLOBAL_LIST_INIT(symphony_gate_free_hrefs, list("src", "title_is_ready", "server_swap"))

/// TRUE only when EVERY key in the href is gate-free. One unrecognised key means the gate applies.
/proc/symphony_href_is_gate_free(list/href_list)
	if(!length(href_list))
		return FALSE
	for(var/key in href_list)
		if(!(key in GLOB.symphony_gate_free_hrefs))
			return FALSE
	return TRUE

/// The single gate. TRUE means this new_player is blocked from readying up or joining the round.
/// Inert (returns FALSE) when the module is disabled.
/mob/dead/new_player/proc/symphony_blocks_play()
	if(!CONFIG_GET(flag/symphony_enabled))
		return FALSE
	if(!client)
		return TRUE
	// Staff are exempt, matching the OOC hook. The gate is fail-closed, so without this a DB blip locks the admin team out of the round.
	if(client.holder)
		return FALSE
	return !is_symphony_whitelisted(ckey)

/// Message shown at the gate, pointing players at the Get Whitelisted verb.
/mob/dead/new_player/proc/symphony_gate_notice()
	// `key`, not `ckey` - ckey() strips the hyphen so is_guest_key would never match.
	if(is_guest_key(key))
		to_chat(src, span_userdanger("You are logged in as a BYOND guest."))
		to_chat(src, span_warning("Guest accounts cannot be whitelisted. Sign in with a real BYOND account and reconnect to play."))
		return
	to_chat(src, span_userdanger("You are not whitelisted."))
	to_chat(src, span_warning("<a href='byond://?src=[REF(src)];get_whitelisted=1'><b>Click here to Get Whitelisted</b></a> - link your Discord account to gain access. You must stay in the Discord with the whitelist role to play."))
