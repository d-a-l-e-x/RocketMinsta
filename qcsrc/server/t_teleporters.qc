void trigger_teleport_use()
{
	if(teams_matter)
		self.team = activator.team;
}

float tdeath_hit;
float tdeath_deathtype;
void tdeath(entity player, entity teleporter, entity telefragger, vector telefragmin, vector telefragmax)
{
	entity head;
	vector deathmin;
	vector deathmax;
	float deathradius;
    float deathtype = (tdeath_deathtype? tdeath_deathtype : DEATH_TELEFRAG);
    float damage;
    
    if(tdeath_deathtype == DEATH_HG_TRANSLOC)
        damage = cvar("g_nadgets_transloc_damage") * Buffs_NadgetPower(player);
    
    if(!damage)
        damage = 10000;
    
	deathmin = player.absmin;
	deathmax = player.absmax;
    
	if(telefragmin != telefragmax)
	{
		if(deathmin_x > telefragmin_x) deathmin_x = telefragmin_x;
		if(deathmin_y > telefragmin_y) deathmin_y = telefragmin_y;
		if(deathmin_z > telefragmin_z) deathmin_z = telefragmin_z;
		if(deathmax_x < telefragmax_x) deathmax_x = telefragmax_x;
		if(deathmax_y < telefragmax_y) deathmax_y = telefragmax_y;
		if(deathmax_z < telefragmax_z) deathmax_z = telefragmax_z;
	}
    
	deathradius = max(vlen(deathmin), vlen(deathmax));
	for(head = findradius(player.origin, deathradius); head; head = head.chain)
		if(head != player)
			if(head.takedamage) if(!(g_freeze && head.frozen))
				if(boxesoverlap(deathmin, deathmax, head.absmin, head.absmax))
				{
					if(player.iscreature && (player.health >= 1)) {
						Damage(head, teleporter, telefragger, damage, deathtype, head.origin, '0 0 0');
                        
                        if(head.iscreature)
                        if(head.deadflag != DEAD_NO || (g_freeze && head.frozen) || (g_jailbreak && head.jb_isprisoned))
                        if(!teams_matter || head.team != player.team)
                            ++tdeath_hit;
					}
					else if(telefragger.health < 1) // corpses gib
						Damage(head, teleporter, telefragger, 10000, deathtype, head.origin, '0 0 0');
					else // dead bodies and monsters gib themselves instead of telefragging
						Damage(telefragger, teleporter, telefragger, 10000, deathtype, telefragger.origin, '0 0 0');
				}
}

void spawn_tdeath(vector v0, entity e, vector v)
{
	tdeath(e, e, e, '0 0 0', '0 0 0');
}

.entity pusher;
.float teleport_effecttime;
void TeleportPlayer(entity teleporter, entity player, vector to, vector to_angles, vector to_velocity, vector telefragmin, vector telefragmax)
{
	entity oldself;
	entity telefragger;
    entity h;
	vector from;

	if(teleporter.owner)
		telefragger = teleporter.owner;
	else
		telefragger = player;
    
	makevectors (to_angles);

	if(self.teleport_effecttime < time) // only show one teleport effect per teleporter per 0.2 seconds, for better fps
	{
		sound (player, CHAN_TRIGGER, "misc/teleport.wav", VOL_BASE, ATTN_NORM);
		pointparticles(particleeffectnum("teleport"), player.origin, '0 0 0', 1);
		pointparticles(particleeffectnum("teleport"), to + v_forward * 32, '0 0 0', 1);
		self.teleport_effecttime = time + 0.2;
	}

	// Relocate the player
	// assuming to allows PL_MIN to PL_MAX box and some more
	from = player.origin;
	setorigin(player, to);
    player.antilag_saved_origin = to; // prevent antilag from taking us back from the teleport destination
	player.oldorigin = to; // don't undo the teleport by unsticking
	player.angles = to_angles;
	player.fixangle = TRUE;
	player.velocity = to_velocity;
	BITXOR_ASSIGN(player.effects, EF_TELEPORT_BIT);
    
	UpdateCSQCProjectileAfterTeleport(player);

	if(player.classname == "player")
	{
		if(player.takedamage && player.deadflag == DEAD_NO && !g_race && !g_cts && cvar("g_telefrags") && !(g_jailbreak && player.jb_isprisoned))
			tdeath(player, teleporter, telefragger, telefragmin, telefragmax);

		// player no longer is on ground
		player.flags &~= FL_ONGROUND;

		// reset tracking of oldvelocity for impact damage (sudden velocity changes)
		player.oldvelocity = player.velocity;

		// reset tracking of who pushed you into a hazard (for kill credit)
		if(teleporter.owner)
		{
			player.pusher = teleporter.owner;
			player.pushltime = time + cvar("g_maxpushtime");
		}
		else
		{
			player.pushltime = 0;
		}

		if(player.isbot)
			player.lastteleporttime = time;

		// stop player name display
		{
			oldself = self;
			self = player;
			ClearSelectedPlayer();
			self = oldself;
		}
	}
    
    for(;(h = find(h, classname, "grapplinghook"));)
        if(h.aiment == player)
            RemoveGrapplingHook(h.owner);
}

void TeleportPlayer_NextFrame_Think() {
    TeleportPlayer(self.owner, self.enemy, self.origin, self.angles, self.velocity, self.mins, self.maxs);
    remove(self);
}

void TeleportPlayer_NextFrame(entity teleporter, entity player, vector to, vector to_angles, vector to_velocity, vector telefragmin, vector telefragmax) {
    entity e = spawn();
    e.think = TeleportPlayer_NextFrame_Think;
    e.nextthink = time;
    e.owner = teleporter;
    e.enemy = player;
    e.origin = to;
    e.angles = to_angles;
    e.velocity = to_velocity;
    e.mins = telefragmin;
    e.maxs = telefragmax;
}

void Teleport_Touch (void)
{
	entity oldself, e;
    
	if (other.health < 1)
		return;
	if not(other.flags & FL_CLIENT)	// FIXME: Make missiles firable through the teleport too
		return;

	if(self.team)
		if((self.spawnflags & 4 == 0) == (self.team != other.team))
			return;

	EXACTTRIGGER_TOUCH;
    
	if(other.classname == "player")
		RemoveGrapplingHook(other);

	if(self.enemy)
	{
		e = self.enemy;
	}
	else
	{
		RandomSelection_Init();
		for(e = world; (e = find(e, targetname, self.target)); )
		{
			if(e.cnt)
				RandomSelection_Add(e, 0, string_null, e.cnt, 0);
			else
				RandomSelection_Add(e, 0, string_null, 1, 0);
		}
		e = RandomSelection_chosen_ent;
	}

	if(!e)
	{
		sprint(other, "Teleport destination vanished. Sorry... please complain to the mapper.\n");
	}

	makevectors(e.mangle);
    
	if(e.speed)
		if(vlen(other.velocity) > e.speed)
			other.velocity = normalize(other.velocity) * max(0, e.speed);

	TeleportPlayer(self, other, e.origin + '0 0 1' * (1 - other.mins_z - 24), e.mangle, v_forward * vlen(other.velocity), '0 0 0', '0 0 0');

	if(e.target)
	{
		oldself = self;
		activator = other;
		self = e;
		SUB_UseTargets();
		self = oldself;
	}
}

void spawnfunc_info_teleport_destination (void)
{
	self.classname = "info_teleport_destination";

	self.mangle = self.angles;
	self.angles = '0 0 0';

	//setorigin (self, self.origin + '0 0 27');	// To fix a mappers' habit as old as Quake
	setorigin (self, self.origin);

	IFTARGETED
	{
	}
	else
		objerror ("^3Teleport destination without a targetname");
}

void spawnfunc_misc_teleporter_dest (void)
{
	spawnfunc_info_teleport_destination();
}

void spawnfunc_target_teleporter (void)
{
	spawnfunc_info_teleport_destination();
}

void teleport_findtarget (void)
{
	entity e;
	float n;

	n = 0;
	for(e = world; (e = find(e, targetname, self.target)); )
	{
		++n;
		if(e.movetype == MOVETYPE_NONE)
			waypoint_spawnforteleporter(self, e.origin, 0);
		if(e.classname != "info_teleport_destination")
			print("^3MAPPER ERROR: teleporter does target an invalid teleport destination entity. Angles will not work.\n");
	}

	if(n == 0)
	{
		// no dest!
		objerror ("Teleporter with nonexistant target");
		return;
	}
	else if(n == 1)
	{
		// exactly one dest - bots love that
		self.enemy = find(e, targetname, self.target);
		self.dest = self.enemy.origin;
	}
	else
	{
		// have to use random selection every single time
		self.enemy = world;
	}

	// now enable touch
	self.touch = Teleport_Touch;
}

void spawnfunc_trigger_teleport (void)
{
	self.angles = '0 0 0';

	EXACTTRIGGER_INIT;

	self.use = trigger_teleport_use;
    
	// this must be called to spawn the teleport waypoints for bots
	InitializeEntity(self, teleport_findtarget, INITPRIO_FINDTARGET);

	if (!self.target)
	{
		objerror ("Teleporter with no target");
		return;
	}
}
