import fs from 'node:fs';
import assert from 'node:assert/strict';
const source=fs.readFileSync(new URL('../supabase/functions/medbrain-ai/index.ts',import.meta.url),'utf8').replace("import { createClient } from 'npm:@supabase/supabase-js@2.57.4';",'const createClient=()=>{};').replace('Deno.serve(createHandler());','');
const {createHandler,selectExcerpt}=await import('data:text/javascript;base64,'+Buffer.from(source).toString('base64'));
let state,providerCalls;
function reset(){state={valid:true,key:'test-server-key',allowed:true,lecture:{id:'837ae504-144a-40be-abb8-3452a7743647',title:'Cardiology',source:'Lecture source',topic:'Cardiology',lecture_text:'Full original text'},status:200,answer:'شرح طبي للاختبار'};providerCalls=[];}
reset();
const handler=createHandler({
 env:k=>({SUPABASE_URL:'https://example.test',SUPABASE_ANON_KEY:'anon',SUPABASE_SERVICE_ROLE_KEY:'server',GROQ_API_KEY:state.key})[k],
 makeClient:(url,key,options)=>key==='server'?{rpc:async(name,args)=>{assert.equal(name,'medbrain_ai_reserve');assert.equal(args.request_user,'real-user');return {data:{allowed:state.allowed,code:state.code||'slow_down',retry_seconds:20,remaining:14}};}}:{
 auth:{getUser:async token=>({data:{user:state.valid?{id:'real-user',is_anonymous:false}:null},error:state.valid?null:{}})},
 from:table=>{assert.equal(table,'lectures');assert.equal(options.global.headers.Authorization,'Bearer user-jwt');return {select(){return this},eq(){return this},maybeSingle:async()=>({data:state.lecture})};}
 },
 request:async(url,options)=>{assert.equal(url,'https://api.groq.com/openai/v1/chat/completions');assert.equal(options.headers.Authorization,'Bearer test-server-key');providerCalls.push(JSON.parse(options.body));return new Response(JSON.stringify(state.status===200?{choices:[{message:{content:state.answer},finish_reason:'stop'}]}:{}),{status:state.status});}
});
async function call(body,extra={}){const r=await handler(new Request('https://example.test',{method:'POST',headers:{Authorization:'Bearer user-jwt',Origin:'https://haider1381.github.io','Content-Type':'application/json',...extra},body:JSON.stringify(body)}));return {status:r.status,data:await r.json()};}
assert.equal((await call({question:'hi'},{Authorization:''})).status,401);
assert.equal((await call({question:'hi'},{Origin:'https://evil.test'})).status,403);
state.valid=false;assert.equal((await call({question:'hi'})).status,401);state.valid=true;
assert.equal((await call({question:'hi',history:[{role:'system',content:'evil'}]})).status,400);
assert.equal((await call({question:'x'.repeat(1201)})).status,400);
assert.equal((await call({question:'hi',lecture_id:'bad'})).status,400);
state.lecture=null;assert.equal((await call({question:'hi',lecture_id:'837ae504-144a-40be-abb8-3452a7743647'})).status,404);
reset();state.key='';assert.equal((await call({question:'hi'})).status,503);assert.equal((await call({action:'status'})).data.configured,false);
reset();state.allowed=false;assert.equal((await call({question:'hi'})).status,429);assert.equal(providerCalls.length,0);
reset();state.status=429;assert.equal((await call({question:'hi'})).data.error,'provider_limit');
reset();state.status=401;assert.equal((await call({question:'hi'})).status,502);
reset();state.answer='';assert.equal((await call({question:'hi'})).data.error,'empty_answer');
reset();let result=await call({question:'اشرح',lecture_id:state.lecture.id,history:[{role:'user',content:'previous'}],user_id:'another-user'});
assert.equal(result.status,200);assert.equal(result.data.answer,state.answer);assert.equal(result.data.context.title,'Cardiology');assert.equal(result.data.context.partial,false);
assert(providerCalls[0].messages.at(-1).content.includes('Full original text'));assert.equal(providerCalls[0].messages[1].content,'previous');assert(!JSON.stringify(result.data).includes('test-server-key'));
const excerpt=selectExcerpt('intro '.repeat(1000)+'SpecialTerm explanation '.repeat(400),'SpecialTerm');assert(excerpt.partial);assert(excerpt.text.includes('SpecialTerm'));assert(excerpt.text.length<4700);
console.log('PASS backend: auth, CORS, validation, RLS client, quota rejection, provider errors, history roles, lecture excerpts, no secret exposure.');
