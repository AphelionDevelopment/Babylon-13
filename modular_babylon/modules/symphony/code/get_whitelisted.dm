/client/verb/get_whitelisted()
	set name = "Get Whitelisted"
	set category = "OOC"
	set desc = "Link your Discord account to gain whitelist access."

	if(is_guest_key(ckey))
		to_chat(src, span_warning("BYOND guest accounts cannot be whitelisted. Sign in with a real BYOND account and reconnect."))
		return
	if(!CONFIG_GET(flag/symphony_enabled))
		to_chat(src, span_warning("Discord whitelisting is not enabled on this server."))
		return
	var/base_url = CONFIG_GET(string/symphony_url)
	if(!base_url)
		to_chat(src, span_warning("The whitelist service is not configured. Contact an admin."))
		return
	if(!SSdbcore.Connect())
		to_chat(src, span_warning("The database is unavailable right now. Try again shortly."))
		return

	var/token = SSdiscord.get_or_generate_one_time_token_for_ckey(ckey)
	if(!token)
		to_chat(src, span_warning("Could not generate a whitelist token. Try again shortly."))
		return

	var/url = "[base_url]/auth/start?ticket=[url_encode(token)]"
	src << link(url)
	to_chat(src, span_notice("Opening the whitelist page in your browser. If nothing happens, open this link:"))
	to_chat(src, span_notice("<a href=\"[url]\">[url]</a>"))
