#if !defined(MY_SHADOWS_INCLUDED)
#define MY_SHADOWS_INCLUDED

#include "UnityCG.cginc"

struct VertexData {
	float4 position : POSITION;
	float3 normal : NORMAL;
};

#if defined(SHADOWS_CUBE) // point light shadow map
	struct Interpolators {
		float4 position : SV_POSITION;
		float3 lightVec : TEXCOORD0;
	};

	Interpolators MyShadowVertexProgram(VertexData v) {
		Interpolators i;
		i.position = UnityObjectToClipPos(v.position);
		i.lightVec =
			mul(unity_ObjectToWorld, v.position).xyz - _LightPositionRange.xyz; // xyz: light position
		return i;
	}
	
	float4 MyShadowFragmentProgram(Interpolators i) : SV_TARGET {
		float depth = length(i.lightVec) + unity_LightShadowBias.x;
		depth *= _LightPositionRange.w; // w: inverse of light range
		return UnityEncodeCubeShadowDepth(depth); // if floating-point cube map is not possible, encode in 8-bit RGBA texture
	}
#else
	float4 MyShadowVertexProgram(VertexData v) : SV_POSITION {
		float4 position = UnityClipSpaceShadowCasterPos(v.position.xyz, v.normal); // transform and apply normal bias
		return UnityApplyLinearShadowBias(position); // apply linear bias
	}

	half4 MyShadowFragmentProgram() : SV_TARGET {
		return 0;
	}
#endif

#endif