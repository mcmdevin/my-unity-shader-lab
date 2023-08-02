#if !defined(MY_LIGHTING_INCLUDED)
#define MY_LIGHTING_INCLUDED

#include "UnityPBSLighting.cginc"
#include "AutoLight.cginc"

#if defined(FOG_LINEAR) || defined(FOG_EXP) || defined(FOG_EXP2)
	#if !defined(FOG_DISTANCE)
		#define FOG_DEPTH 1
	#endif
	#define FOG_ON 1
#endif

float4 _Color;
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
float _Cutoff;

struct VertexData {
	float4 vertex : POSITION;
	float3 normal : NORMAL;
	float4 tangent : TANGENT;
	float2 uv : TEXCOORD0;
	float2 uv1 : TEXCOORD1;
};

struct Interpolators {
	float4 pos : SV_POSITION;
	float2 uv : TEXCOORD0;
	float3 normal : TEXCOORD1;
	float3 tangent : TEXCOORD2;
	float3 bitangent : TEXCOORD3;
	#if FOG_DEPTH
		float4 worldPos : TEXCOORD4;
	#else
		float3 worldPos : TEXCOORD4;
	#endif
	SHADOW_COORDS(5) // shadowCoordinates is TEXCOORD5

	#if defined(VERTEXLIGHT_ON)
		float3 vertexLightColor : TEXCOORD6;
	#elif defined(LIGHTMAP_ON)
		float2 lightmapUV : TEXCOORD6;
	#endif
};

float GetAlpha(Interpolators i) {
	float alpha = _Color.a;
	#if !defined(_SMOOTHNESS_ALBEDO)
		alpha *= tex2D(_MainTex, i.uv).a;
	#endif
	return alpha;
}

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
	#if defined(FORWARD_BASE_PASS) || defined(DEFERRED_PASS)
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
			unity_4LightAtten0, i.worldPos.xyz, i.normal
		); // https://catlikecoding.com/unity/tutorials/rendering/part-5/
	#endif
}

Interpolators MyVertexProgram(VertexData v) {
	Interpolators i;
	i.pos = UnityObjectToClipPos(v.vertex);
	i.worldPos.xyz = mul(unity_ObjectToWorld, v.vertex);
	#if FOG_DEPTH
		i.worldPos.w = i.pos.z;
	#endif
	i.uv = TRANSFORM_TEX(v.uv, _MainTex);
	#if defined(LIGHTMAP_ON)
		i.lightmapUV =		// cannot use TRANSFORM_TEX because it does not end with "_ST"
			v.uv1 * unity_LightmapST.xy + unity_LightmapST.zw; // unity_Lightmap: UnityShaderVariables
	#endif
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

	#if defined(DEFERRED_PASS)
		light.dir = float3(0, 1, 0);
		light.color = 0;
	#else
		// _WorldSpaceLightPos0: current light position
		#if defined(POINT) || defined(POINT_COOKIE) || defined(SPOT)
			light.dir = normalize(_WorldSpaceLightPos0.xyz - i.worldPos.xyz);
		#else
			light.dir = _WorldSpaceLightPos0.xyz;
		#endif
		
		UNITY_LIGHT_ATTENUATION(attenuation, i, i.worldPos.xyz);

		light.color = _LightColor0.rgb * attenuation;
	#endif
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

	#if defined(FORWARD_BASE_PASS) || defined(DEFERRED_PASS)
		#if defined(LIGHTMAP_ON)
			indirectLight.diffuse = DecodeLightmap( // lightmap data are encoded to support high-intensity light
				UNITY_SAMPLE_TEX2D(unity_Lightmap, i.lightmapUV) // lightmap format is platform-dependent, can not use tex2D
			);

			#if defined(DIRLIGHTMAP_COMBINED)
				float4 lightmapDirection = UNITY_SAMPLE_TEX2D_SAMPLER(
					unity_LightmapInd, unity_Lightmap, i.lightmapUV
				);
				indirectLight.diffuse = DecodeDirectionalLightmap(
					indirectLight.diffuse, lightmapDirection, i.normal
				);
			#endif
		#else
			indirectLight.diffuse += max(0, ShadeSH9(float4(i.normal, 1)));
		#endif
		float3 reflectionDir = reflect(-viewDir, i.normal);
		Unity_GlossyEnvironmentData envData;
		envData.roughness = 1 - GetSmoothness(i);
		envData.reflUVW = BoxProjection(
			reflectionDir, i.worldPos.xyz,
			unity_SpecCube0_ProbePosition,
			unity_SpecCube0_BoxMin, unity_SpecCube0_BoxMax
		);
		float3 probe0 = Unity_GlossyEnvironment(
			UNITY_PASS_TEXCUBE(unity_SpecCube0), unity_SpecCube0_HDR, envData
		);
		envData.reflUVW = BoxProjection(
			reflectionDir, i.worldPos.xyz,
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

		#if defined(DEFERRED_PASS) && UNITY_ENABLE_REFLECTION_BUFFERS
			indirectLight.specular = 0;
		#endif
	#endif

	return indirectLight;
}

float4 ApplyFog(float4 color, Interpolators i) {
	#if FOG_ON
		float viewDistance = length(_WorldSpaceCameraPos - i.worldPos.xyz);
		#if FOG_DEPTH
			viewDistance = UNITY_Z_0_FAR_FROM_CLIPSPACE(i.worldPos.w);
		#endif
		UNITY_CALC_FOG_FACTOR_RAW(viewDistance); // handle possibly reversed clip-space Z dimension
		float3 fogColor = 0;
		#if defined(FORWARD_BASE_PASS)
			fogColor = unity_FogColor.rgb;
		#endif
		color.rgb = lerp(fogColor.rgb, color.rgb, saturate(unityFogFactor));
	#endif
	return color;
}

struct FragmentOutput {
	#if defined(DEFERRED_PASS)
		float4 gBuffer0 : SV_Target0;
		float4 gBuffer1 : SV_Target1;
		float4 gBuffer2 : SV_Target2;
		float4 gBuffer3 : SV_Target3;
	#else
		float4 color : SV_Target;
	#endif
};

FragmentOutput MyFragmentProgram(Interpolators i) {
	float alpha = GetAlpha(i);
	#if defined(_RENDERING_CUTOUT)
		clip(alpha - _Cutoff);
	#endif

	float3 viewDir = normalize(_WorldSpaceCameraPos - i.worldPos.xyz);
	float3 albedo = tex2D(_MainTex, i.uv).rgb * _Color.rgb;
	float3 specularTint;
	float oneMinusReflectivity;
	albedo = DiffuseAndSpecularFromMetallic( // set specularTint and oneMinusReflectivity from albedo and metallic
		albedo, GetMetallic(i), specularTint, oneMinusReflectivity
	);
	#if defined(_RENDERING_TRANSPARENT)
		albedo *= alpha;
		alpha = 1 - oneMinusReflectivity + alpha * oneMinusReflectivity; // premultiplied alpha energy conservation
	#endif
	i.normal = CalculateNormalMapping(i); 

	float4 color = UNITY_BRDF_PBS(
		albedo, specularTint,
		oneMinusReflectivity, GetSmoothness(i),
		i.normal, viewDir,
		CreateLight(i), CreateIndirectLight(i, viewDir)
	);
	color.rgb += GetEmission(i);
	#if defined(_RENDERING_FADE) || defined(_RENDERING_TRANSPARENT)
		color.a = alpha;
	#endif
	FragmentOutput output;
	#if defined(DEFERRED_PASS)
		#if !defined(UNITY_HDR_ON)
			color.rgb = exp2(-color.rgb);
		#endif
		output.gBuffer0.rgb = albedo;
		output.gBuffer0.a = GetOcclusion(i);
		output.gBuffer1.rgb = specularTint;
		output.gBuffer1.a = GetSmoothness(i);
		output.gBuffer2 = float4(i.normal * 0.5 + 0.5, 1);
		output.gBuffer3 = color; 
	#else
		output.color = ApplyFog(color, i);
	#endif
	return output;
}

#endif