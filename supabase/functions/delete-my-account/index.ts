import {createClient} from 'npm:@supabase/supabase-js@2.117.2';
import {createDeletionHandler} from './handler.ts';
const admin=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,{auth:{persistSession:false,autoRefreshToken:false}});
Deno.serve(createDeletionHandler({
 getUser:token=>admin.auth.getUser(token),
 context:(uid,session)=>admin.rpc('account_deletion_context',{target_user:uid,target_session:session}),
 removeAvatars:names=>admin.storage.from('avatars').remove(names),
 signOut:token=>admin.auth.admin.signOut(token,'global'),
 deleteUser:uid=>admin.auth.admin.deleteUser(uid,false),
 clearUsage:uid=>admin.rpc('account_deletion_clear_usage',{target_user:uid}),
 now:()=>Date.now()
}));