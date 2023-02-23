#ifdef GL_ES
precision mediump float;
#endif

// Phong related variables
uniform sampler2D uSampler;
uniform vec3 uKd;
uniform vec3 uKs;
uniform vec3 uLightPos;
uniform vec3 uCameraPos;
uniform vec3 uLightIntensity;

varying highp vec2 vTextureCoord;
varying highp vec3 vFragPos;
varying highp vec3 vNormal;

// Shadow map related variables
#define NUM_SAMPLES 80
#define BLOCKER_SEARCH_NUM_SAMPLES NUM_SAMPLES
#define PCF_NUM_SAMPLES NUM_SAMPLES
#define NUM_RINGS 10

#define EPS 1e-3
#define PI 3.141592653589793
#define PI2 6.283185307179586

uniform sampler2D uShadowMap;

varying vec4 vPositionFromLight;

highp float rand_1to1(highp float x){
  // -1 -1
  return fract(sin(x)*10000.);
}

highp float rand_2to1(vec2 uv){
  // 0 - 1
  const highp float a=12.9898,b=78.233,c=43758.5453;
  highp float dt=dot(uv.xy,vec2(a,b)),sn=mod(dt,PI);
  return fract(sin(sn)*c);
}

float unpack(vec4 rgbaDepth){
  const vec4 bitShift=vec4(1.,1./256.,1./(256.*256.),1./(256.*256.*256.));
  return dot(rgbaDepth,bitShift);
}

vec2 poissonDisk[NUM_SAMPLES];

void poissonDiskSamples(const in vec2 randomSeed){
  
  float ANGLE_STEP=PI2*float(NUM_RINGS)/float(NUM_SAMPLES);
  float INV_NUM_SAMPLES=1./float(NUM_SAMPLES);
  
  float angle=rand_2to1(randomSeed)*PI2;
  float radius=INV_NUM_SAMPLES;
  float radiusStep=radius;
  
  for(int i=0;i<NUM_SAMPLES;i++){
    poissonDisk[i]=vec2(cos(angle),sin(angle))*pow(radius,.75);
    radius+=radiusStep;
    angle+=ANGLE_STEP;
  }
}

void uniformDiskSamples(const in vec2 randomSeed){
  
  float randNum=rand_2to1(randomSeed);
  float sampleX=rand_1to1(randNum);
  float sampleY=rand_1to1(sampleX);
  
  float angle=sampleX*PI2;
  float radius=sqrt(sampleY);
  
  for(int i=0;i<NUM_SAMPLES;i++){
    poissonDisk[i]=vec2(radius*cos(angle),radius*sin(angle));
    
    sampleX=rand_1to1(sampleY);
    sampleY=rand_1to1(sampleX);
    
    angle=sampleX*PI2;
    radius=sqrt(sampleY);
  }
}

float findBlocker(sampler2D shadowMap,vec2 uv,float zReceiver){
  int blockerNum=0;
  float blockerDepth=0.;
  float size=2048.;
  float stride=80./size;
  
  poissonDiskSamples(uv);
  
  for(int i=0;i<NUM_SAMPLES;++i){
    vec4 color=texture2D(shadowMap,uv+stride*poissonDisk[i]);
    float depth=unpack(color);
    if(depth+EPS>zReceiver){
      blockerNum++;
      blockerDepth+=depth;
    }
  }
  
  return blockerNum==0?1.:blockerDepth/float(blockerNum);
}

float PCF(sampler2D shadowMap,vec4 coords){
  float size=2048.;//engine.js中定义
  float stride=20./size;
  float curDepth=coords.z;
  float visibility=0.;
  
  poissonDiskSamples(coords.xy);
  
  for(int i=0;i<NUM_SAMPLES;++i){
    vec4 color=texture2D(shadowMap,coords.xy+stride*poissonDisk[i]);
    float depth=unpack(color);
    visibility+=(depth+EPS>curDepth)?1.:0.;
  }
  
  return visibility/float(NUM_SAMPLES);
}

float PCSS(sampler2D shadowMap,vec4 coords){
  
  // STEP 1: avgblocker depth
  float avgblockerDepth=findBlocker(shadowMap,coords.xy,coords.z);
  float lightWidth=1.;
  
  // STEP 2: penumbra size
  float penumbraWeight=lightWidth*(coords.z-avgblockerDepth)/avgblockerDepth;
  
  // STEP 3: filtering
  float size=2048.;
  float stride=20./size;
  float curDepth=coords.z;
  float visibility=0.;
  
  poissonDiskSamples(coords.xy);
  
  for(int i=0;i<NUM_SAMPLES;++i){
    vec4 color=texture2D(shadowMap,coords.xy+stride*poissonDisk[i]*penumbraWeight);
    float depth=unpack(color);
    visibility+=(depth+EPS>curDepth)?1.:0.;
  }
  
  return visibility/float(NUM_SAMPLES);
  
}

float useShadowMap(sampler2D shadowMap,vec4 shadowCoord){
  if(unpack(texture2D(shadowMap,shadowCoord.xy))+EPS>shadowCoord.z){
    return 1.;
  }else{
    return 0.;
  }
}

vec3 blinnPhong(){
  vec3 color=texture2D(uSampler,vTextureCoord).rgb;
  color=pow(color,vec3(2.2));
  
  vec3 ambient=.05*color;
  
  vec3 lightDir=normalize(uLightPos);
  vec3 normal=normalize(vNormal);
  float diff=max(dot(lightDir,normal),0.);
  vec3 light_atten_coff=
  uLightIntensity/pow(length(uLightPos-vFragPos),2.);
  vec3 diffuse=diff*light_atten_coff*color;
  
  vec3 viewDir=normalize(uCameraPos-vFragPos);
  vec3 halfDir=normalize((lightDir+viewDir));
  float spec=pow(max(dot(halfDir,normal),0.),32.);
  vec3 specular=uKs*light_atten_coff*spec;
  
  vec3 radiance=(ambient+diffuse+specular);
  vec3 phongColor=pow(radiance,vec3(1./2.2));
  return phongColor;
}

void main(void){
  vec3 shadowCoord=vPositionFromLight.xyz/vPositionFromLight.w;
  shadowCoord=shadowCoord*.5+.5;
  
  float visibility;
  // visibility=useShadowMap(uShadowMap,vec4(shadowCoord,1.));
  // visibility=PCF(uShadowMap,vec4(shadowCoord,1.));
  visibility=PCSS(uShadowMap,vec4(shadowCoord,1.));
  
  vec3 phongColor=blinnPhong();
  
  gl_FragColor=vec4(phongColor*visibility,1.);
  // gl_FragColor=vec4(phongColor,1.);
}