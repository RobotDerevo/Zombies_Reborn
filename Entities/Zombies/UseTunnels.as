//allow blob to traverse tunnel systems randomly

#define SERVER_ONLY;

#include "TunnelCommon.as";

void onInit(CBlob@ this)
{
	this.getCurrentScript().tickFrequency = 30;
}

void onTick(CBlob@ this)
{
	if (this.hasTag("dead") || XORRandom(6) != 0) return;
	
	CBlob@[] overlapping;
	if (!this.getOverlapping(@overlapping)) return;

	const u16 overlappingLength = overlapping.length;
	for (u16 i = 0; i < overlappingLength; i++)
	{
		CBlob@ blob = overlapping[i];
		
		CBlob@[] tunnels;
		if (blob.hasTag("travel tunnel") && getTunnels(blob, @tunnels))
		{
			CBlob@ tunnel = tunnels[XORRandom(tunnels.length)];
			Vec2f travel_pos = tunnel.getPosition();
			this.setPosition(travel_pos);

			CBitStream params;
			params.write_u16(this.getNetworkID());
			params.write_u16(tunnel.getNetworkID());
			blob.SendCommand(blob.getCommandID("travel to client"), params);

			this.set_Vec2f("brain_destination", Vec2f_zero);
		}
	}
}
