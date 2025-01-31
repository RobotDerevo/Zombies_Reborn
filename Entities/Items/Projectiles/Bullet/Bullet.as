
#include "Hitters.as";
#include "MakeDustParticle.as";
#include "ParticleSparks.as";
#include "Zombie_TechnologyCommon.as";
#include "CustomTiles.as";

const f32 PUSH_FORCE = 22.0f;

void onInit(CBlob@ this)
{
    CShape@ shape = this.getShape();
	ShapeConsts@ consts = shape.getConsts();
    consts.mapCollisions = false;
	consts.bullet = true;
	consts.net_threshold_multiplier = 4.0f;
	
	//dont collide with top of the map
	this.SetMapEdgeFlags(CBlob::map_collide_left | CBlob::map_collide_right);

	this.server_SetTimeToDie(this.get_f32("bullet time"));	
	this.Tag("projectile");
	this.Tag("ignore_saw");
	this.Tag("sawed"); //hack
}

void onCollision(CBlob@ this, CBlob@ blob, bool solid, Vec2f normal, Vec2f point1)
{
    if (blob is null) return;

	if (blob.isPlatform() && !solid) return;

	if ((blob.isCollidable() && blob.getShape().isStatic()) || (blob.hasTag("flesh") && this.getTeamNum() != blob.getTeamNum())) 
	{
		Technology@[]@ TechTree = getTechTree();
		const u8 pierced = this.get_u8("pierced");

		this.server_Hit(blob, point1, normal, getBulletDamage(this, pierced, TechTree), Hitters::arrow);
		
		const u8 pierce_threshold = hasTech(TechTree, Tech::RifledBarrels) ? 3 : 1;
		if (pierced > pierce_threshold)
			this.server_Die();

		this.set_u8("pierced", pierced + 1);
	}
}

f32 getBulletDamage(CBlob@ this, const u8&in pierced, Technology@[]@ TechTree)
{
	f32 percent = 1.0f;
	if (hasTech(TechTree, Tech::FastBurnPowder)) percent += 0.25f;
	if (hasTech(TechTree, Tech::HeavyLead))      percent += 0.45f;
	
	const f32 pierce_factor = 1.0f - (0.07f * pierced);
	const f32 damage = this.get_f32("bullet damage") * pierce_factor * percent;
	return damage;
}

void onTick(CBlob@ this)
{
    const f32 angle = this.getVelocity().Angle();
    this.setAngleDegrees(-angle);
	
	if (isServer())
	{
		Vec2f end;
		if (getMap().rayCastSolidNoBlobs(this.getOldPosition(), this.getPosition(), end))
		{
			this.server_HitMap(end, this.getOldVelocity(), 0.5f, Hitters::arrow);
			this.server_Die();
		}
	}
}

f32 onHit(CBlob@ this, Vec2f worldPoint, Vec2f velocity, f32 damage, CBlob@ hitterBlob, u8 customData)
{
	return 0.0f;
}

void onHitBlob(CBlob@ this, Vec2f worldPoint, Vec2f velocity, f32 damage, CBlob@ hitBlob, u8 customData)
{
	this.getSprite().PlaySound("BulletImpact.ogg");	

	// affect velocity
	const f32 force = (PUSH_FORCE * -0.125f) * Maths::Sqrt(hitBlob.getMass()+1);
	hitBlob.AddForce(velocity * force);
}

void onHitMap(CBlob@ this, Vec2f worldPoint, Vec2f velocity, f32 damage, u8 customData)
{
	this.getSprite().PlaySound(XORRandom(4) == 0 ? "BulletRicochet.ogg" : "BulletImpact.ogg");
	MakeDustParticle(worldPoint, "/DustSmall.png");
	CMap@ map = getMap();
	f32 vellen = velocity.Length();
	TileType tile = map.getTile(worldPoint).type;
	if (map.isTileCastle(tile) || isTileIron(tile))
	{
		sparks(worldPoint, -velocity.Angle(), Maths::Max(vellen*0.05f, damage));
	}
}
