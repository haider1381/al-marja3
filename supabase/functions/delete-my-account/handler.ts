export type DeletionDeps = {getUser:(token:string)=>Promise<any>; context:(uid:string,session:string)=>Promise<any>; removeAvatars:(names:string[])=>Promise<any>; signOut:(token:string)=>Promise<any>; deleteUser:(uid:string)=>Promise<any>; clearUsage:(uid:string)=>Promise<any>; now:()=>number;};
const ORIGINS=new Set(['https://haider1381.github.io','https://localhost','capacitor://localhost']);
export function createDeletionHandler(deps:DeletionDeps){return async(req:Request)=>{
 const origin=req.headers.get('Origin'),headers:Record<string,string>={'Content-Type':'application/json; charset=utf-8','Cache-Control':'no-store','Vary':'Origin'};
 if(origin&&ORIGINS.has(origin)){headers['Access-Control-Allow-Origin']=origin;headers['Access-Control-Allow-Headers']='authorization,apikey,content-type,x-client-info';headers['Access-Control-Allow-Methods']='POST,OPTIONS';}
 const reply=(status:number,data:any)=>new Response(JSON.stringify(data),{status,headers});
 if(origin&&!ORIGINS.has(origin))return reply(403,{error:'مصدر الطلب غير مسموح.'});
 if(req.method==='OPTIONS')return new Response(null,{status:204,headers});
 if(req.method!=='POST')return reply(405,{error:'طريقة الطلب غير مسموحة.'});
 if(Number(req.headers.get('Content-Length')||0)>2048)return reply(413,{error:'طلب غير صالح.'});
 const token=req.headers.get('Authorization')?.match(/^Bearer\s+(.+)$/i)?.[1];if(!token)return reply(401,{error:'سجّل الدخول أولًا.'});
 try{
  const raw=await req.text();if(raw.length>2048)return reply(413,{error:'طلب غير صالح.'});let body;try{body=JSON.parse(raw);}catch(_){return reply(400,{error:'طلب غير صالح.'});}
  if(!body||body.confirmation!=='حذف حسابي'||Object.keys(body).some(k=>k!=='confirmation'))return reply(400,{error:'تأكيد الحذف مطلوب؛ لا يمكن تحديد حساب آخر.'});
  const userResult=await deps.getUser(token),user=userResult.data?.user;if(userResult.error||!user)return reply(401,{error:'الجلسة غير صالحة. أعد تسجيل الدخول.'});
  const age=deps.now()-Date.parse(user.last_sign_in_at||'');if(!Number.isFinite(age)||age<0||age>10*60*1000)return reply(401,{error:'سجّل الخروج ثم ادخل مجددًا، واحذف الحساب خلال عشر دقائق.'});
  let claims;try{claims=JSON.parse(atob(token.split('.')[1].replace(/-/g,'+').replace(/_/g,'/')));}catch(_){return reply(401,{error:'جلسة غير صالحة.'});}
  if(typeof claims.session_id!=='string'||claims.sub!==user.id)return reply(401,{error:'جلسة غير صالحة.'});
  const result=await deps.context(user.id,claims.session_id);if(result.error)throw result.error;const context=result.data;if(!context?.session_active)return reply(401,{error:'انتهت الجلسة. أعد تسجيل الدخول.'});
  if(context.is_owner)return reply(409,{error:'حسابك يدير المنصة. انقل مسؤولية إدارة المنصة قبل حذف الحساب، لحماية المكتبة وحقوق المستخدمين.'});
  const objects=context.objects||[];if(objects.some((o:any)=>o.bucket!=='avatars'))return reply(409,{error:'حسابك يملك ملفات مشتركة. تواصل مع إدارة المنصة لنقل ملكيتها ثم حذف الحساب دون فقد مواد المكتبة.'});
  if(objects.some((o:any)=>typeof o.name!=='string'||!o.name.startsWith(user.id+'/')))return reply(409,{error:'تحتاج ملكية ملفات الحساب إلى مراجعة قبل الحذف.'});
  const revoked=await deps.signOut(token);if(revoked.error)throw revoked.error;
  for(let i=0;i<objects.length;i+=100){const removed=await deps.removeAvatars(objects.slice(i,i+100).map((o:any)=>o.name));if(removed.error)throw removed.error;}
  const deletion=await deps.deleteUser(user.id);if(deletion.error)throw deletion.error;
  // Retried cleanup is safe; non-personal global counters remain intact.
  const cleanup=await deps.clearUsage(user.id);return reply(200,{deleted:true,usage_cleanup_pending:!!cleanup.error});
 }catch(_){return reply(500,{error:'تعذّر إكمال الحذف. جرّب تسجيل الدخول مجددًا أو تواصل مع إدارة المنصة.'});}
};}