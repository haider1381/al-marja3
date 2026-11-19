(() => {
  'use strict';
  if (window.MedbrainNative?.isNative) return;

  const ua = navigator.userAgent;
  const apple = /iPhone|iPad|iPod/i.test(ua) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
  const android = /Android/i.test(ua);
  const samsung = /SamsungBrowser/i.test(ua);
  const embedded = /Telegram|FBAN|FBAV|Instagram|Line\/|; wv\)/i.test(ua) ||
    (apple && /AppleWebKit/i.test(ua) && !/Safari/i.test(ua) && !navigator.standalone);
  const standalone = window.matchMedia('(display-mode: standalone)');
  const dialog = document.getElementById('installAppDialog');
  const status = document.querySelectorAll('#installAppStatus, [data-install-status]');
  const guidance = document.getElementById('installAppGuidance');
  const buttons = document.querySelectorAll('[data-install-app]');
  let offer = null;
  let prompting = false;
  let added = false;

  function announce(message) {
    status.forEach(node => { node.textContent = message; });
  }

  function sync() {
    const running = standalone.matches || navigator.standalone === true;
    buttons.forEach(button => {
      button.disabled = prompting || running || added;
    });
    announce(running ? 'أنت تستخدم Medbrain من أيقونة الشاشة الرئيسية.'
      : added ? 'تمت إضافة Medbrain. افتحه من أيقونته على جهازك.'
      : offer ? 'نافذة التثبيت جاهزة.'
      : '');
  }

  function showGuidance() {
    guidance.textContent = embedded
      ? 'افتح قائمة التطبيق واختر «فتح في المتصفح»، أو انسخ عنوان الصفحة وافتحه في متصفح جهازك. بعدها اضغط زر الإضافة مرة أخرى.'
      : apple
        ? 'على آيفون وآيباد، افتح Medbrain في Safari، ثم اضغط «مشاركة» ← «إضافة إلى الشاشة الرئيسية» ← «إضافة». فعّل «فتح كتطبيق ويب» إذا ظهر.'
        : samsung
          ? 'في Samsung Internet، افتح قائمة ☰ ← «إضافة الصفحة إلى» ← «الشاشة الرئيسية». يمكنك أيضًا استخدام رمز ＋ في شريط العنوان إذا ظهر.'
          : android
            ? 'افتح قائمة متصفحك ⋮، واختر «تثبيت التطبيق» أو «إضافة إلى الشاشة الرئيسية» أو «إنشاء اختصار». إذا كنت في نافذة خاصة، جرّب نافذة عادية.'
            : 'افتح قائمة المتصفح وابحث عن «تثبيت التطبيق» أو «إنشاء اختصار». إذا لم يظهر الخيار، يمكنك استخدام الموقع مباشرة من المتصفح.';
    if (!dialog.open) dialog.showModal();
  }

  async function install() {
    if (!offer) {
      showGuidance();
      return;
    }

    const promptEvent = offer;
    offer = null;
    prompting = true;
    sync();
    try {
      const response = await promptEvent.prompt();
      const choice = response?.outcome ? response : await promptEvent.userChoice;
      if (!added && choice?.outcome === 'accepted') {
        announce('تم تأكيد طلب التثبيت. ابحث عن أيقونة Medbrain على شاشتك.');
      } else if (!added) {
        showGuidance();
      }
    } catch {
      showGuidance();
    } finally {
      prompting = false;
      buttons.forEach(button => { button.disabled = added || standalone.matches || navigator.standalone === true; });
    }
  }

  buttons.forEach(button => button.addEventListener('click', install));
  document.querySelectorAll('[data-install-on-web]').forEach(node => { node.hidden = false; });
  document.getElementById('installAppClose').addEventListener('click', () => dialog.close());
  document.querySelectorAll('[data-embedded-browser-help]').forEach(node => { node.hidden = !embedded; });
  window.addEventListener('beforeinstallprompt', event => {
    event.preventDefault();
    offer = event;
    sync();
  });
  window.addEventListener('appinstalled', () => {
    offer = null;
    added = true;
    sync();
    if (dialog.open) dialog.close();
  });
  standalone.addEventListener?.('change', sync);
  sync();

  if (window.isSecureContext && 'serviceWorker' in navigator) {
    navigator.serviceWorker.register('./sw.js', { scope: './', updateViaCache: 'none' }).catch(() => {
      if (!offer && !added) announce('إذا لم تظهر نافذة التثبيت، جرّب خيار الإضافة من قائمة المتصفح.');
    });
  }
})();
