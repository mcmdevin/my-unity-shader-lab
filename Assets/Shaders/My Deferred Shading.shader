Shader "Custom/My Deferred Shading" {

    Properties {

    }

    SubShader {

        Pass {
            Cull Off
            ZTest Always
            ZWrite Off

            CGPROGRAM

            #pragma target 3.0
            #pragma vertex VertexProgram
            #pragma fragment FragmentProgram

            #pragma exclude_renderers nomrt

            #include "UnityCG.cginc"

            struct VertexData {
                float4 vertex : POSITION;
            };

            struct Interpolators {
                float4 pos : SV_POSITION;
            };

            Interpolators VertexProgram(VertexData v) {
                Interpolators i;
                i.pos = UnityObjectToClipPos(v.vertex);
                return i;
            }

            float4 FragmentProgram(Interpolators i) : SV_Target {
                return 0;
            }

            ENDCG
        }

        Pass {
            Cull Off
            ZTest Always
            ZWrite Off

            Stencil {
                Ref [_StencilNonBackground]
                ReadMask [_StencilNonBackground]
                CompBack Equal
                CompFront Equal
            }

            CGPROGRAM

            #pragma target 3.0
            #pragma vertex VertexProgram
            #pragma fragment FragmentProgram

            #pragma exclude_renderers nomrt

            #include "UnityCG.cginc"

            sampler2D _LightBuffer;

            struct VertexData {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct Interpolators {
                float4 pos : SV_POSITION;
                float2 uv : TEXCOORD0;
            };

            Interpolators VertexProgram(VertexData v) {
                Interpolators i;
                i.pos = UnityObjectToClipPos(v.vertex);
                i.uv = v.uv;
                return i;
            }

            float4 FragmentProgram(Interpolators i) : SV_Target {
                return tex2D(_LightBuffer, i.uv);
            }

            ENDCG
        }
    }
}