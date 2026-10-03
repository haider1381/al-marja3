import fs from 'node:fs/promises';import path from 'node:path';import {fileURLToPath} from 'node:url';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..'),release=JSON.parse(await fs.readFile(path.join(root,'release-config.json'),'utf8')),problems=[];
if(!release.supportEmail||!/^\S+@\S+\.\S+$/.test(release.supportEmail))problems.push('Provide and publish the owner-approved support email.');
if(release.nativeOAuthConfigured&&!release.appleSignInConfigured)problems.push('iOS third-party Google login needs an equivalent Apple-compliant login option, enabled and device-tested, or third-party login must remain disabled in that build.');
if(!release.deviceTestsPassed)problems.push('Run Android and physical iPhone/iPad tests: auth/recovery, PDF, timer/background notification, share/export, deletion, keyboard, offline launch and accessibility.');
if(!release.contentRightsConfirmed)problems.push('Confirm redistribution rights for lecture text/PDF/video content and assets.');
if(!release.storePrivacyReviewed)problems.push('Review Apple privacy labels/manifest and Google Data safety/health declarations with real provider retention settings.');
if(!release.signingConfigured)problems.push('Configure owner developer accounts, final bundle ID, Android signing key and Apple certificates/provisioning.');
if(problems.length){console.error('NOT READY FOR STORE SUBMISSION:\n'+problems.map(x=>'- '+x).join('\n'));process.exitCode=1;}else console.log('Preflight declarations are present. Still archive, verify and submit to store review.');