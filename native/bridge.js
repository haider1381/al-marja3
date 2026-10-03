import {Capacitor} from '@capacitor/core';
import {App} from '@capacitor/app';
import {Share} from '@capacitor/share';
import {Browser} from '@capacitor/browser';
import {Haptics,ImpactStyle} from '@capacitor/haptics';
import {LocalNotifications} from '@capacitor/local-notifications';
import {Filesystem,Directory,Encoding} from '@capacitor/filesystem';
import * as supabase from '@supabase/supabase-js';
import release from './release-config.json';
window.supabase=supabase;
let backHandler=null,authClient=null,queuedAuthUrl=null;
async function handleAuthUrl(url){try{const u=new URL(url),expected=new URL(release.oauthRedirect),started=Number(localStorage.getItem('medbrain_native_oauth_started'));if(u.protocol!==expected.protocol||u.host!==expected.host||u.pathname!==expected.pathname||!started||Date.now()-started>600000)return;if(!authClient){queuedAuthUrl=url;return;}const code=u.searchParams.get('code');if(!code)return;localStorage.removeItem('medbrain_native_oauth_started');const {error}=await authClient.auth.exchangeCodeForSession(code);if(error)throw error;await Browser.close();}catch(_){const field=document.getElementById('gateError');if(field)field.textContent='تعذّر إكمال الدخول. حاول مجددًا.';}}
const native=Capacitor.isNativePlatform();
window.MedbrainNative={isNative:native,
 setAuthClient(client){authClient=client;if(queuedAuthUrl){const url=queuedAuthUrl;queuedAuthUrl=null;handleAuthUrl(url);}},
 async clearExports(){try{const {files}=await Filesystem.readdir({path:'',directory:Directory.Cache});await Promise.all(files.filter(f=>f.name.startsWith('Medbrain-export-')&&f.name.endsWith('.json')).map(f=>Filesystem.deleteFile({path:f.name,directory:Directory.Cache})));}catch(_){}},
 async exportJSON(text){const filename='Medbrain-export-'+Date.now()+'.json';const {uri}=await Filesystem.writeFile({path:filename,data:text,directory:Directory.Cache,encoding:Encoding.UTF8});await Share.share({title:'نسخة بيانات Medbrain',files:[uri],dialogTitle:'احفظ نسخة بياناتك في مكان خاص'});},
 async share(data){await Share.share({...data,dialogTitle:'مشاركة من Medbrain'});},
 async openUrl(url){if(!/^https:\/\//i.test(url))throw Error('Invalid URL');await Browser.open({url});},
 async haptic(){try{await Haptics.impact({style:ImpactStyle.Light});}catch(_){}},
 onBack(handler){backHandler=handler;},
 async cancelFocus(){await LocalNotifications.cancel({notifications:[{id:1081}]});},
 async scheduleFocus(endsAt){let permission=await LocalNotifications.checkPermissions();if(permission.display!=='granted')permission=await LocalNotifications.requestPermissions();if(permission.display!=='granted')throw Error('Notification permission denied');await LocalNotifications.schedule({notifications:[{id:1081,title:'Medbrain — وقت التركيز',body:'انتهت الفترة الحالية. افتح التطبيق للمتابعة.',schedule:{at:new Date(endsAt)}}]});},
 async signIn(client,provider){if(!release.nativeOAuthConfigured)throw Error('Native OAuth setup required');authClient=client;const {data,error}=await client.auth.signInWithOAuth({provider,options:{redirectTo:release.oauthRedirect,skipBrowserRedirect:true}});if(error)throw error;if(!data?.url)throw Error('OAuth URL missing');localStorage.setItem('medbrain_native_oauth_started',String(Date.now()));await Browser.open({url:data.url});}
};
if(native){
 App.addListener('backButton',({canGoBack})=>{if(backHandler?.())return;if(canGoBack)history.back();else App.minimizeApp();});
 App.addListener('appUrlOpen',({url})=>handleAuthUrl(url));
 App.getLaunchUrl().then(result=>{if(result?.url)handleAuthUrl(result.url);});
 document.addEventListener('DOMContentLoaded',()=>{
  document.documentElement.dataset.native='true';
  document.querySelectorAll('[data-install-app]').forEach(b=>b.hidden=true);
  const google=document.getElementById('googleLoginBtn');if(!release.nativeOAuthConfigured){google.hidden=true;document.querySelector('.login-divider')?.remove();}
  document.getElementById('installAppStatus').textContent='هذه نسخة Medbrain المضمّنة على الجهاز.';
 });
}