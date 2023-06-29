#if !defined(MY_LIGHTING_INCLUDED)
#define MY_LIGHTING_INCLUDED

#include "UnityPBSLighting.cginc"
#include "AutoLight.cginc"

float4 _Tint;
sampler2D _MainTex;
float4 _MainTex_ST;
sampler2D _NormalMap;
float _NormalScale;
sampler2D _MetallicMap;
float _Metallic;
float _Smoothness;
sampler2D _OcclusionMap;
float _OcclusionStrength;
sampler2D _EmissionMap;
float3 _Emission;

struct VertexData {
	float4 vertex : POSITION;
	float3 normal : NORMAL;
	float4 tangent : TANGENT;
	float2 uv : TEXCOORD0;
};

struct Interpolators {
	float4 pos : SV_POSITION;
	float2 uv : TEXCOORD0;
	float3 normal : TEXCOORD1;
	float3 tangent : TEXCOORD2;
	float3 bitangent : TEXCOORD3;
	float3 worldPos : TEXCOORD4;

	SHADOW_COORDS(5) // shadowCoordinates is TEXCOORD5

	#if defined(VERTEXLIGHT_ON)
		float3 vertexLightColor : TEXCOORD6;
	#endif
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

float3 GetOcclusion(Interpolators i) {
	#if defined(_OCCLUSION_MAP)
		return lerp(1, tex2D(_OcclusionMap, i.uv).g, _OcclusionStrength);
	#else
		return 1;
	#endif
}

float3 GetEmission(Interpolators i) {
	#if defined(FORWARD_BASE_PASS)
		#if defined(_EMISSION_MAP)
			return tex2D(_EmissionMap, i.uv) * _Emission;
		#else
			return _Emission;
		#endif
	#else
		return 0;
	#endif
}

void ComputeVertexLightColor(inout Interpolators i) {
	#if defined(VERTEXLIGHT_ON)
		i.vertexLightColor = Shade4PointLights(
			unity_4LightPosX0, unity_4LightPosY0, unity_4LightPosZ0,
			unity_LightColor[0].rgb, unity_LightColor[1].rgb,
			unity_LightColor[2].rgb, unity_LightColor[3].rgb,
			unity_4LightAtten0, i.worldPos, i.normal
		); // https://catlikecoding.com/unity/tutorials/rendering/part-5/
	#endif
}

Interpolators MyVertexProgram(VertexData v) {
	Interpolators i;
	i.pos = UnityObjectToClipPos(v.vertex);
	i.worldPos = mul(unity_ObjectToWorld, v.vertex);
	i.uv = TRANSFORM_TEX(v.uv, _MainTex);
	i.normal = UnityObjectToWorldNormal(v.normal);
	i.tangent = UnityObjectToWorldDir(v.tangent.xyz);
	i.bitangent = cross(i.normal, i.tangent.xyz) * (v.tangent.w * unity_WorldTransformParams.w);

	TRANSFER_SHADOW(i); // set i.shadowCoordinates to i.pos
	ComputeVertexLightColor(i);
	return i;
}

float3 CalculateNormalMapping(Interpolators i) {
	float3 normalTS = UnpackScaleNormal(tex2D(_NormalMap, i.uv), _NormalScale);
	float3 normalWS = normalize(
		normalTS.x * i.tangent +
		normalTS.y * i.bitangent +
		normalTS.z * i.normal
	);
	return normalWS;
}

UnityLight CreateLight(Interpolators i) {
	UnityLight light;
	// _WorldSpaceLightPos0: current light position
	#if defined(POINT) || defined(POINT_COOKIE) || defined(SPOT)
		light.dir = normalize(_WorldSpaceLightPos0.xyz - i.worldPos);
	#else
		light.dir = _WorldSpaceLightPos0.xyz;
	#endif
	
	UNITY_LIGHT_ATTENUATION(attenuation, i, i.worldPos);

	light.color = _LightColor0.rgb * attenuation;
	light.ndotl = DotClamped(i.normal, light.dir);
	return light;
}

float3 BoxProjection ( // https://catlikecoding.com/unity/tutorials/rendering/part-8/
	float3 direction, float3 position,
	float4 cubemapPosition, float3 boxMin, float3 boxMax
) {
	#if UNITY_SPECCUBE_BOX_PROJECTION // if box projection is enabled
		UNITY_BRANCH
		if (cubemapPosition.w > 0) {
			float3 factors = ((direction > 0 ? boxMax : boxMin) - position) / direction;
			float scalar = min(min(factors.x, factors.y), factors.z);
			direction = direction * scalar + (position - cubemapPosition);
		}
	#endif
	return direction;
}

UnityIndirect CreateIndirectLight(Interpolators i, float3 viewDir) {
	UnityIndirect indirectLight;
	indirectLight.diffuse = 0;
	indirectLight.specular = 0;

	#if defined(VERTEXLIGHT_ON)
		indirectLight.diffuse = i.vertexLightColor;
	#endif

	#if defined(FORWARD_BASE_PASS)
		indirectLight.diffuse += max(0, ShadeSH9(float4(i.normal, 1)));
		float3 reflectionDir = reflect(-viewDir, i.normal);
		Unity_GlossyEnvironmentData envData;
		envData.roughness = 1 - GetSmoothness(i);
		envData.reflUVW = BoxProjection(
			reflectionDir, i.worldPos,
			unity_SpecCube0_ProbePosition,
			unity_SpecCube0_BoxMin, unity_SpecCube0_BoxMax
		);
		float3 probe0 = Unity_GlossyEnvironment(
			UNITY_PASS_TEXCUBE(unity_SpecCube0), unity_SpecCube0_HDR, envData
		);
		envData.reflUVW = BoxProjection(
			reflectionDir, i.worldPos,
			unity_SpecCube1_ProbePosition,
			unity_SpecCube1_BoxMin, unity_SpecCube0_BoxMax
		);
		#if UNITY_SPECCUBE_BLENDING // if platform supports probe blending
			float Interpolator = unity_SpecCube0_BoxMin.w;
			UNITY_BRANCH
			if (Interpolator < 0.9999) {
				float3 probe1 = Unity_GlossyEnvironment(
					UNITY_PASS_TEXCUBE_SAMPLER(unity_SpecCube1,unity_SpecCube0),
					unity_SpecCube1_HDR, envData
				);
				indirectLight.specular = lerp(probe1, probe0, Interpolator);
			}
			else {
				indirectLight.specular = probe0;
			}
		#else
			indirectLight.specular = probe0;
		#endif

		float occlusion = GetOcclusion(i);
		indirectLight.diffuse *= occlusion;
		indirectLight.specular *= occlusion;
	#endif

	return indirectLight;
}

float4 MyFragmentProgram(Interpolators i) : SV_TARGET {
	float3 viewDir = normalize(_WorldSpaceCameraPos - i.worldPos);
	float3 albedo = tex2D(_MainTex, i.uv).rgb * _Tint.rgb;
	float3 specularTint;
	float oneMinusReflectivity;
	albedo = DiffuseAndSpecularFromMetallic( // set specularTint and oneMinusReflectivity from albedo and metallic
		albedo, GetMetallic(i), specularTint, oneMinusReflectivity
	);
	i.normal = CalculateNormalMapping(i); 

	float4 color = UNITY_BRDF_PBS(
		albedo, specularTint,
		oneMinusReflectivity, GetSmoothness(i),
		i.normal, viewDir,
		CreateLight(i), CreateIndirectLight(i, viewDir)
	);
	color.rgb += GetEmission(i);
	return color;
}

#endif