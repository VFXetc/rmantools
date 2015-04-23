#ifndef KS_REYES_PLASTIC_H
#define KS_REYES_PLASTIC_H
/*
<rman id="rslt">
slim 1 extensions pixar_db {
extensions pixar {} {
    
    template void KSReyesPlastic {

        userdata {
            rfm_nodeid 2000021
            rfm_classification \
                shader/surface:rendernode/RenderMan/shader/surface:swatch/rmanSwatch
        }

        codegenhints {
            shaderobject {
                initDiffuse {
                    diffuseColor
                    ambientColor
                }
                lighting {
                    f:initDiffuse
                }
                diffuselighting {
                    f:initDiffuse
                }
                specularlighting {
                    specularColor
                    roughness
                }
            }
        }
    
        parameter color diffuseColor {
            provider parameterlist
            default {1 1 1}
        }

        parameter color ambientColor {
            provider parameterlist
            default {1 1 1}
        }

        parameter color specularColor {
            provider parameterlist
            default {1 1 1}
        }

        parameter float roughness {
            provider parameterlist
            default 0.1
        }

        RSLSource ShaderPipeline _thisfile_

    }
}}
</rman>
*/

#include <stdrsl/Colors.h>
#include <stdrsl/Fresnel.h>
#include <stdrsl/Lambert.h>
#include <stdrsl/Math.h>
#include <stdrsl/OrenNayar.h>
#include <stdrsl/RadianceSample.h>
#include <stdrsl/ShadingContext.h>
#include <stdrsl/SpecularAS.h>


RSLINJECT_preamble

RSLINJECT_shaderdef
{

    RSLINJECT_members


    uniform float specularRoughness = .00001;

    // Signal that we don't do anything special with opacity.
    uniform float __computesOpacity = 0;

    uniform float m_nSamplesSpecular = 36;
    uniform float m_nSamplesDiffuse = 256;

    uniform float m_ior = 1.8;
    uniform float m_mediaIor = 1;

    stdrsl_ShadingContext m_shadingCtx;
    stdrsl_Fresnel m_fresnel;
    stdrsl_Lambert m_diffuse;
    stdrsl_SpecularAS m_specular;

    uniform string m_lightGroups[];
    uniform float m_nLightGroups;

    // Should we write out all of the GP AOVs (we know about)?
    uniform float WriteGPAOVs = 0;


    public void construct() {
        m_shadingCtx->construct();
        option("user:lightgroups",  m_lightGroups);
        m_nLightGroups = arraylength(m_lightGroups);
    }

    public void begin() {
        m_shadingCtx->init();
        m_fresnel->init(m_shadingCtx, m_mediaIor, m_ior);
    }

    public void prelighting(output color Ci, Oi) {
    }

    public void initDiffuse() {
        RSLINJECT_initDiffuse
        m_diffuse->init(m_shadingCtx, color(m_fresnel->m_Kt), 1, m_nSamplesDiffuse);
    }

    public void initSpecular() {
        RSLINJECT_initSpecular
        m_specular->init(m_shadingCtx,
            color(m_fresnel->m_Kr), // The fresnel is not automatically used by the spec.
            specularRoughness,
            0, // Anistrophy ratio.
            1, // Roughness scale.
            1, // Minimum samples.
            m_nSamplesSpecular // Maximum samples.
        );
    }

    void writeAOVs(string pattern; color diffuseDirect, specularDirect,
        unshadowedDiffuseDirect, unshadowedSpecularDirect, diffuseIndirect
    ) {

        writeaov(format(pattern, "Diffuse"), diffuseColor * (diffuseDirect + diffuseIndirect)); // Same as GP.
        writeaov(format(pattern, "Specular"), specularColor * specularDirect); // DIRECT ONLY! Same as GP.

        writeaov(format(pattern, "DiffuseDirect"), diffuseDirect);
        writeaov(format(pattern, "SpecularDirect"), specularDirect);
        writeaov(format(pattern, "DiffuseDirectNoShadow"), unshadowedDiffuseDirect);
        writeaov(format(pattern, "SpecularDirectNoShadow"), unshadowedSpecularDirect);

        // We find these shadows make a bit more sense.
        writeaov(format(pattern, "DiffuseShadowMult"), diffuseDirect / unshadowedDiffuseDirect);
        writeaov(format(pattern, "SpecularShadowMult"), specularDirect / unshadowedSpecularDirect);

        if (WriteGPAOVs) {
            writeaov(format(pattern, "DiffuseShadow" ), diffuseColor  * (unshadowedDiffuseDirect  - diffuseDirect )); // Same as GP.
            writeaov(format(pattern, "SpecularShadow"), specularColor * (unshadowedSpecularDirect - specularDirect)); // Same as GP.
        }

    }

    public void lighting(output color Ci, Oi)
    {
        RSLINJECT_lighting
        initDiffuse();
        initSpecular();

        float depth = 0;
        rayinfo("depth", depth);

        shader lights[] = getlights();

        color diffuseDirect = 0;
        color specularDirect = 0;
        color unshadowedDiffuseDirect = 0;
        color unshadowedSpecularDirect = 0;
        color groupedDiffuseDirect[];
        color groupedSpecularDirect[];
        color groupedUnshadowedDiffuseDirect[];
        color groupedUnshadowedSpecularDirect[];

        if (depth == 0 && m_nLightGroups != 0) {
            
            // We only need all of this data when we are writing AOVs.
            directlighting(this, lights,
                "diffuseresult", diffuseDirect,
                "specularresult", specularDirect,
                "unshadoweddiffuseresult", unshadowedDiffuseDirect,
                "unshadowedspecularresult", unshadowedSpecularDirect,

                "lightgroups", m_lightGroups,
                "groupeddiffuseresults", groupedDiffuseDirect,
                "groupedspecularresults", groupedSpecularDirect,
                "groupedunshadoweddiffuseresults", groupedUnshadowedDiffuseDirect,
                "groupedunshadowedspecularresults", groupedUnshadowedSpecularDirect
            );
        } else {
            directlighting(this, lights,
                "diffuseresult", diffuseDirect,
                "specularresult", specularDirect
            );
        }

        color diffuseIndirect = indirectdiffuse(P, normalize(N), m_nSamplesDiffuse);
        color specularIndirect = indirectspecular(this);

        Ci += diffuseColor  * (diffuseDirect  + diffuseIndirect ) \
            + specularColor * (specularDirect + specularIndirect);

        if (depth == 0) {

            writeAOVs("%s",
                diffuseDirect, specularDirect,
                unshadowedDiffuseDirect, unshadowedSpecularDirect,
                diffuseIndirect
            );

            writeaov("DiffuseColor", diffuseColor); // Not written by GP.
            writeaov("DiffuseIndirect", diffuseIndirect); // Not written by GP.
            writeaov("SpecularIndirect", specularIndirect); // Same as GP.

            uniform float i;
            for (i = 0; i < m_nLightGroups; i += 1) {
                writeAOVs(concat("Grouped%s_", m_lightGroups[i]),
                    groupedDiffuseDirect[i],
                    groupedSpecularDirect[i],
                    groupedUnshadowedDiffuseDirect[i],
                    groupedUnshadowedSpecularDirect[i],
                    color(0)
                );
            }

        }

    }


    public void evaluateSamples(string distribution; output __radiancesample samples[]) {
        if (distribution == "diffuse" && m_nSamplesDiffuse > 0) {
            m_diffuse->evalDiffuseSamps(m_shadingCtx, m_fresnel, samples);
        }
        if (distribution != "diffuse" && m_nSamplesSpecular > 0) {
            m_specular->evalSpecularSamps(m_shadingCtx, m_fresnel, samples);
        }
    }

    public void generateSamples(string distribution; output __radiancesample samples[]) {
        if (distribution != "diffuse" && m_nSamplesSpecular > 0) {
            m_specular->genSpecularSamps(m_shadingCtx, m_fresnel, distribution, samples);
        }
    }
}

#endif

