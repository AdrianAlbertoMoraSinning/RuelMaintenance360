import {supabase} from './supabase'
export async function localPartPhotoRequest(body:Record<string,unknown>){
 const{data,error}=await supabase.auth.getSession();if(error||!data.session)throw new Error('Sign in to compare catalogue photographs')
 const response=await fetch('/.netlify/functions/part-photo-match-local',{method:'POST',headers:{Authorization:`Bearer ${data.session.access_token}`,'Content-Type':'application/json'},body:JSON.stringify(body),signal:AbortSignal.timeout(55000)})
 let result;try{result=await response.json()}catch{throw new Error('The local photo comparison service is unavailable. Reload the application and try again.')}
 if(!response.ok||result.error)throw new Error(result.error||'Local photo comparison failed')
 return result
}
