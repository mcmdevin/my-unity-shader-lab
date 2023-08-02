#if !defined(MY_SHADOWS_INCLUDED)
#define MY_SHADOWS_INCLUDED

#include "UnityCG.cginc"

#if defined(_RENDERING_FADE) || defined(_RENDERING_TRANSPARENT)
	#if defined(_SEMITRANSPARENT_SHADOWS)
		#define SHADOWS_SEMITRANSPARENT 1
	#else
		#define _RENDERING_CUTOUT
	#endif
#endif

#if SHADOWS_SEMITRANSPARENT || defined(_RENDERING_CUTOUT)
	#if !defined(_SMOOTHNESS_ALBEDO)
		#define SHADOWS_NEED_UV 1
	#endif
#endif

float4 _Color;
sampler2D _MainTex;
float4 _MainTex_ST;
float _Cutoff;
sampler3D _DitherMaskLOD;

struct VertexData {
	float4 position : POSITION;
	float3 normal : NORMAL;
	float2 uv : TEXCOORD0;
};

struct InterpolatorsVertex { // VPOS and SV_POSITION semantics don't play nice
	float4 position : SV_POSITION;
	#if SHADOWS_NEED_UV
		float2 uv : TEXCOORD0;
	#endif
	#if defined(SHADOWS_CUBE)
		float3 lightVec : TEXCOORD1;
	#endif
};

struct Interpolators { // https://catlikecoding.com/unity/tutorials/rendering/part-12/ 2.2 VPOS
	#if SHADOWS_SEMITRANSPARENT
		UNITY_VPOS_TYPE vpos : VPOS;
	#else
		float4 positions : SV_POSITION; // avoid empty struct
	#endif

	#if SHADOWS_NEED_UV
		float2 uv : TEXCOORD0;
	#endif
	#if defined(SHADOWS_CUBE)
		float3 lightVec : TEXCOORD1;
	#endif
};

InterpolatorsVertex MyShadowVertexProgram(VertexData v) {
	InterpolatorsVertex i;
	#if defined(SHADOWS_CUBE)
		i.position = UnityObjectToClipPos(v.position);
		i.lightVec =
		mul(unity_ObjectToWorld, v.position).xyz - _LightPositionRange.xyz; // xyz: light position
	#else
		i.position = UnityClipSpaceShadowCasterPos(v.position.xyz, v.normal);
		i.position = UnityApplyLinearShadowBias(i.position);
	#endif
	#if SHADOWS_NEED_UV
		i.uv = TRANSFORM_TEX(v.uv, _MainTex);
	#endif
	return i;
}
	
float GetAlpha(Interpolators i) {
	float alpha = _Color.a;
	#if SHADOWS_NEED_UV
		alpha *= tex2D(_MainTex, i.uv).a;
	#endif
	return alpha;
}

float4 MyShadowFragmentProgram(Interpolators i) : SV_TARGET {
	float alpha = GetAlpha(i);
	#if defined(_RENDERING_CUTOUT)
		clip(alpha - _Cutoff);
	#endif

	#if  SHADOWS_SEMITRANSPARENT
		float dither =
			tex3D(_DitherMaskLOD, float3(i.vpos.xy * 0.25, alpha * 0.9375)).a; // 0.9375: full opacity
		clip(dither - 0.01); // 0.01: a small number < 0.0625
	#endif

	#if defined(SHADOWS_CUBE)
		float depth = length(i.lightVec) + unity_LightShadowBias.x;
		depth *= _LightPositionRange.w; // w: inverse of light range
		return UnityEncodeCubeShadowDepth(depth); // if floating-point cube map is not possible, encode in 8-bit RGBA texture
	#else
		return 0;
	#endif
}

#endif