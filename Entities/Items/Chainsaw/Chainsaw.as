#include "Hitters.as";
#include "BuilderHittable.as";
#include "ParticleSparks.as";
#include "MaterialCommon.as";
#include "ShieldCommon.as";
#include "KnockedCommon.as";
#include "Zombie_Translation.as";

const f32 speed_thresh = 2.4f;
const f32 speed_hard_thresh = 2.6f;

const string buzz_prop = "drill timer";

const string heat_prop = "drill heat";
const u8 heat_max = 250;

const string last_drill_prop = "drill last active";

const u8 heat_add = 2;
const u8 heat_add_blob = 4;
const u8 heat_cool_amount = 2;

const u8 heat_cooldown_time = 5;
const u8 heat_cooldown_time_water = u8(heat_cooldown_time / 3);

const f32 max_heatbar_view_range = 65;

const bool show_heatbar_when_idle = false;

const string required_class = "builder";

void onInit(CSprite@ this)
{
	CSpriteLayer@ heat = this.addSpriteLayer("heat", this.getFilename(), 32, 16);

	if (heat !is null)
	{
		Animation@ anim = heat.addAnimation("default", 0, true);
		{
			int[] frames = {4, 5, 6, 7};
			anim.AddFrames(frames);
		}
		heat.SetAnimation(anim);
		heat.SetRelativeZ(0.3f);
		heat.SetVisible(false);
		heat.setRenderStyle(RenderStyle::light);
	}
	this.SetEmitSound("/Chainsaw.ogg");
	this.SetEmitSoundVolume(0.3f);
	this.SetEmitSoundSpeed(1.5f);
}

void onInit(CBlob@ this)
{
	this.Tag("ignore_saw");
	this.Tag("sawed");//hack

	this.set_u32("hittime", 0);
	this.Tag("place norotate"); // required to prevent drill from locking in place (blame builder code :kag_angry:)

	this.set_u8(heat_prop, 0);
	this.set_u16("showHeatTo", 0);
	this.set_u16("harvestWoodDoorCap", 4);
	this.set_u16("harvestPlatformCap", 2);

	AddIconToken("$opaque_heatbar$", "Entities/Industry/Drill/HeatBar.png", Vec2f(24, 6), 0);
	AddIconToken("$transparent_heatbar$", "Entities/Industry/Drill/HeatBar.png", Vec2f(24, 6), 1);

	this.set_u32(last_drill_prop, 0);
	
	this.setInventoryName(name(Translate::Chainsaw));
}

void onTick(CSprite@ this)
{
	CBlob@ blob = this.getBlob();

	bool buzz = blob.get_bool(buzz_prop);
	if (buzz)
	{
		this.SetAnimation("buzz");
	}
	else if (this.isAnimationEnded())
	{
		this.SetAnimation("default");
	}

	CSpriteLayer@ heatlayer = this.getSpriteLayer("heat");
	if (heatlayer !is null)
	{
		f32 heat = Maths::Min(blob.get_u8(heat_prop), heat_max);
		f32 heatPercent = heat / float(heat_max);
		if (heatPercent > 0.1f)
		{
			heatlayer.setRenderStyle(RenderStyle::light);
			blob.SetLight(true);
			blob.SetLightRadius(heatPercent * 24.0f);
			SColor lightColor = SColor(255, 255, Maths::Min(255, 128 + int(heatPercent * 128)), 64);
			blob.SetLightColor(lightColor);
			heatlayer.SetVisible(true);
			heatlayer.animation.frame = heatPercent * 3;
			if (heatPercent > 0.7f && getGameTime() % 3 == 0)
			{
				makeSteamParticle(blob, Vec2f());
			}
		}
		else
		{
			blob.SetLight(false);
			heatlayer.SetVisible(false);
		}
	}
}

void onTick(CBlob@ this)
{
	u8 heat = this.get_u8(heat_prop);
	const u32 gametime = getGameTime();
	bool inwater = this.isInWater();

	CSprite@ sprite = this.getSprite();

	if (heat > 0)
	{
		if (gametime % heat_cooldown_time == 0)
		{
			heat--;
		}

		if (inwater && heat >= heat_add && gametime % (Maths::Max(heat_cooldown_time_water, 1)) == 0)
		{
			u8 lim = u8(heat_max * 0.7f);
			if (heat > lim)
			{
				makeSteamPuff(this);
			}
			else
			{
				makeSteamPuff(this, 0.5f, 5, false);
			}
			heat -= heat_cool_amount;
		}
		this.set_u8(heat_prop, heat);
	}
	sprite.SetEmitSoundPaused(true);

	if (!this.isAttached())
	{
		this.getShape().SetRotationsAllowed(true);
		this.set_bool(buzz_prop, false);
		if (heat <= 0)
			this.getCurrentScript().runFlags |= Script::tick_not_sleeping;

		return;
	}

	AttachmentPoint@ point = this.getAttachments().getAttachmentPointByName("PICKUP");
	CBlob@ holder = point.getOccupied();
	if (holder is null) return;

	AimAtMouse(this, holder); // aim at our mouse pos

	// cool faster if holder is moving
	if (heat > 0 && holder.getShape().vellen > 0.01f && getGameTime() % heat_cooldown_time == 0)
	{
		heat--;
	}

	if (int(heat) >= heat_max - (heat_add * 1.5))
	{
		sprite.PlaySound("DrillOverheat.ogg");
		makeSteamPuff(this, 1.5f, 3, false);
		this.server_Hit(holder, holder.getPosition(), Vec2f(), 0.25f, Hitters::burn, true);
		this.server_DetachFrom(holder);
	}

	if (!holder.isKeyPressed(key_action1) || isKnocked(holder))
	{
		this.set_bool(buzz_prop, false);
		return;
	}

	//set funny sound under water
	if (inwater)
	{
		sprite.SetEmitSoundSpeed(0.8f + (getGameTime() % 13) * 0.01f);
	}
	else
	{
		sprite.SetEmitSoundSpeed(1.0f);
	}

	sprite.SetEmitSoundPaused(false);
	this.set_bool(buzz_prop, true);

	if (heat < heat_max)
	{
		heat++;
	}

	const u8 delay_amount = inwater ? 20 : 8;
	bool skip = (gametime < this.get_u32(last_drill_prop) + delay_amount);

	if (skip)
	{
		return;
	}
	else
	{
		this.set_u32(last_drill_prop, gametime); // update last drill time
	}

	// delay drill
	const bool facingleft = this.isFacingLeft();
	Vec2f direction = Vec2f(1, 0).RotateBy(this.getAngleDegrees() + (facingleft ? 180.0f : 0.0f));
	const f32 sign = (facingleft ? -1.0f : 1.0f);

	const f32 attack_distance = 6.0f;
	Vec2f attackVel = direction * attack_distance;

	const f32 distance = 25.0f;

	CMap@ map = getMap();
	HitInfo@[] hitInfos;
	map.getHitInfosFromArc((this.getPosition() - attackVel), -attackVel.Angle(), 30, distance, this, true, @hitInfos);

	bool hitwood = false;
	for (uint i = 0; i < hitInfos.length; i++)
	{
		f32 attack_dam = 1.0f;
		HitInfo@ hi = hitInfos[i];
		CBlob@ b = hi.blob;
		if (b !is null) // blob
		{
			if (b.hasTag("invincible")) continue;

			if ((b.getTeamNum() == holder.getTeamNum() && !b.hasTag("dead")) || b.hasTag("stone") || b.hasTag("blocks sword"))
				continue;

			string name = b.getName();
			if (name == "log" || name == "tree_pine" || name == "tree_bushy" || name == "seed" || b.hasTag("wooden")) 
				hitwood = true;

			if (isServer())
			{
				if (int(heat) > heat_max * 0.7f) // are we at high heat? more damamge!
				{
					attack_dam += 0.5f;
				}

				if (b.hasTag("shielded") && blockAttack(b, attackVel, 0.0f)) // are they shielding? reduce damage!
				{
					attack_dam /= 2;
				}

				this.server_Hit(b, hi.hitpos, attackVel, attack_dam, Hitters::drill, true);

				Material::fromBlob(holder, hi.blob, attack_dam, this);
			}

			if (heat < heat_max)
			{
				const f32 heat_to_add = hitwood ? heat_add : heat_add_blob;

				heat = Maths::Min(heat + heat_to_add, heat_max);
			}
			hitwood = false;
		}
		else // map
		{
			if (map.getSectorAtPosition(hi.hitpos, "no build") !is null)
				continue;

			if (isServer())
			{
				for (uint i = 0; i < 2; i++)
				{
					if (!map.isTileSolid(map.getTile(hi.tileOffset))) break;

					if (map.isTileWood(hi.tile))
					{
						map.server_DestroyTile(hi.hitpos, 1.0f, this);

						//Material::fromTile(holder, hi.tile, 1.0f);
					}
				}
			}
		}
	}
	this.set_u8(heat_prop, heat);
}

f32 onHit(CBlob@ this, Vec2f worldPoint, Vec2f velocity, f32 damage, CBlob@ hitterBlob, u8 customData)
{
	if (customData == Hitters::fire)
	{
		this.set_u8(heat_prop, heat_max);
		makeSteamPuff(this);
	}

	if (customData == Hitters::water)
	{
		this.set_u8(heat_prop, 0);
		makeSteamPuff(this);
	}

	return damage;
}

void onAttach(CBlob@ this, CBlob@ attached, AttachmentPoint @attachedPoint)
{
	this.getCurrentScript().runFlags &= ~Script::tick_not_sleeping;
	this.setPosition(attached.getPosition()); // required to stop the first tick to be out of position
}

void onThisAddToInventory(CBlob@ this, CBlob@ blob)
{
	this.doTickScripts = true;
	this.getSprite().SetEmitSoundPaused(true);
}

void onRender(CSprite@ this)
{
	CBlob@ blob = this.getBlob();
	
	AttachmentPoint@ point = blob.getAttachments().getAttachmentPointByName("PICKUP");
	CBlob@ holder = point.getOccupied();
	if (holder is null || !holder.isMyPlayer()) return;

	if (holder.getName() != required_class) return;

	int transparency = 255;
	u8 heat = blob.get_u8(heat_prop);
	f32 percentage = Maths::Min(1.0, f32(heat) / f32(heat_max));

	Vec2f pos = holder.getInterpolatedScreenPos() + (blob.getScreenPos() - holder.getScreenPos()) + Vec2f(-22, 16);
	Vec2f dimension = Vec2f(42, 4);
	Vec2f bar = Vec2f(pos.x + (dimension.x * percentage), pos.y + dimension.y);

	if ((heat > 0 && show_heatbar_when_idle) || (blob.get_bool(buzz_prop)))
	{
		GUI::DrawIconByName("$opaque_heatbar$", pos);
	}
	else
	{
		transparency = 168;
		GUI::DrawIconByName("$transparent_heatbar$", pos);
	}

	GUI::DrawRectangle(pos + Vec2f(4, 4), bar + Vec2f(4, 4), SColor(transparency, 59, 20, 6));
	GUI::DrawRectangle(pos + Vec2f(6, 6), bar + Vec2f(2, 4), SColor(transparency, 148, 27, 27));
	GUI::DrawRectangle(pos + Vec2f(6, 6), bar + Vec2f(2, 2), SColor(transparency, 183, 51, 51));
}

void makeSteamParticle(CBlob@ this, const Vec2f vel, const string filename = "SmallSteam")
{
	if (!isClient()) return;

	const f32 rad = this.getRadius();
	Vec2f random = Vec2f(XORRandom(128) - 64, XORRandom(128) - 64) * 0.015625f * rad;
	ParticleAnimated(filename, this.getPosition() + random, vel, float(XORRandom(360)), 1.0f, 2 + XORRandom(3), -0.1f, false);
}

void makeSteamPuff(CBlob@ this, const f32 velocity = 1.0f, const int smallparticles = 10, const bool sound = true)
{
	if (sound)
	{
		this.getSprite().PlaySound("Steam.ogg");
	}

	makeSteamParticle(this, Vec2f(), "MediumSteam");
	for (int i = 0; i < smallparticles; i++)
	{
		f32 randomness = (XORRandom(32) + 32) * 0.015625f * 0.5f + 0.75f;
		Vec2f vel = getRandomVelocity(-90, velocity * randomness, 360.0f);
		makeSteamParticle(this, vel);
	}
}

void AimAtMouse(CBlob@ this, CBlob@ holder)
{
	// code used from BlobPlacement.as, just edited to use mouse pos instead of 45 degree angle
	Vec2f aimpos = holder.getAimPos();
	Vec2f pos = this.getPosition();
	Vec2f aim_vec = (pos - aimpos);
	aim_vec.Normalize();

	f32 mouseAngle = aim_vec.getAngleDegrees();

	if (!this.isFacingLeft()) mouseAngle += 180;

	this.setAngleDegrees(-mouseAngle); // set aim pos
}
