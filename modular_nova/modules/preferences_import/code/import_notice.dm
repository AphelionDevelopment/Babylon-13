/**
 * One-time chat notice telling an arriving player they can bring their characters with them.
 *
 * Tracked by a savefile key rather than player_age, so it needs no database and cannot fire twice.
 */

/// How long after login to print the notice, late enough to land under the MOTD and changelog.
#define PREFS_IMPORT_NOTICE_DELAY (12 SECONDS)

/// Queues the import notice. Deferred off the login tick, since the whitelist lookup hits the database.
/client/proc/babylon_offer_preferences_import()
	addtimer(CALLBACK(src, PROC_REF(babylon_show_import_notice)), PREFS_IMPORT_NOTICE_DELAY)

/client/proc/babylon_show_import_notice()
	if(QDELETED(src) || !prefs?.savefile)
		return
	if(prefs.savefile.get_entry(PREFS_IMPORT_NOTICE_KEY))
		return
	if(CONFIG_GET(flag/forbid_preferences_import))
		return
	// Not marked as seen when they fail this, so somebody who is whitelisted later still gets told once.
	if(!symphony_holds_whitelist_role(ckey))
		return

	prefs.savefile.set_entry(PREFS_IMPORT_NOTICE_KEY, TRUE)
	prefs.savefile.save()

	var/list/lines = list(
		span_boldnotice("Coming from another server? You can bring your characters with you."),
		span_notice("1. On the server you are leaving, run <b>Export Preferences</b> from its OOC tab and keep the .json file it saves. Not every server offers this."),
		span_notice("2. Here, <a href='byond://?babylon_import_prefs=1'>click to import</a>, or run <b>Import Preferences</b> from your own OOC tab, and pick that file."),
		span_warning("Importing replaces every character you currently have. A backup of your existing preferences is kept, and you will be reconnected once it finishes."),
		span_notice("<i>You will only see this message once.</i>"),
	)
	to_chat(src, jointext(lines, "<br>"))

#undef PREFS_IMPORT_NOTICE_DELAY
