import sharp from 'sharp'
sharp.concurrency(1)
sharp.cache({memory:32,items:32,files:0})
let runtime
async function openCV(){if(!runtime)runtime=import('@techstark/opencv-js').then(async m=>await m.default);return runtime}
const MAX_SIDE=800,MIN_FEATURES=20
export async function extractFeatures(buffer){
 const raster=(buffer[0]===255&&buffer[1]===216)||buffer.subarray(0,8).equals(Buffer.from([137,80,78,71,13,10,26,10]))||(buffer.subarray(0,4).toString()==='RIFF'&&buffer.subarray(8,12).toString()==='WEBP')
 if(!raster)throw new Error('Unsupported raster image')
 const cv=await openCV();let gray,keypoints,descriptors,mask,orb
 try{
 const {data,info}=await sharp(buffer,{limitInputPixels:25000000,failOn:'error'}).rotate().resize({width:MAX_SIDE,height:MAX_SIDE,fit:'inside',withoutEnlargement:true}).flatten({background:'#fff'}).greyscale().raw().toBuffer({resolveWithObject:true})
 gray=cv.matFromArray(info.height,info.width,cv.CV_8UC1,data);keypoints=new cv.KeyPointVector();descriptors=new cv.Mat();mask=new cv.Mat();orb=new cv.ORB(1000)
 orb.detectAndCompute(gray,mask,keypoints,descriptors)
 const points=[];for(let i=0;i<keypoints.size();i++){const p=keypoints.get(i).pt;points.push([p.x,p.y])}
 return {width:info.width,height:info.height,points,descriptors:new Uint8Array(descriptors.data),rows:descriptors.rows,cols:descriptors.cols}
 }finally{for(const x of [orb,mask,descriptors,keypoints,gray])x?.delete()}
}
export async function compareFeatures(query,reference){
 if(query.rows<MIN_FEATURES||reference.rows<MIN_FEATURES)return null
 const cv=await openCV();const owned=[];const take=x=>(owned.push(x),x)
 try{
 const a=take(cv.matFromArray(query.rows,query.cols,cv.CV_8UC1,query.descriptors)),b=take(cv.matFromArray(reference.rows,reference.cols,cv.CV_8UC1,reference.descriptors)),matcher=take(new cv.BFMatcher(cv.NORM_HAMMING,false)),pairs=take(new cv.DMatchVectorVector())
 matcher.knnMatch(a,b,pairs,2)
 const candidates=[],train=new Set()
 for(let i=0;i<pairs.size();i++){const pair=pairs.get(i);try{if(pair.size()<2)continue;const first=pair.get(0),second=pair.get(1);if(first.distance<=60&&first.distance<.72*second.distance&&!train.has(first.trainIdx)){train.add(first.trainIdx);candidates.push([first.queryIdx,first.trainIdx])}}finally{pair.delete()}}
 if(candidates.length<12)return null
 const src=take(cv.matFromArray(candidates.length,1,cv.CV_32FC2,candidates.flatMap(p=>query.points[p[0]]))),dst=take(cv.matFromArray(candidates.length,1,cv.CV_32FC2,candidates.flatMap(p=>reference.points[p[1]]))),mask=take(new cv.Mat()),transform=take(cv.findHomography(src,dst,cv.RANSAC,3,mask))
 if(transform.empty())return null
 const inliers=candidates.filter((_,i)=>mask.data[i]!==0),ratio=inliers.length/candidates.length
 if(inliers.length<12||ratio<.55)return null
 const coverage=(points,width,height)=>{const xs=points.map(p=>p[0]),ys=points.map(p=>p[1]);return (Math.max(...xs)-Math.min(...xs))*(Math.max(...ys)-Math.min(...ys))/(width*height)}
 const spread=Math.min(coverage(inliers.map(p=>query.points[p[0]]),query.width,query.height),coverage(inliers.map(p=>reference.points[p[1]]),reference.width,reference.height))
 if(spread<.06)return null
 return {inliers:inliers.length,ratio,coverage:spread,score:inliers.length*ratio*Math.sqrt(spread),similarity:inliers.length>=24&&ratio>=.7?'high':'medium'}
 }finally{for(const x of owned.reverse())x.delete()}
}
export async function engineHealth(){const cv=await openCV();const probe=await sharp({create:{width:8,height:8,channels:3,background:'#fff'}}).png().toBuffer();await sharp(probe).metadata();const mat=new cv.Mat(1,1,cv.CV_8UC1);mat.delete();return {engine:'local_opencv_orb',ready:typeof cv.ORB==='function'&&typeof cv.findHomography==='function',opencv:cv.getVersionString?.()||'bundled',image_library:sharp.versions.sharp,external_ai:false}}
export function usableQuery(features){return features.rows>=MIN_FEATURES}
