/obj/machinery/disposal/bin
	icon = 'modular_babylon/modules/aesthetics/disposals/icons/disposals.dmi'

/datum/asset/spritesheet_batched/pipes/create_spritesheets()
	. = ..()
	// Overwritten to have our own pipe sprites in it.
	insert_all_icons("", 'modular_babylon/modules/aesthetics/disposals/icons/disposals.dmi', GLOB.alldirs)
