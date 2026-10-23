export type SignaturePoint=[number,number]
export type SignatureStrokes=SignaturePoint[][]
export const SIGNATURE_MAX_POINTS=4000
export function signaturePoint(x:number,y:number,rect:{left:number;top:number;width:number;height:number}):SignaturePoint{
 if(!Number.isFinite(x)||!Number.isFinite(y)||rect.width<=0||rect.height<=0)throw Error('Signature box is not available')
 const n=(v:number)=>Math.round(Math.max(0,Math.min(1,v))*10000)/10000
 return[n((x-rect.left)/rect.width),n((y-rect.top)/rect.height)]
}
export function validSignature(strokes:SignatureStrokes){
 if(!Array.isArray(strokes)||strokes.length<1||strokes.length>100)return false
 let n=0,minX=1,maxX=0,minY=1,maxY=0
 for(const stroke of strokes){if(!Array.isArray(stroke)||stroke.length<2)return false;for(const p of stroke){if(!Array.isArray(p)||p.length!==2||p.some(v=>!Number.isFinite(v)||v<0||v>1))return false;n++;minX=Math.min(minX,p[0]);maxX=Math.max(maxX,p[0]);minY=Math.min(minY,p[1]);maxY=Math.max(maxY,p[1])}}
 return n>=8&&n<=SIGNATURE_MAX_POINTS&&maxX-minX>=.02&&maxY-minY>=.02
}
export function signaturePath(stroke:SignaturePoint[]){return stroke.map((p,i)=>`${i?'L':'M'}${Math.round(p[0]*9000)/10},${Math.round(p[1]*4500)/10}`).join(' ')}
