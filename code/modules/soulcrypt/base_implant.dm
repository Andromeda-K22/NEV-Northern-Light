/*
Soulcrypt base implant. All base functions are held here.
This also contains the basic functions of the modules.
*/

/obj/item/weapon/implant/soulcrypt
	name = "soulcrypt"
	desc = "A small, immensely complex biocompatible computer. Basic functions include DNA sequence storage, neural engram backups, access transciever functions, and an internal fuel cell using the host's nutrients."
	icon = 'icons/obj/soulcrypt.dmi'
	icon_state = "frame"
	w_class = ITEM_SIZE_SMALL
	origin_tech = list(TECH_MATERIAL=2, TECH_BIO=7, TECH_DATA=5)


	var/host_dead = FALSE //Our host is dead. Or not? Binary doesn't care for philosphy.
	var/was_emp  = FALSE//Were we emp'd? This triggers the longer memory gap message.
	var/sent_revive_notice  = FALSE //We've sent the revive notice to our host, so we're not going to send it again. Until they die again, at least...

	var/energy = 100 //How much energy do we have stored up from user nutrition?
	var/max_energy = 100 //The maximum amount of energy we can have stored.
	var/integrity = 100 //How much integrity we have - this is used pretty rarely, but certain modules might use it.
	var/max_integrity = 100 //Maximum integrity.
	var/next_energy_warning //In deciseconds.
	var/next_integrity_warning //In deciseconds.
	var/host_death_time //What time did our host die - if null, our host has not yet died, or the revive notice has been sent.

	var/nutrition_usage_setting = NUTRITION_USAGE_LOW //These can be found in soulcrypt.dm, under DEFINES.

	var/datum/dna/host_dna
	var/datum/mind/host_mind

	var/low_nutrition_message = "Host malnutrition detected; fuel cell disengaged. Running on internal reserves. Disengage modules to preserve reserves."
	var/low_energy_input_message = "Warning: Current energy usage exceeds fuel cell input. Reduce usage to avoid module shutdown."
	var/integrity_warning_message = "Warning: system integrity low. Service required soon."

	var/list/starting_modules = list()
	var/list/modules = list()
	var/list/access = list()

	var/good_sound = 'sound/machines/synth_yes.ogg'
	var/bad_sound = 'sound/machines/synth_no.ogg'
	var/very_bad_sound = 'sound/machines/warning-buzzer.ogg'

//Inherited procs

/obj/item/weapon/implant/soulcrypt/Initialize()
	. = ..()
	add_modules(starting_modules)

/obj/item/weapon/implant/soulcrypt/update_icon()
	overlays.Cut()
	if(host_mind && host_dna)
		overlays += image('icons/obj/soulcrypt.dmi', "soulcrypt_active")
	else
		overlays += image('icons/obj/soulcrypt.dmi', "soulcrypt_inactive")

/obj/item/weapon/implant/soulcrypt/install(mob/living/target, organ, mob/user)
	. = ..()
	activate()

/obj/item/weapon/implant/soulcrypt/activate()
	if(!host_mind)
		host_mind = wearer.mind
	if(!host_dna)
		host_dna = wearer.dna.Clone()
	if(!is_processing)
		START_PROCESSING(SSobj, src)

/obj/item/weapon/implant/soulcrypt/deactivate()
	STOP_PROCESSING(SSobj, src)

/obj/item/weapon/implant/soulcrypt/GetAccess()
	return access

/obj/item/weapon/implant/soulcrypt/emp_act()
	was_emp = TRUE
	deactivate_modules()

/obj/item/weapon/implant/soulcrypt/Process()
	heartbeat()
	handle_energy()
	handle_integrity()
	handle_modules()


//Unique procs

/obj/item/weapon/implant/soulcrypt/proc/heartbeat() //Pretty much just checks if the host is alive or dead and does things from there.
	if(wearer.stat == DEAD && !host_dead)
		host_death_time = world.time
		host_dead = TRUE
		send_death_message()

	if(wearer.stat != DEAD && host_dead)
		host_death_time = null
		host_dead = FALSE

/obj/item/weapon/implant/soulcrypt/proc/send_death_message() //Sends the death message whenever the person who has this dies.
	to_chat(wearer, SPAN_NOTICE("You are dead, whatever the cause, you are dead. With luck, someone will retrieve your soulcrypt and clone you - otherwise, welcome to purgatory."))
	switch(was_emp)
		if(TRUE)
			to_chat(wearer, SPAN_WARNING("Your soulcrypt has been subjected to an electromagnetic pulse, and thus your neural engrams are unreliable. It's automatically pruning the unsalvagable memories, about five minutes worth. Perhaps more."))
		if(FALSE)
			to_chat(wearer, SPAN_NOTICE("Luckily, your soulcrypt takes neural backups every thirty seconds. When you're cloned, you'll remember everything up to thirty seconds before your death."))

/obj/item/weapon/implant/soulcrypt/proc/send_revive_notice() //Triggered by the cloner.
	to_chat(wearer, SPAN_NOTICE("Congratulations on a new lease on life, you're being cloned."))
	switch(was_emp)
		if(TRUE)
			to_chat(wearer, SPAN_WARNING("Your soulcrypt has been subjected to an electromagnetic pulse, and you're missing about five minutes of memory from before your death."))
		if(FALSE)
			to_chat(wearer, SPAN_NOTICE("As your conciousness slowly emerges from the muck of resurrection, you remember everything that's occured up to about thirty seconds before your death."))

/obj/item/weapon/implant/soulcrypt/proc/handle_modules() //Loops through the modules in the modules list, and handles their effects.
	for(var/datum/soulcrypt_module/M in modules)
		if(M.active)
			if(energy <= 0) //No energy, just deactivate all the modules.
				M.deactivate()
				continue
			M.handle_effects()

/obj/item/weapon/implant/soulcrypt/proc/add_modules(var/starting_list) //Adds modules from a list.
	for(var/M in starting_list)
		add_module(M)

/obj/item/weapon/implant/soulcrypt/proc/add_module(var/module_path)
	var/datum/soulcrypt_module/module = new module_path
	modules += module
	module.owner = src

/obj/item/weapon/implant/soulcrypt/proc/remove_module(var/datum/soulcrypt_module/module) //Removes a module from the implant.
	module.owner = null
	qdel(module)

/obj/item/weapon/implant/soulcrypt/proc/deactivate_modules() //Deactivates all active modules.
	for(var/datum/soulcrypt_module/M in modules)
		if(M.active)
			M.deactivate()

/obj/item/weapon/implant/soulcrypt/proc/handle_energy() //Take some nutrition, provide energy. Remove the energy used by any active modules from this amount.
	var/energy_to_add = 0
	var/active_module_drain = 0
	var/nutrition_to_remove = 0
	var/user_starving = FALSE

	if(energy >= max_energy)
		return

	for(var/datum/soulcrypt_module/M in modules) //Loop through modules that are active and have an upkeep cost, figure out how much the active drain will take from the energy we have.
		if(M.active && M.has_energy_upkeep)
			active_module_drain += M.energy_cost

	if(wearer.nutrition < (wearer.max_nutrition / 2))
		if(next_energy_warning < world.time + ENERGY_WARNING_DELAY)
			send_host_message(low_nutrition_message, MESSAGE_DANGER)
			next_energy_warning = world.time + ENERGY_WARNING_DELAY
		user_starving = TRUE

	switch(nutrition_usage_setting) //Get how much nutrition we use per tick.
		if(NUTRITION_USAGE_LOW)
			nutrition_to_remove = 1
		if(NUTRITION_USAGE_MEDIUM)
			nutrition_to_remove = 2
		if(NUTRITION_USAGE_HIGH)
			nutrition_to_remove = 3

	if(!user_starving)
		energy_to_add = nutrition_to_remove * SOULCRYPT_ENERGY_PER_NUTRITION //Simple maths to figure out what our energy budget is.

	energy_to_add -= active_module_drain

	if(active_module_drain > energy_to_add && (next_energy_warning < world.time + ENERGY_WARNING_DELAY) && !user_starving)
		send_host_message(low_energy_input_message, MESSAGE_WARNING)
		next_energy_warning = world.time + ENERGY_WARNING_DELAY

	energy += energy_to_add
	energy = CLAMP(energy, 0, 100)

	wearer.adjustNutrition(nutrition_to_remove)

/obj/item/weapon/implant/soulcrypt/proc/handle_integrity()
	var/integrity_loss = 0

	for(var/datum/soulcrypt_module/M in modules)
		if(M.active && M.causes_wear)
			integrity_loss += M.wear_cause_amount

	if(integrity < (max_integrity / 2) && (next_integrity_warning < world.time + INTEGRITY_WARNING_DELAY))
		send_host_message(integrity_warning_message, MESSAGE_WARNING)
		next_integrity_warning = world.time + INTEGRITY_WARNING_DELAY

	integrity -= integrity_loss
	integrity = CLAMP(integrity, 0, 100)


/obj/item/weapon/implant/soulcrypt/proc/send_host_message(var/message, var/message_type = MESSAGE_NOTICE)
	switch(message_type)
		if(MESSAGE_NOTICE)
			to_chat(wearer, SPAN_NOTICE("\icon[src] transmits calmly, '[message]'"))
			wearer << good_sound
		if(MESSAGE_WARNING)
			to_chat(wearer, SPAN_WARNING("\icon[src] transmits urgently, '[message]'"))
			wearer << bad_sound
		if(MESSAGE_DANGER)
			to_chat(wearer, SPAN_DANGER("\icon[src] transmits urgently, '[message]'"))
			wearer << very_bad_sound



/datum/soulcrypt_module
	var/name = "soulcrypt module"
	var/description = "A module for a soulcrypt."

	var/cooldown_time = 0 //Time in deciseconds
	var/cooldown_delay = 0 //Time in deciseconds.

	var/energy_cost = 0 //One time, or over time.
	var/wear_cause_amount = 0 //How much wear does this cause on the soulcrypt? Should be rather low - something like 0.02.

	var/has_cooldown = FALSE //Do we have a cooldown?
	var/uses_energy = FALSE //Do we use energy from the soulcrypt?
	var/active = FALSE //Are we even being used right now?
	var/has_energy_upkeep = FALSE //Do we use energy per tick to stay active?
	var/causes_wear = FALSE //Does this cause wear on the soulcrypt's systems?

	var/deactivation_message = "Module deactivated."
	var/activation_message = "Module activated."

	var/list/req_access = list()
	var/list/req_one_access = list()

	var/obj/item/weapon/implant/soulcrypt/owner //The soulcrypt that owns us.

/datum/soulcrypt_module/proc/message_user(var/message, var/message_type = MESSAGE_NOTICE)
	owner.send_host_message(message, message_type)

/datum/soulcrypt_module/proc/check_can_activate() //Can we activate? Do we have enough energy, is our cooldown over, and does our user have access to this?
	if(has_cooldown && (cooldown_time > world.time + cooldown_delay))
		return FALSE

	if(req_access)
		if(!owner.check_access(req_access, req_one_access, owner.GetAccess()))
			return FALSE

	if(uses_energy && (owner.energy < energy_cost))
		return FALSE

	if(owner.wearer.incapacitated())
		return FALSE

	return TRUE

/datum/soulcrypt_module/proc/activate()
	if(!check_can_activate())
		return
	active = TRUE
	var/activation_msg = "<b>[name]:</b> [activation_message]"
	owner.send_host_message(activation_msg, MESSAGE_NOTICE)

/datum/soulcrypt_module/proc/deactivate()
	active = FALSE
	var/deactivation_msg = "<b>[name]:</b> [deactivation_message]"
	owner.send_host_message(deactivation_msg, MESSAGE_NOTICE)

/datum/soulcrypt_module/proc/handle_effects() //What do we do when the soulcrypt itself calls handle_modules()?
	return
