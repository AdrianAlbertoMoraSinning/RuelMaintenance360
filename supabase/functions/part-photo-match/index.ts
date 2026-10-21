// Compatibility endpoint for older clients. All comparison runs on the RUEL server.
// No AI provider configuration, API call or fallback exists in this photo endpoint.
const endpoint='https://ruelmaintenance360.netlify.app/.netlify/functions/part-photo-match-local'
const headers={'Access-Control-Allow-Origin':'https://ruelmaintenance360.netlify.app','Access-Control-Allow-Headers':'authorization, x-client-info, apikey, content-type','Access-Control-Allow-Methods':'POST, OPTIONS','Content-Type':'application/json','Cache-Control':'no-store'}
Deno.serve(async req=>{
 if(req.method==='OPTIONS')return new Response(null,{status:204,headers})
 if(req.method!=='POST')return new Response(JSON.stringify({error:'POST required'}),{status:405,headers})
 const authorization=req.headers.get('authorization')||''
 if(!/^Bearer\s+\S+$/i.test(authorization))return new Response(JSON.stringify({error:'Sign in to compare catalogue photographs'}),{status:401,headers})
 try{
 const body=await req.text();if(body.length>5500000)return new Response(JSON.stringify({error:'Choose a smaller photograph'}),{status:413,headers})
 const response=await fetch(endpoint,{method:'POST',headers:{Authorization:authorization,'Content-Type':'application/json'},body,signal:AbortSignal.timeout(55000)})
 if(!response.headers.get('content-type')?.includes('application/json'))throw new Error('Local engine unavailable')
 return new Response(await response.text(),{status:response.status,headers})
 }catch{return new Response(JSON.stringify({error:'The local photo comparison service is unavailable. Reload the application and try again.'}),{status:503,headers})}
})
