// Fit the complete source rectangle inside a circle with space around its corners.
export function avatarPhotoLayout(width:number,height:number,size=640){
 if(![width,height,size].every(n=>Number.isFinite(n)&&n>0))throw new Error('Unable to read the photo dimensions.')
 const scale=size*.92/Math.hypot(width,height),drawWidth=width*scale,drawHeight=height*scale
 return{x:(size-drawWidth)/2,y:(size-drawHeight)/2,width:drawWidth,height:drawHeight,size}
}
export async function prepareAvatarPhoto(file:File):Promise<Blob>{
 const bitmap=await createImageBitmap(file,{imageOrientation:'from-image'})
 try{
  const layout=avatarPhotoLayout(bitmap.width,bitmap.height),canvas=document.createElement('canvas');canvas.width=layout.size;canvas.height=layout.size
  const ctx=canvas.getContext('2d');if(!ctx)throw new Error('Unable to process photo.')
  // Extend a source background colour into the circular margin, preserving all source pixels.
  ctx.drawImage(bitmap,0,0,1,1,0,0,1,1);const colour=ctx.getImageData(0,0,1,1).data
  ctx.fillStyle=colour[3]>240?`rgb(${colour[0]},${colour[1]},${colour[2]})`:'#edf1f4';ctx.fillRect(0,0,layout.size,layout.size)
  ctx.imageSmoothingEnabled=true;ctx.imageSmoothingQuality='high';ctx.drawImage(bitmap,layout.x,layout.y,layout.width,layout.height)
  const blob=await new Promise<Blob|null>(resolve=>canvas.toBlob(resolve,'image/jpeg',.9));if(!blob)throw new Error('Unable to prepare photo.');return blob
 }finally{bitmap.close()}
}
