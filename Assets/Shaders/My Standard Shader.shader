﻿// References
// https://catlikecoding.com/unity/tutorials/rendering/
// https://www.youtube.com/watch?v=E4PHFnvMzFc&ab_channel=FreyaHolm%C3%A9r

Shader "Custom/My Standard Shader" {

	Properties {
		_Tint ("Tint", Color) = (1, 1, 1, 1)
		_MainTex ("Albedo", 2D) = "white" {}
		[NoScaleOffset] _NormalMap ("Normal Map", 2D) = "bump" {}
		_NormalScale ("Normal Scale", Range(0, 1)) = 1
		[Gamma] _Metallic ("Metallic", Range(0, 1)) = 0 // metallic slider should be Gamma corrected
		_Smoothness ("Smoothness", Range(0, 1)) = 0.1
	}

	SubShader {

		Pass {
			Tags {
				"LightMode" = "ForwardBase"
				// Lightmode: https://docs.unity3d.com/Packages/com.unity.render-pipelines.universal@11.0/manual/urp-shaders/urp-shaderlab-pass-tags.html#urp-pass-tags-lightmode
			}

			CGPROGRAM

			#pragma target 3.0

			#pragma multi_compile _ SHADOWS_SCREEN // keyword when the main light casts shadow
			#pragma multi_compile _ VERTEXLIGHT_ON

			#pragma vertex MyVertexProgram
			#pragma fragment MyFragmentProgram

			#define FORWARD_BASE_PASS // include spherical harmonics in base pass only; https://catlikecoding.com/unity/tutorials/rendering/part-5/ 

			#include "My Standard Lighting.cginc"

			ENDCG
		}

		Pass {
			Tags {
				"LightMode" = "ForwardAdd"
			}

			Blend One One
			ZWrite Off // writing to Z buffer twice isn't necessary

			CGPROGRAM

			#pragma target 3.0

			#pragma multi_compile_fwdadd_fullshadows // let all sorts of light cast shadows

			#pragma vertex MyVertexProgram
			#pragma fragment MyFragmentProgram

			#include "My Standard Lighting.cginc"

			ENDCG
		}

		Pass {
			Tags {
				"LightMode" = "ShadowCaster"
			}

			CGPROGRAM

			#pragma target 3.0

			#pragma multi_compile_shadowcaster // defines SHADOWS_DEPTH and SHADOW_CUBE

			#pragma vertex MyShadowVertexProgram
			#pragma fragment MyShadowFragmentProgram

			#include "My Standard Shadows.cginc"

			ENDCG
		}
	}
}