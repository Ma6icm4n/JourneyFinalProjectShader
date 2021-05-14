Shader "Custom/JourneySand"
{
    Properties
    {
        //Creation of the interface for all the different effect use for the shader
        _MainTex ("Albedo (RGB)", 2D) = "white" {}

        [Toggle]_SandEnabled("SandEnabled", Int) = 1
        _SandTex("Sand Texture (RGB)", 2D) = "white" {}
        _SandStrength("Sand Strength", Range(0, 1)) = 0.1

        [Toggle]_DiffuseEnabled("Diffuse Enabled", Int) = 1
        _TerrainColor("Color", Color) = (1, 1, 1, 1)
        _ShadowColor("Color", Color) = (1, 1, 1, 1)

        [Toggle]_RimEnabled("RimLighting", Int) = 1
        _RimPower("Rim Power", Float) = 1
        _RimStrenght("Rim Strenght", Float) = 1
        _RimColor("Rim Color", Color) = (1, 1, 1, 1)

        [Toggle]_OceanSpecular("Ocean Specular", Int) = 1
        _OceanSpecularPower("Power", Float) = 1
        _OceanSpecularStrenght("Strenght", Float) = 1
        _OceanSpecularColor("Color", Color) = (1, 1, 1, 1)

        [Toggle]_WavesEnabled("Waves", Int) = 1
        _SteepnessSharpnessPower("Steepness Factor", Float) = 1
        _XZBlendPower("XZ Factor", Float) = 1
		_ShallowXTex("Shallow X Texture", 2D) = "white" {}
		_ShallowZTex("Shallow Z Texture", 2D) = "white" {}
		_SteepXTex("Steep X Texture", 2D) = "white" {}
		_SteepZTex("Steep Z Texture", 2D) = "white" {}
		_WaveBlend("Wave Blend", Range(0,1))=0.1

        [Toggle] _GlitterEnabled("Glitter", Int) = 1
        _GlitterTex("GLitter Direction", 2D) = "White" {}
        _GlitterTreshold("Glitter Treshold", Range(0, 1)) = 1
        [HDR] _GlitterColor("Color", Color) = (1, 1, 1, 1)


    }
        
    SubShader
    {
        Tags { "RenderType"="Opaque" }
        LOD 200

        CGPROGRAM
        // Physically based Standard lighting model, and enable shadows on all light types
        #pragma surface surf Journey fullforwardshadows

        // Use shader model 3.0 target, to get nicer looking lighting
        #pragma target 4.0

        sampler2D _MainTex;

        struct Input
        {
            float2 uv_MainTex;

            float3 worldPos;
            //used to write on the world normal not directly on the surface normal
            float3 worldNormal;
            INTERNAL_DATA
        };
        //used in the lighting function
        float3 worldPos;

        //interpolation called Nlerp 
        //this technique is used to close the gap between the simple lerp interpolation
        // and the really ressources consuming Slerp algorithme
        inline float3 normallerp(float3 n1, float3 n2, float t) {
            return normalize(lerp(n1, n2, t));
        }


        //Calculate Waves
        int _WavesEnabled;
		float _SteepnessSharpnessPower;
		float _XZBlendPower;
		sampler2D_float _ShallowXTex;	float4 _ShallowXTex_ST;
		sampler2D_float _ShallowZTex;	float4 _ShallowZTex_ST;
		sampler2D_float _SteepXTex;		float4 _SteepXTex_ST;
		sampler2D_float _SteepZTex;		float4 _SteepZTex_ST;
		float _WaveBlend;
        float3 WavesNormal( float3 W, float3 N, Input IN) {
            if(_WavesEnabled == 0) {
                return N;
            }

            //convert Normal to tangent to compare the steepness of the dune
            //using N_WORLD compare Right_world and Up_world
            float3 N_WORLD = WorldNormalVector(IN, N);

            //Steepness 0 = flat 1 = 90 degrees
            float3 UP_WORLD = float3(0, 1, 0);
            float steepness = saturate(dot(N_WORLD, UP_WORLD));

            steepness = pow(steepness, _SteepnessSharpnessPower);
            steepness = 1 -steepness;

            //Calculate the direction of the waves
            // 0 facing x
            // 1 facing y
            float3 RIGHT_WORLD = float3(1, 0, 0);
            float facing = abs(dot(N_WORLD, RIGHT_WORLD)) * 2;

            //precise the direction
            facing = facing * 2 - 1;
            facing = pow(abs(facing), 1.0 / _XZBlendPower) * sign(facing);
            facing = facing * 0.5 + 0.5;

            //calculate and convert the range to -1, +1
            float2 uv = W.xy;
            float3 shallowX = UnpackNormal(tex2D(_ShallowXTex, TRANSFORM_TEX(uv, _ShallowXTex)));
            float3 shallowZ = UnpackNormal(tex2D(_ShallowZTex, TRANSFORM_TEX(uv, _ShallowZTex)));
            float3 steepX = UnpackNormal(tex2D(_SteepXTex, TRANSFORM_TEX(uv, _SteepXTex)));
            float3 steepZ = UnpackNormal(tex2D(_SteepZTex, TRANSFORM_TEX(uv, _SteepZTex)));


            //Final interpolation

            float3 S = normallerp(normallerp(shallowZ, shallowX, facing), 
                                    normallerp(steepZ, steepX, facing),
                                    steepness);

            //Roation the normal with S 
            float3 Ns = normallerp(N, S, _WaveBlend);
            return Ns;
        }

        //Calculate Normals
        int _SandEnabled;
        sampler2D_float _SandTex;
        float4 _SandTex_ST;
        float _SandStrength;
        float3 SandNormal(float3 W, float3 N) {
            if(_SandEnabled == 0) {
                return N;
            }

            //create random direction and change range to -1, +1
            float2 uv = W.xz;
            float3 S = normalize(tex2D(_SandTex, TRANSFORM_TEX(uv, _SandTex)).rgb * 2 -1);
            float3 Ns = normallerp(N, S, _SandStrength);
            return Ns;
        }

        //calculate Diffuse
        int _DiffuseEnabled;
        float3 _TerrainColor;
        float3 _ShadowColor;

        float3 DiffuseCalculation(float3 N, float3 L) {

            //we calculate the normal direction with the light 
            //we do a dot product to see the difference of direction between 
            // the 2 vectors
            float NdotL = saturate(4 * dot(N * float3(1, 0.3, 1), L));

            if(_DiffuseEnabled == 0) {
                NdotL = saturate(dot(N, L));
            }

            float3 color = lerp(_ShadowColor, _TerrainColor, NdotL);
            return color;
        }

        //Calculate Rim on the edge of dunes
        int _RimEnabled;
        float _RimPower;
        float _RimStrenght;
        float3 _RimColor;

        float3 RimLighting(float3 N, float3 V) {
            if(_RimEnabled == 0) {
                return 0;
            }
            //interpolate direction and normal surface
            float rim = 1.0 - saturate(dot(N, V));
            //precise rim with power and strength
            rim = saturate(pow(rim, _RimPower) * _RimStrenght);
            rim = max(rim, 0); // absolute value
            return rim * _RimColor;
        }

        //Specular called by the creator of the journey sand Ocean Specular
        int _OceanSpecular;
        float _OceanSpecularPower;
        float _OceanSpecularStrenght;
        float3 _OceanSpecularColor;
        float3 OceanSpecular(float3 N, float3 L, float3 V) {
            if(_OceanSpecular == 0) {
                return 0;
            }

            //Blinn Phong algorithme 
            float3 H = normalize(V + L);
            float NdotH = max(0, dot(N, H));
            float specular = pow(NdotH, _OceanSpecularPower) * _OceanSpecularStrenght;
            return specular * _OceanSpecularColor;
        }

        //Simpple Glitter not really showing good dependant on the color choosed
        int _GlitterEnabled;
		sampler2D_float _GlitterTex;
		float4 _GlitterTex_ST;
		float _GlitterTreshold;
		float3 _GlitterColor;
		float3 GlitterSpecular (float3 N, float3 L, float3 V, float3 W)
		{
			if (_GlitterEnabled == 0)
				return 0;

			// Random glitter direction change range -1, +1
			float2 uv = W.xz;
			float3 G = normalize(tex2D(_GlitterTex, TRANSFORM_TEX(uv, _GlitterTex)).rgb * 2 - 1);

			// Light that reflects on the glitter and hits the eye
			float3 R = reflect(L, G);
			float NdotH = max(0, dot(R, V));
			
			// Only the strong ones
			if (NdotH < _GlitterTreshold)
				return 0;

			return NdotH * _GlitterColor;
		}

        //lighting function that encapsulate all other function
        inline float4 LightingJourney(SurfaceOutput s, fixed3 viewDir, UnityGI gi) {
            //get the value of the surface from unity
            float3 L = gi.light.dir;
            float3 V = viewDir;
            float3 N = s.Normal;
            float3 W = worldPos;

            float3 diffuseColor = DiffuseCalculation (N, L);
            float3 rimColor = RimLighting(N, V);
            float3 oceanColor = OceanSpecular(N, L, V);
            float glitterColor = GlitterSpecular(N, L, V, W);

            float3 specularColor = saturate(max(rimColor, oceanColor));
            float3 color = diffuseColor + specularColor + glitterColor;
            return float4(color * s.Albedo, 1);
        }

        void LightingJourney_GI(SurfaceOutput s, UnityGIInput data, inout UnityGI gi) {
            //function to use unityGI without problem default from unity
        }

        void surf (Input IN, inout SurfaceOutput o)
        {
            //Albedo with a tinted color texture
            fixed4 c = tex2D(_MainTex, IN.uv_MainTex);
            o.Albedo = c.rgb;
            o.Alpha = c.a;

            worldPos = IN.worldPos;

            float3 W = worldPos;
            float3 N = float3(0, 0, 1);

            N = WavesNormal(W, N, IN);
            N = SandNormal(W, N);

            o.Normal = N;
        }
        ENDCG
    }
    FallBack "Diffuse"
}
