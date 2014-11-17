// vertex shader input
struct VSInput 
{
	float3 Pos 		 	 : POSITION;
	float3 Normal		 : NORMAL;

#if defined(_DiffuseMap)
	float2 Tex			 : TEXCOORD0;
#endif

#ifdef _NormalMap
	float3 Tangent		 : TANGENT;
	float3 Binormal      : BINORMAL;
#endif
};

// shader output
struct VSOutput
{
	float4 PosCS : TEXCOORD0;      // camera space position
	float2 Tex   : TEXCOORD1;
	
	float4 PrevPosCS : TEXCOORD2;  // last frame camera space position

#ifdef _NormalMap
	float3x3 TangentToWorld : TEXCOORD3;
#else
	float3 NormalWS 	    : TEXCOORD3;
#endif 
	
	float4 Position : SV_POSITION;
};

// shader uniforms
cbuffer cbObjectChanges
{
	float4x4 World;
};

cbuffer cbCameraChange : register( b0 )
{
    float4x4 View;
	float4x4 PrevView;
	float4x4 Projection;
};

// vertex shader
VSOutput GBufferVS(VSInput input)
{
	VSOutput output = (VSOutput)0;
	
	float3 normal = normalize( mul(input.Normal, (float3x3)World) );
	
	// calculate tangent and binormal.
#ifdef _NormalMap
	float3 tangent = normalize( mul(input.Tangent, (float3x3)World) );
	float3 binormal = normalize( mul(input.Binormal, (float3x3)World) );

	// actualy this is a world to tangent matrix, because we always use V * Mat.
	output.TangentToWorld = float3x3( tangent, binormal, normal);
#else
	output.NormalWS = normal;
#endif
	
#ifndef _DiffuseMap
	output.Tex = float2(0, 0); // Todo: Not output tex if no texture
#else 
	output.Tex = input.Tex;
#endif
	
	output.PosCS = mul( float4(input.Pos, 1.0), mul(World, View) );
	output.PrevPosCS = mul( float4(input.Pos, 1.0), mul(World, PrevView) );
	output.Position = mul( output.PosCS, Projection );
	
	return output;
}

//---------------------------------------------------------------------------------------
// Pixel Shader
#include "../ModelMaterialFactory.hlsl"

// Clip sapce to screen space transform
float4x4 ProjectionToScreenMatrix;

#ifdef USE_DEPTH_PEEL

	Texture2D<float> PrevDepthBuffer;
	float3    ClipInfo;
	float MinZSeparation;

#endif 

// pixel shader
void GBufferPS(in VSOutput input,
               out float4 oLambertain : SV_Target0,
			   out float4 oGlossy     : SV_Target1,
			   out float4 oNormal     : SV_Target2,
			   out float2 oSSVelocity : SV_Target3)
{
#ifdef USE_DEPTH_PEEL // Second Layer with minimum separation
	
	float oldDepth = PrevDepthBuffer.Load(int3(input.Position.xy, 0));
	float oldZ = ClipInfo.x / (oldDepth * ClipInfo.y + ClipInfo.z);
	float currZ = input.PosCS.z;
	if (currZ <= oldZ + MinZSeparation)
		discard;

#endif

	Material material;
	GetMaterial(input.Tex, material);
	
	// normal map
#ifdef _NormalMap
	float3 normal = NormalMap.Sample(MaterialSampler , input.Tex ).rgb * 2.0 - 1.0;
	//normal = normalize( mul(normal, input.TangentToWorld) );
	normal = normalize( input.TangentToWorld[2] );
#else
	float3 normal = normalize(input.NormalWS);
#endif	
	
	float4 accurateHomogeneousFragCoord = mul( input.PosCS, ProjectionToScreenMatrix );
	
	if (input.PrevPosCS.z <= 0.0)
	{
		// Projects behind the camera; write zero velocity
        oSSVelocity = float2(0.0, 0.0);
	}
	else
	{
		float4 temp = mul( input.PrevPosCS, ProjectionToScreenMatrix );
		
		// We want the precision of division here and intentionally do not convert to multiplying by an inverse.
        // Expressing the two divisions as a single vector division operation seems to prevent the compiler from
        // computing them at different precisions, which gives non-zero velocity for static objects in some cases.
        // Note that this forces us to compute accurateHomogeneousFragCoord's projection twice, but we hope that
        // the optimizer will share that result without reducing precision.
        float4 ssPositions = float4(temp.xy, accurateHomogeneousFragCoord.xy) / float4(temp.ww, accurateHomogeneousFragCoord.ww);
        oSSVelocity = ssPositions.zw - ssPositions.xy;
	}
			
	oLambertain = float4(material.DiffuseAlbedo, 0.0);
	oGlossy = float4(material.SpecularAlbedo, material.Shininess / 255.0);
	oNormal = float4(normal, 0.0); 
}
