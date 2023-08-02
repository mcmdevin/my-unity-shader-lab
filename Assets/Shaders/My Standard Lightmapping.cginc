#if !defined(MY_LIGHTMAPPING_INCLUDED)
#define MY_LIGHTMAPPING_INCLUDED

#include "UnityPBSLighting.cginc"
#include "UnityMetaPass.cginc"

float4 _Color;
sampler2D _MainTex;
float4 _MainTex_ST;

sampler2D _MetallicMap;
float _Metallic;
float _Smoothness;

sampler2D _EmissionMap;
float3 _Emission;

struct VertexData {
    float4 vertex : POSITION;
    float3 normal : NORMAL;
    float4 tangent : TANGENT;
    float2 uv : TEXCOORD0;
    float2 uv1 : TEXCOORD1;
};

struct Interpolators {
    float4 pos : SV_POSITION;
    float4 uv : TEXCOORD0;
};

float GetMetallic(Interpolators i) {
	return tex2D(_MetallicMap, i.uv).r * _Metallic;
}

float GetSmoothness(Interpolators i) {
	float mapSmoothness = 1;
	#if defined(_SMOOTHNESS_ALBEDO)
		mapSmoothness = tex2D(_MainTex, i.uv).a; 
	#elif defined(_METALLIC_MAP)
		mapSmoothness = tex2D(_MetallicMap, i.uv).a; 
	#endif
	return mapSmoothness * _Smoothness;
}

float3 GetEmission(Interpolators i) {
    #if defined(_EMISSION_MAP)
        return tex2D(_EmissionMap, i.uv) * _Emission;
    #else
        return _Emission;
    #endif
}

Interpolators MyLightmappingVertexProgram(VertexData v) {
    Interpolators i;
    v.vertex.xy = v.uv1 * unity_LightmapST.xy + unity_LightmapST.zw;
    v.vertex.z = v.vertex.z > 0 ? 0.0001 : 0; // some platform requires non-zero z
    i.pos = UnityObjectToClipPos(v.vertex);
    return i;
}

float4 MyLightmappingFragmentProgram(Interpolators i) : SV_TARGET {
    UnityMetaInput surfaceData;
    surfaceData.Emission = GetEmission(i);
	float3 albedo = tex2D(_MainTex, i.uv).rgb * _Color.rgb;
    float oneMinusReflectivity;
    surfaceData.Albedo = DiffuseAndSpecularFromMetallic(
        albedo, GetMetallic(i),
        surfaceData.SpecularColor, oneMinusReflectivity
    );
    // surfaceData.SpecularColor = 0; // SpecularColor is output param, need to include it 
    float roughness = SmoothnessToRoughness(GetSmoothness(i)) * 0.5;
    surfaceData.Albedo += surfaceData.SpecularColor * roughness;
    return UnityMetaFragment(surfaceData);
}

#endif