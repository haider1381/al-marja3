(() => {
  'use strict';
  let installPrompt = null;
  if(window.MedbrainNative?.isNative)return;
  const standalone = window.matchMedia('(display-mode: standalone)');
  const isInstalled = () => standalone.matches || navigator.standalone === true;
  const isIOS = /iPhone|iPad|iPod/.test(navigator.userAgent) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
  const dialog = document.getElementById('installAppDialog');
  const buttons = [...document.querySelectorAll('[data-install-app]')];
  const status = document.getElementById('installAppStatus');
  const guidance = document.getElementById('installAppGuidance');
  function sync() {
    const installed = isInstalled();
    buttons.forEach(button => {button.textContent = installed ? 'التطبيق مثبت ومفتوح' : 'تثبيت Medbrain';button.disabled = installed;});
    status.textContent = installed ? 'أنت تستخدم Medbrain كتطبيق مستقل.' : installPrompt ? 'التطبيق جاهز للتثبيت على جهازك.' : 'ثبّت التطبيق للوصول إليه من الشاشة الرئيسية.';
  }
  function showGuidance() {
    guidance.textContent = isIOS
      ? 'على الآيفون أو الآيباد: افتح هذا الموقع في Safari، واضغط مشاركة، ثم «إضافة إلى الشاشة الرئيسية»، ثم «إضافة». إذا ظهر خيار «فتح كتطبيق ويب» ففعّله.'
      : 'على أندرويد: افتح هذا الموقع في Chrome، ثم القائمة ⋮، واختر «تثبيت التطبيق» أو «إضافة إلى الشاشة الرئيسية». على الكمبيوتر استخدم علامة التثبيت في شريط العنوان. إن كنت داخل تطبيق مراسلة، افتح الرابط في المتصفح أولًا.';
    if (!dialog.open) dialog.showModal();
  }
  async function install() {
    if (isInstalled()) return;
    if (!installPrompt) {showGuidance();return;}
    const prompt = installPrompt;installPrompt = null;
    buttons.forEach(button => {button.disabled = true;});
    try {
      await prompt.prompt();
      const result = await prompt.userChoice;
      sync();
      if (result.outcome === 'accepted') status.textContent = 'تم طلب التثبيت. افتح Medbrain من الشاشة الرئيسية بعد اكتماله.';
      else status.textContent = 'يمكنك التثبيت لاحقًا من قائمة المتصفح.';
    } catch (_) {sync();showGuidance();}
  }
  buttons.forEach(button => button.addEventListener('click', install));
  document.getElementById('installAppClose').addEventListener('click', () => dialog.close());
  dialog.addEventListener('click', event => {if(event.target===dialog){const r=dialog.getBoundingClientRect();if(event.clientX<r.left||event.clientX>r.right||event.clientY<r.top||event.clientY>r.bottom)dialog.close();}});
  window.addEventListener('beforeinstallprompt', event => {event.preventDefault();installPrompt = event;sync();});
  window.addEventListener('appinstalled', () => {installPrompt = null;sync();status.textContent='تم تثبيت Medbrain. افتحه من أيقونته على جهازك.';});
  if (standalone.addEventListener) standalone.addEventListener('change', sync);
  sync();
  // Relative paths keep the worker confined to this GitHub Pages project.
  if ('serviceWorker' in navigator && window.isSecureContext) {
    window.addEventListener('load', () => {
      navigator.serviceWorker.register('./sw.js', {scope:'./',updateViaCache:'none'}).catch(() => {
        status.textContent = 'إذا لم يظهر خيار التثبيت، أعد تحميل الموقع من Safari أو Chrome مع اتصال بالإنترنت.';
      });
    }, {once:true});
  }
})();