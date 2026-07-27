/**
 * Href keys a gated player may still send: the title screen's readiness ping, the server swap button,
 * and BYOND's own routing key.
 *
 * These are checked for EXCLUSIVITY, not presence. The original guard asked "is an allowed key present",
 * which any extra parameter satisfied: `?src=REF;title_is_ready=1;toggle_ready=1` short-circuited the
 * gate and fell through to the ungated toggle_ready handler, readying up an unwhitelisted player
 * silently (symphony_blocks_play was never even called, so no notice printed). title_is_ready is handled
 * LAST in that Topic, so it costs the attacker nothing on the way past.
 */
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
	// Staff are exempt, matching the OOC hook. The gate is fail-closed, so without this a DB blip - or
	// simply switching enforcement on before any role is mapped - locks the admin team out of joining
	// and observing, leaving nobody able to fix it in-round.
	if(client.holder)
		return FALSE
	return !is_symphony_whitelisted(ckey)

/// Message shown at the gate, pointing players at the Get Whitelisted verb.
/mob/dead/new_player/proc/symphony_gate_notice()
	// `key`, not `ckey`: is_guest_key matches the literal "Guest-" and ckey() strips the hyphen, so the
	// ckey form could never match and this check was inert.
	if(is_guest_key(key))
		to_chat(src, span_userdanger("You are logged in as a BYOND guest."))
		to_chat(src, span_warning("Guest accounts cannot be whitelisted. Sign in with a real BYOND account and reconnect to play."))
		return
	to_chat(src, span_userdanger("You are not whitelisted."))
	to_chat(src, span_warning("<a href='byond://?src=[REF(src)];get_whitelisted=1'><b>Click here to Get Whitelisted</b></a> - link your Discord account to gain access. You must stay in the Discord with the whitelist role to play."))
