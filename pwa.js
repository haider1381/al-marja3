(() => {
  'use strict';
  if (window.MedbrainNative?.isNative) return;

  const ua = navigator.userAgent;
  const apple = /iPhone|iPad|iPod/i.test(ua) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
  const android = /Android/i.test(ua);
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

  function announce(message, state = '') {
    status.forEach(node => {
      node.textContent = message;
      node.dataset.installState = state;
    });
  }

  function sync() {
    const running = standalone.matches || navigator.standalone === true;
    buttons.forEach(button => {
      button.disabled = prompting || running || added;
    });
    announce(running ? 'أنت تستخدم Medbrain من أيقونة الشاشة الرئيسية.'
      : added ? 'تمت إضافة Medbrain. افتحه من أيقونته على جهازك.'
      : offer ? 'نافذة التثبيت جاهزة.'
      : '', added || running ? 'success' : '');
  }

  function showGuidance() {
    guidance.textContent = apple
      ? 'اضغط «مشاركة» ← «إضافة إلى الشاشة الرئيسية» ← «إضافة». إذا ظهر «فتح كتطبيق ويب»، فعّله. إذا غاب الخيار، افتح الرابط في متصفح يدعم الإضافة.'
      : embedded
        ? 'من قائمة التطبيق اختر «فتح في المتصفح»، ثم اضغط زر الإضافة مرة أخرى.'
        : android
          ? 'من قائمة المتصفح، اختر «تثبيت التطبيق» أو «إضافة إلى الشاشة الرئيسية».'
          : 'من قائمة المتصفح، اختر «تثبيت التطبيق» أو «إنشاء اختصار» إذا كان متاحًا.';
    if (!dialog.open) dialog.showModal();
  }

  async function install() {
    if (apple || !offer) {
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
        announce('تم تأكيد طلب التثبيت. ابحث عن أيقونة Medbrain على شاشتك.', 'pending');
      } else if (!added && !choice?.outcome) {
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
    if (apple) return;
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
